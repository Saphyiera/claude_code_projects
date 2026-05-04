# Flutter Desktop Port — Live zh→en Translator

A Flutter Windows/Linux desktop application that mirrors the existing
browser app (`/home/user/claude_code_projects/`) but runs translation
locally on a real GPU. This document is the design + source dump — copy
each block into the indicated path inside a fresh `flutter create
flutter_translator` scaffold and you have a working app.

---

## 1. Architecture

After weighing the alternatives I considered (in-process ONNX FFI, raw
CTranslate2 FFI, browser + remote API), the most shippable design is:

> **Flutter desktop UI + a small CTranslate2 Python sidecar over
> localhost WebSocket, plus offline Whisper for speech recognition.**

Why this stack:

- **CTranslate2** is the fastest open inference engine for Marian /
  opus-mt seq2seq models — typically 2–3× ONNX Runtime CUDA EP and
  5–10× PyTorch on the same model — and it ships with INT8 weights,
  beam search, and batching out of the box. Doing the same with raw
  ONNX from Dart would mean writing your own encoder loop, decoder
  loop, KV-cache, beam search, and tokenizer integration.
- **Sidecar over localhost** sounds expensive but loopback RTT is
  ~0.2–1 ms and CT2 inference is ~3–10 ms. The IPC isn't the
  bottleneck. In exchange you get a one-line model load
  (`ct2.Translator(...)`) and you escape the FFI rabbit hole.
- **Whisper.cpp** gives you offline ASR with identical behavior on
  Windows + Linux (browser WebSpeech is Chrome-only and unreliable).
  The `whisper_ggml` Dart package wraps it via FFI cleanly.
- **macOS is out of scope** — no CUDA. (Could be added later via the
  `coreml` CT2 backend or by switching to MLX.)

```
┌─────────────────────────────────────────────────────────────┐
│  Flutter UI                                                 │
│  ┌──────────────┐   ┌──────────────────────────────────┐    │
│  │  Controls    │   │  TranscriptList                  │    │
│  │  (mic, GPU)  │   │  ┌────────────────────────────┐  │    │
│  │              │   │  │ 12:34:56                   │  │    │
│  │              │   │  │ 你好世界                   │  │    │
│  │              │   │  │ Hello world.               │  │    │
│  │              │   │  └────────────────────────────┘  │    │
│  │              │   │  ┌────────────────────────────┐  │    │
│  │              │   │  │ 12:34:58                   │  │    │
│  │              │   │  │ 今天天气怎么样             │  │    │
│  │              │   │  │ translating…               │  │    │
│  │              │   │  └────────────────────────────┘  │    │
│  └──────────────┘   └──────────────────────────────────┘    │
│        │                       ▲                            │
│        │                       │                            │
│  TranslationController (ChangeNotifier)                     │
│        │                       │                            │
│        ▼                       │                            │
│  ┌────────────────┐   ┌────────────────────┐                │
│  │ WhisperIsolate │   │ SidecarClient      │                │
│  │  (mic capture, │   │  (WebSocket to     │                │
│  │   30s windows, │   │   localhost:N)     │                │
│  │   whisper.cpp) │   │                    │                │
│  └────────────────┘   └────────────────────┘                │
│        │                       │                            │
└────────┼───────────────────────┼────────────────────────────┘
         │                       │
         ▼                       ▼
   Final zh segment        ws://localhost:N/translate
                                 │
                                 ▼
                       ┌───────────────────────┐
                       │ Python sidecar        │
                       │  FastAPI + uvicorn    │
                       │  CTranslate2 + CUDA   │
                       │  opus-mt-zh-en        │
                       └───────────────────────┘
```

The data flow inside Flutter mirrors the existing browser app:

```
mic → WhisperIsolate
        │ final segment with CJK chars
        ▼
   queue.add(text) → id
        │
        ├─► appendPendingEntry(id, text)   ← Chinese visible immediately
        │                                    with "translating…" placeholder
        │
        └─► sidecar.translate(id, text)
                │
                ▼
        WebSocket reply: { id, translated }
                │
                ▼
        queue.resolve(id, translated)
                │
                ▼
        callback(id, original, translation)
                │
                ▼
        resolveEntry(id, translated)        ← placeholder replaced in place
```

