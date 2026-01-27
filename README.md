# Ora — Local-First Workout Tracker with Voice Logging

Ora is a **local-first workout tracker** designed to reduce the friction of logging training sessions. It prioritizes **speed**, **privacy**, and **daily usability** through a voice-first workflow and a clean, minimal UI.

> Repo layout note: the Flutter application lives in the `Ora/` directory.

---

## Quick Links
- Project Charter: [PROJECT_CHARTER.md](PROJECT_CHARTER.md)
- Roadmap: [ROADMAP.md](ROADMAP.md)
- How to contribute: [CONTRIBUTING.md](CONTRIBUTING.md)
- Decisions log: [DECISIONS.md](DECISIONS.md)
- Governance: [GOVERNANCE.md](GOVERNANCE.md)

---

## Why Ora (Human-Centered Design)

Logging workouts is a classic “I’ll do it later” problem: it’s tedious, interrupts flow, and often requires too many taps. Ora’s design goal is to make logging feel like sending a voice note—fast enough to do between sets—while keeping your data under your control.

**Human-centered principles:**
- **Local-first by default:** workouts are stored locally so the app stays usable offline and keeps sensitive health routines private.
- **Low-friction capture:** voice logging and quick-entry flows reduce cognitive load during training.
- **Progress that’s easy to interpret:** simple charts and summaries emphasize clarity over complexity.
- **Accessible UI:** large tap targets, predictable navigation, and a high-contrast aesthetic for readability in gyms and outdoors.

---

## Prize Track Alignment

### Overall Prize (General Track) — Sponsored by Vobile
Ora’s innovation is practical: it attacks a real daily-life pain point (workout adherence + tracking) with an offline-first, voice-first workflow and an extensible AI layer for personalized assistance.

### The Design of Everyday Life (Human-Centered Design)
Ora is explicitly built around daily behavior:
- removes friction at the moment of action (between sets),
- reduces “tracking tax” (time/attention cost),
- keeps the user in control of their data and workflow.

### GitHub “Ship It” — Best Use of GitHub
We treat this repo like a real engineering project (planning → implementation → review → delivery).

**What judges want & how we meet it:**
- Public repository ✅
- Clear README with project + run/install ✅ (this file)
- 10+ commits ✅ (see commit history)
- 3+ pull requests ⬜ (see checklist below)
- 1+ PR reviewed by teammate ⬜
- 5+ issues, assigned ⬜

**Repo hygiene checklist (do this before final submission):**
- [ ] Create at least **5 Issues** with clear acceptance criteria; assign owners.
- [ ] Use **labels**: `bug`, `enhancement`, `ui`, `backend`, `ai`, `good first issue`.
- [ ] Open at least **3 PRs** (even small ones) linked to Issues via “Closes #X”.
- [ ] Require at least **1 teammate review** on one PR.
- [ ] Use a lightweight milestone (e.g., `Hackathon Demo`) to show delivery planning.

> Recommended: add `.github/` templates (`PULL_REQUEST_TEMPLATE.md`, issue templates) to make collaboration obvious to judges.

### Best Use of Gemini API
Ora is built to support AI-driven coaching and workflow automation. The most compelling Gemini-enabled features for Ora are:

- **Natural language “Coach”**: personalized training advice (split suggestions, recovery guidance, progression).
- **Structured logging assistant**: convert messy transcripts into clean structured sets/reps/weight.
- **Summaries**: post-workout recap, weekly insights, “what changed since last week?”

See **“Gemini Setup”** below for wiring the Gemini API key into your environment. The integration should emphasize **structured outputs** (JSON) for reliability and easy storage in SQLite.

### Beginner Hack
Ora is intentionally approachable:
- clear module boundaries (UI, state, persistence, voice/AI),
- a straightforward local-first data model,
- “good first issue” tasks that beginners can contribute safely (UI polish, accessibility, seed data cleanup, etc.).

### Best User Design (UX/UI)
The UI philosophy is minimal, readable, and task-oriented:
- log quickly,
- review progress at a glance,
- export/share summaries when needed.

---

## Core Features (Current + Intended)
- **Local-first workout logging** (offline-capable)
- **Voice capture pipeline** (record audio → transcribe → interpret)
- **Exercise catalog + muscle mapping** (seeded content)
- **Progress charts** (volume, frequency, etc.)
- **Export** (PDF/Excel-friendly workflows)
- **Cross-platform**: Android, iOS, Linux, macOS, Windows

---

## Tech Stack
**App:** Flutter (Dart)  
**State management:** Riverpod  
**Persistence:** SQLite (`sqflite` + desktop FFI)  
**Voice:** audio recording + offline transcription (Vosk)  
**On-device AI (optional):** `llama.cpp` via Dart bindings  
**Auth (mobile):** Firebase Auth (Google / Apple sign-in capable)  
**Storage (optional):** Firebase Storage

---

## Getting Started (Run Locally)

### Prerequisites
- Flutter SDK installed (Dart 3.3+ recommended)
- Platform toolchains:
  - **Android:** Android Studio + SDK
  - **iOS:** Xcode (macOS only)
  - **Desktop:** standard Flutter desktop requirements for your OS

### Install & Run
From the repository root:

```bash
cd Ora
flutter pub get
flutter run
```

To run a specific platform:

```bash
flutter run -d android
# or: ios, linux, windows, macos, chrome
```

---

## Platform Notes

### Desktop (Linux/Windows/macOS)

Desktop builds use SQLite via FFI automatically.

### Mobile (Android/iOS)

Mobile builds initialize Firebase (if configured). If you don’t need sign-in for the demo, you can keep the experience local-first and disable auth flows in the UI.

---

## Voice + Model Assets

### Vosk (Offline Speech-to-Text)

The repo includes a Vosk model asset reference. If voice logging isn’t working:

1. Confirm microphone permissions.
2. Confirm the Vosk model asset is present and accessible at runtime.

### On-Device LLM (Optional)

If you enable on-device inference, place your `.gguf` model files under the expected assets path (see `assets/models/llm/`). For hackathon demos, keep models small to reduce startup time.

---

## Gemini Setup (Recommended for Hackathon Submission)

Ora’s AI layer is strongest when it turns natural language into **structured workout data** (JSON) and stores it locally.

1. Create a Gemini API key in Google AI Studio.
2. Store it as an environment variable for local development:

```bash
export GEMINI_API_KEY="YOUR_KEY_HERE"
```

3. In the app, call Gemini’s `generateContent` endpoint and request **JSON output** for a schema like:

```json
{
  "date": "YYYY-MM-DD",
  "workout_name": "string",
  "exercises": [
    {"name": "string", "sets": [{"reps": 10, "weight": 225}]}
  ]
}
```

**Judges care about:** reliability + real user value. Prefer deterministic JSON-mode outputs, validate them, then write to SQLite.

---

## Repository Workflow (How We Ship)

* `main` is always demoable.
* Feature branches use the pattern: `feature/<short-name>` or `fix/<short-name>`.
* Every meaningful change goes through a PR linked to an Issue.
* At least one PR gets teammate review (for the “Ship It” requirement).

---

## Project Structure (High Level)

* `Ora/` — Flutter app root
* `Ora/lib/` — application code (UI, state, services)
* `Ora/assets/` — icons, diagrams, voice models, seed data
* `Ora/third_party/` — local overrides for native/AI dependencies (when needed)

---

## Team

* Raul Valle - PhD in Electrical and Computer Engineering
* Eric Zhu - BS in Computer Science
* Samuel Schneider - BS in *
* Alejandro Jimenez - BS in *
* Haley Tarala - BS in *
* Matty Maloni - BS in *
