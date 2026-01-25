# Ora - Comprehensive Documentation

## Overall Purpose

**Ora** is a local-first fitness companion mobile application built with Flutter that unifies three pillars of fitness tracking into one frictionless experience:

1. **Workout Training** - Structured program management and live session logging
2. **Diet Tracking** - Meal logging with macro/micro nutrient tracking
3. **Appearance Monitoring** - Body measurements and visual progress tracking

### Core Philosophy

| Principle | Description |
|-----------|-------------|
| **Local-First** | All data stays on-device by default. No accounts required. |
| **Voice-Driven** | Log sets naturally with commands like "bench press 185 for 8" |
| **Privacy-Focused** | Cloud features are opt-in and only send text, never audio files |
| **Frictionless** | Minimize taps and typing during workouts |

### Positive Impact
- **Removes friction** from fitness logging - voice commands eliminate fumbling with phones mid-workout
- **Builds consistency** - gamified leaderboard rewards logging habits
- **Provides insights** - tracks PRs, volume trends, and muscle distribution over time
- **Respects privacy** - users own their data completely

---

## Tab Overview & Benefits

### 1. Training Tab
**Purpose:** Central hub for workout program management and live session logging

**Features:**
- Create structured training programs with multiple days
- Configure exercises with detailed set plans (rep ranges, weight rules, rest periods, RPE/RIR targets)
- Start live sessions with voice or manual logging
- Track personal records automatically
- View exercise history and performance trends
- Calorie estimation based on workout volume

**Benefits:**
- Progressive overload tracking ensures continuous improvement
- Voice logging keeps hands free for lifting
- Undo/redo stack prevents data loss from mistakes
- Smart day selection suggests next workout based on history

### 2. Diet Tab
**Purpose:** Nutrition tracking and goal management

**Features:**
- Log meals with calories, protein, carbs, fat, fiber, sodium
- Set daily/weekly nutrition goals
- View aggregated stats over time (daily, weekly, monthly)
- Optional cloud-based meal image analysis

**Benefits:**
- Comprehensive macro/micro tracking in one place
- Goal visualization helps adherence
- Voice input for quick meal logging

### 3. Appearance Tab
**Purpose:** Body composition and aesthetic progress tracking

**Features:**
- Progress rings for skin, physique, and style scores
- Body measurements (waist, chest, hips, weight)
- Timeline with notes and progress photos
- Optional cloud-based appearance analysis

**Benefits:**
- Holistic view of fitness beyond just numbers
- Visual timeline motivates long-term consistency
- Privacy-gated - requires explicit opt-in

### 4. Leaderboard Tab
**Purpose:** Gamification layer to encourage consistency

**Features:**
- Activity scoring based on 30-day rolling window
- Training score: volume (kg x reps) + set count
- Diet score: meal logging consistency
- Appearance score: engagement metrics

**Benefits:**
- Gamification drives habit formation
- Competitive element adds motivation
- Rewards consistency over intensity

### 5. Settings Tab
**Purpose:** App configuration and personalization

**Features:**
- User profile (age, height, weight, bio)
- Unit preferences (lbs/kg, height units)
- Voice settings (enable/disable, wake word)
- Cloud provider configuration (Gemini/OpenAI API keys)
- Feature toggles (Appearance tab visibility)
- Orb position and dock settings

**Benefits:**
- Full control over app behavior
- Secure API key storage (Keychain/Keystore)
- Customizable to individual preferences

---

## Frameworks & Tools

### Core Framework
| Technology | Purpose | Why Chosen |
|------------|---------|------------|
| **Flutter** (Dart 3.3+) | Cross-platform UI | Single codebase for Android, iOS, Linux, Windows, macOS |
| **Material Design 3** | UI components | Modern, accessible, consistent design language |
| **Riverpod** | State management | Compile-safe, testable, scalable state management |

### Database
| Technology | Purpose | Why Chosen |
|------------|---------|------------|
| **SQLite** via `sqflite` | Local persistence | Fast, reliable, zero-config embedded database |
| **sqflite_common_ffi** | Desktop support | Enables same SQLite on Linux/Windows/macOS |
| **7 migrations** | Schema evolution | Safe, versioned database updates |

### Voice & Speech
| Technology | Purpose | Why Chosen |
|------------|---------|------------|
| **vosk_flutter** | Local STT | Offline speech recognition, no cloud dependency |
| **record** | Audio capture | Cross-platform microphone access |
| **llama_cpp_dart** | Local LLM (prepared) | Optional on-device language understanding |

### Cloud Services (Opt-in)
| Technology | Purpose | Why Chosen |
|------------|---------|------------|
| **Firebase Auth** | Authentication | Industry-standard, secure, easy social auth |
| **Firebase Storage** | File uploads | Reliable cloud storage for photos |
| **Gemini API** | Cloud LLM parsing | Advanced natural language understanding |
| **OpenAI API** | Alternative LLM | Flexibility in provider choice |
| **Google Sign-In / Apple Sign-In** | Social auth | Familiar, trusted login methods |

