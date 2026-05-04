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
  SidecarClient({required this.sidecarDir, this.preferCuda = false});

  final String sidecarDir;
  bool preferCuda;

  Process? _proc;
  WebSocketChannel? _ws;
  final _events = StreamController<SidecarMessage>.broadcast();
  Stream<SidecarMessage> get events => _events.stream;

  String _activeDevice = 'cpu';
  String get activeDevice => _activeDevice;

  Future<void> start() async {
    final port = await _freePort();
    final python = Platform.isWindows
        ? p.join(sidecarDir, 'venv', 'Scripts', 'python.exe')
        : p.join(sidecarDir, 'venv', 'bin', 'python');

    _proc = await Process.start(
      python,
      [
        p.join(sidecarDir, 'server.py'),
        '--port', '$port',
        '--device', preferCuda ? 'cuda' : 'cpu',
      ],
      mode: ProcessStartMode.detachedWithStdio,
    );

    _proc!.stderr.transform(utf8.decoder).listen((line) {
      // ignore: avoid_print
      print('[sidecar] $line');
    });

    await _waitForPort(port);
    _ws = IOWebSocketChannel.connect(Uri.parse('ws://127.0.0.1:$port/ws'));
    _ws!.stream.listen(_onMessage, onError: (e) {
      _events.add(SidecarMessage(SidecarEvent.error, {'reason': '$e'}));
    });
  }

  void _onMessage(dynamic raw) {
    final m = jsonDecode(raw as String) as Map<String, dynamic>;
    switch (m['type']) {
      case 'ready':
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
    _ws?.sink.add(jsonEncode({'type': 'translate', 'id': id, 'text': text}));
  }

  Future<void> switchDevice({required bool cuda}) async {
    preferCuda = cuda;
    await stop();
    await start();
  }

  Future<void> stop() async {
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
