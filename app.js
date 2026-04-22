const toggleBtn = document.getElementById("toggleBtn");
const statusEl  = document.getElementById("status");
const leftCol   = document.getElementById("leftCol");
const rightCol  = document.getElementById("rightCol");
const toast     = document.getElementById("toast");

let recognizers = [];
let running = false;

function setStatus(text) { statusEl.textContent = text; }

function showToast(msg, durationMs = 4000) {
  toast.textContent = msg;
  toast.classList.remove("hidden");
  clearTimeout(showToast._t);
  showToast._t = setTimeout(() => toast.classList.add("hidden"), durationMs);
}

if (!("webkitSpeechRecognition" in window) && !("SpeechRecognition" in window)) {
  toggleBtn.disabled = true;
  setStatus("Unsupported browser");
  showToast("Use Chrome or Edge — Firefox does not support the Web Speech API.", 0);
}

async function translate(text, sl, tl) {
  const url =
    "https://translate.googleapis.com/translate_a/single" +
    `?client=gtx&sl=${sl}&tl=${tl}&dt=t&q=${encodeURIComponent(text)}`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const data = await res.json();
  return data[0].map((chunk) => chunk[0]).join("").trim();
}

function appendBubble(col, sourceText) {
  const div = document.createElement("div");
  div.className = "bubble";

  const src = document.createElement("div");
  src.className = "source";
  src.textContent = sourceText;

  const tgt = document.createElement("div");
  tgt.className = "target";
  tgt.textContent = "…";

  const ts = document.createElement("div");
  ts.className = "ts";
  ts.textContent = new Date().toLocaleTimeString();

  div.append(src, tgt, ts);
  col.append(div);
  col.scrollTop = col.scrollHeight;
  return tgt;
}

async function handleResult(transcript, sl, tl, col) {
  const tgtEl = appendBubble(col, transcript);
  try {
    tgtEl.textContent = await translate(transcript, sl, tl);
  } catch (e) {
    tgtEl.textContent = "[translation error]";
    tgtEl.style.color = "#f87171";
    showToast(`Translation error: ${e.message}`);
  }
  col.scrollTop = col.scrollHeight;
}

function createRecognizer(lang, sl, tl, col) {
  const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
  const r = new SR();
  r.lang = lang;
  r.continuous = true;
  r.interimResults = false;
  r.maxAlternatives = 1;

  r.onresult = (e) => {
    for (let i = e.resultIndex; i < e.results.length; i++) {
      if (e.results[i].isFinal) {
        const t = e.results[i][0].transcript.trim();
        if (t) handleResult(t, sl, tl, col);
      }
    }
  };

  r.onerror = (e) => {
    if (e.error === "no-speech" || e.error === "aborted") return;
    showToast(`Recognition error (${lang}): ${e.error}`);
  };

  r.onend = () => { if (running) { try { r.start(); } catch (_) {} } };

  return r;
}

function start() {
  running = true;
  toggleBtn.textContent = "Stop";
  toggleBtn.classList.replace("btn-start", "btn-stop");
  setStatus("Listening…");

  const zh = createRecognizer("zh-CN", "zh-CN", "en", rightCol); // ZH → EN (right)
  const en = createRecognizer("en-US", "en",    "zh-CN", leftCol);  // EN → ZH (left)
  recognizers = [zh, en];
  zh.start();
  en.start();
}

function stop() {
  running = false;
  recognizers.forEach((r) => { try { r.stop(); } catch (_) {} });
  recognizers = [];
  toggleBtn.textContent = "Start";
  toggleBtn.classList.replace("btn-stop", "btn-start");
  setStatus("Idle");
}

toggleBtn.addEventListener("click", () => { if (running) stop(); else start(); });
