// app.js
import { SentenceQueue } from './queue.js';

// --- DOM refs ---
const micBtn           = document.getElementById('mic-btn');
const gpuBtn           = document.getElementById('gpu-btn');
const listeningStatus  = document.getElementById('listening-status');
const statusDot        = document.getElementById('status-dot');
const statusText       = document.getElementById('status-text');
const progressFill     = document.getElementById('progress-fill');
const transcript       = document.getElementById('transcript');
const interimEl        = document.getElementById('interim');
const clearBtn         = document.getElementById('clear-btn');
const errorBanner      = document.getElementById('error-banner');
const errorTextEl      = document.getElementById('error-text');
const retryBtn         = document.getElementById('retry-btn');

// --- Backend device (wasm = CPU, webgpu = GPU via WebGPU) ---
const gpuSupported = 'gpu' in navigator;
let requestedDevice = 'wasm'; // what the user asked for
let activeDevice = 'wasm';    // what's actually loaded (may differ after fallback)

function devicePretty(d) { return d === 'webgpu' ? 'GPU' : 'CPU'; }

function updateGpuBtn() {
  if (!gpuSupported) {
    gpuBtn.hidden = true;
    return;
  }
  gpuBtn.hidden = false;
  const wantGpu = requestedDevice === 'webgpu';
  gpuBtn.textContent = wantGpu ? 'Use CPU' : 'Use GPU';
  gpuBtn.setAttribute('aria-pressed', wantGpu ? 'true' : 'false');
  gpuBtn.classList.toggle('active', wantGpu);
}

// --- Browser support check ---
if (!('webkitSpeechRecognition' in window) && !('SpeechRecognition' in window)) {
  statusDot.className = 'status-dot error';
  statusText.textContent = 'Not supported — please use Chrome or Edge';
  micBtn.disabled = true;
}

// --- Sentence queue ---
const queue = new SentenceQueue((original, translation) => {
  appendEntry(original, translation);
  updatePendingStatus();
});

// --- Worker ---
let worker = null;
let lastProgressPct = -1;
let pendingFallbackMessage = null;

function initWorker() {
  worker = new Worker('./translator-worker.js', { type: 'module' });
  worker.postMessage({ type: 'init', payload: { device: requestedDevice } });
  if (gpuSupported) gpuBtn.disabled = true;

  worker.onmessage = ({ data: { type, payload } }) => {
    if (type === 'progress') {
      const pct = Math.min(100, Math.round(payload.progress ?? 0));
      if (pct === lastProgressPct) return;
      lastProgressPct = pct;
      progressFill.style.width = `${pct}%`;
      progressFill.parentElement.setAttribute('aria-valuenow', pct);
      // Prefer the device the worker is *actually* loading (set after a
      // GPU→CPU fallback) over what the user originally asked for.
      const label = devicePretty(payload.device ?? requestedDevice);
      statusText.textContent = `Loading model on ${label}... ${pct}%`;
      statusDot.className = 'status-dot loading';
    }
    if (type === 'ready') {
      activeDevice = (payload && payload.device) || 'wasm';
      requestedDevice = activeDevice; // sync UI to whatever actually loaded
      statusDot.className = 'status-dot ready';
      statusText.textContent = `Model ready (${devicePretty(activeDevice)})`;
      progressFill.style.width = '100%';
      progressFill.parentElement.setAttribute('aria-valuenow', 100);
      const supported = ('webkitSpeechRecognition' in window) || ('SpeechRecognition' in window);
      if (supported) micBtn.disabled = false;
      if (gpuSupported) gpuBtn.disabled = false;
      updateGpuBtn();
      hideError();
      if (pendingFallbackMessage) {
        showError(pendingFallbackMessage, false);
        pendingFallbackMessage = null;
      }
    }
    if (type === 'fallback') {
      // Defer until after `ready` so it isn't wiped by hideError().
      pendingFallbackMessage = `GPU not available for this model — using CPU. (${payload.reason})`;
    }
    if (type === 'translation') {
      queue.resolve(payload.id, payload.translated);
    }
    if (type === 'translation-error') {
      queue.resolveError(payload.id);
    }
    if (type === 'error') {
      showError(payload, true);
    }
  };

  worker.onerror = (err) => {
    showError('Worker crashed: ' + err.message, false);
    queue.failPending();
    updatePendingStatus();
  };
}

function reloadWorker() {
  micBtn.disabled = true;
  if (gpuSupported) gpuBtn.disabled = true;
  statusDot.className = 'status-dot';
  statusText.textContent = `Loading model on ${devicePretty(requestedDevice)}...`;
  progressFill.style.width = '0%';
  progressFill.parentElement.setAttribute('aria-valuenow', 0);
  lastProgressPct = -1;
  if (worker) worker.terminate();
  queue.failPending();
  updatePendingStatus();
  initWorker();
}

// --- Speech recognition ---
const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
let recognition = null;
let isListening = false;
const CHINESE_CHAR = /[\u4e00-\u9fff\u3400-\u4dbf]/;

