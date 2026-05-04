import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/translation_controller.dart';

class TranscriptTile extends StatelessWidget {
  const TranscriptTile({super.key, required this.entry});
  final TranscriptEntry entry;

  @override
  Widget build(BuildContext context) {
    final time =
        '${entry.time.hour.toString().padLeft(2, '0')}:${entry.time.minute.toString().padLeft(2, '0')}:${entry.time.second.toString().padLeft(2, '0')}';
    final theme = Theme.of(context);
    return InkWell(
      onTap: entry.pending || entry.error
          ? null
          : () => Clipboard.setData(ClipboardData(text: entry.english!)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(time,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.hintColor)),
            const SizedBox(height: 2),
            Text(entry.chinese,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.hintColor)),
            const SizedBox(height: 4),
            if (entry.pending)
              const _Pulsing(text: 'translating…')
            else
              Text(
                entry.english!,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: entry.error ? theme.colorScheme.error : null,
                  fontStyle: entry.error ? FontStyle.italic : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Pulsing extends StatefulWidget {
  const _Pulsing({required this.text});
  final String text;
  @override
  State<_Pulsing> createState() => _PulsingState();
}

class _PulsingState extends State<_Pulsing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.5, end: 1.0).animate(_c),
      child: Text(
        widget.text,
        style: TextStyle(
          fontStyle: FontStyle.italic,
          color: Theme.of(context).hintColor,
        ),
      ),
    );
  }
}
