const toggleBtn = document.getElementById("toggleBtn");
const statusEl = document.getElementById("status");
const leftCol = document.getElementById("leftCol");
const rightCol = document.getElementById("rightCol");
const toast = document.getElementById("toast");

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
  showToast("Use Chrome or Edge for speech recognition support.", 0);
}

function makeBubble(sourceText, translatedText) {
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
  return { div, tgt };
}

async function handleResult(transcript, sourceLang, targetLang, col) {
  const { div, tgt } = makeBubble(transcript, "…");
  col.append(div);
  col.scrollTop = col.scrollHeight;

  try {
    const res = await fetch("/translate", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ text: transcript, source: sourceLang, target: targetLang }),
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    tgt.textContent = data.translation;
  } catch (e) {
    tgt.textContent = "[translation error]";
    tgt.style.color = "#f87171";
    showToast(`Translation error: ${e.message}`);
  }
  col.scrollTop = col.scrollHeight;
}

function createRecognizer(lang, sourceLang, targetLang, col) {
  const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
  const r = new SR();
  r.lang = lang;
  r.continuous = true;
  r.interimResults = false;
  r.maxAlternatives = 1;

  r.onresult = (e) => {
    for (let i = e.resultIndex; i < e.results.length; i++) {
      if (e.results[i].isFinal) {
        const transcript = e.results[i][0].transcript.trim();
        if (transcript) handleResult(transcript, sourceLang, targetLang, col);
      }
    }
  };

  r.onerror = (e) => {
    if (e.error === "no-speech") return;
    if (e.error === "aborted") return;
    showToast(`Recognition error (${lang}): ${e.error}`);
  };

  r.onend = () => {
    if (running) {
      try { r.start(); } catch (_) {}
    }
  };

  return r;
}

function start() {
  running = true;
  toggleBtn.textContent = "Stop";
  toggleBtn.classList.remove("btn-start");
  toggleBtn.classList.add("btn-stop");
  setStatus("Listening…");

  // zh-CN listener → right column (ZH → EN)
  const zhR = createRecognizer("zh-CN", "zh", "en", rightCol);
  // en-US listener → left column (EN → ZH)
  const enR = createRecognizer("en-US", "en", "zh", leftCol);

  recognizers = [zhR, enR];
  zhR.start();
  enR.start();
}

function stop() {
  running = false;
  recognizers.forEach((r) => { try { r.stop(); } catch (_) {} });
  recognizers = [];
  toggleBtn.textContent = "Start";
  toggleBtn.classList.remove("btn-stop");
  toggleBtn.classList.add("btn-start");
  setStatus("Idle");
}

toggleBtn.addEventListener("click", () => {
  if (running) stop(); else start();
});
