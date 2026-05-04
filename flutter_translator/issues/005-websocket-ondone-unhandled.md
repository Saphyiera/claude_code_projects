# 005 — WebSocket onDone unhandled — translate silently no-ops after clean close

**Severity:** high
**File:** `lib/core/sidecar_client.dart`

## Symptom

If the sidecar exits cleanly (e.g., user kills it from Task Manager,
or it self-terminates on a fatal CT2 error that triggers `WebSocketDisconnect`
on the server side without crashing), the Flutter client has a stale
`_ws` handle. New `translate()` calls silently `_ws?.sink.add(...)`
into a closed channel. UI shows "translating…" forever.

## Cause

```dart
_ws!.stream.listen(_onMessage, onError: (e) { ... });
```

No `onDone` handler. On clean WS close, the stream just ends; nothing
notifies the watchdog or the controller. The process exit watchdog
*will* eventually fire and start a retry, but before that, every
incoming segment is dropped on the floor.

## Fix

Add `onDone` and treat it as an error (the sidecar shouldn't close the
WS while we still want to talk):

```dart
_ws!.stream.listen(
  _onMessage,
  onError: (e) => _events.add(SidecarMessage(SidecarEvent.error, {'reason': '$e'})),
  onDone: () {
    _ws = null;
    _events.add(SidecarMessage(SidecarEvent.error, {'reason': 'sidecar disconnected'}));
  },
);
```

`translate()` should also short-circuit and emit `translationError`
when `_ws == null`, so the UI doesn't hang.
