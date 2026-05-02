// queue.js
export class SentenceQueue {
  constructor(onResult) {
    this._nextId = 0;
    this._nextDisplay = 0;
    this._texts = new Map();
    this._results = new Map();
    this._onResult = onResult;
  }

  /** Add a sentence to the queue. Returns the numeric ID for this sentence. */
  add(text) {
    const id = this._nextId++;
    this._texts.set(id, text);
    return id;
  }

  /** Mark a sentence as successfully translated. */
  resolve(id, translation) {
    if (!this._texts.has(id) || this._results.has(id)) return;
    this._results.set(id, { original: this._texts.get(id), translation });
    this._flush();
  }

  /** Mark a sentence as failed. */
  resolveError(id) {
    if (!this._texts.has(id) || this._results.has(id)) return;
    this._results.set(id, { original: this._texts.get(id), translation: '[Translation error]' });
    this._flush();
  }

  /** Number of sentences awaiting translation or in-order display. */
  get pending() {
    return this._texts.size;
  }

  /**
   * Mark every still-unresolved sentence as a translation error.
   * Use when the worker is being torn down or has crashed so that
   * orphaned ids don't linger in the queue forever.
   */
  failPending() {
    for (const id of [...this._texts.keys()]) {
      if (!this._results.has(id)) {
        this._results.set(id, {
          original: this._texts.get(id),
          translation: '[Translation error]',
        });
      }
    }
    this._flush();
  }

  _flush() {
    while (this._results.has(this._nextDisplay)) {
      const id = this._nextDisplay;
      const { original, translation } = this._results.get(id);
      this._results.delete(id);
      this._texts.delete(id);
      this._onResult(id, original, translation);
      this._nextDisplay++;
    }
  }
}
