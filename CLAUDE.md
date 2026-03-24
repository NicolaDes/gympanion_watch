# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Garmin ConnectIQ watch app for gym exercise tracking, written in **Monkey C**. Targets the **fr265** device with `minApiLevel="5.2.0"`. App ID: `f98a251f-fbbe-4b0b-85de-d893670af9fe` (in `manifest.xml`).

## Architecture

### Layered structure

```
source/
  gympApp.mc            — AppBase: DI container, wires all services at startup
  core/
    WorkoutEngine.mc    — Central coordinator; owns session lifecycle and phase transitions
    SessionState.mc     — Mutable state bag; serialized to/from Application.Storage
    SequentialStrategy.mc — Implements TimelineStrategy: advance sets/exercises in order
    TimelineStrategy.mc — Abstract base for workout progression strategies
  domain/
    Workout.mc          — Workout { id, name, exercises[] }
    Exercise.mc         — Exercise { name, targetSets, targetReps, targetWeight, restDurationSec }
    ExerciseSet.mc      — Completed-set record
    MetricSnapshot.mc   — HR sample
  services/
    StaticWorkoutLoader.mc       — Hardcoded default workout (fallback when no companion workout)
    CompanionCommService.mc      — Phone ↔ watch via Toybox.Communications
    PersistenceService.mc        — All Application.Storage reads/writes
    SamplingEngine.mc            — HR sampling during PHASE_WORK
    EventRecorder.mc             — Appends structured events to the storage event log
    TimerService.mc              — Wraps Toybox.Timer; calls onTimerTick() every 1 s
    PhysiologicalProvider.mc     — Abstract HR provider interface
    RealPhysiologicalProvider.mc — Live HR from Activity.getActivityInfo()
    MockPhysiologicalProvider.mc — Simulated HR for simulator testing
  ui/
    DashboardView.mc             — Main workout screen (custom-drawn, no XML layout)
    DashboardDelegate.mc         — START/BACK input; phase-aware button routing
    WorkoutSummaryDelegate.mc    — Initial menu: "Start" + exercise list
    WorkoutReplaceConfirmDelegate.mc — Confirm/discard incoming companion workout
    ExitConfirmDelegate.mc       — Confirm app exit from dashboard BACK press
```

### Service wiring (gympApp.mc)

`gympApp` is the application-lifetime DI container. Dependency order at initialization:

```
PersistenceService
  └─ EventRecorder
PhysiologicalProvider (Real or Mock)
  └─ SamplingEngine(provider, eventRecorder)
TimerService
WorkoutEngine(timerService, samplingEngine, eventRecorder, persistenceService)
CompanionCommService(engine, persistenceService)
```

On `onStart()`: loads a companion workout from storage (if any), falls back to `StaticWorkoutLoader.loadDefaultWorkout()`, then either restores a saved session or starts a new one.

### Session lifecycle and phase state machine

`SessionState` holds all mutable workout state. Phase constants (defined at module scope in `SessionState.mc`):

```
PHASE_IDLE (0) → PHASE_WORK (1) → PHASE_REST (2) → back to PHASE_WORK
                                                   or PHASE_FINISHED (3)
```

- **IDLE → WORK**: user presses START (`engine.startSet()`)
- **WORK → REST**: user presses START again (`engine.completeSet(weight, reps)`); `SequentialStrategy.nextAction()` decides next exercise/set indices
- **REST → WORK**: user presses START early, or rest countdown reaches zero (haptic fires)
- **WORK/REST → FINISHED**: `SequentialStrategy` returns `finished: true` after last set

On restore from storage, WORK/REST phases are normalized back to IDLE (timer context is lost on crash/exit).

### Dashboard UI (DashboardView.mc)

Fully custom-drawn — no XML layout. Uses a y-cursor pattern: starts at y=44, advances by `dc.getFontHeight(font) + GAP_*` for each element. Three zones:
1. Header: exercise name, set indicator (`Set N / M`), phase badge (READY / WORK / REST)
2. Timer: `FONT_NUMBER_MEDIUM`, color changes yellow < 10 s and red when rest overtime
3. Stats: 3-column (REPS | HR | WEIGHT), shows target values from the current exercise

### Companion communication protocol

`CompanionCommService` handles both directions:

- **Phone → Watch** (`onMessageReceived`): receives a workout Dictionary, stores it as pending, shows a `WatchUi.Confirmation` dialog. On accept: persists to storage, calls `engine.setWorkout()` + `engine.startNewSession()`, fires `onWorkoutAccepted` callback to rebuild the summary menu.
- **Watch → Phone** (`sendSetComplete`): fire-and-forget Dictionary with `type: "set_complete"` + exercise metadata. Silently logs if no phone connected.

Incoming workout payload shape:
```json
{ "id": "...", "name": "...", "exercises": [
  { "name": "...", "sets": N, "reps": N, "weight": N, "rest": N }
] }
```

To inject a test workout into the running simulator: **File > Send Message to Device** in the simulator GUI. Watch → phone notifications are printed to the simulator log (**View > Show Log**) when no phone is connected.

### Persistence (Application.Storage keys)

| Key | Content |
|---|---|
| `active_session` | Serialized `SessionState` Dictionary |
| `event_log` | Array of event Dictionaries (append-only) |
| `companion_workout` | Raw companion workout Dictionary |

`SessionState` serializes with short keys (`"sid"`, `"eix"`, `"cst"`, etc.) to minimize storage footprint.

### Resources (`resources/`)

- `strings/strings.xml` — Localizable strings (`@Strings.Id` in XML, `Rez.Strings.Id` in code)
- `layouts/layouts.xml` — XML layouts (only used by non-dashboard screens)
- `menus/menus.xml` — Menu definitions
- `properties.xml` — App properties

New screens follow the View + BehaviorDelegate pair pattern, pushed/popped via `WatchUi.pushView` / `WatchUi.popView` (or `WatchUi.switchToView` when replacing the root).

### Key Conventions

- `gympApp` acts as the DI root — services are created there and passed down via constructors; no globals.
- `WorkoutEngine` is the only component that mutates `SessionState`; UI reads it read-only via `engine.getCurrentState()`.
- All `Toybox.Communications` calls are guarded with `has` checks and `phoneConnected` checks to avoid errors in the simulator.
- `System.println("[Tag] message")` is the logging convention throughout.
