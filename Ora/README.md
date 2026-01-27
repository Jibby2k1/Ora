# Ora

Local-first fitness companion for training sessions, diet logging, and appearance tracking.

## Overview
Ora is a Flutter app that keeps all core data on-device and focuses on fast logging, clear visuals, and optional cloud-assisted parsing. It combines program-based training, voice-logged sessions, diet tracking, and appearance journaling into a single experience.

## Project Docs
Project governance and planning live at the repo root:
- `PROJECT_CHARTER.md`
- `ROADMAP.md`
- `CONTRIBUTING.md`
- `DECISIONS.md`
- `GOVERNANCE.md`

## Features
- Training programs with days, exercises, and set-plan blocks
- Session logging with rest timer, undo/redo, and exercise matching
- Voice capture pipeline (push-to-talk, optional wake word) with local NLU and optional cloud LLM parsing
- Exercise catalog and history views with per-exercise performance history
- Training landing screen with muscle stats grid and interactive anatomy (front/back, male/female SVGs)
- Diet logging with macros/micros, goals, and day/week/month summaries
- Meal entry via manual input, speech-to-text, photo/file analysis (optional cloud)
- Appearance tracking with progress rings, notes, measurements, and photo uploads
- Upload queue screen for diet/appearance analysis tasks
- Leaderboard view with basic activity scoring
- Settings for units, rest defaults, voice, cloud provider/model, and profile info

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
- Flutter UI with tabbed shell navigation
- Local-first SQLite via `sqflite` with schema migrations
- Command bus for deterministic session logging actions, with undo/redo
- Voice pipeline: STT -> rule-based NLU -> optional LLM parser -> command dispatch
- Seeded exercise catalog + muscle map + demo history

## Data model
See `lib/data/db/schema.dart` for table definitions.

## Voice examples
- "chest press machine, 185 for 8"
- "switch to lat pulldown"
- "rest 2 minutes"
- "undo"

## Limitations
- No accounts or cloud sync by default
- Wake word only during active session and foreground
