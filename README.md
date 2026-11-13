# plamo-3-translate-installer-for-resolute

PLaMo 3 Translate installer script for Ubuntu 26.04 LTS Resolute Raccoon (Server or Desktop)

# Prerequisites

- Ubuntu 26.04 LTS (Resolute Raccoon), x86_64, Server or Desktop (tested on Ubuntu Server; Ubuntu on WSL is not supported)
  - On Desktop, the display also uses GPU memory, so the context size chosen automatically may be smaller; the services stop while the machine is suspended
- Root privileges (`sudo`)
- Internet access to GitHub (llama.cpp) and Hugging Face (models), and to the Ubuntu apt repositories
- Enough disk space and memory for the selected model (see [Engine](#engine)); the installer checks them and warns if they look insufficient
- **GPU driver installed in advance** (only for GPU backends). The installer does not install GPU drivers; it installs only the user-space libraries of the selected backend.
  - NVIDIA (`cuda12`, `cuda13`): install the NVIDIA driver and reboot (e.g. `sudo ubuntu-drivers install`), so that `nvidia-smi` works. CUDA 12.8 needs driver 570 or later and CUDA 13.5 needs driver 580 or later. The installer stops if `nvidia-smi` does not work.
  - AMD / Intel (`vulkan`, `rocm`): the in-kernel `amdgpu` / `i915` / `xe` driver must be loaded (`/dev/dri` exists; ROCm also needs `/dev/kfd`).

# Usage

```
bash install-plamo-3-translate.sh                    # interactive install
bash install-plamo-3-translate.sh --accept-license \
    --destdir /opt/plamo-3-translate --model 2b ...  # non-interactive install
bash install-plamo-3-translate.sh --uninstall        # uninstall
```

- Run as root (e.g. `sudo bash install-plamo-3-translate.sh`) from a checkout of this repository; `plamo-3-translate-server.py` must be next to the installer.
- Every prompt has a corresponding command-line option (and environment variable). Only values that are not given are asked. When standard input is not a terminal, the defaults are used without prompting.
- Values are taken in this order: command-line option, environment variable, the previous installation (`/etc/plamo-3-translate/install.conf`), default.
- Re-running the installer updates the existing installation in place (files and systemd units are overwritten; an already-downloaded GGUF file and llama.cpp build are reused after checksum verification). If the model or quantization changed, the installer offers to delete the unused GGUF file. An API key generated for llama-server is kept.
- `--uninstall` stops and disables the services and removes the systemd units, the nginx site configuration, `/etc/plamo-3-translate`, the ufw rules added by the installer and destdir. apt packages and the service user are kept.

## Options

| Option | Environment variable | Default |
|---|---|---|
| `--destdir DIR` | `PLAMO3_DESTDIR` | `/opt/plamo-3-translate` |
| `--user NAME` | `PLAMO3_USER` | `plamo3` |
| `--model 0.8b\|2b\|8b\|31b` | `PLAMO3_MODEL` | `2b` |
| `--quant Q2_K\|Q3_K_M\|Q4_K_M\|Q4_0` | `PLAMO3_QUANT` | `Q4_K_M` |
| `--backend cpu\|vulkan\|cuda12\|cuda13\|rocm` | `PLAMO3_BACKEND` | suggested from the detected GPU |
| `--gpus all\|PCI[,PCI...]` | `PLAMO3_GPUS` | `all` (asked when the backend sees two or more GPUs) |
| `--ctx-size N\|auto` | `PLAMO3_CTX_SIZE` | `auto` (model maximum 262144, reduced to fit the memory) |
| `--web-port PORT` | `PLAMO3_WEB_PORT` | `18080` |
| `--llama-port PORT` | `PLAMO3_LLAMA_PORT` | `28080` |
| `--expose-llama` / `--no-expose-llama` | `PLAMO3_EXPOSE_LLAMA` (`yes`/`no`) | `no` |
| `--interfaces all\|IF[,IF...]` | `PLAMO3_INTERFACES` | `all` (asked when two or more interfaces have addresses) |
| `--accept-license` | `PLAMO3_ACCEPT_LICENSE` (`yes`) | — |
| `--open-ports` / `--no-open-ports` | `PLAMO3_OPEN_PORTS` (`yes`/`no`) | ask when ufw is active |
| `--yes` | — | answer yes to warnings, opening ufw ports and uninstalling |
| `--uninstall` | — | — |
| `--help` | — | — |

Backend suggestion: an NVIDIA GPU with a working driver (`nvidia-smi`) gives `cuda13` for driver 580 or later and `cuda12` otherwise; an AMD GPU gives `vulkan`; otherwise `cpu`. The installer does not install GPU drivers; it installs only the user-space libraries of the backend (`libvulkan1 mesa-vulkan-drivers` for Vulkan, `libhipblas3 librocblas5 libamdhip64-7` for ROCm; the CUDA runtime comes from llama.cpp's `cudart` archive).

GPU selection: when the selected backend can use two or more GPUs (NVIDIA for CUDA, AMD for ROCm, NVIDIA/AMD/Intel for Vulkan), the installer lists them with their PCI addresses and asks which to use (`all` or numbers such as `1,2`). `--gpus` takes PCI addresses as shown by `lspci -D` (e.g. `0000:03:00.0`). With `all`, llama.cpp uses every GPU it supports and splits the model across them. The selection is applied with `CUDA_VISIBLE_DEVICES` (GPU UUIDs), `ROCR_VISIBLE_DEVICES` or `GGML_VK_VISIBLE_DEVICES` in the llama-server unit, and the GPUs llama-server actually uses are shown after it starts.

Network interfaces: when two or more network interfaces have global addresses (container/VM bridges such as `docker0`, `virbr0` and `lxdbr0` are ignored), the installer asks on which of them the web server (and llama-server if exposed) accept connections from other hosts (`all` or numbers). With selected interfaces, nginx and llama-server listen on their current addresses plus `127.0.0.1` (and `::1` for nginx), and the ufw rules are limited to them (`ufw allow in on IF to any port PORT proto tcp`). The interface names are saved and the addresses are looked up at installation, so re-run the installer if an address changes. Rules added by an earlier run that are no longer wanted (e.g. a rule for all interfaces) are removed.

## Files

```
<destdir>/                                  default /opt/plamo-3-translate
  llama.cpp/b12366-<backend>/               llama.cpp prebuilt binaries
  llama.cpp/current -> b12366-<backend>
  models/plamo-3-translate-<size>-<quant>.gguf
  app/plamo-3-translate-server.py
/etc/plamo-3-translate/
  install.conf                              settings of the installation
  llama-server.env                          API key (only when llama-server is exposed)
  uwsgi.ini
/etc/systemd/system/
  plamo-3-translate-llama.service           llama-server (TCP port and socket /run/plamo-3-translate-llama/llama.sock)
  plamo-3-translate-uwsgi.service           uWSGI (socket /run/plamo-3-translate/uwsgi.sock)
/etc/nginx/sites-available/plamo-3-translate (linked from sites-enabled)
```

Downloads are verified with SHA-256 checksums built into the installer (llama.cpp release assets and pinned Hugging Face revisions of the GGUF files).

# Models

- PLaMo 3 Translate 0.8B
  - https://huggingface.co/pfnet/plamo-3-translate-0.8b-GGUF
- PLaMo 3 Translate 2B (default)
  - https://huggingface.co/pfnet/plamo-3-translate-2b-GGUF
- PLaMo 3 Translate 8B
  - https://huggingface.co/pfnet/plamo-3-translate-8b-GGUF
- PLaMo 3 Translate 31B
  - https://huggingface.co/pfnet/plamo-3-translate-31b-GGUF

# License

## License of this repository

The files in this repository (the installer, plamo-3-translate-server.py, plamo-3-translate-client.py and the documentation) are distributed under the MIT License. See [LICENSE](LICENSE).

## License of PLaMo 3 Translate models

The PLaMo 3 Translate models downloaded by the installer are not part of this repository. They are distributed by Preferred Networks, Inc. (PFN) under the PLaMo Community License, not under the MIT License.

- https://plamo.preferredai.jp/info/plamo-community-license-en

Personal and non-commercial use is free. Commercial use requires registration with PFN. Read the full license text before using the models. The installer shows a summary of the license and aborts unless the user types `yes`. In non-interactive mode, `--accept-license` is required.

# Engine

- llama.cpp b12366
  - https://github.com/ggml-org/llama.cpp/releases/tag/b12366
- Prebuilt binary chosen by the user from:
  - CPU (`llama-b12366-bin-ubuntu-x64`)
  - Vulkan (`llama-b12366-bin-ubuntu-vulkan-x64`)
  - CUDA 12.8 / 13.5 (`llama-b12366-bin-ubuntu-cuda-*-x64`)
  - ROCm (`llama-b12366-bin-ubuntu-rocm-10.0-x64`)
- The installer detects available GPUs and suggests a default backend.
- llama-server options: `--jinja --no-prefill-assistant --alias plamo-3-translate`, plus `-c N` when a context size is given
- Context size: by default (`auto`) `-c` is omitted, so llama-server uses the model maximum (262144 tokens for all sizes) and, with its `--fit` feature, reduces the context (down to 4096) when it does not fit in the memory. The actual size is shown at the end of the installation. An explicit `--ctx-size N` (512–262144) is used as is.
- Memory for the full 262144-token context (Q4_K_M, model + KV cache + buffers, approximate): 0.8B 2.1 GB, 2B 4.5 GB, 8B 8.2 GB, 31B 28 GB. Only one layer in eight attends to the whole context, so the KV cache is small for this context length.

# Quantization

- Q2_K
- Q3_K_M
- Q4_K_M (default)
- Q4_0 (0.8B and 2B models only)

# Architecture

```
web browser ──→ nginx-full (TCP 18080) ──→ uWSGI ──→ plamo-3-translate-server.py ──┐
                         (UNIX socket /run/plamo-3-translate/uwsgi.sock)           │ UNIX socket
                                                                                   ↓ /run/plamo-3-translate-llama/llama.sock
plamo-3-translate-client.py ──────────────── TCP 28080 ──────────────────→ llama-server
```

- Web server (TCP 18080 by default) (nginx-full)
  - uWSGI (`uwsgi`, `uwsgi-plugin-python3` from apt)
    - plamo-3-translate-server.py (provided in this repository)
      - `GET /` : translation form (HTML). On PCs, Source text and Translation are side by side, surrounded by four Translate buttons that follow the textarea size; on phones (width below 760px), selectors, Source text, a Translate/Clear button and Translation are stacked, sized so that each screen ends at the button / at the title. Both textareas have a Copy button, and the model size and quantization reported by llama-server are shown.
      - `POST /api/translate` : JSON API
      - connects to llama-server through a UNIX socket (`/run/plamo-3-translate-llama/llama.sock`, accessible only to the service user)
- llama-server (TCP 28080 by default) for plamo-3-translate-client.py and other OpenAI-compatible clients

- plamo-3-translate-server.py and plamo-3-translate-client.py use the Python standard library only.
- `POST /api/translate` takes `{"text", "target_lang", "source_lang"?, "form"?, "glossary"?, "context"?}` and returns `{"translation"}` (`{"error"}` with HTTP 400 for invalid input, including text that does not fit in the context, and 502 for other llama-server errors). `form` is `plain` or `polite` (Japanese target only); `glossary` is a list of `{"source", "target"}`. The settings are passed to llama-server in `chat_template_kwargs`.
  ```
  curl -H 'Content-Type: application/json' \
      -d '{"text": "こんにちは", "target_lang": "en"}' http://localhost:18080/api/translate
  ```
- All services run as the user specified at install time (default: `plamo3`). If the user does not exist, it is created as a system user without login.
- llama-server listens on the UNIX socket and on TCP `127.0.0.1` by default. If exposure is enabled, the TCP port listens on `0.0.0.0` (or on the selected interfaces, see `--interfaces`) and an API key (`--api-key`) generated by the installer is required (on the socket too; plamo-3-translate-server.py sends it).
- TLS and authentication for the web server are out of scope.

# Client

- Web browser (web server, TCP 18080)
- plamo-3-translate-client.py (provided in this repository; connects to llama-server, TCP 28080)

# Procedure

1. Ask user for destdir (default `/opt/plamo-3-translate`), username (default `plamo3`), model (default 2B), quantization (default Q4_K_M), llama.cpp backend, GPUs to use (only if the backend sees two or more), context size (default `auto`: the model maximum, reduced to fit the memory), web server port (default 18080), llama-server port (default 28080), whether to expose the llama-server, network interfaces to listen on (only if two or more have addresses), whether to open the ports in ufw (only if ufw is active and the ports are not allowed yet), and license acceptance
2. Check prerequisites: ports are not in use, enough free disk space and memory for the selected GGUF file (warn and ask to continue if insufficient)
3. Install dependencies via apt
4. Create the service user if needed
5. Download and install llama.cpp and GGUF file
6. Generate and install systemd unit files and nginx site configuration, and start and enable servers (open the ports in ufw as answered in step 1; if ufw became active after step 1, ask here)
7. Test llama-server (`/health`) and translate a short sentence through the web server, checking that a non-empty result is returned
