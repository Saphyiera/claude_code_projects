import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'app.dart';
import 'state/translation_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final exeDir = File(Platform.resolvedExecutable).parent.path;
  final sidecarDir = p.join(exeDir, 'sidecar');

  final ctl = TranslationController(sidecarDir: sidecarDir);

  // (009) Bootstrap in the background. The UI shows a loading state
  // while it runs, and an error screen if it fails — no blank-window
  // crash on missing venv / model / mic permission.
  ctl.bootstrap();

  runApp(
    ChangeNotifierProvider.value(value: ctl, child: const TranslatorApp()),
  );
}
