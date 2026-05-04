import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/translation_controller.dart';

class Controls extends StatelessWidget {
  const Controls({super.key});

  @override
  Widget build(BuildContext context) {
    final ctl = context.watch<TranslationController>();
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          FilledButton.icon(
            onPressed: () =>
                ctl.listening ? ctl.stopListening() : ctl.startListening(),
            icon: Icon(ctl.listening ? Icons.stop : Icons.mic),
            label: Text(ctl.listening ? 'Stop Listening' : 'Start Listening'),
            style: FilledButton.styleFrom(
              backgroundColor: ctl.listening ? Colors.red : null,
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: () => ctl.toggleCuda(),
            icon: Icon(ctl.cudaActive ? Icons.flash_on : Icons.flash_off),
            label: Text(ctl.cudaActive ? 'Use CPU' : 'Use GPU'),
          ),
          const Spacer(),
          if (ctl.listening)
            Text(ctl.pending > 0
                ? 'listening… (${ctl.pending} pending)'
                : 'listening…'),
        ],
      ),
    );
  }
}
