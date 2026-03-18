#!/bin/bash
# simulate.sh — Launch the Garmin simulator and load the compiled app.
#
# Requires: app/bin/workspace.prg must already exist (run build.sh first).
# Requires: the project must be open in VS Code with "Reopen in Container".
#
# Usage:
#   ./scripts/simulate.sh [device]
#
#   device  ConnectIQ device ID to load the app for (default: fr265)
#
# Testing Communications without a phone (SDK 8.x):
#
#   Phone -> Watch (inject a workout):
#     Use the simulator menu: File > Send Message to Device
#     Paste the JSON from scripts/send-test-workout.sh and click Send.
#
#   Watch -> Phone (set_complete notifications):
#     No companion simulator ships with SDK 8.x. When the watch app is running
#     without a connected phone, outgoing payloads are printed to the simulator
#     log (View > Show Log) instead of being transmitted.
#     Full end-to-end testing requires ADB + an Android device running
#     Garmin Connect: adb forward tcp:7381 tcp:7381

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

DEVICE="${1:-fr265}"

# ── Step 1: X11 ───────────────────────────────────────────────────────────────
echo "[1/3] Allowing X11 access to Docker..."
"$SCRIPT_DIR/allowX11.sh"

# ── Step 2: Find the running devcontainer ─────────────────────────────────────
echo "[2/3] Locating devcontainer..."

CONTAINER_ID=$(docker ps \
  --filter "label=devcontainer.local_folder=$REPO_ROOT" \
  --format "{{.ID}}" | head -1)

if [[ -z "$CONTAINER_ID" ]]; then
  echo ""
  echo "  ERROR: Dev container is not running."
  echo ""
  echo "  Open this project in VS Code and run:"
  echo "    Dev Containers: Reopen in Container"
  echo ""
  exit 1
fi

CONTAINER_NAME=$(docker ps --filter "id=$CONTAINER_ID" --format "{{.Names}}")
echo "  Found: $CONTAINER_NAME ($CONTAINER_ID)"

# ── Step 3: Launch simulator and load app ────────────────────────────────────
echo "[3/3] Launching simulator for '$DEVICE'..."
echo "      (Close the simulator window to exit)"
echo "      Tip: File > Send Message to Device to inject a workout from the companion"
echo ""

docker exec \
  -e DISPLAY="${DISPLAY:-:0}" \
  "$CONTAINER_ID" \
  bash -c "
    set -e

    MONKEYBRAINS=\$(ls ~/.Garmin/ConnectIQ/Sdks/*/bin/monkeybrains.jar 2>/dev/null | sort -V | tail -1)

    if [[ -z \"\$MONKEYBRAINS\" ]]; then
      echo ''
      echo '  ERROR: ConnectIQ SDK not found in ~/.Garmin/ConnectIQ/Sdks/'
      echo '  Install the SDK inside the devcontainer terminal:'
      echo '    /workspace/sdk/bin/sdkmanager'
      echo ''
      exit 1
    fi

    SDK_BIN=\"\$(dirname \"\$MONKEYBRAINS\")\"

    if [[ ! -f /workspace/bin/workspace.prg ]]; then
      echo ''
      echo '  ERROR: bin/workspace.prg not found. Run build.sh first:'
      echo '    ./scripts/build.sh'
      echo ''
      exit 1
    fi

    echo '--> Starting simulator...'
    \"\$SDK_BIN/connectiq\" &
    SIM_PID=\$!

    # Give the simulator time to open its IPC socket before monkeydo connects
    sleep 3

    echo '--> Loading app into simulator...'
    \"\$SDK_BIN/monkeydo\" /workspace/bin/workspace.prg ${DEVICE}

    # Block until the simulator window is closed
    wait \"\$SIM_PID\"
  "
