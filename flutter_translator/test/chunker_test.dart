import 'package:test/test.dart';
import 'package:flutter_translator/core/chunker.dart';

void main() {
  test('short text returned unchanged', () {
    expect(chunkText('你好世界'), ['你好世界']);
    expect(chunkText('你好世界', limit: 80), ['你好世界']);
  });

  test('empty / whitespace / null returns empty', () {
    expect(chunkText(''), isEmpty);
    expect(chunkText('   '), isEmpty);
    expect(chunkText(null), isEmpty);
  });

  test('splits on Chinese punctuation, preserves content', () {
    const t = '今天天气很好。我们去公园。然后吃饭。';
    final c = chunkText(t, limit: 10);
    expect(c.length, greaterThan(1));
    for (final x in c) expect(x.length, lessThanOrEqualTo(10));
    expect(c.join(), t);
  });

  test('hard-splits when no punctuation', () {
    expect(chunkText('abcdefghijabcdefghij', limit: 5),
        ['abcde', 'fghij', 'abcde', 'fghij']);
  });

  test('hard-split fallback respects limit on Chinese-only', () {
    const t = '一二三四五六七八九十一二三四五六七八九十';
    final c = chunkText(t, limit: 7);
    for (final x in c) expect(x.length, lessThanOrEqualTo(7));
    expect(c.join(), t);
  });

  test('Latin punctuation also splits', () {
    final c = chunkText('Hello world. This is a test! Done?', limit: 15);
    expect(c.length, greaterThan(1));
    for (final x in c) expect(x.length, lessThanOrEqualTo(15));
  });

  test('punctuation glued to its clause', () {
    final c = chunkText('一二三。四五六！七八九？', limit: 4);
    for (final x in c) {
      if (x.length == 4) {
        expect(RegExp(r'[。！？；.!?;]$').hasMatch(x), isTrue);
      }
    }
  });

  test('long single clause splits into ceil(n/limit) chunks', () {
    final t = '甲' * 173;
    final c = chunkText(t, limit: 50);
    expect(c.length, 4);
    expect(c.join(), t);
    for (final x in c) expect(x.length, lessThanOrEqualTo(50));
  });
}
