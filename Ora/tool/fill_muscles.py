#!/usr/bin/env python3
import argparse
import json
import os
import time
import urllib.parse
import urllib.request

MUSCLES = [
    "Chest",
    "Back",
    "Lats",
    "Upper Back",
    "Traps",
    "Shoulders",
    "Front Delts",
    "Side Delts",
    "Rear Delts",
    "Biceps",
    "Triceps",
    "Forearms",
    "Abs",
    "Obliques",
    "Quads",
    "Hamstrings",
    "Glutes",
    "Calves",
    "Adductors",
    "Abductors",
    "Hip Flexors",
]


def build_prompt(name: str) -> str:
    muscle_list = "\n".join(f"- {m}" for m in MUSCLES)
    return f"""You label exercises with muscle groups.
Return ONLY a single JSON object. No markdown. No extra text.
Schema:
{{
  "primary": string,
  "secondary": [string]
}}
Rules:
- Choose primary from this list:
{muscle_list}
- Secondary must also come from the list.
- Keep secondary list small (0-3).
- If unsure, choose the closest primary and leave secondary empty.
- For "{name}", respond with JSON only.
"""


def extract_json(text: str):
    start = text.find("{")
    end = text.rfind("}")
    if start == -1 or end == -1 or end <= start:
        return None
    try:
        return json.loads(text[start : end + 1])
    except Exception:
        return None


def call_gemini(api_key: str, model: str, prompt: str):
    params = urllib.parse.urlencode({"key": api_key})
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?{params}"
    payload = {
        "contents": [{"role": "user", "parts": [{"text": prompt}]}],
        "generationConfig": {"temperature": 0.0, "topP": 0.9, "topK": 40, "maxOutputTokens": 128},
    }
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=20) as resp:
        body = resp.read().decode("utf-8")
    parsed = json.loads(body)
    candidates = parsed.get("candidates") or []
    if not candidates:
        return None
    content = candidates[0].get("content") or {}
    parts = content.get("parts") or []
    if not parts:
        return None
    return parts[0].get("text") or ""


def normalize_secondary(values):
    out = []
    for v in values:
        if not v:
            continue
        s = str(v).strip()
        if not s:
            continue
        out.append(s)
    return out[:3]


def main():
    parser = argparse.ArgumentParser(description="Fill missing muscle groups in the catalog via Gemini.")
    parser.add_argument("--input", default="lib/data/seed/exercise_catalog_seed.json")
    parser.add_argument("--output", default="")
    parser.add_argument("--limit", type=int, default=0, help="Limit number of fills (0 = no limit).")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    api_key = os.environ.get("GEMINI_API_KEY", "").strip()
    if not api_key:
        print("Missing GEMINI_API_KEY in environment.")
        return 1

    with open(args.input, "r", encoding="utf-8") as f:
        data = json.load(f)

    updated = 0
    for item in data:
        primary = (item.get("primary_muscle") or "").strip()
        secondary = item.get("secondary_muscles") or []
        if primary:
            continue
        if args.limit and updated >= args.limit:
            break
        name = item.get("canonical_name", "").strip()
        if not name:
            continue
        prompt = build_prompt(name)
        try:
            text = call_gemini(api_key, "gemini-2.5-pro", prompt)
        except Exception as e:
            print(f"Request failed for {name}: {e}")
            time.sleep(1.0)
            continue
        payload = extract_json(text or "")
        if not payload:
            print(f"No JSON for {name}")
            time.sleep(0.5)
            continue
        primary = str(payload.get("primary") or "").strip()
        secondary = normalize_secondary(payload.get("secondary") or [])
        if not primary:
            print(f"Missing primary for {name}")
            time.sleep(0.5)
            continue
        item["primary_muscle"] = primary
        item["secondary_muscles"] = secondary
        updated += 1
        print(f"[{updated}] {name} -> {primary} / {secondary}")
        time.sleep(0.25)

    if args.dry_run:
        print("Dry run complete.")
        return 0

    output_path = args.output.strip() or args.input
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")

    print(f"Updated {updated} exercises. Wrote {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
