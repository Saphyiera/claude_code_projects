import 'dart:async';
import 'package:record/record.dart';
import 'package:whisper_ggml/whisper_ggml.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

final _cjk = RegExp(r'[一-鿿㐀-䶿]');

class WhisperListener {
  WhisperListener({required this.modelAssetPath});

  final String modelAssetPath;

  final _record = AudioRecorder();
  final _segments = StreamController<String>.broadcast();
  Whisper? _whisper;
  bool _running = false;
  Timer? _windowTimer;
  String? _wavPath;

  Stream<String> get segments => _segments.stream;

  Future<void> init() async {
    final dir = await getApplicationSupportDirectory();
    _wavPath = p.join(dir.path, 'rolling.wav');
    _whisper = Whisper(model: WhisperModel.base);
    await _whisper!.initialize(modelDir: dir.path);
  }

  Future<void> start() async {
    if (_running) return;
    _running = true;
    await _record.start(
      const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000),
      path: _wavPath!,
    );
    _windowTimer = Timer.periodic(const Duration(seconds: 30), (_) => _flush());
  }

  Future<void> stop() async {
    _running = false;
    _windowTimer?.cancel();
    await _record.stop();
    await _flush();
  }

  Future<void> _flush() async {
    if (!_running) return;
    final path = await _record.stop();
    await _record.start(
      const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000),
      path: _wavPath!,
    );
    if (path == null) return;

    final result = await _whisper!.transcribe(
      transcribeRequest: TranscribeRequest(
        audio: path,
        language: 'zh',
      ),
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
