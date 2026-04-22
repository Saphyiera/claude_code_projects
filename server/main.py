"""FastAPI app: serves the static frontend and a /translate REST endpoint."""
import logging
from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from starlette.concurrency import run_in_threadpool

from . import mt

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s - %(message)s",
)
log = logging.getLogger(__name__)

ROOT = Path(__file__).resolve().parent.parent
PUBLIC = ROOT / "public"

app = FastAPI(title="Live ZH-EN Translator")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["POST"],
    allow_headers=["*"],
)


class TranslateRequest(BaseModel):
    text: str
    source: str  # "en" or "zh"
    target: str  # "zh" or "en"


class TranslateResponse(BaseModel):
    translation: str


@app.post("/translate", response_model=TranslateResponse)
async def translate(req: TranslateRequest):
    if not req.text.strip():
        raise HTTPException(status_code=400, detail="text is empty")
    try:
        result = await run_in_threadpool(mt.translate, req.text, req.source, req.target)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        log.exception("translation failed")
        raise HTTPException(status_code=500, detail=str(e))
    return TranslateResponse(translation=result)


# Serve static files — must be mounted last.
app.mount("/", StaticFiles(directory=str(PUBLIC), html=True), name="public")
