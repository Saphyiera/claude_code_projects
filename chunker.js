// chunker.js
//
// Split a Chinese (or mixed) sentence into smaller pieces so the translator
// can run them as a batch — one forward pass instead of many. Also keeps
// individual pieces well under opus-mt's token limit so very long inputs
// don't get truncated.

const SENTENCE_SPLIT = /(?<=[。！？；.!?;])/;

/**
 * Split `text` into chunks of at most `limit` characters, preferring
 * sentence-ending punctuation as boundaries and falling back to a hard
 * character-count split when a single clause is still too long.
 *
 * Concatenating the returned chunks is equivalent to the original text
 * (modulo whitespace trimming on Latin-style inputs).
 */
export function chunkText(text, limit = 80) {
  const t = (text ?? '').trim();
  if (!t) return [];
  if (t.length <= limit) return [t];

  // Lookbehind keeps the punctuation glued to the clause it terminates.
  const sentences = t.split(SENTENCE_SPLIT);

  const groups = [];
  let cur = '';
  for (const s of sentences) {
    if (!s) continue;
    if (cur && cur.length + s.length > limit) {
      groups.push(cur);
      cur = s;
    } else {
      cur += s;
    }
  }
  if (cur) groups.push(cur);

  // Hard-split anything still over the limit (e.g. a single run with no
  // sentence-ending punctuation).
  const out = [];
  for (const g of groups) {
    if (g.length <= limit) {
      out.push(g);
      continue;
    }
    for (let i = 0; i < g.length; i += limit) {
      out.push(g.slice(i, i + limit));
    }
  }
  return out.map((s) => s.trim()).filter(Boolean);
}
