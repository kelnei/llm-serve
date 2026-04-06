#!/usr/bin/env bash
# status.sh — show container status, health, available models, and recent logs
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
CONTAINER_NAME="vllm-serve"

PORT=8000
if [[ -f "$ENV_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$ENV_FILE"
fi

# ── container status ──────────────────────────────────────────────────────────

echo "── Container ────────────────────────────────────────────────────────────"
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    docker ps -a \
        --filter "name=^${CONTAINER_NAME}$" \
        --format "  {{.Status}}  (image: {{.Image}})"
else
    echo "  Not running"
fi

# ── health check ──────────────────────────────────────────────────────────────

echo ""
echo "── Health (http://localhost:${PORT}) ────────────────────────────────────"
if curl -sf --max-time 5 "http://localhost:${PORT}/health" >/dev/null 2>&1; then
    echo "  /health   OK"
else
    echo "  /health   unreachable (model may still be loading)"
fi

# ── models ────────────────────────────────────────────────────────────────────

echo ""
echo "── Available models ─────────────────────────────────────────────────────"
MODELS=$(curl -sf --max-time 5 "http://localhost:${PORT}/v1/models" 2>/dev/null || true)
if [[ -n "$MODELS" ]]; then
    echo "$MODELS" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for m in data.get('data', []):
    print(f\"  {m['id']}\")
" 2>/dev/null || echo "$MODELS"
else
    echo "  (not available yet)"
fi

# ── recent logs ───────────────────────────────────────────────────────────────

echo ""
echo "── Recent logs ──────────────────────────────────────────────────────────"
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    docker logs --tail 20 "$CONTAINER_NAME" 2>&1
else
    echo "  (no container)"
fi

echo ""
echo "── API endpoints ────────────────────────────────────────────────────────"
echo "  Chat completions:  http://localhost:${PORT}/v1/chat/completions"
echo "  Models:            http://localhost:${PORT}/v1/models"
