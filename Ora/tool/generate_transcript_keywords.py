#!/usr/bin/env python3
import json
import os
import re
from collections import Counter
from datetime import datetime, timezone

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SEED_PATH = os.path.join(ROOT, "lib", "data", "seed", "exercise_catalog_seed.json")
OUT_PATH = os.path.join(ROOT, "lib", "core", "voice", "transcript_keywords.json")

TOKEN_RE = re.compile(r"[^a-z0-9 ]")
WHITESPACE_RE = re.compile(r"\s+")

# Commonly ambiguous or high-impact terms to flag.
FLAG_TERMS = {
    "press",
    "row",
    "curl",
    "raise",
    "fly",
    "pulldown",
    "pull",
    "push",
    "machine",
    "cable",
    "barbell",
    "dumbbell",
    "bench",
    "incline",
    "decline",
    "overhead",
    "lat",
    "chest",
    "pec",
    "rear",
    "front",
    "single",
    "wide",
    "close",
}


def normalize(text: str) -> str:
    lowered = text.lower()
    cleaned = TOKEN_RE.sub(" ", lowered)
    return WHITESPACE_RE.sub(" ", cleaned).strip()


def tokenize(text: str) -> list[str]:
    normalized = normalize(text)
    if not normalized:
        return []
    return normalized.split(" ")


def main() -> int:
    if not os.path.exists(SEED_PATH):
        raise SystemExit(f"Seed not found: {SEED_PATH}")

    with open(SEED_PATH, "r", encoding="utf-8") as handle:
        data = json.load(handle)

    tokens = Counter()
    bigrams = Counter()

    for item in data:
        for field in ("canonical_name",):
            text = item.get(field) or ""
            words = tokenize(text)
            tokens.update(words)
            bigrams.update(" ".join(words[i : i + 2]) for i in range(len(words) - 1))

        for alias in item.get("aliases") or []:
            words = tokenize(alias)
            tokens.update(words)
            bigrams.update(" ".join(words[i : i + 2]) for i in range(len(words) - 1))

    flagged = []
    for token, count in tokens.most_common():
        if count >= 10 or token in FLAG_TERMS or len(token) <= 3:
            flagged.append({"token": token, "count": count})

    payload = {
        "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "token_count": sum(tokens.values()),
        "unique_tokens": len(tokens),
        "top_tokens": [{"token": t, "count": c} for t, c in tokens.most_common(200)],
        "flagged_tokens": flagged,
        "top_bigrams": [{"phrase": p, "count": c} for p, c in bigrams.most_common(200)],
    }

    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)

    print(f"Wrote {OUT_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
