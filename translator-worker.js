// translator-worker.js
import { pipeline, env } from 'https://cdn.jsdelivr.net/npm/@xenova/transformers@2.17.2';
import { chunkText } from './chunker.js';

env.allowLocalModels = false;

let translator = null;
let initPromise = null;

// Serialize translate jobs: the underlying pipeline is not safe to invoke
// concurrently, and concurrent inference balloons memory on slow devices.
let jobChain = Promise.resolve();

function loadPipeline(device) {
  // `device: 'webgpu'` routes inference through ONNX Runtime Web's WebGPU
  // backend. On NVIDIA Windows/Linux this lands on CUDA via the browser's
  // GPU stack. Pass undefined to use the default (wasm/CPU).
  const effective = device && device !== 'wasm' ? device : 'wasm';
  const opts = {
    progress_callback: (progress) => {
      // Tag progress with the device actually being loaded so the UI
      // doesn't keep saying "Loading model on GPU..." after fallback.
      self.postMessage({ type: 'progress', payload: { ...progress, device: effective } });
    },
  };
  if (device && device !== 'wasm') opts.device = device;
  return pipeline('translation', 'Xenova/opus-mt-zh-en', opts);
}

function ensureInit(requestedDevice) {
  if (initPromise) return initPromise;
  initPromise = (async () => {
    try {
      translator = await loadPipeline(requestedDevice);
      return requestedDevice || 'wasm';
    } catch (err) {
      // Auto-fallback to CPU if GPU init failed (model not GPU-compatible,
      // driver issue, etc.) so the user still gets translation.
      if (requestedDevice && requestedDevice !== 'wasm') {
        self.postMessage({
          type: 'fallback',
          payload: { from: requestedDevice, to: 'wasm', reason: err.message },
        });
        translator = await loadPipeline('wasm');
        return 'wasm';
      }
      throw err;
    }
  })();
  return initPromise;
}

async function runTranslate(id, text) {
  // If init is still in flight (e.g. user kept speaking during a device
  // switch), wait for it rather than dropping the sentence.
  if (initPromise) {
    try { await initPromise; } catch { /* error surfaced separately */ }
  }
  if (!translator) {
    self.postMessage({ type: 'translation-error', payload: { id } });
    return;
  }
  try {
    // Chunk long inputs so opus-mt doesn't truncate them, and so we can
    // hand the whole sentence to the model as a single batch — one forward
    // pass through the encoder/decoder for all pieces.
    const chunks = chunkText(text);
    let translated;
    if (chunks.length <= 1) {
      const result = await translator(chunks[0] ?? text);
      translated = result[0].translation_text;
    } else {
      const results = await translator(chunks);
      translated = results
        .map((r) => r.translation_text.trim())
        .filter(Boolean)
        .join(' ');
    }
    self.postMessage({
      type: 'translation',
      payload: { id, translated },
    });
  } catch (err) {
    self.postMessage({ type: 'translation-error', payload: { id } });
  }
}

self.onmessage = (event) => {
  const { type, payload } = event.data;

  if (type === 'init') {
    const device = (event.data.payload && event.data.payload.device) || 'wasm';
    ensureInit(device)
      .then((dev) => self.postMessage({ type: 'ready', payload: { device: dev } }))
      .catch((err) => {
        initPromise = null; // allow retry
        translator = null;
        self.postMessage({ type: 'error', payload: err.message });
      });
    return;
  }

  if (type === 'translate') {
    jobChain = jobChain.then(() => runTranslate(payload.id, payload.text));
  }
};
