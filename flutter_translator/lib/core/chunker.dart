final _sentenceSplit = RegExp(r'(?<=[。！？；.!?;])');

List<String> chunkText(String? text, {int limit = 80}) {
  final t = (text ?? '').trim();
  if (t.isEmpty) return const [];
  if (t.length <= limit) return [t];

  final sentences = t.split(_sentenceSplit);

  final groups = <String>[];
  var cur = '';
  for (final s in sentences) {
    if (s.isEmpty) continue;
    if (cur.isNotEmpty && cur.length + s.length > limit) {
      groups.add(cur);
      cur = s;
    } else {
      cur += s;
    }
  }
  if (cur.isNotEmpty) groups.add(cur);

  final out = <String>[];
  for (final g in groups) {
    if (g.length <= limit) {
      out.add(g);
      continue;
    }
    for (var i = 0; i < g.length; i += limit) {
      final end = (i + limit > g.length) ? g.length : i + limit;
      out.add(g.substring(i, end));
    }
  }
  return [
    for (final s in out)
      if (s.trim().isNotEmpty) s.trim()
  ];
}
