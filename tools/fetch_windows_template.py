"""Fetch only the pinned Windows release member from Godot's official template ZIP."""
import argparse
import hashlib
import io
from pathlib import Path
import urllib.request
import zipfile

VERSION = "4.7.2.stable"
URL = "https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz"
ARCHIVE_SIZE = 1281349702
SHA256 = "d34d36f3be1a6c49c56525ae86469b92e4f417ddf0b43cf00dd80c385c4b0562"


class RemoteZip(io.RawIOBase):
    def __init__(self):
        self.position = 0

    def seekable(self):
        return True

    def readable(self):
        return True

    def tell(self):
        return self.position

    def seek(self, offset, whence=0):
        self.position = offset if whence == 0 else self.position + offset if whence == 1 else ARCHIVE_SIZE + offset
        return self.position

    def read(self, size=-1):
        if size < 0:
            size = ARCHIVE_SIZE - self.position
        if size == 0 or self.position >= ARCHIVE_SIZE:
            return b""
        end = min(ARCHIVE_SIZE, self.position + size) - 1
        request = urllib.request.Request(URL, headers={
            "Range": f"bytes={self.position}-{end}", "User-Agent": "ECHO-Windows-build",
        })
        with urllib.request.urlopen(request, timeout=30) as response:
            if response.status != 206:
                raise RuntimeError("Server declined range download; refusing to fetch the entire archive")
            if response.headers.get("Content-Range") != f"bytes {self.position}-{end}/{ARCHIVE_SIZE}":
                raise RuntimeError("Unexpected archive size or byte range")
            data = response.read()
        if len(data) != end - self.position + 1:
            raise RuntimeError("Truncated template range")
        self.position += len(data)
        return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[1] / ".godot/export_templates" / VERSION)
    args = parser.parse_args()
    destination = args.output.resolve()
    destination.mkdir(parents=True, exist_ok=True)
    executable = destination / "windows_release_x86_64.exe"
    if executable.is_file() and hashlib.sha256(executable.read_bytes()).hexdigest() == SHA256:
        print(f"Verified cached Windows template: {VERSION}")
        return
    with zipfile.ZipFile(RemoteZip()) as archive:
        version = archive.read("templates/version.txt").decode().strip()
        if version != VERSION:
            raise RuntimeError(f"Wrong template version: {version}")
        print("Fetching Windows release member only (about 38 MB compressed)", flush=True)
        payload = archive.read("templates/windows_release_x86_64.exe")
    if hashlib.sha256(payload).hexdigest() != SHA256:
        raise RuntimeError("Windows template hash mismatch")
    temporary = executable.with_suffix(".download")
    temporary.write_bytes(payload)
    temporary.replace(executable)
    (destination / "version.txt").write_text(VERSION, encoding="utf-8")
    print(f"Verified Windows template: {VERSION}, sha256={SHA256}")


if __name__ == "__main__":
    main()
