"""
Run once after converting / downloading the model to produce manifest.json.

    python generate_manifest.py models/opus-mt-zh-en

The manifest is checked by server.py on every startup. If the model files
have been tampered with, the sidecar exits before accepting any connections.
"""

import hashlib
import json
import pathlib
import sys


TRACKED = {
    "model.bin",
    "source.spm",
    "target.spm",
    "shared_vocabulary.json",
    "config.json",
}


def sha256(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> None:
    model_dir = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "models/opus-mt-zh-en")
    manifest: dict[str, str] = {}
    for name in sorted(TRACKED):
        p = model_dir / name
        if p.exists():
            manifest[name] = sha256(p)
            print(f"  {name}: {manifest[name][:16]}…")
        else:
            print(f"  {name}: MISSING (skipped)")

    out = model_dir / "manifest.json"
    out.write_text(json.dumps(manifest, indent=2))
    print(f"\nWrote {out} ({len(manifest)} entries)")


if __name__ == "__main__":
    main()
