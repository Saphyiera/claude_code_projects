# 013 — `_waitForPort` 30 s timeout may be too short for large models

**Severity:** medium
**File:** `lib/core/sidecar_client.dart`

## Symptom

First-time launch with the `small` whisper model + opus-mt model can
take >30 s on a cold disk (model load + manifest hash). `start()`
throws `TimeoutException` and the watchdog kicks in, repeatedly
killing a half-loaded sidecar before it gets a chance to bind the
port.

## Cause

```dart
static Future<void> _waitForPort(int port,
    {Duration timeout = const Duration(seconds: 30)}) async { ... }
```

30 s is not enough headroom when:
- model file is on a spinning disk,
- manifest verification streams every byte through SHA-256 (already
  fast but still measurable on 500 MB models),
- CT2 first-run JIT-compiles kernels.

## Fix

Bump the default to 120 s. That's still bounded — if the sidecar truly
crashed before binding, the process exit watchdog handles it. The port
wait shouldn't fail on slow load.

Better: have the sidecar print a "BOOTING" line on stderr that the
client uses to extend the deadline incrementally. Out of scope; bumping
the constant is enough.
