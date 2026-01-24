# Ora Orb (Floating Input Hub)

## Goals
- Always-available input entry point across all tabs.
- One-tap capture for camera, upload, mic, and text.
- Auto-route to the most relevant section with minimal friction.
- Draggable with a dock zone; optional hide/unhide.

## Placement + Dock
- Default dock: upper/middle right.
- Dock zone appears while dragging; orb snaps in with a spring.
- Safe-area aware; avoids status bar and bottom nav.
- User can drag and pin anywhere; orb persists position.

## States
- **Idle (docked):** Small orb, subtle pulse.
- **Idle (floating):** Orb stays where user pinned it.
- **Expanded:** Tap orb to open input deck.
- **Capturing:** Mic recording with wavy ring animation and live partial text.
- **Routing:** Short "classifying" state before navigation.
- **Hidden:** Orb collapses to a thin tab at screen edge; tap to restore.

## Input Deck
- 2x2 grid: Camera, Upload, Mic, Text.
- Mini-card with glass styling; closes on outside tap.
- Secondary actions: Hide/unhide toggle; drag hint.

## Routing Behavior
- Classify input locally with keyword heuristics and input-type bias.
- Route to Training / Diet / Appearance / Leaderboard / Settings.
- If destination is disabled (Appearance), show a snackbar and route to Settings.
- Always show a short "Routed to X · Change" snackbar for manual override.

## Mic Capture
- Immediate capture on tap.
- Wavy ring animation around orb while recording.
- Auto-stop on silence/final result; manual stop supported.

## Text Capture
- Bottom sheet with multi-line text.
- Submit routes using same classifier.

## Persistence
- Stored in app settings (key/value): hidden, docked, position.

## Accessibility
- Tap targets >= 44px.
- Obeys safe areas.
- All actions accessible without drag.
