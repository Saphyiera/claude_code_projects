import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:path/path.dart' as p;

enum SidecarEvent { ready, fallback, translation, translationError, error }

class SidecarMessage {
  SidecarMessage(this.event, this.payload);
  final SidecarEvent event;
  final Map<String, dynamic> payload;
}

class SidecarClient {
  SidecarClient({
    required this.sidecarDir,
    this.preferCuda = false,
    this.beamSize = 2,
  });

  final String sidecarDir;
  bool preferCuda;
  int beamSize;

  Process? _proc;
  WebSocketChannel? _ws;
  Future<void>? _starting;       // guards concurrent start() (010)
  bool _disposed = false;
  int _retryCount = 0;
  static const int _maxRetries = 3;

  // Wait long enough for first-run model load + manifest hash. (013)
  static const Duration _portWaitTimeout = Duration(seconds: 120);

  final _events = StreamController<SidecarMessage>.broadcast();
  Stream<SidecarMessage> get events => _events.stream;

  String _activeDevice = 'cpu';
  String get activeDevice => _activeDevice;

  // On macOS the GPU toggle is hidden; CT2 uses Apple Accelerate BLAS.
  String get _deviceArg {
    if (Platform.isMacOS) return 'cpu';
    return preferCuda ? 'cuda' : 'cpu';
  }

  Future<void> start() async {
    if (_disposed) return;
    if (_starting != null) return _starting;     // (010)
    final c = Completer<void>();
    _starting = c.future;
    try {
      await _doStart();
      c.complete();
    } catch (e, st) {
      c.completeError(e, st);
      rethrow;
    } finally {
      _starting = null;
    }
  }

  Future<void> _doStart() async {
    final port = await _freePort();
    final python = Platform.isWindows
        ? p.join(sidecarDir, 'venv', 'Scripts', 'python.exe')
        : p.join(sidecarDir, 'venv', 'bin', 'python');

    // ProcessStartMode.normal so the child is in our process group on
    // Unix and dies with us on a clean shutdown. (011)
    final proc = await Process.start(
      python,
      [
        p.join(sidecarDir, 'server.py'),
        '--port', '$port',
        '--device', _deviceArg,
      ],
      mode: ProcessStartMode.normal,
    );
    _proc = proc;

    // Drain stdout (avoid pipe backpressure deadlock) — keep silent. (011)
    proc.stdout.drain<void>();

    // Stream stderr line-by-line. (012)
    proc.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      // ignore: avoid_print
      print('[sidecar] $line');
    });

    _watchProcess(proc);

    try {
      await _waitForPort(port);
    } catch (e) {
      // Port never opened — kill the orphan, surface the error.
      proc.kill(ProcessSignal.sigterm);
      rethrow;
    }

    final ws = IOWebSocketChannel.connect(Uri.parse('ws://127.0.0.1:$port/ws'));
    _ws = ws;
    ws.stream.listen(
      _onMessage,
      onError: (e) =>
          _emit(SidecarEvent.error, {'reason': '$e'}),
      onDone: () {
        // (005) Treat clean WS close as a fault so callers stop hanging.
        if (identical(_ws, ws)) {
          _ws = null;
          _emit(SidecarEvent.error, {'reason': 'sidecar disconnected'});
        }
      },
      cancelOnError: true,
    );
  }

  // Watchdog — only retries when *this* process is still the active one. (001)
  void _watchProcess(Process proc) {
    proc.exitCode.then((code) {
      if (!identical(_proc, proc)) return; // already replaced (e.g., by switchDevice)
      _proc = null;
      _ws = null;
      if (_disposed) return;
      if (_retryCount < _maxRetries) {
        _retryCount++;
        final delay = Duration(seconds: _retryCount * 2);
        _emit(SidecarEvent.error, {
          'reason': 'sidecar exited (code $code), retrying in ${delay.inSeconds}s '
              '(attempt $_retryCount/$_maxRetries)',
        });
        Future.delayed(delay, () {
          // Skip the retry if disposal or a manual start has happened
          // since the watchdog scheduled it.
          if (_disposed || _proc != null || _starting != null) return;
          start().catchError((e) =>
              _emit(SidecarEvent.error, {'reason': 'restart failed: $e'}));
        });
      } else {
        _emit(SidecarEvent.error, {
          'reason': 'sidecar crashed (code $code); max retries exceeded',
        });
      }
    });
  }

  void _onMessage(dynamic raw) {
    final m = jsonDecode(raw as String) as Map<String, dynamic>;
    switch (m['type']) {
      case 'ready':
        _retryCount = 0;
        _activeDevice = m['device'] as String;
        _emit(SidecarEvent.ready, {'device': _activeDevice});
        break;
      case 'fallback':
        _activeDevice = m['to'] as String;
        _emit(SidecarEvent.fallback, m.cast());
        break;
      case 'translation':
        _emit(SidecarEvent.translation, m.cast());
        break;
      case 'translation-error':
        _emit(SidecarEvent.translationError, m.cast());
        break;
      case 'error':
        _emit(SidecarEvent.error, m.cast());
        break;
    }
  }

  /// Enqueue a translation. Returns true if the request was sent;
  /// false if the sidecar isn't connected (caller should resolve the
  /// queue entry as an error so the UI doesn't hang). (006)
  bool translate(int id, String text) {
    final ws = _ws;
    if (ws == null) return false;
    try {
      ws.sink.add(jsonEncode({
        'type': 'translate',
        'id': id,
        'text': text,
        'beam_size': beamSize,
      }));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> switchDevice({required bool cuda}) async {
    preferCuda = cuda;
    await stop();
    await start();
  }

  Future<void> stop() async {
    final proc = _proc;
    final ws = _ws;
    _proc = null;
    _ws = null;
    try { await ws?.sink.close(); } catch (_) {}
    proc?.kill(ProcessSignal.sigterm);
    if (proc != null) {
      // Wait briefly so the next start() doesn't race the previous shutdown.
      await proc.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () { proc.kill(ProcessSignal.sigkill); return -1; },
      );
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    if (!_events.isClosed) await _events.close();
  }

  void _emit(SidecarEvent e, Map<String, dynamic> payload) {
    if (_disposed || _events.isClosed) return;
    _events.add(SidecarMessage(e, payload));
  }

  static Future<int> _freePort() async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = s.port;
    await s.close();
    return port;
  }

  static Future<void> _waitForPort(int port,
      {Duration timeout = _portWaitTimeout}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final sock = await Socket.connect(
            InternetAddress.loopbackIPv4, port,
            timeout: const Duration(milliseconds: 200));
        await sock.close();
        return;
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }
    throw TimeoutException('sidecar did not open port $port within $timeout');
  }
}
