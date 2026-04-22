"""Translation via Claude API using session Bearer token or ANTHROPIC_API_KEY."""
import os
import logging
import httpx

log = logging.getLogger(__name__)

_TOKEN_FILE = os.environ.get(
    "CLAUDE_SESSION_INGRESS_TOKEN_FILE",
    "/home/claude/.claude/remote/.session_ingress_token",
)
_ANTHROPIC_BASE = os.environ.get("ANTHROPIC_BASE_URL", "https://api.anthropic.com")
MODEL = "claude-haiku-4-5-20251001"

_SYSTEM = (
    "You are a translation engine. "
    "Return ONLY the translated text. "
    "No romanization, no parentheses, no explanations."
)


def _load_token() -> tuple[str, str]:
    """Return (token, auth_scheme) where auth_scheme is 'bearer' or 'apikey'."""
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if api_key:
        return api_key, "apikey"
    try:
        with open(_TOKEN_FILE) as f:
            return f.read().strip(), "bearer"
    except FileNotFoundError:
        raise RuntimeError(
            "No ANTHROPIC_API_KEY and no session token found. "
            "Set ANTHROPIC_API_KEY to use this service."
        )


_token, _auth_scheme = _load_token()


def _headers() -> dict:
    if _auth_scheme == "bearer":
        return {
            "Authorization": f"Bearer {_token}",
            "anthropic-version": "2023-06-01",
            "content-type": "application/json",
        }
    return {
        "x-api-key": _token,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
    }


def translate(text: str, source: str, target: str) -> str:
    if source == "en" and target == "zh":
        prompt = f"Translate to Simplified Chinese:\n{text}"
    elif source == "zh" and target == "en":
        prompt = f"Translate to English:\n{text}"
    else:
        raise ValueError(f"Unsupported language pair: {source}→{target}")

    payload = {
        "model": MODEL,
        "max_tokens": 512,
        "system": _SYSTEM,
        "messages": [{"role": "user", "content": prompt}],
    }
    resp = httpx.post(
        f"{_ANTHROPIC_BASE}/v1/messages",
        headers=_headers(),
        json=payload,
        timeout=30,
    )
    resp.raise_for_status()
    return resp.json()["content"][0]["text"].strip()