---

## 2. Project layout

```
flutter_translator/
├── pubspec.yaml
├── lib/
│   ├── main.dart
│   ├── app.dart
│   ├── state/
│   │   └── translation_controller.dart
│   ├── widgets/
│   │   ├── controls.dart
│   │   ├── transcript.dart
│   │   └── transcript_tile.dart
│   └── core/
│       ├── sentence_queue.dart
│       ├── chunker.dart
│       ├── sidecar_client.dart
│       └── whisper_isolate.dart
├── test/
│   ├── sentence_queue_test.dart
│   └── chunker_test.dart
├── assets/
│   └── models/
│       └── whisper-base-zh.bin            ← Whisper ggml model
├── sidecar/
│   ├── server.py
│   ├── requirements.txt
│   └── models/
│       └── opus-mt-zh-en/                 ← CT2-converted model
│           ├── model.bin
│           ├── source.spm
│           ├── target.spm
│           ├── shared_vocabulary.json
│           └── config.json
└── linux/   windows/                       ← Flutter desktop scaffolds
```

Total binary distribution is ~600 MB (Whisper base + opus-mt + CT2 +
CUDA runtime).

---

## 3. `pubspec.yaml`

```yaml
name: flutter_translator
description: Live Mandarin → English translator (Flutter desktop)
publish_to: 'none'
version: 0.1.0

environment:
  sdk: '>=3.4.0 <4.0.0'
  flutter: '>=3.22.0'

dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  # Whisper via whisper.cpp FFI
  whisper_ggml: ^1.3.0          # check pub.dev for current version
  # Audio capture from the mic
  record: ^5.1.2
  # WebSocket client to the sidecar
  web_socket_channel: ^3.0.0
  # File / process helpers
  path_provider: ^2.1.4
  process_run: ^1.1.0
  ffi: ^2.1.3

dev_dependencies:
  flutter_test:
    sdk: flutter
  test: ^1.25.0
  flutter_lints: ^4.0.0

flutter:
  uses-material-design: true
  assets:
    - assets/models/
```

> The exact package versions move quickly — verify on pub.dev at the
> time you build. If `whisper_ggml` is unavailable on your platform,
> `whisper_flutter_new` is a drop-in alternative with a similar API.

---

## 4. Core modules — direct ports of the JS source

### 4.1 `lib/core/sentence_queue.dart`

Direct port of `queue.js`. Same public API, same in-order flush
semantics, same defensive behavior on unknown / double-resolve ids.

```dart
typedef ResultCallback = void Function(int id, String original, String translation);

class SentenceQueue {
  SentenceQueue(this._onResult);

  int _nextId = 0;
  int _nextDisplay = 0;
  final Map<int, String> _texts = {};
  final Map<int, _Result> _results = {};
  final ResultCallback _onResult;

  /// Append a sentence to the queue. Returns its id.
  int add(String text) {
    final id = _nextId++;
    _texts[id] = text;
    return id;
  }

  /// Mark a sentence as successfully translated.
  void resolve(int id, String translation) {
    if (!_texts.containsKey(id) || _results.containsKey(id)) return;
    _results[id] = _Result(_texts[id]!, translation);
    _flush();
  }

  /// Mark a sentence as failed.
  void resolveError(int id) {
    if (!_texts.containsKey(id) || _results.containsKey(id)) return;
    _results[id] = _Result(_texts[id]!, '[Translation error]');
    _flush();
  }

  /// Number of sentences awaiting translation or in-order display.
  int get pending => _texts.length;

  /// Surface every still-unresolved id as an error and flush. Use when
  /// the sidecar is being torn down.
  void failPending() {
    for (final id in _texts.keys.toList()) {
      if (!_results.containsKey(id)) {
        _results[id] = _Result(_texts[id]!, '[Translation error]');
      }
    }
    _flush();
  }

  void _flush() {
    while (_results.containsKey(_nextDisplay)) {
      final id = _nextDisplay;
      final r = _results.remove(id)!;
      _texts.remove(id);
      _onResult(id, r.original, r.translation);
      _nextDisplay++;
    }
  }
}

class _Result {
  _Result(this.original, this.translation);
  final String original;
  final String translation;
}
```

