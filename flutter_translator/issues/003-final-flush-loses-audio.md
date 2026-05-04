# 003 — Final stop() flush throws away the last audio buffer

**Severity:** critical
**File:** `lib/core/whisper_isolate.dart`

## Symptom

Click "Stop Listening" mid-sentence — the last 0–30 s of speech
disappears from the transcript.

## Cause

```dart
Future<void> stop() async {
  _running = false;
  ...
  await _record.stop();          // <- gets the final wav path P, but discards it
  await _flush(final_: true);    // <- _flush calls _record.stop() AGAIN, returns null
}
```

Inside `_flush`, the second `_record.stop()` returns `null` (recorder
already stopped). Then `if (path == null) return;` — the
transcription never runs.

## Fix

Don't call `_record.stop()` twice. Capture the path once in `stop()`
and pass it directly to `_transcribe()`:

```dart
Future<void> stop() async {
  _running = false;
  _hardCapTimer?.cancel();
  _ampSub?.cancel();
  await _ampSub?.cancel();
  final path = await _record.stop();
  if (path != null) await _transcribe(path);
}
```

Refactor `_flush` so the file → transcription step is shared via a
private `_transcribe(path)` helper.
