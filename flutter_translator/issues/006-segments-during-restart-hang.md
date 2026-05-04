# 006 — New segments during sidecar restart hang as "translating…" forever

**Severity:** high
**File:** `lib/state/translation_controller.dart`

## Symptom

While the sidecar is restarting (GPU toggle, watchdog auto-restart, or
crash), Whisper keeps emitting segments. Each gets enqueued, but
`SidecarClient.translate()` finds `_ws == null` and silently drops the
message. Those entries are stuck pending forever.

## Cause

```dart
void _onSegment(String chinese) {
  final id = _queue.add(chinese);
  ...
  _sidecar.translate(id, chinese);   // <- silently no-op if disconnected
  notifyListeners();
}
```

There's no feedback path from `translate()` saying "I couldn't send
this." The queue retains the entry, the UI shows "translating…", the
sidecar comes back, but the original request was never on the wire.

## Fix

Have `SidecarClient.translate(id, text)` return `bool` — `true` if
the message was sent, `false` if not. The controller resolves the
queue entry as an error when the send fails:

```dart
void _onSegment(String chinese) {
  final id = _queue.add(chinese);
  ...
  final sent = _sidecar.translate(id, chinese);
  if (!sent) _queue.resolveError(id);
  notifyListeners();
}
```

The user sees `[Translation error]` instead of an indefinite spinner;
they can speak again once the status banner clears.
