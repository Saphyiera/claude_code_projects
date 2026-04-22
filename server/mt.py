"""Machine translation using Helsinki-NLP OPUS-MT.

Two pipelines, lazily loaded on first use.
"""
import logging
from threading import Lock
from transformers import pipeline

log = logging.getLogger(__name__)

_ZH_EN_NAME = "Helsinki-NLP/opus-mt-zh-en"
_EN_ZH_NAME = "Helsinki-NLP/opus-mt-en-zh"

_zh_en = None
_en_zh = None
_lock = Lock()


def _get_zh_en():
    global _zh_en
    if _zh_en is None:
        with _lock:
            if _zh_en is None:
                log.info("Loading MT model %s", _ZH_EN_NAME)
                _zh_en = pipeline("translation", model=_ZH_EN_NAME)
    return _zh_en


def _get_en_zh():
    global _en_zh
    if _en_zh is None:
        with _lock:
            if _en_zh is None:
                log.info("Loading MT model %s", _EN_ZH_NAME)
                _en_zh = pipeline("translation", model=_EN_ZH_NAME)
    return _en_zh


def zh_to_en(text: str) -> str:
    out = _get_zh_en()(text, max_length=512)
    return out[0]["translation_text"].strip()


def en_to_zh(text: str) -> str:
    out = _get_en_zh()(text, max_length=512)
    return out[0]["translation_text"].strip()


def warmup() -> None:
    """Optional: force both models to load up front (hides first-call latency)."""
    _get_zh_en()
    _get_en_zh()
