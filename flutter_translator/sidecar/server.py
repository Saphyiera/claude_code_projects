import argparse
import asyncio
import hashlib
import json
import pathlib
import sys
import traceback

import ctranslate2
import sentencepiece as spm
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
import uvicorn

app = FastAPI()
translator = None
src_sp = None
tgt_sp = None
active_device = "cpu"


# ---------------------------------------------------------------------------
# Model integrity
# ---------------------------------------------------------------------------

def verify_model(model_dir: str) -> None:
    """Check SHA-256 of each file listed in manifest.json, if present."""
    manifest_path = pathlib.Path(model_dir) / "manifest.json"
    if not manifest_path.exists():
        return
    manifest: dict[str, str] = json.loads(manifest_path.read_text())
    for fname, expected in manifest.items():
        fpath = pathlib.Path(model_dir) / fname
        if not fpath.exists():
            raise FileNotFoundError(f"Model file missing: {fname}")
        actual = hashlib.sha256(fpath.read_bytes()).hexdigest()
        if actual != expected:
            raise ValueError(
                f"Integrity check failed for {fname}: "
                f"expected {expected[:16]}…, got {actual[:16]}…"
            )
    print(
        f"[sidecar] Model integrity verified ({len(manifest)} files)",
        file=sys.stderr,
        flush=True,
    )


# ---------------------------------------------------------------------------
# Model loading with auto CUDA→CPU fallback
# ---------------------------------------------------------------------------

def load(model_dir: str, requested: str) -> dict | None:
    """
    Load CTranslate2 translator. Returns a fallback dict if device was
    downgraded, or None on clean load. Raises on unrecoverable error.
    """
    global translator, src_sp, tgt_sp, active_device

    verify_model(model_dir)

    src_sp = spm.SentencePieceProcessor()
    src_sp.Load(f"{model_dir}/source.spm")
    tgt_sp = spm.SentencePieceProcessor()
    tgt_sp.Load(f"{model_dir}/target.spm")

    def _make_translator(device: str) -> ctranslate2.Translator:
        compute = "int8" if device == "cpu" else "int8_float16"
        return ctranslate2.Translator(model_dir, device=device, compute_type=compute)

    try:
        translator = _make_translator(requested)
        active_device = requested
        return None
    except Exception as e:
        if requested == "cpu":
            raise
        # GPU unavailable — fall back to CPU.
        translator = _make_translator("cpu")
        active_device = "cpu"
        return {"from": requested, "to": "cpu", "reason": str(e)}


# ---------------------------------------------------------------------------
# Text chunking (mirrors chunker.dart)
# ---------------------------------------------------------------------------

import re as _re
_SPLIT = _re.compile(r"(?<=[。！？；.!?;])")

def chunk_text(t: str, limit: int = 80) -> list[str]:
    t = (t or "").strip()
    if not t:
        return []
    if len(t) <= limit:
        return [t]
    sentences = _SPLIT.split(t)
    groups: list[str] = []
    cur = ""
    for s in sentences:
        if not s:
            continue
        if cur and len(cur) + len(s) > limit:
            groups.append(cur)
            cur = s
        else:
            cur += s
    if cur:
        groups.append(cur)
    out: list[str] = []
    for g in groups:
        if len(g) <= limit:
            out.append(g)
        else:
            for i in range(0, len(g), limit):
                out.append(g[i : i + limit])
    return [s.strip() for s in out if s.strip()]


# ---------------------------------------------------------------------------
# Translation
# ---------------------------------------------------------------------------

def translate_text(text: str, beam_size: int = 2) -> str:
    pieces = chunk_text(text) or [text]
    tokens = [src_sp.EncodeAsPieces(p) for p in pieces]
    results = translator.translate_batch(
        tokens, beam_size=beam_size, max_batch_size=8
    )
    return " ".join(tgt_sp.DecodePieces(r.hypotheses[0]) for r in results)


# ---------------------------------------------------------------------------
# WebSocket endpoint
# ---------------------------------------------------------------------------

@app.websocket("/ws")
async def ws_endpoint(ws: WebSocket) -> None:
    await ws.accept()
    await ws.send_text(json.dumps({"type": "ready", "device": active_device}))
    loop = asyncio.get_running_loop()
    try:
        while True:
            msg = json.loads(await ws.receive_text())
            if msg.get("type") == "translate":
                tid = msg["id"]
                beam = int(msg.get("beam_size", 2))
                try:
                    translated = await loop.run_in_executor(
                        None, translate_text, msg["text"], beam
                    )
                    await ws.send_text(
                        json.dumps(
                            {"type": "translation", "id": tid, "translated": translated}
                        )
                    )
                except Exception:
                    traceback.print_exc()
                    await ws.send_text(
                        json.dumps({"type": "translation-error", "id": tid})
                    )
    except WebSocketDisconnect:
        pass


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, required=True)
    ap.add_argument(
        "--device", choices=["cpu", "cuda"], default="cpu",
        help="Preferred compute device. Automatically falls back to CPU if unavailable.",
    )
    ap.add_argument(
        "--model-dir", default="models/opus-mt-zh-en",
        help="Path to the CTranslate2 model directory.",
    )
    args = ap.parse_args()

    try:
        fallback = load(args.model_dir, args.device)
    except Exception as exc:
        print(f"[sidecar] Fatal: could not load model: {exc}", file=sys.stderr, flush=True)
        sys.exit(1)

    if fallback:
        print(
            f"[sidecar] FALLBACK {fallback['from']} → {fallback['to']}: {fallback['reason']}",
            file=sys.stderr,
            flush=True,
        )

    uvicorn.run(app, host="127.0.0.1", port=args.port, log_level="warning")