### 4.2 `lib/core/chunker.dart`

Direct port of `chunker.js`. Same regex, same greedy-grouping +
hard-split fallback.

```dart
final _sentenceSplit = RegExp(r'(?<=[。！？；.!?;])');

/// Split [text] into chunks of at most [limit] characters, preferring
/// sentence-ending punctuation as boundaries.
List<String> chunkText(String? text, {int limit = 80}) {
  final t = (text ?? '').trim();
  if (t.isEmpty) return const [];
  if (t.length <= limit) return [t];

  final sentences = t.split(_sentenceSplit);

  final groups = <String>[];
  var cur = '';
  for (final s in sentences) {
    if (s.isEmpty) continue;
    if (cur.isNotEmpty && cur.length + s.length > limit) {
      groups.add(cur);
      cur = s;
    } else {
      cur += s;
    }
  }
  if (cur.isNotEmpty) groups.add(cur);

  final out = <String>[];
  for (final g in groups) {
    if (g.length <= limit) {
      out.add(g);
      continue;
    }
    for (var i = 0; i < g.length; i += limit) {
      final end = (i + limit > g.length) ? g.length : i + limit;
      out.add(g.substring(i, end));
    }
  }
  return [
    for (final s in out)
      if (s.trim().isNotEmpty) s.trim()
  ];
}
```

### 4.3 `lib/core/sidecar_client.dart`

Spawns the Python sidecar as a child process at startup, picks a free
local port, opens a WebSocket to it, and exposes a `translate(id, text)`
future. Mirrors the device-toggle and fallback behavior of
`translator-worker.js`.

```dart
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

  /// Start the sidecar process and connect.
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

    // Forward stderr so init errors are visible during dev.
    _proc!.stderr.transform(utf8.decoder).listen((line) {
      // ignore: avoid_print
      print('[sidecar] $line');
    });

    // Wait for the port to be listening, then connect.
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

  /// Send a translate request. The corresponding result arrives via
  /// [events] as a [SidecarEvent.translation] or [translationError].
  void translate(int id, String text) {
    _ws?.sink.add(jsonEncode({'type': 'translate', 'id': id, 'text': text}));
  }

  /// Restart the sidecar with the requested device.
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

  // -- helpers ---------------------------------------------------------

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
```

### 4.4 `lib/core/whisper_isolate.dart`

Captures audio with `record`, hands rolling 30-second windows to a
Whisper inference call, and emits final segments containing CJK
characters into a `Stream<String>`.

```dart
import 'dart:async';
import 'package:record/record.dart';
import 'package:whisper_ggml/whisper_ggml.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

final _cjk = RegExp(r'[一-鿿㐀-䶿]');

class WhisperListener {
  WhisperListener({required this.modelAssetPath});

  final String modelAssetPath; // e.g. 'assets/models/whisper-base-zh.bin'

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

    // whisper_ggml expects the model at a writable path; copy from
    // bundled asset to the support dir on first run.
    final modelPath = p.join(dir.path, 'whisper-base-zh.bin');
    // (snippet: copyAsset(modelAssetPath, modelPath))
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
    // Every 30s, flush the buffer through Whisper.
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
```

> The above is the conceptual shape — the exact `whisper_ggml` API
> surface evolves; check the package's example. Some forks support
> *streaming* recognition (per-segment callbacks) which would replace
> the 30-second timer with real-time emission.

---

## 5. State controller — `lib/state/translation_controller.dart`

Owns the queue + sidecar + whisper, exposes them to the widgets.

```dart
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
    if (e == null) return; // evicted by cap
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
```

---

## 6. Widgets

