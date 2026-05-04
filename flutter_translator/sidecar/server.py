import argparse
import asyncio
import json
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


def load(model_dir: str, requested: str):
    global translator, src_sp, tgt_sp, active_device
    src_sp = spm.SentencePieceProcessor()
    src_sp.Load(f"{model_dir}/source.spm")
    tgt_sp = spm.SentencePieceProcessor()
    tgt_sp.Load(f"{model_dir}/target.spm")
    try:
        translator = ctranslate2.Translator(
            model_dir,
            device=requested,
            compute_type="int8" if requested == "cpu" else "int8_float16",
        )
        active_device = requested
        return None
    except Exception as e:
        if requested != "cpu":
            translator = ctranslate2.Translator(
                model_dir, device="cpu", compute_type="int8"
            )
            active_device = "cpu"
            return {"from": requested, "to": "cpu", "reason": str(e)}
        raise


def chunk_text(t: str, limit: int = 80):
    import re

    t = (t or "").strip()
    if not t:
        return []
    if len(t) <= limit:
        return [t]
    sentences = re.split(r"(?<=[。！？；.!?;])", t)
    groups, cur = [], ""
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
    out = []
    for g in groups:
        if len(g) <= limit:
            out.append(g)
            continue
        for i in range(0, len(g), limit):
            out.append(g[i : i + limit])
    return [s.strip() for s in out if s.strip()]


def translate_text(text: str) -> str:
    pieces = chunk_text(text)
    if not pieces:
        pieces = [text]
    tokens = [src_sp.EncodeAsPieces(p) for p in pieces]
    results = translator.translate_batch(tokens, beam_size=4, max_batch_size=8)
    return " ".join(tgt_sp.DecodePieces(r.hypotheses[0]) for r in results)


@app.websocket("/ws")
async def ws(ws: WebSocket):
    await ws.accept()
    await ws.send_text(json.dumps({"type": "ready", "device": active_device}))
    try:
        while True:
            msg = json.loads(await ws.receive_text())
            if msg.get("type") == "translate":
                tid = msg["id"]
                try:
                    en = await asyncio.get_running_loop().run_in_executor(
                        None, translate_text, msg["text"]
                    )
                    await ws.send_text(
                        json.dumps(
                            {"type": "translation", "id": tid, "translated": en}
                        )
                    )
                except Exception:
                    traceback.print_exc()
                    await ws.send_text(
                        json.dumps({"type": "translation-error", "id": tid})
                    )
    except WebSocketDisconnect:
        pass


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, required=True)
    ap.add_argument("--device", choices=["cpu", "cuda"], default="cpu")
    ap.add_argument("--model-dir", default="models/opus-mt-zh-en")
    args = ap.parse_args()

    fb = load(args.model_dir, args.device)
    if fb is not None:
        print(
            f"FALLBACK from {fb['from']} to {fb['to']}: {fb['reason']}",
            file=sys.stderr,
            flush=True,
        )

    uvicorn.run(app, host="127.0.0.1", port=args.port, log_level="warning")
