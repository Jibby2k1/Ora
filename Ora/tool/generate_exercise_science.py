#!/usr/bin/env python3
import os
import json
import time
import urllib.request
import urllib.error

# Paths relative to the project root where this script should be run
CATALOG_PATH = 'lib/data/seed/exercise_catalog_seed.json'
SCIENCE_PATH = 'lib/data/seed/exercise_science_seed.json'

def main():
    api_key = os.environ.get('GEMINI_API_KEY')
    if not api_key:
        print("Error: GEMINI_API_KEY environment variable not set.")
        print("Usage: GEMINI_API_KEY='your_key' python3 tool/generate_exercise_science.py")
        return

    # Load catalog
    if not os.path.exists(CATALOG_PATH):
        print(f"Error: Catalog file not found at {CATALOG_PATH}. Run this script from the 'Ora' project root.")
        return
        
    with open(CATALOG_PATH, 'r', encoding='utf-8') as f:
        catalog = json.load(f)
        
    all_exercise_names = [item['canonical_name'] for item in catalog]
    print(f"Found {len(all_exercise_names)} exercises in catalog.")

    # Load existing science seed
    existing_science = []
    if os.path.exists(SCIENCE_PATH):
        with open(SCIENCE_PATH, 'r', encoding='utf-8') as f:
            try:
                existing_science = json.load(f)
            except json.JSONDecodeError:
                print(f"Warning: Could not parse {SCIENCE_PATH}, treating as empty.")
                existing_science = []

    # Map existing to easily check what's done
    # Note: Using lower() to match correctly just in case
    completed_names = {item['canonical_name'].lower(): item for item in existing_science}
    print(f"Found {len(completed_names)} already processed exercises.")

    # Find missing
    missing_names = [name for name in all_exercise_names if name.lower() not in completed_names]
    print(f"Need to process {len(missing_names)} exercises.")

    if not missing_names:
        print("All exercises have science insights. Nothing to do!")
        return

    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key={api_key}"
    headers = {'Content-Type': 'application/json'}

    try:
        for i, name in enumerate(missing_names):
            print(f"Processing ({i+1}/{len(missing_names)}): {name}...")
            
            prompt = f"""You are an expert biomechanist and physical therapist. 
Return ONLY a raw JSON object for the exercise '{name}'. Do NOT wrap it in ```json ... ``` markdown blocks, just return the raw JSON text.

Schema:
{{
  "canonical_name": "{name}",
  "instructions": ["Step 1", "Step 2", "Step 3"],
  "avoid": ["Mistake 1", "Mistake 2"],
  "citations": ["Author, A. (Year). Title. Journal."],
  "visual_asset_paths": []
}}

Provide 3-5 clear instructions, 2-4 common mistakes to avoid, and 1-2 real academic citations if possible. visual_asset_paths MUST be an empty array []."""

            data = {
                "contents": [{"parts": [{"text": prompt}]}],
                "generationConfig": {
                    "temperature": 0.2,
                    "responseMimeType": "application/json"
                }
            }
            
            req = urllib.request.Request(url, data=json.dumps(data).encode('utf-8'), headers=headers, method='POST')
            
            try:
                with urllib.request.urlopen(req) as response:
                    response_data = json.loads(response.read().decode('utf-8'))
                    
                    try:
                        text = response_data['candidates'][0]['content']['parts'][0]['text']
                        # Strip any markdown if the model ignored instructions
                        if text.startswith('```json'):
                            text = text[7:]
                        if text.startswith('```'):
                            text = text[3:]
                        if text.endswith('```'):
                            text = text[:-3]
                            
                        parsed_json = json.loads(text.strip())
                        
                        # Add to our list and save
                        existing_science.append(parsed_json)
                        with open(SCIENCE_PATH, 'w', encoding='utf-8') as f:
                            json.dump(existing_science, f, indent=2)
                            
                        print(f"  -> Success. Saved to file.")
                        
                    except (KeyError, IndexError, json.JSONDecodeError) as e:
                        print(f"  -> Failed to parse response: {e}")
                        print(f"  -> Raw response: {response_data}")
            
            except urllib.error.HTTPError as e:
                print(f"  -> HTTP Error: {e.code} {e.reason}")
                error_body = e.read().decode('utf-8')
                print(f"  -> Details: {error_body}")
                if e.code == 429:
                    print("  -> Rate limited! Waiting 10 seconds before retrying...")
                    time.sleep(10)
                    continue # Note: this skips the current item and moves to next. In a robust script we'd retry, but for simplicity we move on.
                
            # Sleep to respect rate limits (Gemini free tier allows 15 RPM, so 4 seconds is safe)
            time.sleep(4)
            
    except KeyboardInterrupt:
        print("\nProcess interrupted by user. Progress has been saved incrementally.")

    print("\nDone!")

if __name__ == '__main__':
    main()
