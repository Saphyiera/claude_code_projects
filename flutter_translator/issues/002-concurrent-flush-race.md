# 002 — Concurrent VAD + hard-cap flush corrupts the wav file

**Severity:** critical
**File:** `lib/core/whisper_isolate.dart`

## Symptom

Occasional silent drops in the transcript when speaking continuously
for ~30 s. On Windows the `record` plugin throws "file is being used by
another process". On Linux/macOS the wav file is sometimes truncated to
0 bytes and Whisper returns empty.

## Cause

Two timers can call `_flush()` at the same instant: the amplitude
listener (running every 300 ms) and the hard-cap `Timer.periodic`
(every 30 s). Both call `_record.stop()` then `_record.start()` to the
**same path**. The two stop/start sequences interleave — one closes the
file, the other tries to write to it, the third opens a fresh recorder
and the second's restart bombs.

## Fix

Two changes:

1. Serialize all flushes through a `_flushing` guard so only one is in
   flight at a time. Subsequent flush calls skip with no-op.
2. Rotate the wav path so the file we hand to Whisper is never the file
   the recorder is currently writing to.

```dart
bool _flushing = false;
int _wavSeq = 0;

Future<void> _flush({bool final_ = false}) async {
  if (_flushing) return;
  _flushing = true;
  try {
    final path = await _record.stop();
    if (_running && !final_) {
      _wavSeq++;
      await _record.start(_config, path: _wavPathFor(_wavSeq));
    }
    if (path != null) await _transcribe(path);
  } finally {
    _flushing = false;
  }
}
```

This also resolves issue 015 (Windows handle delay).
