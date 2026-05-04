# 008 — reinit() doesn't dispose the old Whisper instance

**Severity:** high
**File:** `lib/core/whisper_isolate.dart`

## Symptom

Switching whisper model size in settings (tiny → base → small) causes
RAM to grow by the size of each model loaded. After three switches,
~700 MB of native memory is held with no way to reclaim it short of
restarting the app.

## Cause

```dart
Future<void> reinit(WhisperModelSize newSize) async {
  await stop();
  modelSize = newSize;
  _whisper = Whisper(model: newSize.ggmlModel);   // old _whisper just dropped
  ...
}
```

`whisper_ggml`'s `Whisper` wraps a native context allocated via
`whisper_init_from_file`. The Dart object becoming unreferenced does
**not** automatically free that context.

## Fix

The `whisper_ggml` package exposes a `release()` / `free()` method on
the model. Call it before replacing.

```dart
await _whisper?.release();
_whisper = Whisper(model: newSize.ggmlModel);
```

(Exact API name varies by package version — check `Whisper`'s public
interface for `dispose`/`release`/`free` and use the available one.)
