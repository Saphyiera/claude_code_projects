typedef ResultCallback = void Function(int id, String original, String translation);

class SentenceQueue {
  SentenceQueue(this._onResult);

  int _nextId = 0;
  int _nextDisplay = 0;
  final Map<int, String> _texts = {};
  final Map<int, _Result> _results = {};
  final ResultCallback _onResult;

  int add(String text) {
    final id = _nextId++;
    _texts[id] = text;
    return id;
  }

  void resolve(int id, String translation) {
    if (!_texts.containsKey(id) || _results.containsKey(id)) return;
    _results[id] = _Result(_texts[id]!, translation);
    _flush();
  }

  void resolveError(int id) {
    if (!_texts.containsKey(id) || _results.containsKey(id)) return;
    _results[id] = _Result(_texts[id]!, '[Translation error]');
    _flush();
  }

  int get pending => _texts.length;

  void failPending() {
    for (final id in _texts.keys.toList()) {
      if (!_results.containsKey(id)) {
        _results[id] = _Result(_texts[id]!, '[Translation error]');
      }
    }
    _flush();
  }

  void _flush() {
    while (_results.containsKey(_nextDisplay)) {
      final id = _nextDisplay;
      final r = _results.remove(id)!;
      _texts.remove(id);
      _onResult(id, r.original, r.translation);
      _nextDisplay++;
    }
  }
}

class _Result {
  _Result(this.original, this.translation);
  final String original;
  final String translation;
}
