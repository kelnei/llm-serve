#!/usr/bin/env bash
# install.sh — check prerequisites, pull the vLLM Docker image, and set up .env
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VLLM_IMAGE="vllm/vllm-openai:gemma4"

# ── checks ────────────────────────────────────────────────────────────────────

echo "==> Checking Docker..."
if ! command -v docker &>/dev/null; then
    echo "ERROR: docker not found. Install Docker Engine and retry."
    exit 1
fi
if ! docker info &>/dev/null; then
    echo "ERROR: Docker daemon is not running, or you need to add yourself to the docker group."
    echo "       Try: sudo usermod -aG docker \$USER  (then log out and back in)"
    exit 1
fi
echo "    Docker — OK"

echo "==> Checking NVIDIA Container Toolkit..."
if ! docker run --rm --device nvidia.com/gpu=all nvidia/cuda:12.1.0-base-ubuntu22.04 nvidia-smi &>/dev/null; then
    echo "ERROR: GPU passthrough failed. Make sure nvidia-container-toolkit is installed."
    echo "       See: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html"
    exit 1
fi
echo "    NVIDIA Container Toolkit — OK"

echo "==> GPU info:"
docker run --rm --device nvidia.com/gpu=all nvidia/cuda:12.1.0-base-ubuntu22.04 \
    nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader \
    2>/dev/null | sed 's/^/    /'

# ── pull image ────────────────────────────────────────────────────────────────

echo "==> Pulling $VLLM_IMAGE ..."
echo "    (this is several GB — grab a coffee)"
docker pull "$VLLM_IMAGE"

# ── .env ─────────────────────────────────────────────────────────────────────

if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
    cp "$SCRIPT_DIR/.env.example" "$SCRIPT_DIR/.env"
    echo ""
    echo "==> Created .env from .env.example"
    echo "    Edit .env and set your HF_TOKEN and MODEL before starting."
else
    echo "==> .env already exists — not overwriting."
fi

# ── done ─────────────────────────────────────────────────────────────────────

echo ""
echo "Installation complete."
echo ""
echo "Next steps:"
echo "  1. Edit .env  — set HF_TOKEN and MODEL"
echo "  2. Accept the model license on huggingface.co (required for gated models)"
echo "  3. Run: ./start.sh        (foreground, use with screen/tmux)"
echo "       or ./start.sh -d     (background daemon)"