### Data & File Handling
| Technology | Purpose | Why Chosen |
|------------|---------|------------|
| **http** | HTTP requests | Standard Dart HTTP client |
| **excel** | Excel import/export | Program import from spreadsheets |
| **syncfusion_flutter_pdf** | PDF export | Generate workout reports |
| **image_picker** | Camera/gallery | Capture progress photos |
| **file_picker** | File selection | Import programs from files |
| **image** | Image processing | Resize/optimize photos |

### Storage & Security
| Technology | Purpose | Why Chosen |
|------------|---------|------------|
| **flutter_secure_storage** | Secure storage | Keychain (iOS) / Keystore (Android) for API keys |
| **path_provider** | App directories | Platform-appropriate file paths |
| **flutter_svg** | SVG rendering | Anatomy diagrams for muscle mapping |

---

## Technical Architecture

### Layered Architecture (Clean Architecture)

```
lib/
├── main.dart                    # Entry point
├── app.dart                     # App bootstrap + initialization
├── core/                        # Cross-cutting concerns
│   ├── command_bus/            # Session logging commands + undo/redo
│   ├── voice/                  # STT + NLU + LLM parsing pipeline
│   ├── cloud/                  # Firebase + cloud services
│   ├── input/                  # Input routing + classification
│   └── theme/                  # Dark theme styling
├── data/                        # Data layer
│   ├── db/                     # SQLite database + migrations
│   ├── repositories/           # Data access objects
│   └── seed/                   # Exercise catalog, muscle map
├── domain/                      # Business logic
│   ├── models/                 # Data models
│   └── services/               # Business services
└── ui/                          # Presentation layer
    ├── screens/                # Main screens
    └── widgets/                # Reusable UI components
```

### Data Flow

```
User Input -> Input Router -> Command Bus -> Repository -> SQLite
                |
         Voice Pipeline (if voice)
                |
         STT -> NLU Parser -> (Optional LLM) -> Structured Command
```

### Voice Pipeline Architecture

```
+-------------------------------------------------------------+
|                      Voice Pipeline                          |
+-------------------------------------------------------------+
|  1. Audio Capture (record package)                          |
|         |                                                    |
|  2. Speech-to-Text (Vosk - local, offline)                  |
|         |                                                    |
|  3. NLU Parser (rule-based command parsing)                 |
|         |                                                    |
|  4. Optional: Cloud LLM (Gemini/OpenAI for refinement)      |
|         |                                                    |
|  5. Muscle Enricher (adds muscle group context)             |
|         |                                                    |
|  6. Command Dispatch (LogSet, SwitchExercise, etc.)         |
+-------------------------------------------------------------+
```

### Command Bus Pattern

The app uses a command bus for deterministic session logging with undo/redo:

```dart
// Commands
LogSet, SwitchExercise, StartRestTimer, Undo, Redo, FinishWorkout

// Flow
User Action -> Command Created -> Dispatcher -> Reducer -> State Update
                                    |
                            UndoRedoStack (for history)
```

### Database Schema (Key Tables)

| Table | Purpose |
|-------|---------|
| `exercise` | 500+ exercises with equipment type, muscles, aliases |
| `program` | User training programs |
| `program_day` | Days within programs |
| `program_day_exercise` | Exercises assigned to days |
| `set_plan_block` | Detailed set configuration (reps, weight rules, rest) |
| `workout_session` | Individual workout records |
| `session_exercise` | Exercises performed in sessions |
| `set_entry` | Individual set data (weight, reps, RPE, RIR) |
| `diet_entry` | Meal records with nutrition data |
| `appearance_entry` | Appearance logging entries |
| `user_profile` | User demographics |
| `app_setting` | Key-value configuration |

### Exercise Matching System

```
Input: "chest press machine 185 for 8"
         |
Normalization: lowercase, remove special chars
         |
Tokenization: ["chest", "press", "machine", "185", "8"]
         |
Phrase Fixups: handle speech errors ("lap pulldown" -> "lat pulldown")
         |
Fuzzy Scoring: match against exercise catalog
         |
Result: { exercise: "Machine Chest Press", weight: 185, reps: 8 }
```

### Input Hub (Ora Orb)

The floating Ora Orb provides always-accessible input:

| State | Behavior |
|-------|----------|
| Idle | Floating button, tap to expand |
| Expanded | Shows input options (mic, camera, text, file) |
| Capturing | Recording audio or processing input |
| Routing | Classifying input -> routing to relevant module |
| Hidden | During certain modal interactions |

Auto-routing classifies input intent:
- Training keywords -> Workout logging
- Diet keywords -> Meal logging
- Appearance keywords -> Appearance module
- File upload -> Program import

---

## Key Design Patterns

1. **Repository Pattern** - Data access abstraction
2. **Service Layer** - Business logic encapsulation
3. **Command Bus** - Deterministic session logging with undo/redo
4. **Singleton Services** - Voice engine, upload service, database
5. **Layered Architecture** - Core/Data/Domain/UI separation
6. **Async/Await** - Heavy use of Futures for I/O operations
7. **Riverpod Providers** - State management
8. **Custom Exceptions** - Error handling throughout

---

## Platform Support

- Android
- iOS
- Linux
- Windows
- macOS

Web platform is not supported due to local SQLite dependency.
