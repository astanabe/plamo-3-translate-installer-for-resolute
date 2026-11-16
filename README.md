# plamo-3-translate-installer-for-resolute

PLaMo 3 Translate installer script for Ubuntu 26.04 LTS Resolute Raccoon (Server or Desktop)

## Prerequisites

- Ubuntu 26.04 LTS (Resolute Raccoon), x86_64, Server or Desktop (tested on Ubuntu Server; Ubuntu on WSL is not supported)
  - On Desktop, the display also uses GPU memory, so the context size chosen automatically may be smaller; the services stop while the machine is suspended
- Root privileges (`sudo`)
- Internet access to GitHub (llama.cpp) and Hugging Face (models), and to the Ubuntu apt repositories
- Enough disk space and memory for the selected model (see [Engine](#engine)); the installer checks them and warns if they look insufficient
- **GPU driver installed in advance** (only for GPU backends). The installer does not install GPU drivers; it installs only the user-space libraries of the selected backend.
  - NVIDIA (`cuda12`, `cuda13`): install the NVIDIA driver and reboot (e.g. `sudo ubuntu-drivers install`), so that `nvidia-smi` works. CUDA 12.8 needs driver 570 or later and CUDA 13.5 needs driver 580 or later. The installer stops if `nvidia-smi` does not work.
  - AMD / Intel (`vulkan`, `rocm`): the in-kernel `amdgpu` / `i915` / `xe` driver must be loaded (`/dev/dri` exists; ROCm also needs `/dev/kfd`).

## Usage

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

### Options

| Option | Environment variable | Default |
|---|---|---|
| `--destdir DIR` | `PLAMO3_DESTDIR` | `/opt/plamo-3-translate` |
| `--user NAME` | `PLAMO3_USER` | `plamo3` |
| `--model 0.8b\|2b\|8b\|31b` | `PLAMO3_MODEL` | `2b` |
| `--quant Q2_K\|Q3_K_M\|Q4_K_M\|Q4_0` | `PLAMO3_QUANT` | `Q4_K_M` |
| `--backend cpu\|vulkan\|cuda12\|cuda13\|rocm` | `PLAMO3_BACKEND` | suggested from the detected GPU |
| `--gpus PCI[,PCI...]\|all` | `PLAMO3_GPUS` | one GPU, chosen as described below (asked when the backend sees two or more GPUs) |
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

GPU selection: when the selected backend can use two or more GPUs (NVIDIA for CUDA, AMD for ROCm, NVIDIA/AMD/Intel for Vulkan), the installer lists them with their PCI addresses, total memory and memory in use, and asks which to use (numbers such as `1` or `1,2`, or `all`). `--gpus` takes PCI addresses as shown by `lspci -D` (e.g. `0000:03:00.0`). The default is one GPU: NVIDIA before AMD before Intel (this matters only for Vulkan), then the most free memory, then the largest memory, then the lowest PCI address. So a GPU that another service already uses, or that drives the display, is avoided when a freer one exists. The chosen GPU is saved, so a re-run keeps it; on a re-run, the memory used by the installed llama-server itself is not counted as in use (NVIDIA only). An installation made by an earlier version of the installer keeps its saved `all`. With `all`, llama.cpp uses every GPU it supports and splits the model across them; with the CUDA backends, the installer suggests it when the model does not fit in the free memory of the selected GPUs. The selection is applied with `CUDA_VISIBLE_DEVICES` (GPU UUIDs), `ROCR_VISIBLE_DEVICES` or `GGML_VK_VISIBLE_DEVICES` in the llama-server unit (not set when every GPU of the backend is selected), and the GPUs llama-server uses are shown after it starts. llama-server logs them only at log verbosity 4, which the service does not use (it would log about five times as many lines per request), so the installer finds them with a short test run of llama-server (`-lv 4`, same user and environment as the unit, stopped before the model is loaded) just before it starts the service.

Network interfaces: when two or more network interfaces have global addresses (container/VM bridges such as `docker0`, `virbr0` and `lxdbr0` are ignored), the installer asks on which of them the web server (and llama-server if exposed) accept connections from other hosts (`all` or numbers). With selected interfaces, nginx and llama-server listen on their current addresses plus `127.0.0.1` (and `::1` for nginx), and the ufw rules are limited to them (`ufw allow in on IF to any port PORT proto tcp`). The interface names are saved and the addresses are looked up at installation, so re-run the installer if an address changes. Rules added by an earlier run that are no longer wanted (e.g. a rule for all interfaces) are removed.

### Sharing nginx with other sites

The installer uses the system nginx (`nginx.service` from apt) and shares it with whatever else runs on the machine, e.g. unrelated sites on ports 80/443 or a reverse proxy for another application:

- It writes only its own site file (`/etc/nginx/sites-available/plamo-3-translate` and the link in `sites-enabled`). `nginx.conf`, `conf.d`, the `default` site and other sites are not touched, and all its settings (body limit, timeouts) are inside its own `server` block, which listens only on the web server port and is not a `default_server`.
- nginx keeps running as its own user (`www-data` on Ubuntu), not as the service user. The uWSGI socket is owned by the service user and the group of the nginx workers (mode 0660); the group is taken from the `user` directive of the nginx configuration at installation, so re-run the installer if you change that directive.
- nginx is reloaded, not restarted, so connections of other sites are kept. If nginx was disabled or stopped, the installer enables/starts it and says so (nginx then serves all enabled sites).
- If nginx rejects the configuration, the installer restores the previous site file (or removes the new one) and stops, so that reloads for the other sites keep working. It also tells whether the configuration was already invalid without its changes.
- `--uninstall` removes only its own site and reloads nginx.

On a machine without nginx, apt also enables nginx's `default` site (port 80, "Welcome to nginx!"); the installer leaves it as it is.

### Start-up order with other services

`plamo-3-translate-llama.service` counts as started only when the model is loaded, not when the llama-server process is running: an `ExecStartPost=` command in the unit waits until llama-server's `/health` returns HTTP 200 (asked through the UNIX socket), and systemd keeps the unit "activating" until then. So another service that takes much of the free memory at its start (e.g. [qwen-strata-installer-for-resolute](https://github.com/astanabe/qwen-strata-installer-for-resolute) or [deepseek-maya-installer-for-resolute](https://github.com/astanabe/deepseek-maya-installer-for-resolute)) can leave PLaMo 3 Translate its memory by being ordered after it:

```
[Unit]
After=plamo-3-translate-llama.service
```

- If llama-server exits while it loads the model, the wait ends with a failure and systemd restarts the unit after 5 seconds (`Restart=on-failure`). Units ordered after it are started when the first attempt has failed; they do not wait for the retries.
- There is no time limit for loading the model (`TimeoutStartSec=infinity`), and `multi-user.target` is reached only when it is loaded. `systemctl start` / `restart` of the unit also return only then (use `--no-block` not to wait).
- `plamo-3-translate-uwsgi.service` does not wait for the model: the web page is available at once, and translation requests fail with an error message until the model is loaded.
- The order holds only at start-up. If `plamo-3-translate-llama.service` is restarted while the other services run, it gets only the memory they left.

### Files

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
/etc/nginx/sites-available/plamo-3-translate (linked from sites-enabled; the only file written under /etc/nginx)
```

Downloads are verified with SHA-256 checksums built into the installer (llama.cpp release assets and pinned Hugging Face revisions of the GGUF files).

## Models

- PLaMo 3 Translate 0.8B
  - https://huggingface.co/pfnet/plamo-3-translate-0.8b-GGUF
- PLaMo 3 Translate 2B (default)
  - https://huggingface.co/pfnet/plamo-3-translate-2b-GGUF
- PLaMo 3 Translate 8B
  - https://huggingface.co/pfnet/plamo-3-translate-8b-GGUF
- PLaMo 3 Translate 31B
  - https://huggingface.co/pfnet/plamo-3-translate-31b-GGUF

## License

### License of this repository

The files in this repository (the installer, plamo-3-translate-server.py, plamo-3-translate-client.py and the documentation) are distributed under the MIT License. See [LICENSE](LICENSE).

### License of PLaMo 3 Translate models

The PLaMo 3 Translate models downloaded by the installer are not part of this repository. They are distributed by Preferred Networks, Inc. (PFN) under the PLaMo Community License, not under the MIT License.

- https://plamo.preferredai.jp/info/plamo-community-license-en

Personal and non-commercial use is free. Commercial use requires registration with PFN. Read the full license text before using the models. The installer shows a summary of the license and aborts unless the user types `yes`. In non-interactive mode, `--accept-license` is required.

## Engine

- llama.cpp b12366
  - https://github.com/ggml-org/llama.cpp/releases/tag/b12366
- Prebuilt binary chosen by the user from:
  - CPU (`llama-b12366-bin-ubuntu-x64`)
  - Vulkan (`llama-b12366-bin-ubuntu-vulkan-x64`)
  - CUDA 12.8 / 13.5 (`llama-b12366-bin-ubuntu-cuda-*-x64`)
  - ROCm (`llama-b12366-bin-ubuntu-rocm-10.0-x64`)
- The installer detects available GPUs and suggests a default backend.
- llama-server options: `--jinja --no-prefill-assistant --alias plamo-3-translate`, plus `-c N` when a context size is given
- Context size: by default (`auto`) `-c` is omitted, so llama-server uses the model maximum (262144 tokens for all sizes) and, with its `--fit` feature, reduces the context (down to 4096) when it does not fit in the memory. The actual size is shown at the end of the installation, with a warning if it is smaller than about 40000 tokens, which plamo-3-translate-client.py may need for long documents with its default `--chunk-chars 20000` (the warning suggests a `--chunk-chars` value that fits). An explicit `--ctx-size N` (512–262144) is used as is.
- Memory for the full 262144-token context (Q4_K_M, model + KV cache + buffers, approximate): 0.8B 2.1 GB, 2B 4.5 GB, 8B 8.2 GB, 31B 28 GB. Only one layer in eight attends to the whole context, so the KV cache is small for this context length.

## Quantization

- Q2_K
- Q3_K_M
- Q4_K_M (default)
- Q4_0 (0.8B and 2B models only)

## Architecture

```
web browser ──→ nginx-full (TCP 18080) ──→ uWSGI ──→ plamo-3-translate-server.py ──┐
                         (UNIX socket /run/plamo-3-translate/uwsgi.sock)           │ UNIX socket
                                                                                   ↓ /run/plamo-3-translate-llama/llama.sock
plamo-3-translate-client.py ──────────────── TCP 28080 ──────────────────→ llama-server
```

- Web server (TCP 18080 by default) (nginx-full; the system nginx running as `www-data`, shared with other sites)
  - uWSGI (`uwsgi`, `uwsgi-plugin-python3` from apt)
    - plamo-3-translate-server.py (provided in this repository)
      - `GET /` : translation form (HTML). On PCs, Source text and Translation are side by side, surrounded by four Translate buttons that follow the textarea size; on phones (width below 760px), selectors, Source text, a Translate/Clear button and Translation are stacked, sized so that each screen ends at the button / at the title. The translation appears as it is generated. On PCs the status line shows the progress (prompt processing in percent, then the number of characters generated); phones have no status line, to give its height to Translation: the button shows the progress, and only errors appear below the form. Both textareas have a Copy button and, below it, a ConcatCopy button that copies Source text and Translation joined by a `---` line (a Markdown horizontal rule) between two empty lines; the model size and quantization reported by llama-server are shown.
      - `POST /api/translate` : JSON API
      - connects to llama-server through a UNIX socket (`/run/plamo-3-translate-llama/llama.sock`, accessible only to the service user)
- llama-server (TCP 28080 by default) for plamo-3-translate-client.py and other OpenAI-compatible clients

- plamo-3-translate-server.py and plamo-3-translate-client.py use the Python standard library only.
- `POST /api/translate` takes `{"text", "target_lang", "source_lang"?, "form"?, "glossary"?, "context"?}` and returns `{"translation", "target_lang"}` (`{"error"}` with HTTP 400 for invalid input, including text that does not fit in the context, and 502 for other llama-server errors). `target_lang` may be `auto` (the default in the form): Japanese source text is translated into English and anything else into Japanese; the source is Japanese if `source_lang` is `ja`, or, without `source_lang` ("Auto-detect (Japanese preferred)" in the form), if the text contains kana, or kanji but no hangul (so Chinese text is also translated into English; choose the target explicitly for Chinese to Japanese). The response's `target_lang` is the language actually used. `form` is `plain` or `polite` (Japanese target only; ignored with `auto` when the result is not Japanese); `glossary` is a list of `{"source", "target"}`. The settings are passed to llama-server in `chat_template_kwargs`.
- With `"stream": true` (used by the web form), a successful response is NDJSON (`application/x-ndjson`), one JSON object per line sent as llama-server makes progress: `{"target_lang"}` first, then `{"progress": {"processed", "total"}}` (prompt processing, in tokens, excluding cached ones) and `{"delta"}` (a piece of the translation), and finally `{"translation"}` (the whole text) or `{"error"}`. Errors detected before the stream starts are returned as a normal JSON error with HTTP 400/502. The response carries `X-Accel-Buffering: no` so that nginx passes each line on at once.
- A translation that llama-server stops at the token limit (`finish_reason` `"length"`) is returned as an error, not as a partial result. The cause is told from llama-server's token counts: when the context is full (HTTP 400), the message asks the user to translate the text in smaller parts; when the output reached its limit of 4 tokens per source character (HTTP 502; e.g. the model kept repeating itself), to retry with a shorter or reworded text. Both ask the user to see the server log or contact the administrator if the problem remains. With `"stream": true` the same messages come as the final `{"error"}` (the translation shown so far stays in the web form). The token counts are logged to stderr, i.e. the uWSGI log (`journalctl -u plamo-3-translate-uwsgi`).
  ```
  curl -H 'Content-Type: application/json' \
      -d '{"text": "こんにちは", "target_lang": "en"}' http://localhost:18080/api/translate
  ```
- All services run as the user specified at install time (default: `plamo3`). If the user does not exist, it is created as a system user without login.
- llama-server listens on the UNIX socket and on TCP `127.0.0.1` by default. If exposure is enabled, the TCP port listens on `0.0.0.0` (or on the selected interfaces, see `--interfaces`) and an API key (`--api-key`) generated by the installer is required (on the socket too; plamo-3-translate-server.py sends it).
- TLS and authentication for the web server are out of scope.

## Client

- Web browser (web server, TCP 18080)
- plamo-3-translate-client.py (provided in this repository; connects to llama-server, TCP 28080)

### plamo-3-translate-client.py

A command-line client that translates a plain text or Markdown file (or standard input) through llama-server, keeping the layout of the document. It uses the Python standard library only and is not installed by the installer: run it from a checkout of this repository, on the server or on any host that can reach the llama-server port (`--expose-llama`). It runs on Linux and Windows; plamo-3-translate-installer-for-windows installs a copy of it.

```
./plamo-3-translate-client.py doc.md                  # -> doc.en.md (or doc.ja.md)
./plamo-3-translate-client.py --to en -o out.txt in.txt
echo 'こんにちは' | ./plamo-3-translate-client.py -    # standard input -> standard output
./plamo-3-translate-client.py --intermediate en --to ja -o out.md in.md   # round trip: -> en -> ja
```

| Option | Default |
|---|---|
| `INPUT` | file to translate, or `-` for standard input |
| `-o`, `--output PATH` | output file, or `-` for standard output. Default: for a file, an automatically named file (see below); for standard input, standard output. Required with `--intermediate` |
| `-f`, `--force` | overwrite an existing output file (without it, an existing output file is an error) |
| `--from LANG` | detected (Japanese preferred, as in the web form) |
| `--to LANG\|auto` | `auto`: Japanese to English, anything else to Japanese (decided once for the whole document). A language is required with `--intermediate` |
| `--intermediate LANG` | none. Round-trip translation: translate into `LANG` first, then from `LANG` into `--to` (see below) |
| `--intermediate-output PATH` | none. With `--intermediate`, also write the whole document in the intermediate language to this file |
| `--form plain\|polite` | style of Japanese translations (target `ja` only; ignored when `auto` gives another language). With `--intermediate`, used in the second pass |
| `--format auto\|text\|markdown` | `auto`: `markdown` for `.md` and `.markdown` files, `text` otherwise (also for standard input) |
| `--glossary FILE` | one `source => target` per line (blank lines and lines starting with `#` are ignored; up to 500 entries). With `--intermediate`, used in the first pass (source to intermediate) |
| `--glossary2 FILE` | with `--intermediate`, the glossary of the second pass (intermediate to target); same format and limits as `--glossary` |
| `--context TEXT` / `--context-file FILE` | background information about the document passed to the model |
| `--chunk-chars N` | `20000`: maximum source characters per request |
| `--url URL` | `$PLAMO3_LLAMA_URL`, or `http://127.0.0.1:28080` (`http://` only) |
| `--api-key-file FILE` | the API key is taken from `$PLAMO3_LLAMA_API_KEY` |
| `-q`, `--quiet` | no progress output (warnings and errors are still shown) |
| `--list-languages` | print the language codes and exit |

- Output file names: `dir/stem.ext` becomes `dir/stem.<target>.ext` (`README` → `README.en`, `doc.md` → `doc.zh-hans.md`). A language code at the end of the stem is replaced when it matches the source language (`--from`, or `ja`/`en` as detected): `doc.ja.md` → `doc.en.md`, but an English `report.id.txt` → `report.id.ja.txt`. The output is written to a temporary file in the same directory and renamed when the translation is complete; on an error or Ctrl-C nothing is left behind. The exception: if the finished temporary file cannot be renamed to the output file (e.g. on Windows the output file is open in another program or read-only), the client keeps it, reports its path and exits with status 1; a failing `--intermediate-output` file is reported the same way, after the second pass has been completed. The input file itself is never overwritten.
- Input must be UTF-8, on Windows too (files, standard input, and the translation on standard output). A BOM and CRLF line ends are kept in the output.
- Markdown: front matter (`---` or `+++` at the beginning), fenced code blocks (```` ``` ```` / `~~~`), HTML blocks (from a line starting with a tag or comment to the next blank line), link reference definitions (`[label]: url`) and `$$` math blocks are copied unchanged; everything else (headings, lists, tables, quotes, ...) is translated with its markup. Indented code blocks are not recognized (they cannot be told apart from list continuation lines with a line-based parser) and are translated.
- Long documents are split into chunks of at most `--chunk-chars` characters: paragraphs (separated by blank lines) are packed together; a paragraph longer than that is split between lines, keeping a Markdown table (consecutive lines starting with `|`) in one piece. Lines are never split: a line or table longer than `--chunk-chars` is sent alone with a warning. Blank lines and the whitespace around each chunk are kept as in the source. Each request carries the preceding source/translation pairs (source and translation, up to 2.5 × `--chunk-chars` characters in all) as translation history, as described in the model card, so that terms and style stay consistent. With the defaults, a request of a long Japanese or English document can need about 40000 tokens of context (the tokenizer uses about 0.4 tokens per Japanese character and 0.16 per English character; Chinese, Korean and some other scripts use 0.8 or more, so they need more). Lower `--chunk-chars` if llama-server reports that the request does not fit in its context; the installer warns when the context is smaller than that.
- Progress goes to standard error: the chunk number and the prompt processing percentage, then, when writing to a file, the translation as it is generated; when writing to standard output, only the number of characters generated, and each chunk is written to standard output as soon as it is translated.
- If llama-server stops a translation at the token limit (`finish_reason` `"length"`: the context is full, or the output reached the limit of 4 tokens per source character, e.g. because the model kept repeating itself), the client stops with an error instead of writing a truncated translation, and advises a smaller `--chunk-chars` (which also shortens the history) or breaking up a very long line or table.
- Round-trip translation (`--intermediate LANG`): the document is translated twice, from the input language into `LANG` and from `LANG` into `--to`, which flattens the personal style of the text (e.g. Japanese → English → Japanese). Without `--intermediate` nothing changes.
  ```
  ./plamo-3-translate-client.py --intermediate en --to ja --glossary ja-en.txt --glossary2 en-ja.txt \
      --intermediate-output doc.mid.md -o doc.out.md doc.md
  ```
  - `--to` must be given as a language (not `auto`) different from `LANG`, and `-o` is required, also for standard input (`-o -` for standard output); no output file name is chosen automatically.
  - There are two passes: every chunk is translated into `LANG` (pass 1), then every intermediate chunk into the target language (pass 2). The chunks are those of the source document in both passes (the intermediate text is not split again), and each pass has its own translation history. `--from` (if given) and `--glossary` apply to pass 1; pass 2 always names `LANG` as its source language and uses `--glossary2` and `--form`. `--context` is passed to both.
  - `--intermediate-output PATH` writes the whole document in the intermediate language (with the parts copied unchanged, BOM and CRLF as in the input) when pass 1 is complete. It must be a file (not `-`) other than the input and `-o`; an existing file needs `-f`. It is kept when pass 2 fails.
  - An empty translation in pass 1 is an error. Progress shows a heading per pass (`Pass 1/2: ja -> en`, with `auto` when `--from` is not given) and, when writing to a file, the intermediate translation as well.
  - If the input is already written in `LANG`, pass 1 is pointless; this is not checked.
  - Proper nouns and terms can change on the way there and back; the two glossaries keep them in place (`--glossary`: source => intermediate, `--glossary2`: intermediate => target).
  - Markdown markup is more likely to be damaged than with one translation, and the run takes about twice as long.
  - There is no resume. If pass 2 fails, translate the `--intermediate-output` document as usual: `./plamo-3-translate-client.py --from LANG --to <target> --glossary <the --glossary2 file> -o doc.out.md doc.mid.md`.
- Exit status: 0 success, 1 translation error (connection, API key, llama-server error), 2 invalid arguments or input, 130 interrupted.
- API key: when llama-server is exposed, every request needs the key the installer generated, which is stored in `/etc/plamo-3-translate/llama-server.env` (readable by root and the service user only). Copy it into a file of your own and pass it with `--api-key-file` (or set `PLAMO3_LLAMA_API_KEY`):
  ```
  sudo sed -n 's/^LLAMA_API_KEY=//p' /etc/plamo-3-translate/llama-server.env > ~/.plamo3-key
  chmod 600 ~/.plamo3-key
  ./plamo-3-translate-client.py --api-key-file ~/.plamo3-key doc.md
  ```
  Without a key (or with a wrong one) the client stops with an explanation of how to give it.

## Procedure

1. Ask user for destdir (default `/opt/plamo-3-translate`), username (default `plamo3`), model (default 2B), quantization (default Q4_K_M), llama.cpp backend, GPUs to use (only if the backend sees two or more), context size (default `auto`: the model maximum, reduced to fit the memory), web server port (default 18080), llama-server port (default 28080), whether to expose the llama-server, network interfaces to listen on (only if two or more have addresses), whether to open the ports in ufw (only if ufw is active and the ports are not allowed yet), and license acceptance
2. Check prerequisites: ports are not in use, enough free disk space and memory for the selected GGUF file (warn and ask to continue if insufficient)
3. Install dependencies via apt
4. Create the service user if needed
5. Download and install llama.cpp and GGUF file
6. Generate and install systemd unit files and nginx site configuration (rolled back if nginx rejects it), start and enable servers (llama-server is started without waiting for the model), and reload nginx (open the ports in ufw as answered in step 1; if ufw became active after step 1, ask here)
7. Wait until llama-server has loaded the model (`/health`; time limit by model size: 3 minutes for 0.8B, 5 for 2B, 15 for 8B, 30 for 31B; fails at once if llama-server exits or is restarted) and translate a short sentence through the web server, checking that a non-empty result is returned
