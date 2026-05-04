import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

// Silence threshold in dBFS. Audio below this level is considered silence.
const double _silenceThresholdDb = -40.0;
const Duration _silenceDuration = Duration(milliseconds: 1500);
const Duration _hardCapDuration = Duration(seconds: 30);

const _config =
    RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000);

final _cjk = RegExp(r'[一-鿿㐀-䶿]');

enum WhisperModelSize {
  tiny,   // ~75 MB
  base,   // ~140 MB
  small,  // ~460 MB
}

extension WhisperModelSizeExt on WhisperModelSize {
  WhisperModel get ggmlModel => const {
        WhisperModelSize.tiny: WhisperModel.tiny,
        WhisperModelSize.base: WhisperModel.base,
        WhisperModelSize.small: WhisperModel.small,
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
  String? _dir;

  bool _running = false;
  bool _flushing = false;             // (002) serialize concurrent flush calls
  int _wavSeq = 0;                    // (002, 015) rotating wav path
  StreamSubscription<Amplitude>? _ampSub; // (004) cancellable subscription
  Timer? _hardCapTimer;
  DateTime? _silenceSince;

  Stream<String> get segments => _segments.stream;

  String _wavPath(int seq) => p.join(_dir!, 'rolling-$seq.wav');

  Future<void> init() async {
    _dir = (await getApplicationSupportDirectory()).path;
    _whisper = Whisper(model: modelSize.ggmlModel);
    await _whisper!.initialize(modelDir: _dir!);
  }

  Future<void> reinit(WhisperModelSize newSize) async {
    await stop();
    await _disposeWhisper();
    modelSize = newSize;
    _whisper = Whisper(model: newSize.ggmlModel);
    await _whisper!.initialize(modelDir: _dir!);
  }

  // (008) Best-effort release of the previous native context. The exact
  // method name depends on whisper_ggml version — try each common one and
  // swallow NoSuchMethodError if absent.
  Future<void> _disposeWhisper() async {
    final old = _whisper;
    _whisper = null;
    if (old == null) return;
    final names = ['dispose', 'release', 'free', 'close'];
    for (final name in names) {
      try {
        final dyn = old as dynamic;
        switch (name) {
          case 'dispose': await dyn.dispose(); return;
          case 'release': await dyn.release(); return;
          case 'free':    await dyn.free();    return;
          case 'close':   await dyn.close();   return;
        }
      } catch (_) {
        // Method doesn't exist on this version — try the next name.
      }
    }
  }

  Future<void> start() async {
    if (_running) return;
    if (_whisper == null) {
      throw StateError('WhisperListener.init() must be called before start()');
    }
    _running = true;
    _silenceSince = null;
    _wavSeq++;

    await _record.start(_config, path: _wavPath(_wavSeq));

    // (004) Hold the subscription so stop() can cancel it.
    _ampSub = _record
        .onAmplitude(const Duration(milliseconds: 300))
        .listen(_onAmplitude);

    _hardCapTimer = Timer.periodic(_hardCapDuration, (_) {
      if (_running) _flush();
    });
  }

  void _onAmplitude(Amplitude amp) {
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
  }

  Future<void> stop() async {
    if (!_running && _ampSub == null) return;
    _running = false;
    _hardCapTimer?.cancel();
    _hardCapTimer = null;
    await _ampSub?.cancel();
    _ampSub = null;
    _silenceSince = null;

    // (003) Capture the path once and transcribe directly. No second stop().
    String? path;
    try {
      path = await _record.stop();
    } catch (_) {
      path = null;
    }
    if (path != null) await _transcribe(path);
  }

  // (002) Single point of entry for mid-recording flushes. Serialized so
  // VAD and the hard-cap timer can't both stop+start the recorder.
  Future<void> _flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      final wasRunning = _running;
      String? path;
      try {
        path = await _record.stop();
      } catch (_) {
        path = null;
      }
      if (wasRunning && _running) {
        // (015) Rotate path so the next chunk doesn't collide with the
        // file we're about to transcribe.
        _wavSeq++;
        try {
          await _record.start(_config, path: _wavPath(_wavSeq));
        } catch (e) {
          // ignore: avoid_print
          print('[whisper] failed to restart recorder: $e');
          _running = false;
        }
      }
      if (path != null) await _transcribe(path);
    } finally {
      _flushing = false;
    }
  }

  Future<void> _transcribe(String path) async {
    final w = _whisper;
    if (w == null) return;
    try {
      final result = await w.transcribe(
        transcribeRequest: TranscribeRequest(audio: path, language: 'zh'),
      );
      final text = (result.transcription?.text ?? '').trim();
      if (text.isNotEmpty && _cjk.hasMatch(text) && !_segments.isClosed) {
        _segments.add(text);
      }
    } catch (e) {
      // ignore: avoid_print
      print('[whisper] transcribe failed: $e');
    } finally {
      // Tidy up the consumed wav so we don't fill ApplicationSupport.
      try { await File(path).delete(); } catch (_) {}
    }
  }

  Future<void> dispose() async {
    await stop();
    await _disposeWhisper();
    if (!_segments.isClosed) await _segments.close();
  }
}
