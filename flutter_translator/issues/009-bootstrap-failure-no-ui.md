# 009 — bootstrap() failures kill the app with no error UI

**Severity:** high
**File:** `lib/main.dart`

## Symptom

If the sidecar's Python venv is missing, the model isn't downloaded, or
the user denied microphone permission, `bootstrap()` throws and `runApp`
is never reached. The user sees a frozen splash for a few seconds, then
the window closes.

## Cause

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ...
  final ctl = TranslationController(sidecarDir: sidecarDir);
  await ctl.bootstrap();   // <- throws → uncaught → app dies
  runApp(...);
}
```

## Fix

Run the app first with a loading state, then run `bootstrap()` and let
the controller surface the error to the UI. Or wrap in try/catch and
show a fallback Scaffold:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final ctl = TranslationController(sidecarDir: sidecarDir);
  runApp(ChangeNotifierProvider.value(value: ctl, child: const TranslatorApp()));
  // Bootstrap in the background; controller exposes an `initError` / `ready` flag.
  ctl.bootstrap();
}
```

`TranslationController` then needs `bool ready` and
`String? initError` getters that drive an alternate widget when not
ready.
