import 'package:flutter/material.dart';

import 'widgets/controls.dart';
import 'widgets/transcript.dart';

class TranslatorApp extends StatelessWidget {
  const TranslatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Live Chinese → English Translator',
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF0D6EFD),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF0D6EFD),
      ),
      home: const Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Controls(),
              Divider(height: 1),
              Expanded(child: TranscriptList()),
            ],
          ),
        ),
      ),
    );
  }
}
