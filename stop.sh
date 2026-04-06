#!/usr/bin/env bash
# stop.sh — stop and remove the vLLM container
set -euo pipefail

CONTAINER_NAME="vllm-serve"

if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Container '$CONTAINER_NAME' does not exist. Nothing to stop."
    exit 0
fi

STATE=$(docker inspect --format '{{.State.Status}}' "$CONTAINER_NAME")

if [[ "$STATE" != "running" && "$STATE" != "restarting" ]]; then
    echo "Container is not running (state: $STATE). Removing..."
    docker rm "$CONTAINER_NAME"
    exit 0
fi

echo "==> Stopping $CONTAINER_NAME..."
docker stop "$CONTAINER_NAME" 2>/dev/null || true
docker rm -f "$CONTAINER_NAME"
echo "==> Stopped."
