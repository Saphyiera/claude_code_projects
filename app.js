// app.js
import { SentenceQueue } from './queue.js';

// --- DOM refs ---
const micBtn           = document.getElementById('mic-btn');
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

// --- Browser support check ---
if (!('webkitSpeechRecognition' in window) && !('SpeechRecognition' in window)) {
  statusDot.className = 'status-dot error';
  statusText.textContent = 'Not supported — please use Chrome or Edge';
  micBtn.disabled = true;
}

// --- Sentence queue ---
const queue = new SentenceQueue((original, translation) => {
  appendEntry(original, translation);
});

// --- Worker ---
let worker = null;

function initWorker() {
  worker = new Worker('./translator-worker.js', { type: 'module' });
  worker.postMessage({ type: 'init' });

  worker.onmessage = ({ data: { type, payload } }) => {
    if (type === 'progress') {
      const pct = Math.min(100, Math.round(payload.progress ?? 0));
      progressFill.style.width = `${pct}%`;
      progressFill.parentElement.setAttribute('aria-valuenow', pct);
      statusText.textContent = `Loading model... ${pct}%`;
      statusDot.className = 'status-dot loading';
    }
    if (type === 'ready') {
      statusDot.className = 'status-dot ready';
      statusText.textContent = 'Model ready';
      progressFill.style.width = '100%';
      progressFill.parentElement.setAttribute('aria-valuenow', 100);
      const supported = ('webkitSpeechRecognition' in window) || ('SpeechRecognition' in window);
      if (supported) micBtn.disabled = false;
      hideError();
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
  };
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
    if (fatal.includes(event.error)) stopListening();
  };

  recognition.onend = () => {
    if (isListening) recognition.start(); // auto-restart for continuous mode
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

function appendEntry(chinese, english) {
  const isError = english === '[Translation error]';
  const time = new Date().toTimeString().slice(0, 8);

  const entry = document.createElement('div');
  entry.className = 'entry';
  entry.innerHTML =
    `<div class="entry-time">${time}</div>` +
    `<div class="entry-chinese">${escapeHtml(chinese)}</div>` +
    `<div class="entry-english${isError ? ' error' : ''}">${escapeHtml(english)}</div>`;

  transcript.insertBefore(entry, interimEl);
  transcript.scrollTop = transcript.scrollHeight;
}

// --- Clear ---
clearBtn.addEventListener('click', () => {
  transcript.querySelectorAll('.entry').forEach(e => e.remove());
  interimEl.textContent = '';
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
  micBtn.disabled = true;
  statusDot.className = 'status-dot';
  statusText.textContent = 'Loading model...';
  progressFill.style.width = '0%';
  progressFill.parentElement.setAttribute('aria-valuenow', 0);
  if (worker) worker.terminate();
  initWorker();
});

// --- Init ---
initWorker();
