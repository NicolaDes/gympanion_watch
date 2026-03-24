#!/usr/bin/env python3
"""Fake companion app for GymPanion ConnectIQ simulator testing.

The Garmin simulator 9.1.0 crashes when a companion socket connects via
registerForPhoneAppMessages (simulator bug on macOS). Use the GUI instead:

  Phone -> Watch (inject a workout):
    1. Run this script and choose a preset (or load a file).
    2. The JSON is printed and copied to the clipboard.
    3. In the simulator: File > Send Message to Device > paste > Send.

  Watch -> Phone (set_complete notifications):
    No companion socket needed. When no phone is connected the watch app
    logs the payload instead of transmitting it.
    View it in the simulator: View > Show Log.
"""

import json
import subprocess
import sys

# ---------------------------------------------------------------------------
# Workout presets
# ---------------------------------------------------------------------------

PRESETS = {
    "1": {
        "label": "Push Day",
        "payload": {
            "id": "push_day_001",
            "name": "Push Day",
            "exercises": [
                {"name": "Overhead Press", "sets": 4, "reps": 8,  "weight": 40.0, "rest": 120},
                {"name": "Bench Press",    "sets": 4, "reps": 8,  "weight": 60.0, "rest": 120},
                {"name": "Dips",           "sets": 3, "reps": 12, "weight": 0.0,  "rest": 90},
            ],
        },
    },
    "2": {
        "label": "Pull Day",
        "payload": {
            "id": "pull_day_001",
            "name": "Pull Day",
            "exercises": [
                {"name": "Pull-ups",      "sets": 4, "reps": 8,  "weight": 0.0,  "rest": 120},
                {"name": "Barbell Row",   "sets": 4, "reps": 8,  "weight": 60.0, "rest": 120},
                {"name": "Face Pulls",    "sets": 3, "reps": 15, "weight": 15.0, "rest": 60},
            ],
        },
    },
    "3": {
        "label": "Leg Day",
        "payload": {
            "id": "leg_day_001",
            "name": "Leg Day",
            "exercises": [
                {"name": "Squat",          "sets": 4, "reps": 8,  "weight": 80.0, "rest": 150},
                {"name": "Romanian DL",    "sets": 3, "reps": 10, "weight": 70.0, "rest": 120},
                {"name": "Leg Press",      "sets": 3, "reps": 12, "weight": 120.0,"rest": 90},
            ],
        },
    },
}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _copy_to_clipboard(text: str) -> bool:
    """Copy text to the macOS clipboard via pbcopy. Returns True on success."""
    try:
        subprocess.run(["pbcopy"], input=text.encode("utf-8"), check=True)
        return True
    except (FileNotFoundError, subprocess.CalledProcessError):
        return False


def _emit(payload: dict) -> None:
    """Print the payload and copy it to the clipboard."""
    text = json.dumps(payload, indent=2)
    print()
    print(text)
    print()

    if _copy_to_clipboard(text):
        print("  ✓ Copied to clipboard.")
    else:
        print("  (pbcopy not available — copy the JSON above manually.)")

    print()
    print("  Now in the simulator: File > Send Message to Device > paste > Send")
    print()


# ---------------------------------------------------------------------------
# Interactive menu
# ---------------------------------------------------------------------------

def _menu() -> None:
    print()
    print("GymPanion fake companion — simulator payload generator")
    print("=" * 54)
    for key, preset in PRESETS.items():
        print(f"  {key}  {preset['label']}")
    print("  f  Load from JSON file")
    print("  q  Quit")
    print()

    while True:
        try:
            cmd = input("> ").strip().lower()
        except (EOFError, KeyboardInterrupt):
            print()
            break

        if cmd in PRESETS:
            _emit(PRESETS[cmd]["payload"])

        elif cmd == "f":
            path = input("  JSON file path: ").strip()
            if not path:
                continue
            try:
                with open(path, "r") as f:
                    payload = json.load(f)
                _emit(payload)
            except FileNotFoundError:
                print(f"  [error] File not found: {path}")
            except json.JSONDecodeError as e:
                print(f"  [error] Invalid JSON: {e}")

        elif cmd == "q":
            break

        elif cmd == "":
            pass

        else:
            print(f"  Unknown command. Use {', '.join(PRESETS)}, f, or q.")


if __name__ == "__main__":
    _menu()
