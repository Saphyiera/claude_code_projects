# 012 — stderr printed in chunk boundaries, not lines

**Severity:** medium (cosmetic)
**File:** `lib/core/sidecar_client.dart`

## Symptom

Sidecar stderr is logged with arbitrary line splits — sometimes two
messages share a line, sometimes a single message spans two `print`
calls. Hard to grep.

## Cause

```dart
_proc!.stderr.transform(utf8.decoder).listen((line) { ... });
```

`utf8.decoder` doesn't promise line boundaries; it just decodes bytes.
Whatever chunk arrived from the OS pipe is what `line` contains.

## Fix

Add `LineSplitter`:

```dart
_proc!.stderr
    .transform(utf8.decoder)
    .transform(const LineSplitter())
    .listen((line) => print('[sidecar] $line'));
```
