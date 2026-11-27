"""Run the real sprite CLI twice with pinned dependencies and isolated outputs."""
from pathlib import Path
import hashlib
import importlib.metadata
import json
import shutil
import subprocess
import sys
import tempfile

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent


def main() -> None:
    cache = (ROOT / ".godot").resolve()
    cache.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="sprite-verification-", dir=cache) as temporary:
        workspace = Path(temporary).resolve()
        if not workspace.is_relative_to(cache):
            raise RuntimeError("Verification outputs must remain in the project cache")
        source = workspace / "input"
        source.mkdir()
        shutil.copyfile(ROOT / "assets/actors/raw/sevrin.png", source / "sevrin.png")
        for directory in ("first", "second"):
            subprocess.run([
                sys.executable, str(ROOT / "tools/process_sprites.py"),
                "--input", str(source), "--output", str(workspace / directory),
            ], check=True, cwd=ROOT)
        results = {}
        for relative in ("sevrin.png", "portraits/sevrin.png"):
            first = (workspace / "first" / relative).read_bytes()
            second = (workspace / "second" / relative).read_bytes()
            if first != second:
                raise RuntimeError(f"Pipeline is not repeatable: {relative}")
            with Image.open(workspace / "first" / relative) as image:
                expected = (128, 128) if relative.startswith("portraits/") else None
                if image.mode != "RGBA" or (expected and image.size != expected):
                    raise RuntimeError(f"Wrong portrait shape or mode: {relative}")
                if not expected and (image.height != 256 or image.getchannel("A").getextrema() != (0, 255)):
                    raise RuntimeError("Standee must have normalized height and transparent background")
            results[relative] = hashlib.sha256(first).hexdigest()
        print(json.dumps({
            "python": sys.version.split()[0],
            "dependencies": {package: importlib.metadata.version(package) for package in (
                "numpy", "Pillow", "opencv-python-headless")},
            "sha256": results,
        }, ensure_ascii=False, sort_keys=True))


if __name__ == "__main__":
    main()
