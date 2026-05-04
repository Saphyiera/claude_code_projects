# 011 — Detached child Python process leaks if Flutter app crashes

**Severity:** medium
**File:** `lib/core/sidecar_client.dart`

## Symptom

If the Flutter app is force-killed (Task Manager / `kill -9`), the
detached Python sidecar continues to run, holding the GPU and the
model file. Subsequent app launches conflict.

## Cause

```dart
mode: ProcessStartMode.detachedWithStdio,
```

`detached*` modes deliberately decouple the child's lifetime from the
parent. The child becomes a session leader, signals don't propagate.

## Fix (partial)

Switch to `ProcessStartMode.normal` so the child shares the parent's
process group on Unix. SIGTERM/SIGKILL on the parent reaches the child
via group propagation. On Windows there is no signal, but Job Objects
provide the same guarantee — adding that requires a small `dart:ffi`
binding to `AssignProcessToJobObject`, which is out of scope for this
fix. Document the gap.

Trade-off: with `normal` mode, the child inherits stdin/stdout. We
need to keep the stderr drain and explicitly redirect stdin to
`/dev/null` (or close it) so the Python interpreter doesn't read input.
