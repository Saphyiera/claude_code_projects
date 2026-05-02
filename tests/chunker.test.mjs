import { chunkText } from '../chunker.js';
import assert from 'assert';

// Test 1: short text returned as a single chunk unchanged
{
  assert.deepStrictEqual(chunkText('你好世界'), ['你好世界']);
  assert.deepStrictEqual(chunkText('你好世界', 80), ['你好世界']);
  console.log('✓ Short text returned unchanged');
}

// Test 2: empty / whitespace-only text returns []
{
  assert.deepStrictEqual(chunkText(''), []);
  assert.deepStrictEqual(chunkText('   '), []);
  assert.deepStrictEqual(chunkText(null), []);
  assert.deepStrictEqual(chunkText(undefined), []);
  console.log('✓ Empty / whitespace / nullish input returns []');
}

// Test 3: splits on Chinese sentence-ending punctuation, every chunk <= limit
{
  const txt = '今天天气很好。我们去公园。然后吃饭。';
  const chunks = chunkText(txt, 10);
  assert.ok(chunks.length > 1, 'should split');
  for (const c of chunks) {
    assert.ok(c.length <= 10, `chunk too long (${c.length}): ${c}`);
  }
  // Concatenation preserves the original (no whitespace between Chinese clauses)
  assert.strictEqual(chunks.join(''), txt);
  console.log('✓ Splits on Chinese punctuation and preserves content');
}

// Test 4: hard-split when a single clause has no sentence-ending punctuation
{
  const txt = 'abcdefghijabcdefghij';
  const chunks = chunkText(txt, 5);
  assert.deepStrictEqual(chunks, ['abcde', 'fghij', 'abcde', 'fghij']);
  console.log('✓ Hard-splits on character count when no punctuation');
}

// Test 5: each chunk respects the limit even after hard-split fallback
{
  // No sentence-enders at all, plus mixed length
  const txt = '一二三四五六七八九十一二三四五六七八九十';
  const chunks = chunkText(txt, 7);
  for (const c of chunks) assert.ok(c.length <= 7);
  assert.strictEqual(chunks.join(''), txt);
  console.log('✓ Hard-split fallback respects limit on Chinese-only input');
}

// Test 6: Latin punctuation ('.' '!' '?' ';') also splits
{
  const txt = 'Hello world. This is a test! Done?';
  const chunks = chunkText(txt, 15);
  assert.ok(chunks.length > 1, 'expected more than one chunk');
  for (const c of chunks) assert.ok(c.length <= 15);
  console.log('✓ Latin punctuation also splits');
}

// Test 7: punctuation stays attached to the preceding clause
{
  const chunks = chunkText('一二三。四五六！七八九？', 4);
  assert.ok(chunks.every((c) => c.length <= 4));
  // Each chunk should end in the punctuation that closed its clause.
  for (const c of chunks) {
    if (c.length === 4) {
      assert.ok(/[。！？；.!?;]$/.test(c), `punctuation not glued: ${c}`);
    }
  }
  console.log('✓ Punctuation stays glued to its clause');
}

// Test 8: very long single clause greater than limit hard-splits without losing chars
{
  const txt = '甲'.repeat(173);
  const chunks = chunkText(txt, 50);
  assert.strictEqual(chunks.join(''), txt);
  for (const c of chunks) assert.ok(c.length <= 50);
  // 173 / 50 = 3.46 → 4 chunks
  assert.strictEqual(chunks.length, 4);
  console.log('✓ Very long single clause splits cleanly into ceil(n/limit) chunks');
}

console.log('\nAll chunker tests passed.');
