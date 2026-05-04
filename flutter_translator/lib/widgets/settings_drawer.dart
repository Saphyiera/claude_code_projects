import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/whisper_isolate.dart';
import '../state/translation_controller.dart';

class SettingsDrawer extends StatelessWidget {
  const SettingsDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final ctl = context.watch<TranslationController>();
    return Drawer(
      width: 300,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            Text('Settings', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 20),

            // --- Whisper model size ---
            Text('Speech recognition model',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            ...WhisperModelSize.values.map((size) => RadioListTile<WhisperModelSize>(
                  title: Text(size.label),
                  value: size,
                  groupValue: ctl.modelSize,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) {
                    if (v != null) ctl.setModelSize(v);
                  },
                )),
            const Divider(height: 28),

            // --- Beam size ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Translation beam size',
                    style: Theme.of(context).textTheme.labelLarge),
                Text('${ctl.beamSize}',
                    style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
            Slider(
              value: ctl.beamSize.toDouble(),
              min: 1,
              max: 5,
              divisions: 4,
              label: '${ctl.beamSize}',
              onChanged: (v) => ctl.setBeamSize(v.round()),
            ),
            Text(
              'Lower = faster, higher = more accurate.\n'
              '2 is recommended for live speech.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).hintColor),
            ),
            const Divider(height: 28),

            // --- GPU toggle (hidden on macOS) ---
            if (!ctl.isMacOS) ...[
              SwitchListTile(
                title: const Text('Use GPU (CUDA)'),
                subtitle: Text(
                  ctl.cudaActive ? 'Active' : 'Using CPU',
                  style: TextStyle(color: Theme.of(context).hintColor),
                ),
                value: ctl.cudaActive,
                contentPadding: EdgeInsets.zero,
                onChanged: (_) => ctl.toggleCuda(),
              ),
              const Divider(height: 28),
            ],

            // --- Clear transcript ---
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.delete_outline),
              title: const Text('Clear transcript'),
              onTap: () {
                ctl.clear();
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}
