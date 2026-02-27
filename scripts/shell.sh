#!/bin/bash
# shell.sh — Open an interactive shell inside the running devcontainer.
#
# Use this to inspect the container, debug issues, check installed SDKs/devices,
# or run any command manually.
#
# Requires: the project must be open in VS Code with "Reopen in Container".
#
# Usage:
#   ./scripts/shell.sh           # interactive bash shell
#   ./scripts/shell.sh <cmd>     # run a single command and exit

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

CONTAINER_ID=$(docker ps \
  --filter "label=devcontainer.local_folder=$REPO_ROOT" \
  --format "{{.ID}}" | head -1)

if [[ -z "$CONTAINER_ID" ]]; then
  echo ""
  echo "  ERROR: Dev container is not running."
  echo "  Open this project in VS Code → Dev Containers: Reopen in Container"
  echo ""
  exit 1
fi

CONTAINER_NAME=$(docker ps --filter "id=$CONTAINER_ID" --format "{{.Names}}")
echo "Entering: $CONTAINER_NAME ($CONTAINER_ID)"
echo ""

if [[ $# -gt 0 ]]; then
  # Run a single command passed as arguments
  docker exec -it -e DISPLAY="${DISPLAY:-:0}" "$CONTAINER_ID" bash -c "$*"
else
  # Interactive shell
  docker exec -it -e DISPLAY="${DISPLAY:-:0}" "$CONTAINER_ID" bash
fi
