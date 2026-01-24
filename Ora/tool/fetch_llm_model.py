#!/usr/bin/env python3
import os
import sys
from urllib.request import urlopen

DEFAULT_URL = (
    "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/"
    "qwen2.5-0.5b-instruct-q4_k_m.gguf"
)


def main() -> int:
    url = os.environ.get("LLM_MODEL_URL", DEFAULT_URL)
    dest_dir = os.path.join(
        os.path.dirname(__file__),
        "..",
        "assets",
        "models",
        "llm",
    )
    dest_path = os.path.join(dest_dir, "qwen2.5-0.5b-instruct-q4_k_m.gguf")
    os.makedirs(dest_dir, exist_ok=True)

    if os.path.exists(dest_path):
        print(f"Model already exists at {dest_path}")
        return 0

    try:
        print(f"Downloading model from {url}")
        with urlopen(url) as response, open(dest_path, "wb") as out:
            out.write(response.read())
        print(f"Saved model to {dest_path}")
        return 0
    except Exception as exc:
        print(f"Failed to download model: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
