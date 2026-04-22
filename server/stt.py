"""Speech-to-text using faster-whisper. Singleton model load."""
import os
import logging
from faster_whisper import WhisperModel

log = logging.getLogger(__name__)

MODEL_SIZE = os.environ.get("WHISPER_MODEL", "small")
DEVICE = os.environ.get("WHISPER_DEVICE", "cpu")
COMPUTE_TYPE = os.environ.get("WHISPER_COMPUTE_TYPE", "int8" if DEVICE == "cpu" else "float16")

log.info("Loading faster-whisper model=%s device=%s compute=%s", MODEL_SIZE, DEVICE, COMPUTE_TYPE)
_model = WhisperModel(MODEL_SIZE, device=DEVICE, compute_type=COMPUTE_TYPE)
log.info("faster-whisper model loaded.")


def transcribe(path: str) -> tuple[str, str, float]:
    """Transcribe an audio file.

    Returns (text, language, avg_no_speech_prob).
    """
    segments, info = _model.transcribe(
        path,
        vad_filter=True,
        vad_parameters={"min_silence_duration_ms": 500},
        beam_size=1,
    )
    pieces: list[str] = []
    no_speech_probs: list[float] = []
    for seg in segments:
        if seg.text:
            pieces.append(seg.text.strip())
        no_speech_probs.append(seg.no_speech_prob)
    text = " ".join(p for p in pieces if p).strip()
    avg_nsp = sum(no_speech_probs) / len(no_speech_probs) if no_speech_probs else 1.0
    return text, info.language, avg_nsp
