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
  bool _ready = false;                  // (009) bootstrap status
  String? _initError;                   // (009)
  int _beamSize = 2;
  WhisperModelSize _modelSize = WhisperModelSize.tiny;
  String? _statusMessage;

  bool get listening => _listening;
  bool get ready => _ready;
  String? get initError => _initError;
  bool get cudaActive => _sidecar.activeDevice == 'cuda';
  bool get isMacOS => Platform.isMacOS;
  int get pending => _queue.pending;
  int get beamSize => _beamSize;
  WhisperModelSize get modelSize => _modelSize;
  String? get statusMessage => _statusMessage;

  static const int maxEntries = 200;

  // (009) bootstrap is non-throwing: any failure surfaces via initError
  // so the UI can render an error screen instead of crashing main().
  Future<void> bootstrap() async {
    try {
      await _whisper.init();
      _sidecar.events.listen(_onSidecarEvent);
      _whisper.segments.listen(_onSegment);
      await _sidecar.start();
      _ready = true;
      notifyListeners();
    } catch (e) {
      _initError = '$e';
      notifyListeners();
    }
  }

  Future<void> startListening() async {
    if (_listening || !_ready) return;
    _listening = true;
    notifyListeners();
    try {
      await _whisper.start();
    } catch (e) {
      _listening = false;
      _statusMessage = 'Microphone error: $e';
      notifyListeners();
    }
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

  Future<void> toggleCuda() async {
    if (Platform.isMacOS) return;
    _queue.failPending();
    await _sidecar.switchDevice(cuda: !_sidecar.preferCuda);
    notifyListeners();
  }

  void setBeamSize(int size) {
    _beamSize = size;
    _sidecar.beamSize = size;
    notifyListeners();
  }

  Future<void> setModelSize(WhisperModelSize size) async {
    if (size == _modelSize) return;
    final wasListening = _listening;
    if (wasListening) await stopListening();
    _modelSize = size;
    try {
      await _whisper.reinit(size);
    } catch (e) {
      _statusMessage = 'Model load failed: $e';
      notifyListeners();
      return;
    }
    if (wasListening) await startListening();
    notifyListeners();
  }

  void _onSegment(String chinese) {
    final id = _queue.add(chinese);
    final entry =
        TranscriptEntry(id: id, time: DateTime.now(), chinese: chinese);
    _byId[id] = entry;
    entries.add(entry);
    while (entries.length > maxEntries) {
      final removed = entries.removeAt(0);
      _byId.remove(removed.id);
    }

    // (006) If the sidecar is mid-restart, mark the entry as errored
    // immediately so the UI doesn't hang on a request that was never sent.
    final sent = _sidecar.translate(id, chinese);
    if (!sent) _queue.resolveError(id);

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
        // Disconnect / restart in flight: error any still-pending entries
        // so the UI doesn't keep showing "translating…" indefinitely.
        _queue.failPending();
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