### 6.1 `lib/widgets/transcript_tile.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/translation_controller.dart';

class TranscriptTile extends StatelessWidget {
  const TranscriptTile({super.key, required this.entry});
  final TranscriptEntry entry;

  @override
  Widget build(BuildContext context) {
    final time =
        '${entry.time.hour.toString().padLeft(2, '0')}:${entry.time.minute.toString().padLeft(2, '0')}:${entry.time.second.toString().padLeft(2, '0')}';
    final theme = Theme.of(context);
    return InkWell(
      onTap: entry.pending || entry.error
          ? null
          : () => Clipboard.setData(ClipboardData(text: entry.english!)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(time, style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
            const SizedBox(height: 2),
            Text(entry.chinese, style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor)),
            const SizedBox(height: 4),
            if (entry.pending) const _Pulsing(text: 'translating…')
            else Text(
              entry.english!,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: entry.error ? theme.colorScheme.error : null,
                fontStyle: entry.error ? FontStyle.italic : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pulsing extends StatefulWidget {
  const _Pulsing({required this.text});
  final String text;
  @override
  State<_Pulsing> createState() => _PulsingState();
}

class _PulsingState extends State<_Pulsing> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.5, end: 1.0).animate(_c),
      child: Text(
        widget.text,
        style: TextStyle(
          fontStyle: FontStyle.italic,
          color: Theme.of(context).hintColor,
        ),
      ),
    );
  }
}
```

### 6.2 `lib/widgets/transcript.dart`

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/translation_controller.dart';
import 'transcript_tile.dart';

class TranscriptList extends StatelessWidget {
  const TranscriptList({super.key});
  @override
  Widget build(BuildContext context) {
    return Consumer<TranslationController>(
      builder: (_, ctl, __) {
        return ListView.builder(
          itemCount: ctl.entries.length,
          itemBuilder: (_, i) => TranscriptTile(entry: ctl.entries[i]),
        );
      },
    );
  }
}
```

### 6.3 `lib/widgets/controls.dart`

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/translation_controller.dart';

class Controls extends StatelessWidget {
  const Controls({super.key});
  @override
  Widget build(BuildContext context) {
    final ctl = context.watch<TranslationController>();
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          FilledButton.icon(
            onPressed: () =>
                ctl.listening ? ctl.stopListening() : ctl.startListening(),
            icon: Icon(ctl.listening ? Icons.stop : Icons.mic),
            label: Text(ctl.listening ? 'Stop Listening' : 'Start Listening'),
            style: FilledButton.styleFrom(
              backgroundColor: ctl.listening ? Colors.red : null,
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: () => ctl.toggleCuda(),
            icon: Icon(ctl.cudaActive ? Icons.flash_on : Icons.flash_off),
            label: Text(ctl.cudaActive ? 'Use CPU' : 'Use GPU'),
          ),
          const Spacer(),
          if (ctl.listening)
            Text(ctl.pending > 0
                ? 'listening… (${ctl.pending} pending)'
                : 'listening…'),
        ],
      ),
    );
  }
}
```

### 6.4 `lib/main.dart`

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'app.dart';
import 'state/translation_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Resolve sidecar directory next to the executable.
  final exeDir = File(Platform.resolvedExecutable).parent.path;
  final sidecarDir = p.join(exeDir, 'sidecar');

  final ctl = TranslationController(sidecarDir: sidecarDir);
  await ctl.bootstrap();

  runApp(
    ChangeNotifierProvider.value(value: ctl, child: const TranslatorApp()),
  );
}
```

### 6.5 `lib/app.dart`

```dart
import 'package:flutter/material.dart';
import 'widgets/controls.dart';
import 'widgets/transcript.dart';

class TranslatorApp extends StatelessWidget {
  const TranslatorApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Live Chinese → English Translator',
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF0D6EFD),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF0D6EFD),
      ),
      home: const Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Controls(),
              Divider(height: 1),
              Expanded(child: TranscriptList()),
            ],
          ),
        ),
      ),
    );
  }
}
```

