#!/bin/bash
# simulate.sh — Build the GymPanion app and launch it in the Garmin simulator.
#
# Requires: the project must be open in VS Code with "Reopen in Container".
# The script finds the running devcontainer and runs the build + simulator
# inside it via docker exec.
#
# Usage:
#   ./scripts/simulate.sh [device]
#
#   device  ConnectIQ device ID to compile for (default: fr265)
#           Must match a directory in ~/.Garmin/ConnectIQ/Devices/ inside the container.
#           Use fr265_sim only if you have downloaded that device definition via the SDK Manager.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
DEVICE="${1:-fr265}"

# ── Step 1: X11 ───────────────────────────────────────────────────────────────
echo "[1/3] Allowing X11 access to Docker..."
"$SCRIPT_DIR/allowX11.sh"

# ── Step 2: Find the running devcontainer ─────────────────────────────────────
echo "[2/3] Locating devcontainer..."

# VS Code labels every devcontainer with devcontainer.local_folder=<project root>
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

# ── Step 3: Build + simulate inside the devcontainer ─────────────────────────
echo "[3/3] Building for '$DEVICE' and launching simulator..."
echo "      (Close the simulator window to exit)"
echo ""

docker exec \
  -e DISPLAY="${DISPLAY:-:0}" \
  "$CONTAINER_ID" \
  bash -c "
    set -e

    # Find the latest installed SDK version
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
    SDK_NAME=\"\$(basename \"\$(dirname \"\$SDK_BIN\")\")\"
    echo \"--> SDK: \$SDK_NAME\"

    echo '--> Compiling...'
    mkdir -p /workspace/bin
    java -Xms1g \
      -Dfile.encoding=UTF-8 \
      -Dapple.awt.UIElement=true \
      -jar \"\$MONKEYBRAINS\" \
      -o /workspace/bin/workspace.prg \
      -f /workspace/monkey.jungle \
      -y /workspace/developer_key \
      -d ${DEVICE} \
      -w
    echo '--> Build OK: bin/workspace.prg'

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
