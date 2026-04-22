"""FastAPI app: serves the static frontend and a WebSocket audio endpoint."""
import logging
import os
import uuid
from pathlib import Path

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.staticfiles import StaticFiles
from starlette.concurrency import run_in_threadpool

from . import stt, mt

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s - %(message)s",
)
log = logging.getLogger(__name__)

ROOT = Path(__file__).resolve().parent.parent
PUBLIC = ROOT / "public"
TMP = ROOT / "tmp"
TMP.mkdir(exist_ok=True)

NO_SPEECH_THRESHOLD = float(os.environ.get("NO_SPEECH_THRESHOLD", "0.6"))

app = FastAPI(title="Live ZH-EN Translator")


async def _process_chunk(data: bytes, chunk_id: int) -> dict:
    """Write audio to a tmp file, run STT + MT, return payload dict."""
    path = TMP / f"chunk-{uuid.uuid4().hex}.webm"
    try:
        path.write_bytes(data)
        text, lang, no_speech = await run_in_threadpool(stt.transcribe, str(path))

        if not text or no_speech >= NO_SPEECH_THRESHOLD:
            return {"chunkId": chunk_id, "skipped": True, "reason": "no_speech"}

        if lang == "en":
            translated = await run_in_threadpool(mt.en_to_zh, text)
            return {
                "chunkId": chunk_id,
                "sourceLang": "en",
                "sourceText": text,
                "targetLang": "zh",
                "targetText": translated,
                "side": "left",
            }
        if lang.startswith("zh"):
            translated = await run_in_threadpool(mt.zh_to_en, text)
            return {
                "chunkId": chunk_id,
                "sourceLang": "zh",
                "sourceText": text,
                "targetLang": "en",
                "targetText": translated,
                "side": "right",
            }
        return {
            "chunkId": chunk_id,
            "skipped": True,
            "reason": f"unsupported_language:{lang}",
            "sourceText": text,
        }
    finally:
        try:
            path.unlink()
        except FileNotFoundError:
            pass


@app.websocket("/ws")
async def ws_endpoint(ws: WebSocket):
    await ws.accept()
    log.info("WebSocket client connected")
    chunk_id = 0
    try:
        while True:
            data = await ws.receive_bytes()
            chunk_id += 1
            this_id = chunk_id
            try:
                payload = await _process_chunk(data, this_id)
            except Exception as e:  # noqa: BLE001
                log.exception("chunk %d failed", this_id)
                payload = {"chunkId": this_id, "error": str(e)}
            await ws.send_json(payload)
    except WebSocketDisconnect:
        log.info("WebSocket client disconnected")


# Serve static files last so /ws is matched first.
app.mount("/", StaticFiles(directory=str(PUBLIC), html=True), name="public")