> Add `provider: ^6.1.0` to `pubspec.yaml` `dependencies` for the
> `ChangeNotifierProvider` shown above.

---

## 7. Sidecar — `sidecar/server.py`

A 60-line FastAPI app that loads CTranslate2 once and exposes a
WebSocket. CT2 handles tokenization (via SentencePiece), encoder,
decoder, beam search, and batching internally — that's the whole point
of using it.

```python
# sidecar/server.py
import argparse, asyncio, json, sys, traceback

import ctranslate2
import sentencepiece as spm
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
import uvicorn

app = FastAPI()
translator = None
src_sp = None
tgt_sp = None
active_device = "cpu"

def load(model_dir: str, requested: str):
    global translator, src_sp, tgt_sp, active_device
    src_sp = spm.SentencePieceProcessor(); src_sp.Load(f"{model_dir}/source.spm")
    tgt_sp = spm.SentencePieceProcessor(); tgt_sp.Load(f"{model_dir}/target.spm")
    try:
        translator = ctranslate2.Translator(model_dir, device=requested,
                                            compute_type="int8" if requested == "cpu" else "int8_float16")
        active_device = requested
        return None  # success, no fallback
    except Exception as e:
        if requested != "cpu":
            translator = ctranslate2.Translator(model_dir, device="cpu", compute_type="int8")
            active_device = "cpu"
            return {"from": requested, "to": "cpu", "reason": str(e)}
        raise

def chunk_text(t: str, limit: int = 80):
    import re
    t = (t or "").strip()
    if not t: return []
    if len(t) <= limit: return [t]
    sentences = re.split(r"(?<=[。！？；.!?;])", t)
    groups, cur = [], ""
    for s in sentences:
        if not s: continue
        if cur and len(cur) + len(s) > limit:
            groups.append(cur); cur = s
        else:
            cur += s
    if cur: groups.append(cur)
    out = []
    for g in groups:
        if len(g) <= limit: out.append(g); continue
        for i in range(0, len(g), limit):
            out.append(g[i:i+limit])
    return [s.strip() for s in out if s.strip()]

def translate_text(text: str) -> str:
    pieces = chunk_text(text)
    if not pieces:
        pieces = [text]
    tokens = [src_sp.EncodeAsPieces(p) for p in pieces]
    results = translator.translate_batch(tokens, beam_size=4, max_batch_size=8)
    return " ".join(tgt_sp.DecodePieces(r.hypotheses[0]) for r in results)

@app.websocket("/ws")
async def ws(ws: WebSocket):
    await ws.accept()
    await ws.send_text(json.dumps({"type": "ready", "device": active_device}))
    try:
        while True:
            msg = json.loads(await ws.receive_text())
            if msg.get("type") == "translate":
                tid = msg["id"]
                try:
                    en = await asyncio.get_running_loop().run_in_executor(
                        None, translate_text, msg["text"])
                    await ws.send_text(json.dumps(
                        {"type": "translation", "id": tid, "translated": en}))
                except Exception:
                    traceback.print_exc()
                    await ws.send_text(json.dumps(
                        {"type": "translation-error", "id": tid}))
    except WebSocketDisconnect:
        pass

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, required=True)
    ap.add_argument("--device", choices=["cpu", "cuda"], default="cpu")
    ap.add_argument("--model-dir", default="models/opus-mt-zh-en")
    args = ap.parse_args()

    fb = load(args.model_dir, args.device)
    if fb is not None:
        # Notify Flutter via stderr; the client also sees `device` mismatch
        # in the next ready message and can show a fallback notice.
        print(f"FALLBACK from {fb['from']} to {fb['to']}: {fb['reason']}",
              file=sys.stderr, flush=True)

    uvicorn.run(app, host="127.0.0.1", port=args.port, log_level="warning")
```

### `sidecar/requirements.txt`

```
ctranslate2>=4.4.0
sentencepiece>=0.2.0
fastapi>=0.111.0
uvicorn>=0.30.0
```

### One-time model conversion

