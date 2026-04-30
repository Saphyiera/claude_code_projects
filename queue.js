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
    this._results.set(id, { original: this._texts.get(id), translation });
    this._flush();
  }

  /** Mark a sentence as failed. */
  resolveError(id) {
    this._results.set(id, { original: this._texts.get(id), translation: '[Translation error]' });
    this._flush();
  }

  _flush() {
    while (this._results.has(this._nextDisplay)) {
      const { original, translation } = this._results.get(this._nextDisplay);
      this._results.delete(this._nextDisplay);
      this._texts.delete(this._nextDisplay);
      this._onResult(original, translation);
      this._nextDisplay++;
    }
  }
}