function startListening() {
  recognition = new SpeechRecognition();
  recognition.lang = 'zh-CN';
  recognition.continuous = true;
  recognition.interimResults = true;

  recognition.onresult = (event) => {
    let interim = '';
    for (let i = event.resultIndex; i < event.results.length; i++) {
      const result = event.results[i];
      if (result.isFinal) {
        const text = result[0].transcript.trim();
        if (text && CHINESE_CHAR.test(text)) {
          const id = queue.add(text);
          worker.postMessage({ type: 'translate', payload: { id, text } });
          updatePendingStatus();
        }
        interimEl.textContent = '';
      } else {
        interim += result[0].transcript;
      }
    }
    if (interim) interimEl.textContent = interim;
  };

  recognition.onerror = (event) => {
    if (event.error === 'aborted') return;
    listeningStatus.textContent = `error: ${event.error}`;
    const fatal = ['not-allowed', 'service-not-allowed', 'network', 'audio-capture'];
    if (fatal.includes(event.error)) { stopListening(); return; }
    // Non-fatal (e.g. no-speech): clear the stale error label after a pause
    // so the user doesn't stare at "error: no-speech" forever while we
    // continue listening.
    setTimeout(() => {
      if (isListening && listeningStatus.textContent.startsWith('error:')) {
        updatePendingStatus();
        if (!listeningStatus.textContent.startsWith('listening')) {
          listeningStatus.textContent = 'listening...';
        }
      }
    }, 1500);
  };

  recognition.onend = () => {
    if (!isListening) return;
    // auto-restart for continuous mode; guard against rapid-fire restarts that
    // some browsers reject with InvalidStateError.
    try {
      recognition.start();
    } catch {
      setTimeout(() => {
        if (isListening && recognition) {
          try { recognition.start(); } catch { /* give up until user toggles */ }
        }
      }, 250);
    }
  };

  recognition.start();
  isListening = true;
  micBtn.textContent = 'Stop Listening';
  micBtn.classList.add('listening');
  micBtn.setAttribute('aria-pressed', 'true');
  listeningStatus.textContent = 'listening...';
}

function stopListening() {
  isListening = false;
  if (recognition) {
    recognition.onend = null; // prevent auto-restart
    recognition.stop();
    recognition = null;
  }
  micBtn.textContent = 'Start Listening';
  micBtn.classList.remove('listening');
  micBtn.setAttribute('aria-pressed', 'false');
  listeningStatus.textContent = 'idle';
  interimEl.textContent = '';
}

micBtn.addEventListener('click', () => {
  if (!isListening) startListening();
  else stopListening();
});

// --- Transcript helpers ---
function escapeHtml(str) {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#x27;');
}

const MAX_ENTRIES = 200;
let entryCount = 0;

function appendEntry(chinese, english) {
  const isError = english === '[Translation error]';
  const time = new Date().toTimeString().slice(0, 8);

  const entry = document.createElement('div');
  entry.className = 'entry';
  entry.title = 'Click to copy translation';
  entry.dataset.translation = english;
  entry.innerHTML =
    `<div class="entry-time">${time}</div>` +
    `<div class="entry-chinese">${escapeHtml(chinese)}</div>` +
    `<div class="entry-english${isError ? ' error' : ''}">${escapeHtml(english)}</div>`;

  transcript.insertBefore(entry, interimEl);
  entryCount++;

  // Auto-scroll only if user is already near the bottom — preserves position
  // when scrolling back to read older entries.
  const atBottom = transcript.scrollHeight - transcript.scrollTop - transcript.clientHeight < 80;
  if (atBottom) transcript.scrollTop = transcript.scrollHeight;

  // Cap transcript size. Counter + first-match query is amortized O(1) per
  // append; the previous querySelectorAll('.entry') was O(n) every time.
  while (entryCount > MAX_ENTRIES) {
    const first = transcript.querySelector('.entry');
    if (!first) { entryCount = 0; break; }
    first.remove();
    entryCount--;
  }
}

function updatePendingStatus() {
  if (!isListening) return;
  const n = queue.pending;
  listeningStatus.textContent = n > 0 ? `listening... (${n} pending)` : 'listening...';
}

// --- Clear ---
clearBtn.addEventListener('click', () => {
  transcript.querySelectorAll('.entry').forEach(e => e.remove());
  entryCount = 0;
  interimEl.textContent = '';
});

// --- Click an entry to copy its English translation ---
transcript.addEventListener('click', (event) => {
  const entry = event.target.closest('.entry');
  if (!entry || !navigator.clipboard) return;
  const text = entry.dataset.translation;
  if (!text || text === '[Translation error]') return;
  navigator.clipboard.writeText(text).then(() => {
    entry.classList.add('copied');
    setTimeout(() => entry.classList.remove('copied'), 600);
  }).catch(() => { /* clipboard refused; ignore */ });
});

// --- Error banner ---
function showError(message, showRetry) {
  errorTextEl.textContent = message;
  retryBtn.style.display = showRetry ? 'inline-block' : 'none';
  errorBanner.classList.remove('hidden');
}

function hideError() {
  errorBanner.classList.add('hidden');
}

retryBtn.addEventListener('click', () => {
  hideError();
  reloadWorker();
});

if (gpuSupported) {
  gpuBtn.addEventListener('click', () => {
    requestedDevice = requestedDevice === 'webgpu' ? 'wasm' : 'webgpu';
    updateGpuBtn();
    hideError();
    reloadWorker();
  });
}

// --- Warn before unload if translations are still in flight ---
window.addEventListener('beforeunload', (e) => {
  if (queue.pending > 0) {
    e.preventDefault();
    e.returnValue = ''; // some legacy browsers need a non-empty returnValue
  }
});

// --- Init ---
updateGpuBtn();
initWorker();