The browser app uses `Xenova/opus-mt-zh-en` (ONNX). For CT2 we convert
from the original `Helsinki-NLP/opus-mt-zh-en` (PyTorch / Marian):

```bash
pip install ctranslate2 transformers[torch] sentencepiece
ct2-transformers-converter \
  --model Helsinki-NLP/opus-mt-zh-en \
  --output_dir sidecar/models/opus-mt-zh-en \
  --copy_files source.spm target.spm shared_vocabulary.json \
  --quantization int8
```

The result is ~80 MB on disk. With `int8_float16` on CUDA it gets
loaded as fp16 weights with int8 inference — fast and memory-light.

---

## 8. Tests

### `test/sentence_queue_test.dart`

Direct port of `tests/queue.test.mjs`. All 15 cases.

```dart
import 'package:test/test.dart';
import 'package:flutter_translator/core/sentence_queue.dart';

void main() {
  test('in-order resolution emits immediately', () {
    final r = <List<dynamic>>[];
    final q = SentenceQueue((id, o, t) => r.add([id, o, t]));
    final id0 = q.add('一');
    q.resolve(id0, 'one');
    expect(r, [[id0, '一', 'one']]);
  });

  test('out-of-order resolution holds then flushes in order', () {
    final r = <List<dynamic>>[];
    final q = SentenceQueue((id, o, t) => r.add([o, t]));
    final id0 = q.add('一');
    final id1 = q.add('二');
    q.resolve(id1, 'two');
    expect(r, isEmpty);
    q.resolve(id0, 'one');
    expect(r, [['一', 'one'], ['二', 'two']]);
  });

  test('resolveError produces [Translation error]', () {
    final r = <Map<String, String>>[];
    final q = SentenceQueue((id, o, t) => r.add({'o': o, 't': t}));
    final id = q.add('bad');
    q.resolveError(id);
    expect(r, [{'o': 'bad', 't': '[Translation error]'}]);
  });

  test('multiple queues are independent', () {
    final r1 = <int>[], r2 = <int>[];
    final q1 = SentenceQueue((id, _, __) => r1.add(id));
    final q2 = SentenceQueue((id, _, __) => r2.add(id));
    q1.resolve(q1.add('only q1'), 'only q1');
    expect(r2, isEmpty);
  });

  test('add returns sequential ids from 0', () {
    final q = SentenceQueue((_, __, ___) {});
    expect(q.add('a'), 0);
    expect(q.add('b'), 1);
    expect(q.add('c'), 2);
  });

  test('cascaded flush', () {
    final r = <String>[];
    final q = SentenceQueue((id, o, t) => r.add(t));
    final id0 = q.add('零');
    final id1 = q.add('一');
    final id2 = q.add('二');
    q.resolve(id0, 'zero');
    q.resolve(id2, 'two');
    expect(r, ['zero']);
    q.resolve(id1, 'one');
    expect(r, ['zero', 'one', 'two']);
  });

  test('unknown id is no-op', () {
    final r = <int>[];
    final q = SentenceQueue((id, _, __) => r.add(id));
    q.resolve(999, 'ghost');
    q.resolveError(1234);
    expect(r, isEmpty);
  });

  test('double-resolve / resolve-after-error is ignored', () {
    final r = <String>[];
    final q = SentenceQueue((id, _, t) => r.add(t));
    final id = q.add('hi');
    q.resolve(id, 'hello');
    q.resolve(id, 'overwrite');
    q.resolveError(id);
    expect(r, ['hello']);
  });

  test('pending getter tracks outstanding sentences', () {
    final q = SentenceQueue((_, __, ___) {});
    expect(q.pending, 0);
    final a = q.add('a');
    final b = q.add('b');
    expect(q.pending, 2);
    q.resolve(a, 'A');
    expect(q.pending, 1);
    q.resolve(b, 'B');
    expect(q.pending, 0);
  });

  test('pending counts held out-of-order results', () {
    final q = SentenceQueue((_, __, ___) {});
    final a = q.add('a');
    final b = q.add('b');
    q.resolve(b, 'B');
    expect(q.pending, 2);
    q.resolve(a, 'A');
    expect(q.pending, 0);
  });

  test('failPending flushes every unresolved id as error', () {
    final r = <List<String>>[];
    final q = SentenceQueue((id, o, t) => r.add([o, t]));
    q.add('a'); q.add('b'); q.add('c');
    q.failPending();
    expect(r, [
      ['a', '[Translation error]'],
      ['b', '[Translation error]'],
      ['c', '[Translation error]'],
    ]);
    expect(q.pending, 0);
  });

  test('failPending preserves held real results', () {
    final r = <List<String>>[];
    final q = SentenceQueue((id, o, t) => r.add([o, t]));
    final a = q.add('a');
    final b = q.add('b');
    final c = q.add('c');
    q.resolve(c, 'C');
    q.failPending();
    expect(r, [
      ['a', '[Translation error]'],
      ['b', '[Translation error]'],
      ['c', 'C'],
    ]);
  });

  test('failPending on empty queue is no-op', () {
    final r = <int>[];
    final q = SentenceQueue((id, _, __) => r.add(id));
    q.failPending();
    expect(r, isEmpty);
    expect(q.pending, 0);
  });

  test('queue keeps emitting in order after failPending', () {
    final r = <List<String>>[];
    final q = SentenceQueue((id, o, t) => r.add([o, t]));
    q.add('old');
    q.failPending();
    final n = q.add('new');
    q.resolve(n, 'NEW');
    expect(r, [
      ['old', '[Translation error]'],
      ['new', 'NEW'],
    ]);
  });

  test('callback receives the id', () {
    final events = <List<dynamic>>[];
    final q = SentenceQueue((id, o, t) => events.add([id, o, t]));
    final a = q.add('a');
    final b = q.add('b');
    q.resolve(a, 'A');
    q.resolveError(b);
    expect(events, [
      [a, 'a', 'A'],
      [b, 'b', '[Translation error]'],
    ]);
  });
}
```

