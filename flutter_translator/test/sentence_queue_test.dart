import 'package:test/test.dart';
import 'package:flutter_translator/core/sentence_queue.dart';

void main() {
  test('in-order resolution emits immediately', () {
    final r = <List<dynamic>>[];
    final q = SentenceQueue((id, o, t) => r.add([id, o, t]));
    final id0 = q.add('一');
    q.resolve(id0, 'one');
    expect(r, [[id0, '一', 'one']]);
  });

  test('out-of-order resolution holds then flushes in order', () {
    final r = <List<dynamic>>[];
    final q = SentenceQueue((id, o, t) => r.add([o, t]));
    final id0 = q.add('一');
    final id1 = q.add('二');
    q.resolve(id1, 'two');
    expect(r, isEmpty);
    q.resolve(id0, 'one');
    expect(r, [
      ['一', 'one'],
      ['二', 'two']
    ]);
  });

  test('resolveError produces [Translation error]', () {
    final r = <Map<String, String>>[];
    final q = SentenceQueue((id, o, t) => r.add({'o': o, 't': t}));
    final id = q.add('bad');
    q.resolveError(id);
    expect(r, [
      {'o': 'bad', 't': '[Translation error]'}
    ]);
  });

  test('multiple queues are independent', () {
    final r1 = <int>[], r2 = <int>[];
    final q1 = SentenceQueue((id, _, __) => r1.add(id));
    final q2 = SentenceQueue((id, _, __) => r2.add(id));
    q1.resolve(q1.add('only q1'), 'only q1');
    expect(r2, isEmpty);
  });

  test('add returns sequential ids from 0', () {
    final q = SentenceQueue((_, __, ___) {});
    expect(q.add('a'), 0);
    expect(q.add('b'), 1);
    expect(q.add('c'), 2);
  });

  test('cascaded flush', () {
    final r = <String>[];
    final q = SentenceQueue((id, o, t) => r.add(t));
    final id0 = q.add('零');
    final id1 = q.add('一');
    final id2 = q.add('二');
    q.resolve(id0, 'zero');
    q.resolve(id2, 'two');
    expect(r, ['zero']);
    q.resolve(id1, 'one');
    expect(r, ['zero', 'one', 'two']);
  });

  test('unknown id is no-op', () {
    final r = <int>[];
    final q = SentenceQueue((id, _, __) => r.add(id));
    q.resolve(999, 'ghost');
    q.resolveError(1234);
    expect(r, isEmpty);
  });

  test('double-resolve / resolve-after-error is ignored', () {
    final r = <String>[];
    final q = SentenceQueue((id, _, t) => r.add(t));
    final id = q.add('hi');
    q.resolve(id, 'hello');
    q.resolve(id, 'overwrite');
    q.resolveError(id);
    expect(r, ['hello']);
  });

  test('pending getter tracks outstanding sentences', () {
    final q = SentenceQueue((_, __, ___) {});
    expect(q.pending, 0);
    final a = q.add('a');
    final b = q.add('b');
    expect(q.pending, 2);
    q.resolve(a, 'A');
    expect(q.pending, 1);
    q.resolve(b, 'B');
    expect(q.pending, 0);
  });

  test('pending counts held out-of-order results', () {
    final q = SentenceQueue((_, __, ___) {});
    final a = q.add('a');
    final b = q.add('b');
    q.resolve(b, 'B');
    expect(q.pending, 2);
    q.resolve(a, 'A');
    expect(q.pending, 0);
  });

  test('failPending flushes every unresolved id as error', () {
    final r = <List<String>>[];
    final q = SentenceQueue((id, o, t) => r.add([o, t]));
    q.add('a');
    q.add('b');
    q.add('c');
    q.failPending();
    expect(r, [
      ['a', '[Translation error]'],
      ['b', '[Translation error]'],
      ['c', '[Translation error]'],
    ]);
    expect(q.pending, 0);
  });

  test('failPending preserves held real results', () {
    final r = <List<String>>[];
    final q = SentenceQueue((id, o, t) => r.add([o, t]));
    final a = q.add('a');
    final b = q.add('b');
    final c = q.add('c');
    q.resolve(c, 'C');
    q.failPending();
    expect(r, [
      ['a', '[Translation error]'],
      ['b', '[Translation error]'],
      ['c', 'C'],
    ]);
  });

  test('failPending on empty queue is no-op', () {
    final r = <int>[];
    final q = SentenceQueue((id, _, __) => r.add(id));
    q.failPending();
    expect(r, isEmpty);
    expect(q.pending, 0);
  });

  test('queue keeps emitting in order after failPending', () {
    final r = <List<String>>[];
    final q = SentenceQueue((id, o, t) => r.add([o, t]));
    q.add('old');
    q.failPending();
    final n = q.add('new');
    q.resolve(n, 'NEW');
    expect(r, [
      ['old', '[Translation error]'],
      ['new', 'NEW'],
    ]);
  });

  test('callback receives the id', () {
    final events = <List<dynamic>>[];
    final q = SentenceQueue((id, o, t) => events.add([id, o, t]));
    final a = q.add('a');
    final b = q.add('b');
    q.resolve(a, 'A');
    q.resolveError(b);
    expect(events, [
      [a, 'a', 'A'],
      [b, 'b', '[Translation error]'],
    ]);
  });
}
