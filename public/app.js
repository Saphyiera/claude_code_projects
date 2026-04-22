const TIMESLICE_MS = 3000;

const toggleBtn = document.getElementById("toggleBtn");
const statusEl = document.getElementById("status");
const levelEl = document.getElementById("level");
const leftCol = document.getElementById("leftCol");
const rightCol = document.getElementById("rightCol");
const toast = document.getElementById("toast");

let ws = null;
let recorder = null;
let stream = null;
let audioCtx = null;
let analyser = null;
let levelRaf = 0;
let running = false;
let reconnectTimer = 0;

function setStatus(text) { statusEl.textContent = text; }

function showToast(msg, durationMs = 3500) {
  toast.textContent = msg;
  toast.classList.remove("hidden");
  clearTimeout(showToast._t);
  showToast._t = setTimeout(() => toast.classList.add("hidden"), durationMs);
}

function pickMimeType() {
  const candidates = [
    "audio/webm;codecs=opus",
    "audio/webm",
    "audio/mp4",
    "audio/ogg;codecs=opus",
  ];
  for (const c of candidates) {
    if (window.MediaRecorder && MediaRecorder.isTypeSupported(c)) return c;
  }
  return "";
}

function openSocket() {
  const proto = location.protocol === "https:" ? "wss" : "ws";
  ws = new WebSocket(`${proto}://${location.host}/ws`);
  ws.binaryType = "arraybuffer";

  ws.addEventListener("open", () => {
    setStatus("Listening…");
  });

  ws.addEventListener("message", (ev) => {
    let msg;
    try { msg = JSON.parse(ev.data); } catch { return; }
    if (msg.error) {
      showToast(`Error: ${msg.error}`);
      return;
    }
    if (msg.skipped) {
      if (msg.reason && msg.reason.startsWith("unsupported_language")) {
        showToast(`Skipped: ${msg.reason}`);
      }
      return;
    }
    renderBubble(msg);
  });

  ws.addEventListener("close", () => {
    if (running) {
      setStatus("Reconnecting…");
      showToast("Connection lost; reconnecting");
      clearTimeout(reconnectTimer);
      reconnectTimer = setTimeout(openSocket, 2000);
    } else {
      setStatus("Idle");
    }
  });

  ws.addEventListener("error", () => {
    setStatus("WebSocket error");
  });
}

function renderBubble(msg) {
  const col = msg.side === "left" ? leftCol : rightCol;
  const div = document.createElement("div");
  div.className = "bubble";
  const src = document.createElement("div");
  src.className = "source";
  src.textContent = msg.sourceText;
  const tgt = document.createElement("div");
  tgt.className = "target";
  tgt.textContent = msg.targetText;
  const ts = document.createElement("div");
  ts.className = "ts";
  ts.textContent = new Date().toLocaleTimeString();
  div.append(src, tgt, ts);
  col.append(div);
  col.scrollTop = col.scrollHeight;
}

function startLevelMeter() {
  audioCtx = new (window.AudioContext || window.webkitAudioContext)();
  const src = audioCtx.createMediaStreamSource(stream);
  analyser = audioCtx.createAnalyser();
  analyser.fftSize = 512;
  src.connect(analyser);
  const buf = new Uint8Array(analyser.fftSize);
  const tick = () => {
    analyser.getByteTimeDomainData(buf);
    let sum = 0;
    for (let i = 0; i < buf.length; i++) {
      const v = (buf[i] - 128) / 128;
      sum += v * v;
    }
    const rms = Math.sqrt(sum / buf.length);
    const pct = Math.min(100, Math.round(rms * 300));
    levelEl.style.setProperty("--level", pct + "%");
    levelRaf = requestAnimationFrame(tick);
  };
  tick();
}

function stopLevelMeter() {
  cancelAnimationFrame(levelRaf);
  if (audioCtx) { audioCtx.close().catch(() => {}); audioCtx = null; }
  analyser = null;
  levelEl.style.setProperty("--level", "0%");
}

async function start() {
  try {
    stream = await navigator.mediaDevices.getUserMedia({ audio: true });
  } catch (e) {
    showToast("Microphone permission denied");
    return;
  }
  const mimeType = pickMimeType();
  if (!mimeType) {
    showToast("MediaRecorder not supported in this browser");
    return;
  }

  running = true;
  toggleBtn.textContent = "Stop";
  toggleBtn.classList.remove("btn-start");
  toggleBtn.classList.add("btn-stop");
  setStatus("Connecting…");

  openSocket();
  startLevelMeter();

  recorder = new MediaRecorder(stream, { mimeType });
  recorder.addEventListener("dataavailable", async (e) => {
    if (!e.data || e.data.size === 0) return;
    if (!ws || ws.readyState !== WebSocket.OPEN) return;
    const buf = await e.data.arrayBuffer();
    ws.send(buf);
  });
  recorder.start(TIMESLICE_MS);
}

function stop() {
  running = false;
  clearTimeout(reconnectTimer);
  toggleBtn.textContent = "Start";
  toggleBtn.classList.remove("btn-stop");
  toggleBtn.classList.add("btn-start");
  setStatus("Idle");

  if (recorder && recorder.state !== "inactive") recorder.stop();
  recorder = null;
  if (stream) { stream.getTracks().forEach((t) => t.stop()); stream = null; }
  stopLevelMeter();
  if (ws) { ws.close(); ws = null; }
}

toggleBtn.addEventListener("click", () => {
  if (running) stop(); else start();
});
