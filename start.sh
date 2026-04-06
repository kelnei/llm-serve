#!/usr/bin/env bash
# start.sh — start the vLLM OpenAI-compatible server via Docker
#
# Usage:
#   ./start.sh          run in foreground (recommended with screen/tmux)
#   ./start.sh -d       run as background daemon (auto-restarts on crash)
#   ./start.sh --help   show this help
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
VLLM_IMAGE="vllm/vllm-openai:gemma4"
CONTAINER_NAME="vllm-serve"

# ── parse args ────────────────────────────────────────────────────────────────

DAEMON=false
for arg in "$@"; do
    case "$arg" in
        -d|--daemon) DAEMON=true ;;
        -h|--help)
            echo "Usage: $0 [-d|--daemon]"
            echo "  -d  Run as a background daemon (restarts automatically on crash)"
            exit 0
            ;;
        *) echo "Unknown argument: $arg"; exit 1 ;;
    esac
done

# ── pre-flight ────────────────────────────────────────────────────────────────

if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: .env not found. Run ./install.sh first, then edit .env."
    exit 1
fi

# Remove any existing container with this name (stopped or crashed)
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    STATE=$(docker inspect --format '{{.State.Status}}' "$CONTAINER_NAME")
    if [[ "$STATE" == "running" ]]; then
        echo "ERROR: Container '$CONTAINER_NAME' is already running."
        echo "       Run ./stop.sh to stop it first."
        exit 1
    else
        echo "==> Removing stale container ($STATE)..."
        docker rm "$CONTAINER_NAME" >/dev/null
    fi
fi

# ── load config ───────────────────────────────────────────────────────────────

# shellcheck source=/dev/null
source "$ENV_FILE"

: "${HF_TOKEN:?HF_TOKEN is not set in .env}"
: "${MODEL:?MODEL is not set in .env}"
: "${HF_CACHE:=${HOME}/.cache/huggingface}"
: "${HOST:=0.0.0.0}"
: "${PORT:=8000}"
: "${TENSOR_PARALLEL:=1}"
: "${GPU_MEM_UTIL:=0.92}"
: "${MAX_MODEL_LEN:=262144}"
: "${KV_CACHE_DTYPE:=fp8}"
: "${MAX_NUM_SEQS:=256}"
: "${ENABLE_PREFIX_CACHING:=true}"
: "${TOOL_CALL_PARSER:=gemma4}"
: "${REASONING_PARSER:=gemma4}"
: "${QUANTIZATION:=}"
: "${MODEL_PATH:=}"

# Expand ~ in HF_CACHE
HF_CACHE="${HF_CACHE/#\~/$HOME}"
mkdir -p "$HF_CACHE"

# ── build docker args ─────────────────────────────────────────────────────────

DOCKER_ARGS=(
    --name "$CONTAINER_NAME"
    --device nvidia.com/gpu=all
    --ipc host                          # required for tensor parallelism shared memory
    -e "HF_TOKEN=${HF_TOKEN}"
    -e "HUGGING_FACE_HUB_TOKEN=${HF_TOKEN}"
    -p "${PORT}:8000"
    -v "${HF_CACHE}:/root/.cache/huggingface"
)

if [[ "$DAEMON" == "true" ]]; then
    DOCKER_ARGS+=(-d --restart unless-stopped)
fi

if [[ -n "$MODEL_PATH" ]]; then
    MODEL_PATH="${MODEL_PATH/#\~/$HOME}"
    MOUNT_NAME=$(basename "$MODEL_PATH")
    DOCKER_ARGS+=(-v "${MODEL_PATH}:/models/${MOUNT_NAME}:ro")
    # Only override MODEL if the user hasn't already set a container path (starting with /)
    if [[ "$MODEL" != /* ]]; then
        MODEL="/models/${MOUNT_NAME}"
    fi
fi

# ── build vllm server args ────────────────────────────────────────────────────

SERVER_ARGS=(
    --model "$MODEL"
    --host 0.0.0.0
    --port 8000
    --tensor-parallel-size "$TENSOR_PARALLEL"
    --gpu-memory-utilization "$GPU_MEM_UTIL"
    --max-model-len "$MAX_MODEL_LEN"
    --kv-cache-dtype "$KV_CACHE_DTYPE"
    --max-num-seqs "$MAX_NUM_SEQS"
    --enable-chunked-prefill
    --enable-auto-tool-choice
    --tool-call-parser "$TOOL_CALL_PARSER"
    --reasoning-parser "$REASONING_PARSER"
    --trust-remote-code
)

if [[ -n "$QUANTIZATION" ]]; then
    SERVER_ARGS+=(--quantization "$QUANTIZATION")
fi

if [[ "${ENABLE_PREFIX_CACHING}" == "true" ]]; then
    SERVER_ARGS+=(--enable-prefix-caching)
fi

if [[ -n "${MODEL_ALIAS:-}" ]]; then
    SERVER_ARGS+=(--served-model-name "$MODEL_ALIAS")
fi

# ── launch ────────────────────────────────────────────────────────────────────

echo "==> Model:        $MODEL"
echo "==> Listen:       http://${HOST}:${PORT}"
echo "==> Context:      ${MAX_MODEL_LEN} tokens"
echo "==> GPU mem util: ${GPU_MEM_UTIL}  |  TP: ${TENSOR_PARALLEL}"
echo "==> KV cache:     ${KV_CACHE_DTYPE}  |  prefix caching: ${ENABLE_PREFIX_CACHING}"
echo "==> HF cache:     ${HF_CACHE}"
echo ""

if [[ "$DAEMON" == "true" ]]; then
    docker run "${DOCKER_ARGS[@]}" "$VLLM_IMAGE" "${SERVER_ARGS[@]}"
    echo "==> Container '$CONTAINER_NAME' started in background."
    echo ""
    echo "    The model is still loading — it takes a few minutes before the API is ready."
    echo "    Check status with: ./status.sh"
    echo "    Stop with:         ./stop.sh"
else
    echo "==> Running in foreground. Press Ctrl+C to stop."
    echo "    Tip: use 'screen' or 'tmux' to keep it running after logout."
    echo ""
    docker run "${DOCKER_ARGS[@]}" "$VLLM_IMAGE" "${SERVER_ARGS[@]}"
fi
