// translator-worker.js
import { pipeline, env } from 'https://cdn.jsdelivr.net/npm/@xenova/transformers@2.17.2';

env.allowLocalModels = false;

let translator = null;

self.onmessage = async (event) => {
  const { type, payload } = event.data;

  if (type === 'init') {
    if (translator !== null) {
      self.postMessage({ type: 'ready' });
      return;
    }
    try {
      translator = await pipeline('translation', 'Xenova/opus-mt-zh-en', {
        progress_callback: (progress) => {
          self.postMessage({ type: 'progress', payload: progress });
        },
      });
      self.postMessage({ type: 'ready' });
    } catch (err) {
      self.postMessage({ type: 'error', payload: err.message });
    }
    return;
  }

  if (type === 'translate') {
    if (!translator) {
      self.postMessage({
        type: 'translation-error',
        payload: { id: payload.id },
      });
      return;
    }
    try {
      const result = await translator(payload.text);
      self.postMessage({
        type: 'translation',
        payload: {
          id: payload.id,
          translated: result[0].translation_text,
        },
      });
    } catch (err) {
      self.postMessage({
        type: 'translation-error',
        payload: { id: payload.id },
      });
    }
  }
};
