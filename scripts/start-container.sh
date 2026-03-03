#!/bin/bash
# start-container.sh — Build the devcontainer image (if needed) and start it.
#
# This is an alternative to opening the project in VS Code and using
# "Dev Containers: Reopen in Container". The container it starts is
# labelled identically to what VS Code would create, so simulate.sh,
# shell.sh, and setup-sdk.sh all work without modification.
#
# Usage:
#   ./scripts/start-container.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
IMAGE_NAME="gympanion-devcontainer"
CONTAINER_NAME="gympanion-devcontainer"

# ── Step 1: Check if already running ──────────────────────────────────────────
EXISTING=$(docker ps \
  --filter "label=devcontainer.local_folder=$REPO_ROOT" \
  --format "{{.ID}}" | head -1)

if [[ -n "$EXISTING" ]]; then
  EXISTING_NAME=$(docker ps --filter "id=$EXISTING" --format "{{.Names}}")
  echo "Container is already running: $EXISTING_NAME ($EXISTING)"
  echo "Nothing to do."
  exit 0
fi

# ── Step 2: Build the image ───────────────────────────────────────────────────
echo "[1/2] Building devcontainer image '$IMAGE_NAME'..."
docker build \
  --tag "$IMAGE_NAME" \
  --file "$REPO_ROOT/.devcontainer/Dockerfile" \
  "$REPO_ROOT/.devcontainer"

echo "      Image built OK."

# ── Step 3: Start the container ───────────────────────────────────────────────
echo "[2/2] Starting container '$CONTAINER_NAME'..."

# Remove any stopped container with the same name before starting fresh.
docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

docker run \
  --detach \
  --name "$CONTAINER_NAME" \
  --network host \
  --ipc host \
  --label "devcontainer.local_folder=$REPO_ROOT" \
  --volume "$REPO_ROOT/app:/workspace" \
  --user vscode \
  "$IMAGE_NAME" \
  sleep infinity

echo ""
echo "Container started: $CONTAINER_NAME"
echo ""
echo "You can now use:"
echo "  ./scripts/simulate.sh   — build and run in the Garmin simulator"
echo "  ./scripts/shell.sh      — open an interactive shell in the container"
echo "  ./scripts/setup-sdk.sh  — open the Garmin SDK Manager GUI"
echo ""
echo "To stop the container:"
echo "  docker stop $CONTAINER_NAME"
echo ""
