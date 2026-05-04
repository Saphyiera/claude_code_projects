# 015 — WAV path reused; Windows handle delay can fail back-to-back start

**Severity:** medium
**File:** `lib/core/whisper_isolate.dart`

## Symptom

On Windows, intermittent "ERROR: file is being used by another
process" when `_flush()` runs, because the recorder writes to and
reads from the **same** path `rolling.wav` between stop and start.

## Cause

```dart
_wavPath = p.join(dir.path, 'rolling.wav');
...
await _record.start(..., path: _wavPath!);   // same path every time
```

Windows file handles aren't released synchronously when a writer
closes — there's a brief window during which the path is still locked.
A back-to-back `_record.stop()` → `_record.start()` to the same path
hits that window often.

## Fix

Rotate the path. Since issue 002 already requires a `_wavSeq` counter
to avoid concurrent overwrites, reuse it:

```dart
String _wavPathFor(int seq) => p.join(_dir, 'rolling-$seq.wav');
```

Whisper transcribes the just-written file (path returned by `stop`),
the recorder writes the next chunk to a fresh path. Old files can be
deleted after transcription.
