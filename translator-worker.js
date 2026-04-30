// translator-worker.js
import { pipeline, env } from 'https://cdn.jsdelivr.net/npm/@xenova/transformers@2.17.2';

env.allowLocalModels = false;

let translator = null;
let initPromise = null;

// Serialize translate jobs: the underlying pipeline is not safe to invoke
// concurrently, and concurrent inference balloons memory on slow devices.
let jobChain = Promise.resolve();

function ensureInit() {
  if (initPromise) return initPromise;
  initPromise = pipeline('translation', 'Xenova/opus-mt-zh-en', {
    progress_callback: (progress) => {
      self.postMessage({ type: 'progress', payload: progress });
    },
  }).then((t) => {
    translator = t;
    return t;
  });
  return initPromise;
}

async function runTranslate(id, text) {
  if (!translator) {
    self.postMessage({ type: 'translation-error', payload: { id } });
    return;
  }
  try {
    const result = await translator(text);
    self.postMessage({
      type: 'translation',
      payload: { id, translated: result[0].translation_text },
    });
  } catch (err) {
    self.postMessage({ type: 'translation-error', payload: { id } });
  }
}

self.onmessage = (event) => {
  const { type, payload } = event.data;

  if (type === 'init') {
    ensureInit()
      .then(() => self.postMessage({ type: 'ready' }))
      .catch((err) => {
        initPromise = null; // allow retry
        self.postMessage({ type: 'error', payload: err.message });
      });
    return;
  }

  if (type === 'translate') {
    jobChain = jobChain.then(() => runTranslate(payload.id, payload.text));
  }
};
