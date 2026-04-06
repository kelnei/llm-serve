# llm-serve

Scripts to run a self-hosted, OpenAI-compatible LLM inference server on your local network using [vLLM](https://github.com/vllm-project/vllm) and Docker. Optimized for NVFP4-quantized models on NVIDIA Blackwell GPUs.

## Features

- OpenAI-compatible API (`/v1/chat/completions`) — works with any client that supports OpenAI
- FP8 KV cache quantization — cuts KV memory ~50% with negligible quality loss
- Prefix caching — reuses KV cache across requests sharing a common prefix (big win for agentic workloads with repeated system prompts)
- Continuous batching — handles concurrent requests automatically
- Daemon mode with auto-restart on crash

## Prerequisites

- **Docker Engine** — [install guide](https://docs.docker.com/engine/install/)
- **NVIDIA Container Toolkit** 1.17+ — [install guide](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html)
- **NVIDIA GPU** — Blackwell (sm_120) or later recommended for NVFP4 models
- A [HuggingFace account](https://huggingface.co) with a read token

### Docker daemon config (required)

Docker 25+ enables the containerd image store by default, which has a bug pulling images with zstd:chunked layer compression. Disable it before running `install.sh`:

```bash
echo '{ "features": { "containerd-snapshotter": false } }' | sudo tee /etc/docker/daemon.json
sudo systemctl restart docker
```

### NVIDIA Container Toolkit — CDI mode

Toolkit 1.17+ defaults to CDI mode. Verify your CDI devices are registered:

```bash
nvidia-ctk cdi list
# should show: nvidia.com/gpu=0  nvidia.com/gpu=all
```

If the list is empty, generate the specs:

```bash
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
```

## Setup

```bash
# 1. Pull the image and create .env
./install.sh

# 2. Edit .env — set HF_TOKEN and MODEL at minimum
#    For gated models, accept the license on huggingface.co first
nano .env

# 3. Start
./start.sh          # foreground (use with screen or tmux)
./start.sh -d       # background daemon, auto-restarts on crash
```

## Usage

```bash
./status.sh         # container state, health check, model list, recent logs
./stop.sh           # stop and remove the container
```

The API is available at `http://<host-ip>:8000` from any machine on the network.

```bash
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "nvidia/Gemma-4-31B-IT-NVFP4",
    "messages": [{"role": "user", "content": "Hello"}]
  }'
```

## Configuration

All settings live in `.env` (created from `.env.example` by `install.sh`).

| Variable | Default | Description |
|---|---|---|
| `HF_TOKEN` | — | HuggingFace read token (required) |
| `HF_CACHE` | `~/.cache/huggingface` | Local path for cached model weights |
| `MODEL` | — | HuggingFace model ID (required) |
| `MODEL_ALIAS` | — | Override the model name exposed in the API |
| `PORT` | `8000` | Host port to expose the API on |
| `TENSOR_PARALLEL` | `1` | Number of GPUs for tensor parallelism |
| `GPU_MEM_UTIL` | `0.92` | Fraction of VRAM to use |
| `MAX_MODEL_LEN` | `262144` | Max context length in tokens (256K) |
| `KV_CACHE_DTYPE` | `fp8` | KV cache precision (`fp8` or `auto`) |
| `MAX_NUM_SEQS` | `256` | Max concurrent sequences |
| `ENABLE_PREFIX_CACHING` | `true` | Cache KV for shared prompt prefixes |

## Docker image

`vllm/vllm-openai:gemma4` is used instead of `latest` because it is the build explicitly validated for Gemma 4 architecture support (MoE, multimodal, tool use). The `latest` tag moves forward and may not maintain Gemma 4 compatibility.

## License

MIT — see [LICENSE](LICENSE).
