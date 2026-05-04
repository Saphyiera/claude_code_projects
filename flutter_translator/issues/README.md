# Code Review Findings

Pass over `flutter_translator/` reading every source file in isolation.
Each issue is its own file. Severity: **critical** (data loss, hangs,
duplicate processes), **high** (memory leak, broken UX), **medium**
(degraded behaviour), **low** (cosmetic / hygiene).

| ID | File | Severity | Title | Fixed |
|----|------|----------|-------|:----:|
| 001 | sidecar_client.dart | critical | Watchdog race spawns duplicate sidecars on device switch | yes |
| 002 | whisper_isolate.dart | critical | Concurrent VAD + hard-cap flush corrupts the wav file | yes |
| 003 | whisper_isolate.dart | critical | Final stop() flush throws away the last audio buffer | yes |
| 004 | whisper_isolate.dart | high | Amplitude listener leaked on every start/stop cycle | yes |
| 005 | sidecar_client.dart | high | WebSocket onDone unhandled — translate silently no-ops after clean close | yes |
| 006 | translation_controller.dart | high | New segments during sidecar restart hang as "translating…" forever | yes |
| 007 | sidecar_client.dart | high | dispose() doesn't await stop(); events may fire after StreamController close | yes |
| 008 | whisper_isolate.dart | high | reinit() doesn't dispose the old Whisper instance (native memory leak) | yes |
| 009 | main.dart | high | bootstrap() failures kill the app with no error UI | yes |
| 010 | sidecar_client.dart | medium | Concurrent start() calls aren't guarded | yes |
| 011 | sidecar_client.dart | medium | Detached child process leaks if Flutter app crashes | partial |
| 012 | sidecar_client.dart | medium | stderr printed in chunk boundaries, not lines | yes |
| 013 | server.py | medium | `_waitForPort` 30 s default may be too short for large models | yes |
| 014 | server.py | medium | Translate request without `id` crashes the server loop | yes |
| 015 | whisper_isolate.dart | medium | WAV path reused — Windows handle delay can fail back-to-back start | yes |
| 016 | pubspec.yaml | low | Unused dependencies (`process_run`, `ffi`, `cupertino_icons`) | yes |
