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

  late final SidecarClient _sidecar = SidecarClient(sidecarDir: sidecarDir);
  late final WhisperListener _whisper = WhisperListener(
      modelAssetPath: 'assets/models/whisper-base-zh.bin');
  late final SentenceQueue _queue = SentenceQueue(_onResolved);

  final List<TranscriptEntry> entries = [];
  final Map<int, TranscriptEntry> _byId = {};

  bool _listening = false;
  bool get listening => _listening;
  bool get cudaActive => _sidecar.activeDevice == 'cuda';
  int get pending => _queue.pending;

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

  Future<void> retrySidecar() async {
    _queue.failPending();
    await _sidecar.switchDevice(cuda: _sidecar.preferCuda);
  }

  Future<void> toggleCuda() async {
    _queue.failPending();
    await _sidecar.switchDevice(cuda: !_sidecar.preferCuda);
    notifyListeners();
  }

  void _onSegment(String chinese) {
    final id = _queue.add(chinese);
    final entry = TranscriptEntry(
      id: id,
      time: DateTime.now(),
      chinese: chinese,
    );
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
        _queue.resolve(m.payload['id'] as int,
            m.payload['translated'] as String);
        break;
      case SidecarEvent.translationError:
        _queue.resolveError(m.payload['id'] as int);
        break;
      case SidecarEvent.fallback:
      case SidecarEvent.ready:
      case SidecarEvent.error:
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
