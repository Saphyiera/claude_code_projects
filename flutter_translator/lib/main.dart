import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'app.dart';
import 'state/translation_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final exeDir = File(Platform.resolvedExecutable).parent.path;
  final sidecarDir = p.join(exeDir, 'sidecar');

  final ctl = TranslationController(sidecarDir: sidecarDir);
  await ctl.bootstrap();

  runApp(
    ChangeNotifierProvider.value(value: ctl, child: const TranslatorApp()),
  );
}
