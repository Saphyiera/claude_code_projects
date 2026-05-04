# 001 — Watchdog race spawns duplicate sidecars on device switch

**Severity:** critical
**File:** `lib/core/sidecar_client.dart`

## Symptom

Toggling GPU/CPU intermittently leaves multiple Python processes
running, each holding a CUDA context. After two or three toggles the
machine OOMs. On Windows the orphan processes block the model file and
the next start fails with a "file in use" error.

## Cause

`stop()` sets `_intentionalStop = true` and SIGTERMs the process, then
`start()` immediately resets `_intentionalStop = false`. The previous
process's `exitCode` future has not resolved yet — when it eventually
does, `_watchProcess`'s closure reads the **current** value of the
flag, which is now `false`, and triggers a redundant retry.

```
P1 alive, _intentionalStop=false, watchdog W1 registered on P1.exitCode
↓ user toggles
stop()  : _intentionalStop=true; SIGTERM P1; _proc=null
start() : _intentionalStop=false; spawn P2; _proc=P2; watchdog W2 registered
... time passes ...
P1 finally exits → W1 fires → reads _intentionalStop (false!) → retry
                            → start() spawns P3 → orphan P2 left running
```

## Fix

The watchdog must reason about the process *it was registered on*, not
the current `_proc` slot. Capture the `Process` reference inside the
closure, and only retry if `_proc` is still that process at the time
the exit fires. `_intentionalStop` can be removed.

```dart
void _watchProcess(Process proc) {
  proc.exitCode.then((code) {
    if (!identical(_proc, proc)) return;   // already replaced
    _proc = null;
    if (_disposed) return;
    if (_retryCount < _maxRetries) { ... schedule restart ... }
  });
}
```

`switchDevice` then doesn't need any flag dance — `stop()` reassigns
`_proc = null`, the `identical` check on the old proc fails, the
watchdog quietly exits.
