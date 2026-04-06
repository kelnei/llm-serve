# llm-serve — notes for AI assistants

## What this repo does

Bash scripts to run vLLM as a Docker container, exposing an OpenAI-compatible API on the local network. The target hardware is a single NVIDIA RTX Pro 6000 Blackwell (96 GB VRAM, sm_120).

## File map

| File | Purpose |
|---|---|
| `.env.example` | Template config — all tunables live here |
| `install.sh` | One-time setup: checks prereqs, pulls Docker image, creates `.env` |
| `start.sh` | Starts the container (foreground or `-d` daemon) |
| `stop.sh` | Stops and removes the container |
| `status.sh` | Shows container state, `/health`, model list, and recent logs |

## Key decisions

**Docker image: `vllm/vllm-openai:gemma4`** — pinned to this tag (not `latest`) because it is the build validated for Gemma 4 support. Update deliberately, not automatically.

**`--device nvidia.com/gpu=all` not `--gpus all`** — nvidia-container-toolkit 1.17+ defaults to CDI mode. The old `--gpus` flag does not work in CDI mode. Do not change this back.

**`--ipc host`** — required for NCCL shared memory when using tensor parallelism. Safe to keep even with a single GPU.

**`--restart unless-stopped`** — only applied in daemon mode (`-d`). Foreground mode has no restart policy so Ctrl+C cleanly exits.

**Docker daemon: `containerd-snapshotter: false`** — Docker 25+ enables the containerd image store by default, which has a digest mismatch bug with zstd:chunked layers. This setting in `/etc/docker/daemon.json` disables it.

## Configuration approach

All tunables are in `.env`, sourced by `start.sh` at runtime. Defaults are set with `${VAR:=default}` so unset variables fall back gracefully. `HF_TOKEN` and `MODEL` use `${VAR:?message}` to fail loudly if missing.

The HF cache (`~/.cache/huggingface`) is bind-mounted into the container so model weights persist across container restarts and rebuilds.

## What to be careful about

- Never commit `.env` — it contains the HuggingFace token. It is in `.gitignore`.
- The container name `vllm-serve` is hardcoded across `start.sh`, `stop.sh`, and `status.sh`. If you change it, update all three.
- `start.sh` removes stale stopped containers before starting. This is intentional — a crashed container would otherwise block a fresh start.
