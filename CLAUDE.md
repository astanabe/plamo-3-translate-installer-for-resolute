# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project status

`install-plamo-3-translate.sh` and `plamo-3-translate-server.py` are implemented; `plamo-3-translate-client.py` is not yet. `README.md` is the source of truth for behavior, options, defaults, file layout and procedure — keep it in sync when the implementation changes.

Pinned data lives at the top of the installer: llama.cpp asset names/SHA-256/sizes (`PLAMO3INS_LLAMA_ASSETS`), Hugging Face revisions (`PLAMO3INS_MODEL_REVISION`) and GGUF SHA-256/sizes (`PLAMO3INS_GGUF`). Update them together when bumping llama.cpp or a model.

Every shell variable in the installer — globals, arrays and `local`s — is prefixed with `PLAMO3INS_` to avoid clashes (e.g. with `/etc/os-release` or the environment). Exceptions: bash builtins (`BASH_REMATCH`, `EUID`, `SECONDS`, ...), the user-facing `PLAMO3_*` environment variables, `DEBIAN_FRONTEND`, and the key names inside `install.conf` and associative arrays (`DESTDIR`, `UFW_PORTS`, ...). Do not source external files into the installer's shell.

## Purpose

A bash installer that sets up a PLaMo 3 Translate web service on **Ubuntu 26.04 LTS (Resolute Raccoon)**, x86_64, Server or Desktop (tested on Server; WSL not supported). Entry point: `bash install-plamo-3-translate.sh`.

## Planned deliverables

- `install-plamo-3-translate.sh` — installer (interactive, non-interactive via options/env vars, `--uninstall`; re-runnable in place)
- `plamo-3-translate-server.py` — WSGI app under uWSGI: `GET /` HTML form, `POST /api/translate` JSON API, calls llama-server
- `plamo-3-translate-client.py` — CLI client that talks to llama-server directly (TCP 28080 default)

## Architecture (request path)

```
browser
  → nginx-full (TCP 18080 default)
    → uWSGI (apt: uwsgi, uwsgi-plugin-python3; UNIX socket /run/plamo-3-translate/uwsgi.sock)
      → plamo-3-translate-server.py
        → llama-server from llama.cpp (UNIX socket /run/plamo-3-translate-llama/llama.sock)

plamo-3-translate-client.py
  → llama-server (TCP 28080 default)
```

llama-server listens on both (`--host <127.0.0.1|0.0.0.0>,<socket path>`). The socket's RuntimeDirectory is 0750 and owned by the service user; a stale socket makes llama-server fail to start, hence `ExecStartPre=rm -f`.

All services are systemd units running as the install-time user (default `plamo3`, created as a system user if missing).

## Design decisions (agreed; don't change without asking)

- **Python: standard library only** for both server and client. No pip / venv / Flask; Python deps come from apt.
- **llama.cpp b12366 prebuilt binaries**; the user picks the backend (CPU / Vulkan / CUDA 12.8・13.5 / ROCm), with a default suggested from GPU detection.
- **llama-server flags**: `--jinja --no-prefill-assistant --alias plamo-3-translate`. Context size defaults to `auto`: `-c` is omitted so llama-server uses the native 262144 and its `--fit` (on by default) shrinks it to fit memory; `-c 0` or an explicit `-c N` disables that shrinking. `--ctx-size N` (512–262144) passes `-c N`. Timeouts (1 h) and body limits (8 MiB) are sized for long documents. The model's GGUF ships a chat template that takes translation settings (`target_lang`, `source_lang`, `form`, glossary) via `chat_template_kwargs` or a `[plamo-translate]` system block — see the model card on Hugging Face.
- **Exposure**: llama-server's TCP port binds `127.0.0.1` by default; when exposed, `0.0.0.0` plus an installer-generated `--api-key` (passed as `LLAMA_API_KEY` via EnvironmentFile; it applies to the socket too). The web server has no TLS/auth (out of scope).
- **Quantization**: `Q2_K`, `Q3_K_M`, `Q4_K_M` (default), `Q4_0` — `Q4_0` exists only for 0.8B and 2B; reject it for 8B/31B. GGUF file names follow `plamo-3-translate-<size>-<quant>.gguf` in `pfnet/plamo-3-translate-<size>-GGUF`.
- **License**: PLaMo Community License must be accepted (`yes` interactively, `--accept-license` non-interactively).
- **Re-run**: overwrite files/units, but reuse an already-downloaded GGUF.
- **Interface selection** (`INTERFACES` = `all` or interface names): nginx/llama-server cannot bind to an interface, so the names are resolved to their current global addresses when the config is written (`listen_addresses`); 127.0.0.1 (and ::1 for nginx) are always added for local clients and the smoke test. ufw rules are tracked in install.conf as `UFW_RULES` (`PORT` or `PORT@IF`; legacy `UFW_PORTS` is still read); rules the installer added earlier and no longer wants are deleted on re-run. ufw shows interface rules as `PORT/tcp on IF`.
- **GPU selection** (`GPUS` = `all` or PCI addresses): mapped at unit-writing time to `CUDA_VISIBLE_DEVICES` (UUIDs via nvidia-smi, plus `CUDA_DEVICE_ORDER=PCI_BUS_ID`), `ROCR_VISIBLE_DEVICES` (GPU index in KFD topology node order) or `GGML_VK_VISIBLE_DEVICES` (index in `vkEnumeratePhysicalDevices` order, listed by an embedded Python ctypes script). After start-up, `report_gpus` compares the `using device ... (<PCI>)` log lines with the selection. Multi-GPU has been tested only with fake devices.

