import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/translation_controller.dart';
import 'widgets/controls.dart';
import 'widgets/settings_drawer.dart';
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
      home: const _Home(),
    );
  }
}

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) {
    final ctl = context.watch<TranslationController>();

    if (ctl.initError != null) {
      return Scaffold(body: _ErrorScreen(message: ctl.initError!));
    }
    if (!ctl.ready) {
      return const Scaffold(body: _LoadingScreen());
    }

    return const Scaffold(
      endDrawer: SettingsDrawer(),
      body: SafeArea(
        child: Column(
          children: [
            Controls(),
            Divider(height: 1),
            Expanded(child: TranscriptList()),
          ],
        ),
      ),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Starting translator…'),
        ],
      ),
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text('Failed to start', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            SelectableText(message, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 24),
            Text(
              'Check that the sidecar venv is installed and that the '
              'model files are present under sidecar/models/.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.hintColor),
            ),
          ],
        ),
      ),
    );
  }
}
