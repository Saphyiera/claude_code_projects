import { SentenceQueue } from '../queue.js';
import assert from 'assert';

// Test 1: In-order resolution emits immediately
{
  const results = [];
  const q = new SentenceQueue((_id, orig, trans) => results.push({ orig, trans }));
  const id0 = q.add('一');
  q.resolve(id0, 'one');
  assert.deepStrictEqual(results, [{ orig: '一', trans: 'one' }], 'Test 1 failed');
  console.log('✓ In-order resolution emits immediately');
}

// Test 2: Out-of-order resolution holds later, then flushes all when earlier arrives
{
  const results = [];
  const q = new SentenceQueue((_id, orig, trans) => results.push({ orig, trans }));
  const id0 = q.add('一');
  const id1 = q.add('二');

  q.resolve(id1, 'two');
  assert.deepStrictEqual(results, [], 'Test 2a failed — should not emit yet');

  q.resolve(id0, 'one');
  assert.deepStrictEqual(results, [
    { orig: '一', trans: 'one' },
    { orig: '二', trans: 'two' },
  ], 'Test 2b failed — wrong order or missing entries');
  console.log('✓ Out-of-order resolution holds then flushes in order');
}

// Test 3: resolveError produces [Translation error]
{
  const results = [];
  const q = new SentenceQueue((_id, orig, trans) => results.push({ orig, trans }));
  const id0 = q.add('bad');
  q.resolveError(id0);
  assert.deepStrictEqual(results, [{ orig: 'bad', trans: '[Translation error]' }], 'Test 3 failed');
  console.log('✓ resolveError produces [Translation error]');
}

// Test 4: Multiple queues are independent (no shared state)
{
  const r1 = [], r2 = [];
  const q1 = new SentenceQueue((_id, o, t) => r1.push({ o, t }));
  const q2 = new SentenceQueue((_id, o, t) => r2.push({ o, t }));
  const id = q1.add('only q1');
  q1.resolve(id, 'only q1 translation');
  assert.deepStrictEqual(r2, [], 'Test 4 failed — q2 should be empty');
  console.log('✓ Multiple queues are independent');
}

// Test 5: add() returns sequential IDs starting from 0
{
  const q = new SentenceQueue(() => {});
  const id0 = q.add('first');
  const id1 = q.add('second');
  const id2 = q.add('third');
  assert.strictEqual(id0, 0, 'Test 5a failed — first id should be 0');
  assert.strictEqual(id1, id0 + 1, 'Test 5b failed — ids should be sequential');
  assert.strictEqual(id2, id1 + 1, 'Test 5c failed — ids should be sequential');
  console.log('✓ add() returns sequential IDs starting from 0');
}

// Test 6: Cascaded flush — item 2 arrives before item 1
{
  const results = [];
  const q = new SentenceQueue((_id, orig, trans) => results.push({ orig, trans }));
  const id0 = q.add('零');
  const id1 = q.add('一');
  const id2 = q.add('二');

  q.resolve(id0, 'zero');
  assert.deepStrictEqual(results, [{ orig: '零', trans: 'zero' }], 'Test 6a failed');

  q.resolve(id2, 'two');
  assert.deepStrictEqual(results, [{ orig: '零', trans: 'zero' }], 'Test 6b failed — id2 should be held');

  q.resolve(id1, 'one');
  assert.deepStrictEqual(results, [
    { orig: '零', trans: 'zero' },
    { orig: '一', trans: 'one' },
    { orig: '二', trans: 'two' },
  ], 'Test 6c failed — should flush id1 then id2 in order');
  console.log('✓ Cascaded flush — item 2 held until item 1 resolves');
}

// Test 7: resolve() on unknown id is a no-op
{
  const results = [];
  const q = new SentenceQueue((_id, orig, trans) => results.push({ orig, trans }));
  q.resolve(999, 'ghost');
  q.resolveError(1234);
  assert.deepStrictEqual(results, [], 'Test 7 failed — unknown ids must not emit');
  console.log('✓ resolve()/resolveError() on unknown id is a no-op');
}

// Test 8: Double-resolve is ignored (first wins)
{
  const results = [];
  const q = new SentenceQueue((_id, orig, trans) => results.push({ orig, trans }));
  const id0 = q.add('hi');
  q.resolve(id0, 'hello');
  q.resolve(id0, 'overwrite');     // ignored
  q.resolveError(id0);             // ignored
  assert.deepStrictEqual(results, [{ orig: 'hi', trans: 'hello' }], 'Test 8 failed');
  console.log('✓ Double-resolve / resolve-after-error is ignored');
}

