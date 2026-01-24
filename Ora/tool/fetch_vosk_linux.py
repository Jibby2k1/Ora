#!/usr/bin/env python3
import os
import sys
import tempfile
import zipfile
from urllib.request import urlopen

VOSK_LIB_VERSION = "0.3.45"
VOSK_URL = (
    "https://github.com/alphacep/vosk-api/releases/download/"
    f"v{VOSK_LIB_VERSION}/vosk-linux-x86_64-{VOSK_LIB_VERSION}.zip"
)


def _repo_root() -> str:
    return os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def _target_path() -> str:
    return os.path.join(_repo_root(), "linux", "lib", "libvosk.so")


def _download_zip(path: str) -> None:
    with urlopen(VOSK_URL) as response, open(path, "wb") as handle:
        handle.write(response.read())


def _extract_lib(zip_path: str, out_dir: str) -> None:
    os.makedirs(out_dir, exist_ok=True)
    with zipfile.ZipFile(zip_path) as archive:
        lib_member = None
        for name in archive.namelist():
            if name.endswith("/libvosk.so"):
                lib_member = name
                break
        if not lib_member:
            raise RuntimeError("libvosk.so not found in archive")
        archive.extract(lib_member, out_dir)
        extracted = os.path.join(out_dir, lib_member)
        target = os.path.join(out_dir, "libvosk.so")
        os.replace(extracted, target)
        for root, dirs, files in os.walk(out_dir, topdown=False):
            if root == out_dir:
                continue
            if not dirs and not files:
                os.rmdir(root)


def main() -> int:
    target = _target_path()
    if os.path.exists(target):
        print(f"libvosk.so already present at {target}")
        return 0

    out_dir = os.path.dirname(target)
    try:
        with tempfile.TemporaryDirectory() as tmp_dir:
            zip_path = os.path.join(tmp_dir, "vosk-linux.zip")
            print(f"Downloading {VOSK_URL}")
            _download_zip(zip_path)
            print(f"Extracting libvosk.so to {out_dir}")
            _extract_lib(zip_path, out_dir)
        print(f"Saved {target}")
        return 0
    except Exception as exc:
        print(f"Failed to fetch Vosk lib: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
