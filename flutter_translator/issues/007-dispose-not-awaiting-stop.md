# 007 — dispose() doesn't await stop(); events may fire after StreamController close

**Severity:** high
**File:** `lib/core/sidecar_client.dart`

## Symptom

When the app shuts down, intermittent `Bad state: Cannot add event after
closing` is logged from the Dart VM. On hot reload during dev, the same
exception spams the console.

## Cause

```dart
void dispose() {
  stop();           // returns Future<void>, NOT awaited
  _events.close();  // runs immediately
}
```

`stop()` schedules SIGTERM and WS close. The WS subscription's
`onError` / `onDone` callbacks may fire AFTER `_events.close()`, so
they hit a closed StreamController.

## Fix

Make `dispose()` async and await the teardown. Also guard the
StreamController against double-add:

```dart
bool _disposed = false;

Future<void> dispose() async {
  _disposed = true;
  await stop();
  await _events.close();
}

void _emit(SidecarEvent e, Map<String, dynamic> p) {
  if (_disposed || _events.isClosed) return;
  _events.add(SidecarMessage(e, p));
}
```

Replace every `_events.add(...)` call with `_emit(...)`.
