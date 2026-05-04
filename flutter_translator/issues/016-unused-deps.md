# 016 — Unused dependencies in pubspec.yaml

**Severity:** low (hygiene)
**File:** `pubspec.yaml`

## Symptom

`pub get` pulls down `process_run`, `ffi`, and `cupertino_icons`, none
of which are actually imported anywhere in `lib/`. They inflate the
build, the lockfile, and the dependency tree.

## Fix

Remove from `pubspec.yaml`:

```yaml
# delete these:
cupertino_icons: ^1.0.8     # we use Material icons only
process_run: ^1.1.0         # never imported
ffi: ^2.1.3                 # never imported
```

Keep `path` (used in main.dart and sidecar_client.dart),
`whisper_ggml`, `record`, `web_socket_channel`, `path_provider`,
`provider`.
