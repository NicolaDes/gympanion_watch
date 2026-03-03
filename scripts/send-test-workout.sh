#!/bin/bash
# send-test-workout.sh — Send a test workout to the running GymPanion simulator.
#
# This script sends a workout payload to the ConnectIQ simulator to test
# the companion workout injection feature (CompanionCommService).
#
# Prerequisites:
#   1. The simulator must be running (use ./scripts/simulate.sh first).
#   2. The VS Code devcontainer must be active.
#
# How it works:
#   - Prints the JSON test payload to stdout so you can inspect it.
#   - Writes the payload to /tmp/test-workout.json inside the devcontainer.
#   - Prints step-by-step instructions for injecting the message via the
#     simulator GUI (File > Send Message to Device).
#
# The watch app expects the payload to be a JSON object matching this shape:
#   {
#     "id":        <string>,   — unique workout ID
#     "name":      <string>,   — human-readable workout name
#     "exercises": [           — array of exercise objects
#       {
#         "name":   <string>,  — exercise name
#         "sets":   <number>,  — target number of sets
#         "reps":   <number>,  — target reps per set
#         "weight": <number>,  — target weight in kg (can be float)
#         "rest":   <number>   — rest duration in seconds
#       }, ...
#     ]
#   }

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# ---------------------------------------------------------------------------
# Test payload — "Push Day" with three exercises
# ---------------------------------------------------------------------------
TEST_PAYLOAD='{
  "id": "test_push_day_001",
  "name": "Push Day (from companion)",
  "exercises": [
    {
      "name": "Overhead Press",
      "sets": 4,
      "reps": 8,
      "weight": 40.0,
      "rest": 120
    },
    {
      "name": "Incline DB Press",
      "sets": 3,
      "reps": 12,
      "weight": 24.0,
      "rest": 90
    },
    {
      "name": "Lateral Raises",
      "sets": 3,
      "reps": 15,
      "weight": 10.0,
      "rest": 60
    }
  ]
}'

echo "=== Test Workout Payload ==="
echo "$TEST_PAYLOAD"
echo ""

# ---------------------------------------------------------------------------
# Instructions for simulator injection (GUI method — most reliable)
# ---------------------------------------------------------------------------
echo "=== How to send this workout to the simulator ==="
echo ""
echo "Option 1 — Simulator GUI (recommended):"
echo "  1. Make sure the simulator is running (./scripts/simulate.sh)."
echo "  2. In the ConnectIQ simulator window, click on the fr265 watch face."
echo "  3. Go to File > Send Message to Device."
echo "  4. In the dialog, paste the JSON payload printed above."
echo "  5. Click Send."
echo "  The watch app will receive the message, update the workout, reset"
echo "  the session, and redraw the dashboard with the new exercise name."
echo ""
echo "Option 2 — Companion App Simulator:"
echo "  The ConnectIQ SDK includes a companion app simulator binary."
echo "  Look for it at:"
echo "    ~/.Garmin/ConnectIQ/Sdks/<version>/bin/companionsimulator"
echo "  Launch it and use it to transmit the payload above to the watch app."
echo ""

# ---------------------------------------------------------------------------
# Write payload to /tmp inside the devcontainer for convenience
# ---------------------------------------------------------------------------
CONTAINER_ID=$(docker ps \
  --filter "label=devcontainer.local_folder=$REPO_ROOT" \
  --format "{{.ID}}" | head -1)

if [[ -z "$CONTAINER_ID" ]]; then
    echo "WARNING: Dev container not found. Cannot write payload to container."
    echo "  Start the devcontainer in VS Code first, then re-run this script."
    echo "  You can still use the payload printed above manually."
    exit 0
fi

echo "Writing payload to /tmp/test-workout.json inside the devcontainer (ID: $CONTAINER_ID)..."
docker exec "$CONTAINER_ID" bash -c "cat > /tmp/test-workout.json << 'PAYLOAD_EOF'
$TEST_PAYLOAD
PAYLOAD_EOF
echo 'Payload written to /tmp/test-workout.json'
cat /tmp/test-workout.json"

echo ""
echo "Payload is ready at /tmp/test-workout.json inside the container."
echo "Use Option 1 (simulator GUI) to inject it into the running watch app."
