# 010 — Concurrent start() calls aren't guarded

**Severity:** medium
**File:** `lib/core/sidecar_client.dart`

## Symptom

A rapid GPU/CPU toggle (double-click) can spawn two Python processes
because `start()` is awaited but the second call is initiated before
the first has set `_proc`.

## Fix

Track an in-flight start operation and short-circuit:

```dart
Future<void>? _starting;

Future<void> start() async {
  if (_starting != null) return _starting;
  _starting = _doStart();
  try { await _starting; } finally { _starting = null; }
}

Future<void> _doStart() async { ... actual start logic ... }
```
