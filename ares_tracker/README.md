# ares_tracker

Local-first workout tracking app with voice logging.

## Run
- `flutter pub get`
- `flutter run`

## Firebase config
Firebase config files are not committed. Copy the examples and fill in your own keys:

```bash
cp android/app/google-services.json.example android/app/google-services.json
cp ios/Runner/GoogleService-Info.plist.example ios/Runner/GoogleService-Info.plist
```

## Architecture
- Local-first SQLite via `sqflite` with schema migrations.
- Command bus for deterministic logging actions, undo/redo.
- Voice pipeline: push-to-talk STT -> rule-based NLU -> command dispatch.

## Data model
See `lib/data/db/schema.dart` for table definitions.

## Voice examples
- "chest press machine, 185 for 8"
- "switch to lat pulldown"
- "rest 2 minutes"
- "undo"

## Limitations
- No cloud, no accounts, no analytics.
- No bodyweight exercises in MVP.
- Wake word only during active session and foreground (scaffolded).
