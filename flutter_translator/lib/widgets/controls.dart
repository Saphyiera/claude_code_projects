import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/translation_controller.dart';

class Controls extends StatelessWidget {
  const Controls({super.key});

  @override
  Widget build(BuildContext context) {
    final ctl = context.watch<TranslationController>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FilledButton.icon(
                onPressed: () =>
                    ctl.listening ? ctl.stopListening() : ctl.startListening(),
                icon: Icon(ctl.listening ? Icons.stop : Icons.mic),
                label: Text(ctl.listening ? 'Stop' : 'Start Listening'),
                style: FilledButton.styleFrom(
                  backgroundColor: ctl.listening ? Colors.red : null,
                ),
              ),
              const Spacer(),
              if (ctl.listening)
                Text(
                  ctl.pending > 0
                      ? 'listening… (${ctl.pending} pending)'
                      : 'listening…',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Settings',
                icon: const Icon(Icons.tune),
                onPressed: () => Scaffold.of(context).openEndDrawer(),
              ),
            ],
          ),
          if (ctl.statusMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                ctl.statusMessage!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
              ),
            ),
        ],
      ),
    );
  }
}
