#!/bin/bash
# build.sh — Compile the GymPanion app inside the devcontainer.
#
# Requires: the project must be open in VS Code with "Reopen in Container".
# Produces: app/bin/workspace.prg
#
# Usage:
#   ./scripts/build.sh [device]
#
#   device  ConnectIQ device ID to compile for (default: fr265)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

DEVICE="${1:-fr265}"

# ── Step 1: Find the running devcontainer ─────────────────────────────────────
echo "[1/2] Locating devcontainer..."

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

# ── Step 2: Compile inside the devcontainer ───────────────────────────────────
echo "[2/2] Compiling for '$DEVICE'..."

docker exec \
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

    SDK_NAME=\"\$(basename \"\$(dirname \"\$(dirname \"\$MONKEYBRAINS\")\")\")\";
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
  "