## Installer procedure (order matters)

1. Prompts (destdir, username, model, quant, backend, GPUs — asked only if the backend sees two or more, context size, two ports, expose?, interfaces — asked only if two or more have global addresses, open ports in ufw? — asked only if ufw is active and the ports are not yet allowed, license). Step 6 asks about ufw again only if it was not answered here (e.g. ufw enabled meanwhile).
2. Prerequisite checks (ports free, disk/memory vs. GGUF size)
3. apt install → 4. create user → 5. download llama.cpp + GGUF → 6. systemd units + nginx site, start/enable (offer to open ports if ufw is active)
7. Smoke test: llama-server `/health`, then a real translation through nginx returning non-empty output

## Testing

No test suite exists yet. End-to-end verification is step 7 of the installer itself.

- Static checks: `shellcheck install-plamo-3-translate.sh`, `bash -n`, `python3 -m py_compile plamo-3-translate-server.py`
- server.py can be run without uWSGI for development: `PLAMO3_LLAMA_URL=http://127.0.0.1:<port> python3 plamo-3-translate-server.py 8080` (`PLAMO3_LLAMA_URL` takes `unix:<path>` or `http://host:port`; default is the installed socket)
- Vulkan, CUDA and ROCm backends are untested (no supported GPU in the development machine).

## TODO (handover for the next session)

### Implement `plamo-3-translate-client.py`

The only remaining deliverable. README already refers to it (Architecture, Client, License) — update README when it is implemented.

Agreed so far:
- CLI client that talks to **llama-server directly over TCP** (default `http://127.0.0.1:28080`), not to the web server. The TCP port exists for this client; the web server uses the UNIX socket.
- Python standard library only (`urllib`/`http.client`, `json`, `argparse`); no pip.
- Request format is the same as `plamo-3-translate-server.py` → `translate()`: `POST /v1/chat/completions` with `model: plamo-3-translate`, the source text as the last user message, settings in `chat_template_kwargs` (`target_lang`, `source_lang`, `form`, `glossary` as `[{source, target}]`, `context`), `temperature: 0`, `stop: ["<|plamo:tag|>", "<|plamo:bos|>"]`, bounded `max_tokens`. Validation and the 53-language list in server.py can be reused (copy; server.py is deployed as a single standalone file).
- API key: required when llama-server is exposed (`Authorization: Bearer <key>`). The installer stores it in `/etc/plamo-3-translate/llama-server.env` (`LLAMA_API_KEY`, mode 0640 root:<service user>), which ordinary users cannot read, so the client needs its own way to get the key (option and/or environment variable).

To decide with the user before implementing:
- CLI interface: input from arguments / stdin / files, output format, option names (e.g. `--to`, `--from`, `--form`, `--glossary FILE`, `--context`), and environment variable names (follow the `PLAMO3_` prefix).
- Whether the installer should also install the client (e.g. into `<destdir>/app/` or `/usr/local/bin`) or it is only used from this repository.
- Whether to support long documents (splitting into paragraphs and passing previous pairs as translation history, as the model card describes) or translate the input in one request.

Verification: `python3 -m py_compile`, then against an installed llama-server, both local (`127.0.0.1`) and exposed (API key required; a request without it must fail with a clear message).

### Other open items

- Real-hardware tests of the GPU backends (Vulkan, CUDA, ROCm) and of multi-GPU selection; in particular the ROCm index order (KFD topology) and the Vulkan PCI addresses (`VK_EXT_pci_bus_info`) are untested.
