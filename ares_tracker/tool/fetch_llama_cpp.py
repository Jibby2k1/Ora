#!/usr/bin/env python3
import io
import os
import shutil
import sys
import tarfile
from urllib.request import urlopen

DEFAULT_URL = "https://github.com/ggml-org/llama.cpp/archive/refs/heads/master.tar.gz"


def main() -> int:
    url = os.environ.get("LLAMA_CPP_URL", DEFAULT_URL)
    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    dest_dir = os.path.join(repo_root, "third_party", "llama.cpp")

    if os.path.exists(os.path.join(dest_dir, "CMakeLists.txt")):
        print(f"llama.cpp already present at {dest_dir}")
        return 0

    if os.path.exists(dest_dir):
        shutil.rmtree(dest_dir)

    os.makedirs(dest_dir, exist_ok=True)

    try:
        print(f"Downloading llama.cpp from {url}")
        with urlopen(url) as response:
            data = response.read()
        with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as tar:
            root = None
            for member in tar.getmembers():
                if member.isdir() and member.name.count("/") == 0:
                    root = member.name
                    break
            tar.extractall(path=os.path.dirname(dest_dir))
            if root:
                extracted = os.path.join(os.path.dirname(dest_dir), root)
                if extracted != dest_dir:
                    if os.path.exists(dest_dir):
                        shutil.rmtree(dest_dir)
                    shutil.move(extracted, dest_dir)
        if not os.path.exists(os.path.join(dest_dir, "CMakeLists.txt")):
            print("llama.cpp extract failed: CMakeLists.txt missing", file=sys.stderr)
            return 1
        print(f"Saved llama.cpp to {dest_dir}")
        return 0
    except Exception as exc:
        print(f"Failed to download llama.cpp: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