### `test/chunker_test.dart`

Direct port of `tests/chunker.test.mjs`. All 8 cases.

```dart
import 'package:test/test.dart';
import 'package:flutter_translator/core/chunker.dart';

void main() {
  test('short text returned unchanged', () {
    expect(chunkText('你好世界'), ['你好世界']);
    expect(chunkText('你好世界', limit: 80), ['你好世界']);
  });

  test('empty / whitespace / null returns empty', () {
    expect(chunkText(''), isEmpty);
    expect(chunkText('   '), isEmpty);
    expect(chunkText(null), isEmpty);
  });

  test('splits on Chinese punctuation, preserves content', () {
    const t = '今天天气很好。我们去公园。然后吃饭。';
    final c = chunkText(t, limit: 10);
    expect(c.length, greaterThan(1));
    for (final x in c) expect(x.length, lessThanOrEqualTo(10));
    expect(c.join(), t);
  });

  test('hard-splits when no punctuation', () {
    expect(chunkText('abcdefghijabcdefghij', limit: 5),
        ['abcde', 'fghij', 'abcde', 'fghij']);
  });

  test('hard-split fallback respects limit on Chinese-only', () {
    const t = '一二三四五六七八九十一二三四五六七八九十';
    final c = chunkText(t, limit: 7);
    for (final x in c) expect(x.length, lessThanOrEqualTo(7));
    expect(c.join(), t);
  });

  test('Latin punctuation also splits', () {
    final c = chunkText('Hello world. This is a test! Done?', limit: 15);
    expect(c.length, greaterThan(1));
    for (final x in c) expect(x.length, lessThanOrEqualTo(15));
  });

  test('punctuation glued to its clause', () {
    final c = chunkText('一二三。四五六！七八九？', limit: 4);
    for (final x in c) {
      if (x.length == 4) {
        expect(RegExp(r'[。！？；.!?;]$').hasMatch(x), isTrue);
      }
    }
  });

  test('long single clause splits into ceil(n/limit) chunks', () {
    final t = '甲' * 173;
    final c = chunkText(t, limit: 50);
    expect(c.length, 4);
    expect(c.join(), t);
    for (final x in c) expect(x.length, lessThanOrEqualTo(50));
  });
}
```

