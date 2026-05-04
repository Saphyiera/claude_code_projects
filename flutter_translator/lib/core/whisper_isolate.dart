import 'dart:async';
import 'package:record/record.dart';
import 'package:whisper_ggml/whisper_ggml.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

// Silence threshold in dBFS. Audio below this level is considered silence.
const double _silenceThresholdDb = -40.0;

// How long continuous silence must last before we flush.
const Duration _silenceDuration = Duration(milliseconds: 1500);

// Hard cap: flush even if no silence detected.
const Duration _hardCapDuration = Duration(seconds: 30);

final _cjk = RegExp(r'[一-鿿㐀-䶿]');

enum WhisperModelSize {
  tiny,   // ~75 MB  — fastest, good for conversational Mandarin
  base,   // ~140 MB — balanced
  small,  // ~460 MB — higher accuracy
}

extension WhisperModelSizeExt on WhisperModelSize {
  WhisperModel get ggmlModel => const {
    WhisperModelSize.tiny: WhisperModel.tiny,
    WhisperModelSize.base: WhisperModel.base,
    WhisperModelSize.small: WhisperModel.small,
  }[this]!;

  String get assetName => const {
    WhisperModelSize.tiny: 'ggml-tiny.bin',
    WhisperModelSize.base: 'ggml-base.bin',
    WhisperModelSize.small: 'ggml-small.bin',
  }[this]!;

  String get label => const {
    WhisperModelSize.tiny: 'Tiny (~75 MB)',
    WhisperModelSize.base: 'Base (~140 MB)',
    WhisperModelSize.small: 'Small (~460 MB)',
  }[this]!;
}

class WhisperListener {
  WhisperListener({this.modelSize = WhisperModelSize.tiny});

  WhisperModelSize modelSize;

  final _record = AudioRecorder();
  final _segments = StreamController<String>.broadcast();
  Whisper? _whisper;
  bool _running = false;

  // VAD state
  DateTime? _silenceSince;
  Timer? _hardCapTimer;
  String? _wavPath;

  Stream<String> get segments => _segments.stream;

  Future<void> init() async {
    final dir = await getApplicationSupportDirectory();
    _wavPath = p.join(dir.path, 'rolling.wav');
    _whisper = Whisper(model: modelSize.ggmlModel);
    await _whisper!.initialize(modelDir: dir.path);
  }

  Future<void> reinit(WhisperModelSize newSize) async {
    await stop();
    modelSize = newSize;
    _whisper = Whisper(model: newSize.ggmlModel);
    final dir = await getApplicationSupportDirectory();
    await _whisper!.initialize(modelDir: dir.path);
  }

  Future<void> start() async {
    if (_running) return;
    _running = true;
    _silenceSince = null;

    await _record.start(
      const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000),
      path: _wavPath!,
    );

    // VAD: watch amplitude, flush on sustained silence.
    _record.onAmplitude(interval: const Duration(milliseconds: 300)).listen(
      (amp) {
        if (!_running) return;
        if (amp.current < _silenceThresholdDb) {
          _silenceSince ??= DateTime.now();
          if (DateTime.now().difference(_silenceSince!) >= _silenceDuration) {
            _silenceSince = null;
            _flush();
          }
        } else {
          _silenceSince = null;
        }
      },
    );

    // Hard cap: always flush after 30s even with continuous speech.
    _hardCapTimer =
        Timer.periodic(_hardCapDuration, (_) { if (_running) _flush(); });
  }

  Future<void> stop() async {
    _running = false;
    _hardCapTimer?.cancel();
    _hardCapTimer = null;
    _silenceSince = null;
    await _record.stop();
    await _flush(final_: true);
  }

  Future<void> _flush({bool final_ = false}) async {
    if (!final_ && !_running) return;
    final path = await _record.stop();

    if (_running) {
      // Restart capture immediately so we don't lose audio while processing.
      await _record.start(
        const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000),
        path: _wavPath!,
      );
    }

    if (path == null) return;

    final result = await _whisper!.transcribe(
      transcribeRequest: TranscribeRequest(audio: path, language: 'zh'),
    );
    final text = (result.transcription?.text ?? '').trim();
    if (text.isNotEmpty && _cjk.hasMatch(text)) {
      _segments.add(text);
    }
  }

  void dispose() {
    stop();
    _segments.close();
  }
}
