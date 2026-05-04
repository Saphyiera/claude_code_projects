import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/translation_controller.dart';
import 'transcript_tile.dart';

class TranscriptList extends StatelessWidget {
  const TranscriptList({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<TranslationController>(
      builder: (_, ctl, __) {
        return ListView.builder(
          itemCount: ctl.entries.length,
          itemBuilder: (_, i) => TranscriptTile(entry: ctl.entries[i]),
        );
      },
    );
  }
}
