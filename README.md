# Live ZH ↔ EN Translator

Browser-based live translation app for mixed Chinese/English conversations. Runs fully locally with **no paid APIs** — `faster-whisper` for speech-to-text and Helsinki-NLP OPUS-MT for translation.

- **Left column:** English speech → Chinese translation.
- **Right column:** Chinese speech → English translation.

## Setup

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

On first launch the app downloads ~1 GB of model weights:

- faster-whisper `small` (~460 MB) — cached under `~/.cache/huggingface/hub`
- `Helsinki-NLP/opus-mt-zh-en` (~300 MB)
- `Helsinki-NLP/opus-mt-en-zh` (~300 MB)

After the first run everything works offline.

## Run

```bash
./run.sh
# or
uvicorn server.main:app --host 0.0.0.0 --port 8000 --reload
```

Open http://localhost:8000, click **Start**, and grant microphone access.

## Configuration (environment variables)

| Variable | Default | Notes |
|---|---|---|
| `WHISPER_MODEL` | `small` | `tiny`, `base`, `small`, `medium`, `large-v3` |
| `WHISPER_DEVICE` | `cpu` | set to `cuda` for GPU |
| `WHISPER_COMPUTE_TYPE` | `int8` (cpu) / `float16` (cuda) | |
| `NO_SPEECH_THRESHOLD` | `0.6` | drop chunks whose avg no-speech probability exceeds this |

### GPU

```bash
pip install --upgrade torch --index-url https://download.pytorch.org/whl/cu121
WHISPER_DEVICE=cuda WHISPER_MODEL=medium ./run.sh
```

## How it works

1. Browser captures microphone via `MediaRecorder`, emits `audio/webm;opus` blobs every 3 seconds.
2. Each blob is streamed over a WebSocket to the FastAPI backend.
3. `faster-whisper` transcribes the clip and returns text + detected language.
4. Based on the language, the backend routes through `opus-mt-en-zh` or `opus-mt-zh-en`.
5. Result is pushed back to the browser and rendered in the left (EN→ZH) or right (ZH→EN) column.

## Known limitations

- 3-second chunk boundaries may split words; expect minor artefacts.
- If a chunk mixes both languages, Whisper picks the dominant one — the minority snippet is mis-routed.
- OPUS-MT is conversational-grade. Swap to `facebook/nllb-200-distilled-600M` in `server/mt.py` for higher quality (one larger model for both directions).
- Browser support: Chrome/Edge/Firefox. Safari's WebM support is flaky; the frontend auto-falls-back to `audio/mp4` where available.

## Project layout

```
server/
  main.py       FastAPI app + WebSocket endpoint
  stt.py        faster-whisper wrapper
  mt.py         OPUS-MT translation wrapper
public/
  index.html    two-column UI
  app.js        mic capture + WebSocket client
  styles.css
```
