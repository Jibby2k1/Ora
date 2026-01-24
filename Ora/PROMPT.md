# Build Prompt: Ora (feature-complete)

You are a senior Flutter engineer. Build a local-first fitness app named "Ora" that matches the feature set described below. Use Dart/Flutter, SQLite via `sqflite`, and a clean layered architecture (core/data/domain/ui). Keep all data on-device by default. Optional cloud features must be opt-in and send only text (no audio).

## Core product goals
- Fast, offline-first logging for workouts, diet, and appearance.
- A single tabbed shell with training, diet, appearance, leaderboard, and settings.
- Voice-driven session logging with deterministic command dispatch and undo/redo.

## App structure
- `lib/app.dart` bootstraps DB, seeds exercise catalog and muscle map, and loads demo history.
- `lib/main.dart` runs the app.
- `lib/core`: theme, command bus, voice pipeline, cloud helpers.
- `lib/data`: db + schema + repositories + seed data.
- `lib/domain`: models + services.
- `lib/ui`: screens + widgets.

## UI shell
- Bottom navigation tabs:
  - Training
  - Diet
  - Appearance (toggleable by settings)
  - Leaderboard
  - Settings
- Dark theme, glassmorphic cards for primary sections.

## Training (Programs + Sessions)
- Programs screen with:
  - Create/select/delete programs
  - Day picker to pick a program day and start a session
  - Program editor and day editor (exercise list + set-plan blocks)
  - Calories bar that shows workout calories vs BMR for a date range
  - Muscle stats grid and interactive anatomy (front/back toggle, male/female SVGs)
- Session screen with:
  - Active session exercise list and sets
  - Rest timer (default from settings)
  - Undo/redo stack
  - Manual log controls + voice input
  - Exercise matching against current day, other days, and catalog
- History:
  - Exercise catalog
  - Per-exercise performance history (sets over time)

## Voice pipeline
- Push-to-talk STT and optional wake word (settings toggle)
- Command parsing flow:
  - Local NLU parser for structured commands
  - Optional LLM parsing (Gemini or OpenAI) when cloud enabled
  - Command bus with reducers that update session data
- Show voice debug panel (raw transcript, chosen parser, parsed fields)

## Diet
- Diet overview with day/week/month scales
- Summary cards: calories + macros (protein, carbs, fat) and micros (fiber, sodium)
- Goals editor (calories, macros, fiber, sodium)
- Meal logging:
  - Manual entry (name + nutrition fields + notes)
  - Speech-to-text to prefill meal name
  - Image/file upload for cloud analysis (optional)
- Recent meal list with edit/delete

## Appearance
- Consent gate for appearance features (local storage only)
- Progress rings for face/physique/style scores
- Fit feedback module with notes and score
- Confidence and routine tracking
- Measurements (waist/hips/chest/weight)
- Style notes with weekly summary
- Timeline of entries
- Photo/file uploads, queued via upload service

## Uploads
- Central uploads screen that lists queued diet/appearance analysis tasks with status.

## Settings
- Units (lb/kg), increment size, rest defaults
- Voice on/off, wake word toggle
- Cloud parsing toggle + provider selector (Gemini/OpenAI)
- API key storage on-device (Keychain/Keystore) + model selection
- Account placeholder and local-only profile screen
- Appearance access toggle

## Data model (SQLite)
Include tables for:
- workout_session, session_exercise, session_set
- program, program_day, program_day_exercise, set_plan_block
- exercise catalog and muscle map
- diet_entry
- appearance_entry
- settings key/value

## Seeds
- Exercise catalog JSON
- Muscle map JSON (used for anatomy highlights)
- Demo history seed

## Behavior details
- Appearance tab can be disabled via settings and adjusts tab index safely.
- Cloud parsing sends only text transcripts, never audio.
- Use repository classes for data access.
- Use services for cross-cutting calculations (e.g., calorie service).

Deliver all code, assets, and minimal docs (README) to run locally.