// Test 9: pending getter reflects outstanding sentences
{
  const q = new SentenceQueue(() => {});
  assert.strictEqual(q.pending, 0, 'Test 9a failed');
  const id0 = q.add('a');
  const id1 = q.add('b');
  assert.strictEqual(q.pending, 2, 'Test 9b failed');
  q.resolve(id0, 'A');
  assert.strictEqual(q.pending, 1, 'Test 9c failed — resolved entry should leave queue');
  q.resolve(id1, 'B');
  assert.strictEqual(q.pending, 0, 'Test 9d failed');
}
console.log('✓ pending getter tracks outstanding sentences');

// Test 10: pending stays > 0 while later id is held waiting for earlier id
{
  const q = new SentenceQueue(() => {});
  const id0 = q.add('a');
  const id1 = q.add('b');
  q.resolve(id1, 'B');
  // id1 result is held; both entries still pending
  assert.strictEqual(q.pending, 2, 'Test 10 failed — held results should still count as pending');
  q.resolve(id0, 'A');
  assert.strictEqual(q.pending, 0, 'Test 10b failed');
  console.log('✓ pending counts held out-of-order results');
}

// Test 11: failPending() flushes every unresolved id as an error
{
  const results = [];
  const q = new SentenceQueue((_id, orig, trans) => results.push({ orig, trans }));
  q.add('a');
  q.add('b');
  q.add('c');
  q.failPending();
  assert.deepStrictEqual(results, [
    { orig: 'a', trans: '[Translation error]' },
    { orig: 'b', trans: '[Translation error]' },
    { orig: 'c', trans: '[Translation error]' },
  ], 'Test 11 failed — failPending should flush every unresolved id in order');
  assert.strictEqual(q.pending, 0, 'Test 11b failed — pending should be 0 after failPending');
  console.log('✓ failPending() flushes every unresolved id as an error');
}

// Test 12: failPending() preserves already-resolved results and unblocks held ones
{
  const results = [];
  const q = new SentenceQueue((_id, orig, trans) => results.push({ orig, trans }));
  const id0 = q.add('a');
  const id1 = q.add('b');
  const id2 = q.add('c');
  q.resolve(id2, 'C'); // held behind id0/id1
  q.failPending();
  assert.deepStrictEqual(results, [
    { orig: 'a', trans: '[Translation error]' },
    { orig: 'b', trans: '[Translation error]' },
    { orig: 'c', trans: 'C' },
  ], 'Test 12 failed — held real result must be preserved, others fail in order');
  assert.strictEqual(q.pending, 0, 'Test 12b failed');
  console.log('✓ failPending() preserves held real results and drains the queue');
}

// Test 13: failPending() on an empty queue is a no-op
{
  const results = [];
  const q = new SentenceQueue((_id, o, t) => results.push({ o, t }));
  q.failPending();
  assert.deepStrictEqual(results, [], 'Test 13 failed — empty failPending must not emit');
  assert.strictEqual(q.pending, 0, 'Test 13b failed');
  console.log('✓ failPending() on empty queue is a no-op');
}

// Test 14: ids assigned after failPending() continue from where they left off
{
  const results = [];
  const q = new SentenceQueue((_id, o, t) => results.push({ o, t }));
  q.add('old');
  q.failPending();
  const id1 = q.add('new');
  q.resolve(id1, 'NEW');
  assert.deepStrictEqual(results, [
    { o: 'old', t: '[Translation error]' },
    { o: 'new', t: 'NEW' },
  ], 'Test 14 failed — post-failPending ids must still flush in order');
  console.log('✓ Queue keeps emitting in order after failPending()');
}

// Test 15: callback receives the id of the resolved sentence
{
  const events = [];
  const q = new SentenceQueue((id, orig, trans) => events.push({ id, orig, trans }));
  const id0 = q.add('a');
  const id1 = q.add('b');
  q.resolve(id0, 'A');
  q.resolveError(id1);
  assert.deepStrictEqual(events, [
    { id: id0, orig: 'a', trans: 'A' },
    { id: id1, orig: 'b', trans: '[Translation error]' },
  ], 'Test 15 failed — id should be the first callback argument');
  console.log('✓ Callback receives id of the resolved sentence');
}

console.log('\nAll queue tests passed.');
