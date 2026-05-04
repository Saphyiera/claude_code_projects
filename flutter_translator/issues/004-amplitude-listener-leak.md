# 004 — Amplitude listener leaked on every start/stop cycle

**Severity:** high
**File:** `lib/core/whisper_isolate.dart`

## Symptom

CPU usage rises every time the user starts and stops listening. After
the 10th cycle, the VAD callback runs ten times per tick, each one
trying to flush. Combined with issue 002, this is a fast path to the
race.

## Cause

```dart
_record.onAmplitude(...).listen((amp) { ... });
```

The returned `StreamSubscription` is never stored or cancelled. Every
`start()` adds a new listener; `stop()` doesn't remove any.

## Fix

Hold the subscription, cancel it on stop:

```dart
StreamSubscription<Amplitude>? _ampSub;

Future<void> start() async {
  ...
  _ampSub = _record.onAmplitude(...).listen(...);
}

Future<void> stop() async {
  await _ampSub?.cancel();
  _ampSub = null;
  ...
}
```
