import { SentenceQueue } from '../queue.js';
import assert from 'assert';

// Test 1: In-order resolution emits immediately
{
  const results = [];
  const q = new SentenceQueue((orig, trans) => results.push({ orig, trans }));
  const id0 = q.add('一');
  q.resolve(id0, '一', 'one');
  assert.deepStrictEqual(results, [{ orig: '一', trans: 'one' }], 'Test 1 failed');
  console.log('✓ In-order resolution emits immediately');
}

// Test 2: Out-of-order resolution holds later, then flushes all when earlier arrives
{
  const results = [];
  const q = new SentenceQueue((orig, trans) => results.push({ orig, trans }));
  const id0 = q.add('一');
  const id1 = q.add('二');

  q.resolve(id1, '二', 'two');
  assert.deepStrictEqual(results, [], 'Test 2a failed — should not emit yet');

  q.resolve(id0, '一', 'one');
  assert.deepStrictEqual(results, [
    { orig: '一', trans: 'one' },
    { orig: '二', trans: 'two' },
  ], 'Test 2b failed — wrong order or missing entries');
  console.log('✓ Out-of-order resolution holds then flushes in order');
}

// Test 3: resolveError produces [Translation error]
{
  const results = [];
  const q = new SentenceQueue((orig, trans) => results.push({ orig, trans }));
  const id0 = q.add('bad');
  q.resolveError(id0, 'bad');
  assert.deepStrictEqual(results, [{ orig: 'bad', trans: '[Translation error]' }], 'Test 3 failed');
  console.log('✓ resolveError produces [Translation error]');
}

// Test 4: Multiple queues are independent (no shared state)
{
  const r1 = [], r2 = [];
  const q1 = new SentenceQueue((o, t) => r1.push({ o, t }));
  const q2 = new SentenceQueue((o, t) => r2.push({ o, t }));
  const id = q1.add('only q1');
  q1.resolve(id, 'only q1', 'only q1 translation');
  assert.deepStrictEqual(r2, [], 'Test 4 failed — q2 should be empty');
  console.log('✓ Multiple queues are independent');
}

console.log('\nAll queue tests passed.');
