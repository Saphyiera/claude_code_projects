import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/sentence_queue.dart';
import '../core/sidecar_client.dart';
import '../core/whisper_isolate.dart';

class TranscriptEntry {
  TranscriptEntry({
    required this.id,
    required this.time,
    required this.chinese,
  });

  final int id;
  final DateTime time;
  final String chinese;
  String? english;
  bool error = false;
  bool get pending => english == null;
}

class TranslationController extends ChangeNotifier {
  TranslationController({required this.sidecarDir});

  final String sidecarDir;

  late final SidecarClient _sidecar = SidecarClient(
    sidecarDir: sidecarDir,
    beamSize: _beamSize,
  );
  late WhisperListener _whisper = WhisperListener(modelSize: _modelSize);
  late final SentenceQueue _queue = SentenceQueue(_onResolved);

  final List<TranscriptEntry> entries = [];
  final Map<int, TranscriptEntry> _byId = {};

  bool _listening = false;
  int _beamSize = 2;
  WhisperModelSize _modelSize = WhisperModelSize.tiny;

  bool get listening => _listening;
  bool get cudaActive => _sidecar.activeDevice == 'cuda';
  bool get isMacOS => Platform.isMacOS;
  int get pending => _queue.pending;
  int get beamSize => _beamSize;
  WhisperModelSize get modelSize => _modelSize;

  String? _statusMessage;
  String? get statusMessage => _statusMessage;

  static const int maxEntries = 200;

  Future<void> bootstrap() async {
    await _whisper.init();
    await _sidecar.start();
    _sidecar.events.listen(_onSidecarEvent);
    _whisper.segments.listen(_onSegment);
  }

  Future<void> startListening() async {
    if (_listening) return;
    _listening = true;
    notifyListeners();
    await _whisper.start();
  }

  Future<void> stopListening() async {
    if (!_listening) return;
    _listening = false;
    notifyListeners();
    await _whisper.stop();
  }

  void clear() {
    entries.clear();
    _byId.clear();
    notifyListeners();
  }

  // Graceful device switch: let in-flight translations resolve before
  // restarting. failPending() errors out anything still queued after
  // the restart so the UI never hangs on a stale entry.
  Future<void> toggleCuda() async {
    if (Platform.isMacOS) return;
    await _sidecar.stop();
    _queue.failPending();
    await _sidecar.switchDevice(cuda: !_sidecar.preferCuda);
    notifyListeners();
  }

  Future<void> setBeamSize(int size) async {
    _beamSize = size;
    _sidecar.beamSize = size;
    notifyListeners();
  }

  Future<void> setModelSize(WhisperModelSize size) async {
    if (size == _modelSize) return;
    final wasListening = _listening;
    if (wasListening) await stopListening();
    _modelSize = size;
    await _whisper.reinit(size);
    if (wasListening) await startListening();
    notifyListeners();
  }

  void _onSegment(String chinese) {
    final id = _queue.add(chinese);
    final entry = TranscriptEntry(id: id, time: DateTime.now(), chinese: chinese);
    _byId[id] = entry;
    entries.add(entry);
    while (entries.length > maxEntries) {
      final removed = entries.removeAt(0);
      _byId.remove(removed.id);
    }
    _sidecar.translate(id, chinese);
    notifyListeners();
  }

  void _onSidecarEvent(SidecarMessage m) {
    switch (m.event) {
      case SidecarEvent.translation:
        _queue.resolve(
            m.payload['id'] as int, m.payload['translated'] as String);
        break;
      case SidecarEvent.translationError:
        _queue.resolveError(m.payload['id'] as int);
        break;
      case SidecarEvent.fallback:
        _statusMessage =
            'GPU unavailable — fell back to CPU (${m.payload['reason']})';
        notifyListeners();
        break;
      case SidecarEvent.ready:
        _statusMessage = null;
        notifyListeners();
        break;
      case SidecarEvent.error:
        _statusMessage = m.payload['reason'] as String?;
        notifyListeners();
        break;
    }
  }

  void _onResolved(int id, String _, String translation) {
    final e = _byId[id];
    if (e == null) return;
    e.english = translation;
    e.error = translation == '[Translation error]';
    notifyListeners();
  }

  @override
  void dispose() {
    _whisper.dispose();
    _sidecar.dispose();
    super.dispose();
  }
}
