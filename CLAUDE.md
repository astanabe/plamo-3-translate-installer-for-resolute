# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project status

The repository currently contains only `README.md` (the specification) and `LICENSE`. The scripts are not yet implemented; `README.md` is the source of truth for behavior, options, defaults and procedure — keep it in sync when the implementation changes.

## Purpose

A bash installer that sets up a PLaMo 3 Translate web service on **Ubuntu Server 26.04 (Resolute Raccoon)**, x86_64. Entry point: `bash install-plamo-3-translate.sh`.

## Planned deliverables

- `install-plamo-3-translate.sh` — installer (interactive, non-interactive via options/env vars, `--uninstall`; re-runnable in place)
- `plamo-3-translate-server.py` — WSGI app under uWSGI: `GET /` HTML form, `POST /api/translate` JSON API, calls llama-server
- `plamo-3-translate-client.py` — CLI client for the web server

## Architecture (request path)

```
client (browser / plamo-3-translate-client.py)
  → nginx-full (TCP 18080 default)
    → uWSGI (apt: uwsgi, uwsgi-plugin-python3)
      → plamo-3-translate-server.py
        → llama-server from llama.cpp (TCP 28080 default)
```

All services are systemd units running as the install-time user (default `plamo`, created as a system user if missing).

## Design decisions (agreed; don't change without asking)

- **Python: standard library only** for both server and client. No pip / venv / Flask; Python deps come from apt.
- **llama.cpp b12366 prebuilt binaries**; the user picks the backend (CPU / Vulkan / CUDA 12.8・13.5 / ROCm), with a default suggested from GPU detection.
- **llama-server flags**: `-c 16384 --jinja --no-prefill-assistant --alias plamo-3-translate` (`-c` configurable). The model's GGUF ships a chat template that takes translation settings (`target_lang`, `source_lang`, `form`, glossary) via `chat_template_kwargs` or a `[plamo-translate]` system block — see the model card on Hugging Face.
- **Exposure**: llama-server binds `127.0.0.1` by default; when exposed, `0.0.0.0` plus an installer-generated `--api-key`. The web server has no TLS/auth (out of scope).
- **Quantization**: `Q2_K`, `Q3_K_M`, `Q4_K_M` (default), `Q4_0` — `Q4_0` exists only for 0.8B and 2B; reject it for 8B/31B. GGUF file names follow `plamo-3-translate-<size>-<quant>.gguf` in `pfnet/plamo-3-translate-<size>-GGUF`.
- **License**: PLaMo Community License must be accepted (`yes` interactively, `--accept-license` non-interactively).
- **Re-run**: overwrite files/units, but reuse an already-downloaded GGUF.

## Installer procedure (order matters)

1. Prompts (destdir, username, model, quant, backend, context size, two ports, expose?, license)
2. Prerequisite checks (ports free, disk/memory vs. GGUF size)
3. apt install → 4. create user → 5. download llama.cpp + GGUF → 6. systemd units + nginx site, start/enable (offer to open ports if ufw is active)
7. Smoke test: llama-server `/health`, then a real translation through nginx returning non-empty output

## Testing

No test suite exists yet. End-to-end verification is step 7 of the installer itself.
