// queue.js
export class SentenceQueue {
  constructor(onResult) {
    this._nextId = 0;
    this._nextDisplay = 0;
    this._results = new Map();
    this._onResult = onResult;
  }

  /** Add a sentence to the queue. Returns the numeric ID for this sentence. */
  add(text) {
    const id = this._nextId++;
    return id;
  }

  /** Mark a sentence as successfully translated. */
  resolve(id, original, translation) {
    this._results.set(id, { original, translation });
    this._flush();
  }

  /** Mark a sentence as failed. */
  resolveError(id, original) {
    this._results.set(id, { original, translation: '[Translation error]' });
    this._flush();
  }

  _flush() {
    while (this._results.has(this._nextDisplay)) {
      const { original, translation } = this._results.get(this._nextDisplay);
      this._results.delete(this._nextDisplay);
      this._onResult(original, translation);
      this._nextDisplay++;
    }
  }
}
