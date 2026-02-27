#!/bin/bash
# setup-sdk.sh — Run the Garmin SDK Manager inside the devcontainer.
#
# Use this once to:
#   1. Download and install a ConnectIQ SDK version
#   2. Generate your developer key
#
# The SDK Manager is a GUI app — it will open a window on your host display.
# After it exits, run ./scripts/simulate.sh to build and test the app.
#
# Requires: the project must be open in VS Code with "Reopen in Container".

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# ── X11 ───────────────────────────────────────────────────────────────────────
echo "[1/2] Allowing X11 access to Docker..."
"$SCRIPT_DIR/allowX11.sh"

# ── Find the running devcontainer ─────────────────────────────────────────────
echo "[2/2] Locating devcontainer..."

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
echo ""
echo "  The Garmin SDK Manager will open. In the GUI:"
echo "    1. Sign in with your Garmin developer account"
echo "    2. Install a ConnectIQ SDK version (8.x recommended)"
echo "    3. Generate your developer key (Preferences → Developer Key)"
echo ""

# Launch the SDK Manager GUI inside the devcontainer
docker exec \
  -e DISPLAY="${DISPLAY:-:0}" \
  "$CONTAINER_ID" \
  /workspace/sdk/bin/sdkmanager
