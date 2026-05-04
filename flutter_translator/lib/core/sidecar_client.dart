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
  bool _intentionalStop = false;
  int _retryCount = 0;
  static const int _maxRetries = 3;

  final _events = StreamController<SidecarMessage>.broadcast();
  Stream<SidecarMessage> get events => _events.stream;

  String _activeDevice = 'cpu';
  String get activeDevice => _activeDevice;

  // On macOS, let CT2 pick the best CPU backend (Accelerate BLAS).
  // GPU toggle is hidden on macOS in the UI.
  String get _deviceArg {
    if (Platform.isMacOS) return 'cpu';
    return preferCuda ? 'cuda' : 'cpu';
  }

  Future<void> start() async {
    _intentionalStop = false;
    final port = await _freePort();
    final python = Platform.isWindows
        ? p.join(sidecarDir, 'venv', 'Scripts', 'python.exe')
        : p.join(sidecarDir, 'venv', 'bin', 'python');

    _proc = await Process.start(
      python,
      [
        p.join(sidecarDir, 'server.py'),
        '--port', '$port',
        '--device', _deviceArg,
      ],
      mode: ProcessStartMode.detachedWithStdio,
    );

    _proc!.stderr.transform(utf8.decoder).listen((line) {
      // ignore: avoid_print
      print('[sidecar] $line');
    });

    _watchProcess();

    await _waitForPort(port);
    _ws = IOWebSocketChannel.connect(Uri.parse('ws://127.0.0.1:$port/ws'));
    _ws!.stream.listen(_onMessage, onError: (e) {
      _events.add(SidecarMessage(SidecarEvent.error, {'reason': '$e'}));
    });
  }

  // Watchdog: if the sidecar crashes unexpectedly, retry with backoff.
  void _watchProcess() {
    _proc?.exitCode.then((code) {
      if (_intentionalStop) return;
      if (_retryCount < _maxRetries) {
        _retryCount++;
        final delay = Duration(seconds: _retryCount * 2);
        _events.add(SidecarMessage(SidecarEvent.error, {
          'reason': 'sidecar exited (code $code), retrying in ${delay.inSeconds}s '
              '(attempt $_retryCount/$_maxRetries)',
        }));
        Future.delayed(delay, () {
          if (!_intentionalStop) start();
        });
      } else {
        _events.add(SidecarMessage(SidecarEvent.error, {
          'reason': 'sidecar crashed (code $code); max retries exceeded',
        }));
      }
    });
  }

  void _onMessage(dynamic raw) {
    final m = jsonDecode(raw as String) as Map<String, dynamic>;
    switch (m['type']) {
      case 'ready':
        _retryCount = 0; // successful start resets retry counter
        _activeDevice = m['device'] as String;
        _events.add(SidecarMessage(SidecarEvent.ready, {'device': _activeDevice}));
        break;
      case 'fallback':
        _activeDevice = m['to'] as String;
        _events.add(SidecarMessage(SidecarEvent.fallback, m.cast()));
        break;
      case 'translation':
        _events.add(SidecarMessage(SidecarEvent.translation, m.cast()));
        break;
      case 'translation-error':
        _events.add(SidecarMessage(SidecarEvent.translationError, m.cast()));
        break;
      case 'error':
        _events.add(SidecarMessage(SidecarEvent.error, m.cast()));
        break;
    }
  }

  void translate(int id, String text) {
    _ws?.sink.add(jsonEncode({
      'type': 'translate',
      'id': id,
      'text': text,
      'beam_size': beamSize,
    }));
  }

  Future<void> switchDevice({required bool cuda}) async {
    preferCuda = cuda;
    await stop();
    await start();
  }

  Future<void> stop() async {
    _intentionalStop = true;
    await _ws?.sink.close();
    _proc?.kill(ProcessSignal.sigterm);
    _proc = null;
    _ws = null;
  }

  void dispose() {
    stop();
    _events.close();
  }

  static Future<int> _freePort() async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = s.port;
    await s.close();
    return port;
  }

  static Future<void> _waitForPort(int port,
      {Duration timeout = const Duration(seconds: 30)}) async {
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
    throw TimeoutException('sidecar did not open port $port');
  }
}
