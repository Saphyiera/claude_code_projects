# 014 — Translate request without `id` crashes the server loop

**Severity:** medium
**File:** `sidecar/server.py`

## Symptom

A malformed message (e.g., `{"type": "translate", "text": "..."}`
missing `id`) raises `KeyError: 'id'`, which propagates out of the
`while True` loop, the `finally` runs, and the connection closes. The
sidecar itself stays up, but every in-flight translation on that
connection is lost.

## Cause

```python
tid = msg["id"]      # KeyError if absent
beam = int(msg.get("beam_size", 2))
...
translated = ...
```

Only the inner translation is in a try/except.

## Fix

Validate the payload before doing work, treat missing keys as a
client-side error:

```python
tid = msg.get("id")
text = msg.get("text")
if tid is None or text is None:
    # protocol error — log and drop, but don't tear the connection down
    print("[sidecar] dropped malformed translate", file=sys.stderr)
    continue
```

Also wrap the whole `while True` body in a try/except for any other
unforeseen error so a single bad message can't kill the connection.