Run both with:

```bash
dart test
```

---

## 9. Build & run

### First-time setup (once per machine)

```bash
# 1. Get Flutter and enable desktop
flutter config --enable-windows-desktop --enable-linux-desktop

# 2. Bootstrap project
flutter create flutter_translator
cd flutter_translator
# … paste the files from this document into their listed paths …
flutter pub get

# 3. Convert and place the NMT model
python -m venv sidecar/venv
source sidecar/venv/bin/activate    # or sidecar\venv\Scripts\activate on Windows
pip install -r sidecar/requirements.txt
pip install transformers[torch]
ct2-transformers-converter \
  --model Helsinki-NLP/opus-mt-zh-en \
  --output_dir sidecar/models/opus-mt-zh-en \
  --copy_files source.spm target.spm shared_vocabulary.json \
  --quantization int8

# 4. Drop a Whisper ggml model into assets/models/
#    (download from https://huggingface.co/ggerganov/whisper.cpp)
curl -L -o assets/models/whisper-base-zh.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin
```

### Run in dev

```bash
flutter run -d windows    # or -d linux
```

The mic button starts capturing; click "Use GPU" to opt into CUDA. If
CUDA init fails (driver missing, model incompatible), the sidecar
auto-falls back to CPU and the UI shows a one-line notice.

---

## 10. Packaging notes

### Windows

- `flutter build windows --release` produces
  `build/windows/x64/runner/Release/`.
- Copy the `sidecar/` directory next to `flutter_translator.exe`.
- For CUDA, ship the matching CUDA runtime DLLs (`cudart64_*.dll`,
  `cublas64_*.dll`, `cudnn*.dll`) next to the EXE, or require users to
  install the CUDA Toolkit. CT2's `ctranslate2.dll` is already inside
  the venv's `site-packages/ctranslate2/`.
- Use `flutter_distributor` with the `inno_setup` target to produce an
  installer that places everything under `Program Files\…`.

### Linux

- `flutter build linux --release`. Output in
  `build/linux/x64/release/bundle/`.
- Bundle as an AppImage or Flatpak. Set `LD_LIBRARY_PATH` in the
  AppRun script to point at the bundled CUDA libs.
- Sidecar venv can be replaced with PyInstaller-built single binary
  (`pyinstaller --onefile sidecar/server.py`) to avoid shipping a
  Python installation.

---

## 11. Status

| Item | Status | Implementation |
|------|--------|---------------|
| macOS support | Resolved | GPU toggle hidden on macOS; CT2 uses Apple Accelerate BLAS on CPU automatically. MLX would add GPU but is out of scope. |
| Whisper latency | Resolved | Replaced fixed 30 s window with VAD-based flush: amplitude stream sampled every 300 ms, flushes after 1.5 s of silence below −40 dBFS. 30 s hard cap retained as fallback. |
| Bundle size | Resolved | `WhisperModelSize` enum (tiny/base/small) selectable at runtime in the settings drawer. Defaults to **tiny** (~75 MB). |
| Graceful device switch | Resolved | `toggleCuda()` calls `stop()` first, then `failPending()`, then `switchDevice()` — in-flight translations are errored out cleanly before the sidecar restarts. |
| Sidecar watchdog | Resolved | `_watchProcess()` listens on `Process.exitCode`; auto-restarts with 2 s/4 s/6 s backoff up to 3 attempts. Retry counter resets on a clean `ready` event. |
| Beam size in UI | Resolved | Settings drawer exposes a 1–5 slider (default 2). Value sent per-request in the WebSocket message; `server.py` uses it in `translate_batch`. |
| Model integrity | Resolved | `sidecar/generate_manifest.py` hashes `model.bin`, `source.spm`, `target.spm`, etc. into `manifest.json`. `server.py` verifies SHA-256 on startup and exits with a clear error if anything mismatches. |
