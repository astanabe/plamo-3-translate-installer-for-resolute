#!/bin/bash
# PLaMo 3 Translate installer for Ubuntu 26.04 LTS (Resolute Raccoon), x86_64, Server or Desktop.
#
#   bash install-plamo-3-translate.sh [options]     install or update in place
#   bash install-plamo-3-translate.sh --uninstall   uninstall
#
# See README.md or --help for the options.

set -euo pipefail
umask 022

PLAMO3INS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PLAMO3INS_SCRIPT_DIR
readonly PLAMO3INS_SERVER_PY="plamo-3-translate-server.py"
readonly PLAMO3INS_APP_NAME="plamo-3-translate"
readonly PLAMO3INS_CONF_DIR="/etc/$PLAMO3INS_APP_NAME"
readonly PLAMO3INS_CONF_FILE="$PLAMO3INS_CONF_DIR/install.conf"
readonly PLAMO3INS_ENV_FILE="$PLAMO3INS_CONF_DIR/llama-server.env"
readonly PLAMO3INS_UWSGI_INI="$PLAMO3INS_CONF_DIR/uwsgi.ini"
readonly PLAMO3INS_LLAMA_UNIT="$PLAMO3INS_APP_NAME-llama.service"
readonly PLAMO3INS_UWSGI_UNIT="$PLAMO3INS_APP_NAME-uwsgi.service"
readonly PLAMO3INS_UNIT_DIR="/etc/systemd/system"
readonly PLAMO3INS_NGINX_SITE="/etc/nginx/sites-available/$PLAMO3INS_APP_NAME"
readonly PLAMO3INS_NGINX_LINK="/etc/nginx/sites-enabled/$PLAMO3INS_APP_NAME"
readonly PLAMO3INS_RUN_DIR="/run/$PLAMO3INS_APP_NAME"
readonly PLAMO3INS_SOCKET="$PLAMO3INS_RUN_DIR/uwsgi.sock"
# llama-server also listens on a UNIX socket for plamo-3-translate-server.py;
# the TCP port is for plamo-3-translate-client.py and other clients.
readonly PLAMO3INS_LLAMA_RUN_DIR="/run/$PLAMO3INS_APP_NAME-llama"
readonly PLAMO3INS_LLAMA_SOCKET="$PLAMO3INS_LLAMA_RUN_DIR/llama.sock"
readonly PLAMO3INS_MARKER=".$PLAMO3INS_APP_NAME-installation"
readonly PLAMO3INS_MODEL_ALIAS="plamo-3-translate"
readonly PLAMO3INS_LICENSE_URL="https://plamo.preferredai.jp/info/plamo-community-license-en"

readonly PLAMO3INS_LLAMA_TAG="b12366"
readonly PLAMO3INS_LLAMA_BASE_URL="https://github.com/ggml-org/llama.cpp/releases/download/$PLAMO3INS_LLAMA_TAG"

# Prebuilt llama.cpp archives: "<file> <sha256> <size>", one per line.
declare -A PLAMO3INS_LLAMA_ASSETS=(
  [cpu]="llama-b12366-bin-ubuntu-x64.tar.gz 60c318605a52ad7b15640cae72d6cb6b84b9737d4322be84f4a8e4bde699c1d7 23332283"
  [vulkan]="llama-b12366-bin-ubuntu-vulkan-x64.tar.gz f11eb7528080a85fc3e04fbc4b288facfcb3f5f9299c9840aede2c86b5d66304 36185244"
  [cuda12]="llama-b12366-bin-ubuntu-cuda-12.8-x64.tar.gz 7a8d47aab18101b536fc59c7b6c257c1c3eb0e573bf90ecb493fafa2aacc7531 199478939
cudart-llama-b12366-bin-ubuntu-cuda-12.8-x64.tar.gz 32b1f9caafd3de2051b9037d978ef021cc9377c77b3ef7a1d1dac3e6fd55fc4a 594371887"
  [cuda13]="llama-b12366-bin-ubuntu-cuda-13.5-x64.tar.gz db5463516175268a806cb26dcc2f52f43791f8a55921ada92f3bd64d763b5630 178616907
cudart-llama-b12366-bin-ubuntu-cuda-13.5-x64.tar.gz 7693ca40e8d95be53bcf5f46e37771704b4537a74448343e9059e07a1af75ba5 444078770"
  [rocm]="llama-b12366-bin-ubuntu-rocm-10.0-x64.tar.gz 899a5b4f2ab9f2db0064f99ad4cd4ea9bb2e12742399fb93bbebcdd8fa656a13 271160278"
)
declare -A PLAMO3INS_BACKEND_DESC=(
  [cpu]="CPU only"
  [vulkan]="Vulkan (AMD / Intel / NVIDIA GPUs)"
  [cuda12]="CUDA 12.8 (NVIDIA, driver 570 or later)"
  [cuda13]="CUDA 13.5 (NVIDIA, driver 580 or later)"
  [rocm]="ROCm (AMD GPUs supported by ROCm; experimental)"
)
readonly PLAMO3INS_BACKENDS="cpu vulkan cuda12 cuda13 rocm"
declare -A PLAMO3INS_BACKEND_PACKAGES=(
  [cpu]=""
  [vulkan]="libvulkan1 mesa-vulkan-drivers"
  [cuda12]=""
  [cuda13]=""
  [rocm]="libhipblas3 librocblas5 libamdhip64-7"
)
readonly PLAMO3INS_BASE_PACKAGES="nginx-full uwsgi uwsgi-plugin-python3 python3 curl ca-certificates iproute2 libgomp1 libssl3t64 libzstd1 zlib1g"

# Hugging Face repository revisions (pinned) and GGUF files: "<sha256> <size>".
declare -A PLAMO3INS_MODEL_REVISION=(
  [0.8b]=1cf96ae02133958a20074bfdfab76517bb737d00
  [2b]=4f672106b847200bfdc0f6af6c321cd94eba1aed
  [8b]=c67efa4eefdc14d3c97bf8f4f35ee58e2ecd2f42
  [31b]=8b797b290907c84403877cb9d03150929f10b467
)
declare -A PLAMO3INS_GGUF=(
  [0.8b-Q2_K]="97f0fd4a68d3d8eda39b018fd2f1ce2c58a6f86fad7dafd6d8b17cbdfab60709 410138816"
  [0.8b-Q3_K_M]="6c64dd53a367966ec00a7335ff34bb77ad5a893b6fbc7bf9ae51f7241e0dbfbe 486385856"
  [0.8b-Q4_0]="33deed2822f799de4d15bb03bea1ac40efa7d663d9239ee54cc7f65f5ab92917 547543232"
  [0.8b-Q4_K_M]="70891ec70dc7ab4205745a38307867c2881b99239f20327927633abfe4bc9ec6 573126848"
  [2b-Q2_K]="238232fe01810b5a0b42e93a4788bedb6b8831cc0baa4e1213ffb8394053b20d 1225612000"
  [2b-Q3_K_M]="fd79d48441cbb6eed8377084b43077ed006c9575ca55e47c002a8ee2f7e9faff 1495886560"
  [2b-Q4_0]="429b7934c88332262b4cca9fd5de36eb02e00f42dcd08ceb511a23e7ee4abafb 1698577120"
  [2b-Q4_K_M]="1ffd9073afcc70e35ccc942428aa2b73d7aa2b9ea779bf504b775369e0276c13 1807203040"
  [8b-Q2_K]="3322a15c142d2a30e552fe1ba054fa84174996c4537ee9161c1a1c96657dc127 3450746144"
  [8b-Q3_K_M]="ddd9697162fe3c8e6ece064863ae694fb28430ee98c0addfbd241f56a7f45578 4310218016"
  [8b-Q4_K_M]="94e5d3f91b421f7c8900ddaac27b11a19f7441426c954bbb25a2fd60a1640187 5280445728"
  [31b-Q2_K]="27b50ef2359e908aec72e0fc589535442eca8b17406c585d7f73db1d3e88cd65 12609924512"
  [31b-Q3_K_M]="2b91a6dc48a3544f08150e4e979a67af6ea489ac06ead39d0a3343bad2a2e330 15863131552"
  [31b-Q4_K_M]="47788c3eb71b830919a8454022381de943a43edfab65dad9e742997028d1f9df 19526593952"
)
readonly PLAMO3INS_MODELS="0.8b 2b 8b 31b"
readonly PLAMO3INS_QUANTS="Q2_K Q3_K_M Q4_K_M Q4_0"
# Native context length of all PLaMo 3 Translate models (GGUF plamo3.context_length).
readonly PLAMO3INS_NATIVE_CTX=262144
# KV cache bytes per context token: full-attention layers (1 in 8) x 2 (K, V) x KV heads x 128 x 2 bytes (f16).
# The sliding-window layers use a small fixed-size cache.  Measured with llama.cpp b12366.
declare -A PLAMO3INS_KV_BYTES=([0.8b]=1024 [2b]=6144 [8b]=8192 [31b]=32768)
# Context (tokens) that one request of plamo-3-translate-client.py with its defaults can
# need for long Japanese/English documents: chunk (DEFAULT_CHUNK_CHARS 20000 characters) +
# history (HISTORY_FACTOR 2.5 x 20000) + translation (~ the chunk), at ~0.4 tokens per
# character (Japanese; English is ~0.16), plus a margin.  Keep in sync with the client.
readonly PLAMO3INS_CLIENT_CHUNK_CHARS=20000
readonly PLAMO3INS_CLIENT_CTX=40000
# Seconds to wait for llama-server to load the model.
declare -A PLAMO3INS_HEALTH_TIMEOUT=([0.8b]=180 [2b]=300 [8b]=900 [31b]=1800)

# Settings: KEY -> default.  Values come from options > environment > install.conf > default.
readonly PLAMO3INS_KEYS="DESTDIR USER MODEL QUANT BACKEND GPUS CTX_SIZE WEB_PORT LLAMA_PORT EXPOSE_LLAMA INTERFACES"
declare -A PLAMO3INS_DEFAULT=(
  [DESTDIR]=/opt/plamo-3-translate [USER]=plamo3 [MODEL]=2b [QUANT]=Q4_K_M [BACKEND]=""
  [GPUS]=all [CTX_SIZE]=auto [WEB_PORT]=18080 [LLAMA_PORT]=28080 [EXPOSE_LLAMA]=no [INTERFACES]=all
)
declare -A PLAMO3INS_ARG=() PLAMO3INS_VAL=() PLAMO3INS_SAVED=() PLAMO3INS_FROM_USER=()
PLAMO3INS_ACTION=install
PLAMO3INS_ASSUME_YES=no
PLAMO3INS_ACCEPT_LICENSE=no
PLAMO3INS_OPEN_PORTS=""   # yes/no: open the ports in ufw; empty: ask when ufw is active
PLAMO3INS_INTERACTIVE=no
[[ -t 0 ]] && PLAMO3INS_INTERACTIVE=yes
PLAMO3INS_UFW_RULES=""   # ufw rules added by the installer: PORT (any interface) or PORT@INTERFACE
PLAMO3INS_N_CTX=""

# ---------------------------------------------------------------- utilities

info()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33mWarning:\033[0m %s\n' "$*" >&2; }
die()   { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: bash $(basename "$0") [options]

Installs a PLaMo 3 Translate web service (nginx + uWSGI + llama.cpp).
Values that are not given are asked interactively; when standard input is
not a terminal, defaults are used.  Re-running updates the installation.

Options (environment variable in brackets):
  --destdir DIR            install directory [PLAMO3_DESTDIR] (default ${PLAMO3INS_DEFAULT[DESTDIR]})
  --user NAME              service user [PLAMO3_USER] (default ${PLAMO3INS_DEFAULT[USER]})
  --model SIZE             0.8b, 2b, 8b or 31b [PLAMO3_MODEL] (default ${PLAMO3INS_DEFAULT[MODEL]})
  --quant TYPE             Q2_K, Q3_K_M, Q4_K_M or Q4_0 (0.8b/2b only)
                           [PLAMO3_QUANT] (default ${PLAMO3INS_DEFAULT[QUANT]})
  --backend NAME           cpu, vulkan, cuda12, cuda13 or rocm [PLAMO3_BACKEND]
                           (default: suggested from the detected GPU)
  --gpus all|PCI[,PCI...]  GPUs used by llama-server, by PCI address such as
                           0000:03:00.0 [PLAMO3_GPUS] (default all; asked when the
                           backend sees two or more GPUs)
  --ctx-size N|auto        llama-server context size [PLAMO3_CTX_SIZE] (default auto: the model
                           maximum $PLAMO3INS_NATIVE_CTX, reduced by llama.cpp to fit the memory)
  --web-port PORT          web server port [PLAMO3_WEB_PORT] (default ${PLAMO3INS_DEFAULT[WEB_PORT]})
  --llama-port PORT        llama-server port [PLAMO3_LLAMA_PORT] (default ${PLAMO3INS_DEFAULT[LLAMA_PORT]})
  --expose-llama           let llama-server listen on 0.0.0.0 with an API key
  --no-expose-llama        let llama-server listen on 127.0.0.1 only (default)
                           [PLAMO3_EXPOSE_LLAMA=yes|no]
  --interfaces all|IF[,IF...]
                           network interfaces on which the web server (and
                           llama-server if exposed) accept connections from other
                           hosts [PLAMO3_INTERFACES] (default all; asked when two or
                           more interfaces have addresses); 127.0.0.1 always works
  --accept-license         accept the PLaMo Community License [PLAMO3_ACCEPT_LICENSE=yes]
  --open-ports             open the web server port (and the llama-server port if
                           exposed) in ufw when ufw is active
  --no-open-ports          do not open ports in ufw [PLAMO3_OPEN_PORTS=yes|no]
                           (default: ask when ufw is active)
  --yes                    answer yes to warnings, opening ufw ports and uninstalling
  --uninstall              uninstall
  -h, --help               show this help
EOF
}

yesno() {  # normalize yes/no; prints "yes", "no" or nothing
  case "${1,,}" in
    y|yes|true|1|on) echo yes ;;
    n|no|false|0|off) echo no ;;
  esac
}

# confirm "question" -> returns 0 for yes.  --yes answers yes; non-interactive answers no.
confirm() {
  local PLAMO3INS_answer
  [[ $PLAMO3INS_ASSUME_YES == yes ]] && return 0
  [[ $PLAMO3INS_INTERACTIVE == yes ]] || return 1
  read -r -p "$1 [y/N] " PLAMO3INS_answer || return 1
  [[ $(yesno "$PLAMO3INS_answer") == yes ]]
}

# Warn about a problem and ask whether to continue.
warn_continue() {
  warn "$1"
  confirm "Continue anyway?" || die "aborted (use --yes to continue despite warnings)"
}

ask() {  # ask KEY "prompt" [extra help]: sets VAL[KEY] unless given by option/env
  local PLAMO3INS_key=$1 PLAMO3INS_prompt=$2 PLAMO3INS_answer
  [[ -n ${PLAMO3INS_FROM_USER[$PLAMO3INS_key]:-} || $PLAMO3INS_INTERACTIVE != yes ]] && return 0
  [[ -n ${3:-} ]] && printf '%s\n' "$3"
  read -r -p "$PLAMO3INS_prompt [${PLAMO3INS_VAL[$PLAMO3INS_key]}]: " PLAMO3INS_answer || die "no input"
  PLAMO3INS_answer="${PLAMO3INS_answer#"${PLAMO3INS_answer%%[![:space:]]*}"}"
  PLAMO3INS_answer="${PLAMO3INS_answer%"${PLAMO3INS_answer##*[![:space:]]}"}"
  [[ -n $PLAMO3INS_answer ]] && PLAMO3INS_VAL[$PLAMO3INS_key]=$PLAMO3INS_answer
  return 0
}

ctx_label() {
  if [[ ${PLAMO3INS_VAL[CTX_SIZE]} == auto ]]; then
    echo "auto (up to $PLAMO3INS_NATIVE_CTX, reduced to fit the memory)"
  else
    echo "${PLAMO3INS_VAL[CTX_SIZE]}"
  fi
}

gguf_name() { echo "plamo-3-translate-$1-$2.gguf"; }  # model quant
human() { numfmt --to=iec --suffix=B "$1"; }

sha256_of() { sha256sum "$1" | cut -d' ' -f1; }

service_exists() { [[ -f $PLAMO3INS_UNIT_DIR/$1 ]]; }

# ------------------------------------------------------------------ options

parse_args() {
  local PLAMO3INS_opt
  while (($#)); do
    PLAMO3INS_opt=$1
    case $PLAMO3INS_opt in
      --destdir|--user|--model|--quant|--backend|--gpus|--ctx-size|--web-port|--llama-port|--interfaces)
        (($# >= 2)) || die "$PLAMO3INS_opt requires a value"
        local PLAMO3INS_key=${PLAMO3INS_opt#--}; PLAMO3INS_key=${PLAMO3INS_key//-/_}; PLAMO3INS_key=${PLAMO3INS_key^^}
        PLAMO3INS_ARG[$PLAMO3INS_key]=$2; shift 2 ;;
      --destdir=*|--user=*|--model=*|--quant=*|--backend=*|--gpus=*|--ctx-size=*|--web-port=*|--llama-port=*|--interfaces=*)
        local PLAMO3INS_key=${PLAMO3INS_opt%%=*}; PLAMO3INS_key=${PLAMO3INS_key#--}; PLAMO3INS_key=${PLAMO3INS_key//-/_}; PLAMO3INS_key=${PLAMO3INS_key^^}
        PLAMO3INS_ARG[$PLAMO3INS_key]=${PLAMO3INS_opt#*=}; shift ;;
      --expose-llama) PLAMO3INS_ARG[EXPOSE_LLAMA]=yes; shift ;;
      --no-expose-llama) PLAMO3INS_ARG[EXPOSE_LLAMA]=no; shift ;;
      --accept-license) PLAMO3INS_ACCEPT_LICENSE=yes; shift ;;
      --open-ports) PLAMO3INS_OPEN_PORTS=yes; shift ;;
      --no-open-ports) PLAMO3INS_OPEN_PORTS=no; shift ;;
      --yes|-y) PLAMO3INS_ASSUME_YES=yes; shift ;;
      --uninstall) PLAMO3INS_ACTION=uninstall; shift ;;
      -h|--help) usage; exit 0 ;;
      *) usage >&2; die "unknown option: $PLAMO3INS_opt" ;;
    esac
  done
}

load_saved_config() {
  local PLAMO3INS_line PLAMO3INS_key PLAMO3INS_value
  [[ -f $PLAMO3INS_CONF_FILE ]] || return 0
  while IFS= read -r PLAMO3INS_line || [[ -n $PLAMO3INS_line ]]; do
    [[ $PLAMO3INS_line =~ ^([A-Z_]+)=(.*)$ ]] || continue
    PLAMO3INS_key=${BASH_REMATCH[1]}; PLAMO3INS_value=${BASH_REMATCH[2]}
    PLAMO3INS_value=${PLAMO3INS_value#\'}; PLAMO3INS_value=${PLAMO3INS_value%\'}
    PLAMO3INS_SAVED[$PLAMO3INS_key]=$PLAMO3INS_value
  done < "$PLAMO3INS_CONF_FILE"
}

# Merge options > environment > install.conf > default into VAL.
resolve_values() {
  local PLAMO3INS_key PLAMO3INS_env
  for PLAMO3INS_key in $PLAMO3INS_KEYS; do
    PLAMO3INS_env="PLAMO3_$PLAMO3INS_key"
    if [[ -n ${PLAMO3INS_ARG[$PLAMO3INS_key]:-} ]]; then
      PLAMO3INS_VAL[$PLAMO3INS_key]=${PLAMO3INS_ARG[$PLAMO3INS_key]}; PLAMO3INS_FROM_USER[$PLAMO3INS_key]=1
    elif [[ -n ${!PLAMO3INS_env:-} ]]; then
      PLAMO3INS_VAL[$PLAMO3INS_key]=${!PLAMO3INS_env}; PLAMO3INS_FROM_USER[$PLAMO3INS_key]=1
    elif [[ -n ${PLAMO3INS_SAVED[$PLAMO3INS_key]:-} ]]; then
      PLAMO3INS_VAL[$PLAMO3INS_key]=${PLAMO3INS_SAVED[$PLAMO3INS_key]}
    else
      PLAMO3INS_VAL[$PLAMO3INS_key]=${PLAMO3INS_DEFAULT[$PLAMO3INS_key]}
    fi
  done
  [[ $(yesno "${PLAMO3_ACCEPT_LICENSE:-}") == yes ]] && PLAMO3INS_ACCEPT_LICENSE=yes
  if [[ -z $PLAMO3INS_OPEN_PORTS && -n ${PLAMO3_OPEN_PORTS:-} ]]; then
    PLAMO3INS_OPEN_PORTS=$(yesno "$PLAMO3_OPEN_PORTS")
    [[ -n $PLAMO3INS_OPEN_PORTS ]] || die "invalid value for PLAMO3_OPEN_PORTS: $PLAMO3_OPEN_PORTS (use yes or no)"
  fi
  if [[ -n ${PLAMO3INS_VAL[EXPOSE_LLAMA]} ]]; then
    local PLAMO3INS_e; PLAMO3INS_e=$(yesno "${PLAMO3INS_VAL[EXPOSE_LLAMA]}")
    [[ -n $PLAMO3INS_e ]] || die "invalid value for expose-llama: ${PLAMO3INS_VAL[EXPOSE_LLAMA]} (use yes or no)"
    PLAMO3INS_VAL[EXPOSE_LLAMA]=$PLAMO3INS_e
  fi
  if [[ -z ${PLAMO3INS_VAL[BACKEND]} ]]; then
    PLAMO3INS_VAL[BACKEND]=$(detect_gpu)
  fi
  return 0
}

# --------------------------------------------------------------- detection

# Print the NVIDIA driver major version, or nothing if nvidia-smi does not work.
nvidia_driver_major() {
  local PLAMO3INS_v
  command -v nvidia-smi >/dev/null 2>&1 || return 0
  PLAMO3INS_v=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null) || return 0
  PLAMO3INS_v=${PLAMO3INS_v%%$'\n'*}
  [[ $PLAMO3INS_v =~ ^([0-9]+) ]] && echo "${BASH_REMATCH[1]}"
  return 0
}

# Print the vendors of display controllers (nvidia, amd, intel) found on PCI.
gpu_vendors() {
  local PLAMO3INS_dev PLAMO3INS_class PLAMO3INS_vendor
  for PLAMO3INS_dev in /sys/bus/pci/devices/*; do
    [[ -r $PLAMO3INS_dev/class && -r $PLAMO3INS_dev/vendor ]] || continue
    PLAMO3INS_class=$(<"$PLAMO3INS_dev/class"); PLAMO3INS_vendor=$(<"$PLAMO3INS_dev/vendor")
    [[ $PLAMO3INS_class == 0x03* ]] || continue
    case $PLAMO3INS_vendor in
      0x10de) echo nvidia ;;
      0x1002) echo amd ;;
      0x8086) echo intel ;;
    esac
  done | sort -u
}

# Suggest a backend from the detected GPUs.  CUDA is suggested only when the
# NVIDIA driver works (nvidia-smi), since the installer does not install drivers.
detect_gpu() {
  local PLAMO3INS_vendors PLAMO3INS_major
  PLAMO3INS_vendors=$(gpu_vendors)
  PLAMO3INS_major=$(nvidia_driver_major)
  if grep -qx nvidia <<<"$PLAMO3INS_vendors" && [[ -n $PLAMO3INS_major ]]; then
    if ((PLAMO3INS_major < 580)); then echo cuda12; else echo cuda13; fi
  elif grep -qx amd <<<"$PLAMO3INS_vendors"; then
    echo vulkan
  else
    echo cpu
  fi
}

# ------------------------------------------------------------- GPU selection
#
# GPUs are selected by PCI address (stable across reboots and backends) and passed to
# llama-server through the backend's own variable, mapped when the units are written:
#   CUDA   CUDA_VISIBLE_DEVICES=<GPU UUIDs from nvidia-smi>
#   ROCm   ROCR_VISIBLE_DEVICES=<GPU agent indices, in KFD topology node order>
#   Vulkan GGML_VK_VISIBLE_DEVICES=<indices in vkEnumeratePhysicalDevices order>
# After start-up, the "using device ... (<PCI address>)" lines of llama-server are checked.

# normalize_pci ADDRESS: print a PCI address as dddd:bb:dd.f (lower case), or nothing if invalid.
normalize_pci() {
  local PLAMO3INS_a=${1,,}
  [[ $PLAMO3INS_a =~ ^[0-9a-f]{2}:[0-9a-f]{2}\.[0-7]$ ]] && PLAMO3INS_a="0000:$PLAMO3INS_a"
  [[ $PLAMO3INS_a =~ ^([0-9a-f]{4,8}):([0-9a-f]{2}:[0-9a-f]{2}\.[0-7])$ ]] || return 0
  printf '%04x:%s\n' "$((16#${BASH_REMATCH[1]}))" "${BASH_REMATCH[2]}"
}

# Print "PCI address<TAB>description" for the GPUs the selected backend can use.
gpu_devices() {
  local PLAMO3INS_vendors PLAMO3INS_dev PLAMO3INS_pci PLAMO3INS_vendor PLAMO3INS_name PLAMO3INS_mem PLAMO3INS_mem_mib PLAMO3INS_smi="" PLAMO3INS_line
  case ${PLAMO3INS_VAL[BACKEND]} in
    cuda12|cuda13) PLAMO3INS_vendors="0x10de" ;;
    rocm) PLAMO3INS_vendors="0x1002" ;;
    vulkan) PLAMO3INS_vendors="0x10de 0x1002 0x8086" ;;
    *) return 0 ;;
  esac
  if command -v nvidia-smi >/dev/null 2>&1; then
    PLAMO3INS_smi=$(nvidia-smi --query-gpu=pci.bus_id,memory.total --format=csv,noheader,nounits 2>/dev/null || true)
  fi
  for PLAMO3INS_dev in /sys/bus/pci/devices/*; do
    [[ -r $PLAMO3INS_dev/class && -r $PLAMO3INS_dev/vendor ]] || continue
    [[ $(<"$PLAMO3INS_dev/class") == 0x03* ]] || continue
    PLAMO3INS_vendor=$(<"$PLAMO3INS_dev/vendor")
    [[ " $PLAMO3INS_vendors " == *" $PLAMO3INS_vendor "* ]] || continue
    PLAMO3INS_pci=$(basename "$PLAMO3INS_dev")
    PLAMO3INS_name=""
    command -v lspci >/dev/null 2>&1 && PLAMO3INS_name=$(lspci -vmm -s "$PLAMO3INS_pci" 2>/dev/null | sed -n 's/^Device:[[:space:]]*//p;T;q' || true)
    [[ -n $PLAMO3INS_name ]] || PLAMO3INS_name="${PLAMO3INS_vendor#0x}:$(sed 's/^0x//' "$PLAMO3INS_dev/device")"
    PLAMO3INS_mem=""
    if [[ -r $PLAMO3INS_dev/mem_info_vram_total ]]; then
      PLAMO3INS_mem=$(human "$(<"$PLAMO3INS_dev/mem_info_vram_total")")
    else
      while IFS=', ' read -r PLAMO3INS_line PLAMO3INS_mem_mib; do
        [[ $(normalize_pci "$PLAMO3INS_line") == "$PLAMO3INS_pci" && $PLAMO3INS_mem_mib =~ ^[0-9]+$ ]] \
          && PLAMO3INS_mem=$(human $((PLAMO3INS_mem_mib * 1024 * 1024)))
      done <<<"$PLAMO3INS_smi"
    fi
    printf '%s\t%s%s\n' "$PLAMO3INS_pci" "$PLAMO3INS_name" "${PLAMO3INS_mem:+ ($PLAMO3INS_mem)}"
  done
}

# Print "UUID<TAB>PCI address" for each NVIDIA GPU.
cuda_devices() {
  local PLAMO3INS_out PLAMO3INS_uuid PLAMO3INS_bus
  PLAMO3INS_out=$(nvidia-smi --query-gpu=uuid,pci.bus_id --format=csv,noheader 2>/dev/null) || return 0
  while IFS=', ' read -r PLAMO3INS_uuid PLAMO3INS_bus; do
    [[ -n $PLAMO3INS_uuid ]] && printf '%s\t%s\n' "$PLAMO3INS_uuid" "$(normalize_pci "$PLAMO3INS_bus")"
  done <<<"$PLAMO3INS_out"
  return 0
}

# Print "index<TAB>PCI address" for each GPU agent in ROCR_VISIBLE_DEVICES order (KFD topology nodes).
rocm_devices() {
  local PLAMO3INS_nodes=/sys/class/kfd/kfd/topology/nodes PLAMO3INS_n=0 PLAMO3INS_idx=0 PLAMO3INS_props PLAMO3INS_domain PLAMO3INS_loc
  while [[ -d $PLAMO3INS_nodes/$PLAMO3INS_n ]]; do
    if [[ $(<"$PLAMO3INS_nodes/$PLAMO3INS_n/gpu_id") != 0 ]]; then
      PLAMO3INS_props=$(<"$PLAMO3INS_nodes/$PLAMO3INS_n/properties")
      PLAMO3INS_domain=$(awk '$1 == "domain" {print $2}' <<<"$PLAMO3INS_props")
      PLAMO3INS_loc=$(awk '$1 == "location_id" {print $2}' <<<"$PLAMO3INS_props")
      printf '%d\t%04x:%02x:%02x.%x\n' "$PLAMO3INS_idx" "${PLAMO3INS_domain:-0}" $((PLAMO3INS_loc >> 8)) $(((PLAMO3INS_loc >> 3) & 31)) $((PLAMO3INS_loc & 7))
      PLAMO3INS_idx=$((PLAMO3INS_idx + 1))
    fi
    PLAMO3INS_n=$((PLAMO3INS_n + 1))
  done
}

# Print "index<TAB>PCI address<TAB>type<TAB>name" for each Vulkan physical device ("-" if the
# PCI address is unknown), in vkEnumeratePhysicalDevices order.  Needs libvulkan1.
vulkan_devices() {
  python3 -I - <<'PY'
import ctypes
import sys

c_u32, c_vp = ctypes.c_uint32, ctypes.c_void_p
try:
    vk = ctypes.CDLL("libvulkan.so.1")
except OSError as e:
    sys.exit(f"cannot load libvulkan.so.1: {e}")


class AppInfo(ctypes.Structure):
    _fields_ = [("sType", c_u32), ("pNext", c_vp), ("pApplicationName", ctypes.c_char_p),
                ("applicationVersion", c_u32), ("pEngineName", ctypes.c_char_p),
                ("engineVersion", c_u32), ("apiVersion", c_u32)]


class InstanceInfo(ctypes.Structure):
    _fields_ = [("sType", c_u32), ("pNext", c_vp), ("flags", c_u32),
                ("pApplicationInfo", ctypes.POINTER(AppInfo)), ("enabledLayerCount", c_u32),
                ("ppEnabledLayerNames", c_vp), ("enabledExtensionCount", c_u32),
                ("ppEnabledExtensionNames", c_vp)]


class ExtensionProperties(ctypes.Structure):
    _fields_ = [("extensionName", ctypes.c_char * 256), ("specVersion", c_u32)]


class PciBusInfo(ctypes.Structure):  # VkPhysicalDevicePCIBusInfoPropertiesEXT
    _fields_ = [("sType", c_u32), ("pNext", c_vp), ("pciDomain", c_u32), ("pciBus", c_u32),
                ("pciDevice", c_u32), ("pciFunction", c_u32)]


class Properties2(ctypes.Structure):  # VkPhysicalDeviceProperties2; properties is 824 bytes
    _fields_ = [("sType", c_u32), ("pNext", c_vp), ("properties", ctypes.c_uint8 * 1024)]


vk.vkCreateInstance.argtypes = [ctypes.POINTER(InstanceInfo), c_vp, ctypes.POINTER(c_vp)]
vk.vkCreateInstance.restype = ctypes.c_int32
vk.vkDestroyInstance.argtypes = [c_vp, c_vp]
vk.vkDestroyInstance.restype = None
vk.vkEnumeratePhysicalDevices.argtypes = [c_vp, ctypes.POINTER(c_u32), c_vp]
vk.vkEnumeratePhysicalDevices.restype = ctypes.c_int32
vk.vkEnumerateDeviceExtensionProperties.argtypes = [c_vp, ctypes.c_char_p, ctypes.POINTER(c_u32), c_vp]
vk.vkEnumerateDeviceExtensionProperties.restype = ctypes.c_int32
vk.vkGetPhysicalDeviceProperties2.argtypes = [c_vp, ctypes.POINTER(Properties2)]
vk.vkGetPhysicalDeviceProperties2.restype = None

app = AppInfo(0, None, b"plamo-3-translate-installer", 0, None, 0, (1 << 22) | (1 << 12))  # Vulkan 1.1
info = InstanceInfo(1, None, 0, ctypes.pointer(app), 0, None, 0, None)
instance = c_vp()
if vk.vkCreateInstance(ctypes.byref(info), None, ctypes.byref(instance)) != 0:
    sys.exit("vkCreateInstance failed")
try:
    count = c_u32()
    vk.vkEnumeratePhysicalDevices(instance, ctypes.byref(count), None)
    devices = (c_vp * count.value)()
    vk.vkEnumeratePhysicalDevices(instance, ctypes.byref(count), devices)
    types = {0: "other", 1: "integrated", 2: "discrete", 3: "virtual", 4: "cpu"}
    for i in range(count.value):
        dev = c_vp(devices[i])
        n = c_u32()
        vk.vkEnumerateDeviceExtensionProperties(dev, None, ctypes.byref(n), None)
        exts = (ExtensionProperties * n.value)()
        vk.vkEnumerateDeviceExtensionProperties(dev, None, ctypes.byref(n), exts)
        has_pci = any(e.extensionName == b"VK_EXT_pci_bus_info" for e in exts)
        pci = PciBusInfo(1000212000, None)
        props = Properties2(1000059001, ctypes.cast(ctypes.pointer(pci), c_vp) if has_pci else None)
        vk.vkGetPhysicalDeviceProperties2(dev, ctypes.byref(props))
        raw = bytes(props.properties)
        dev_type = int.from_bytes(raw[16:20], "little")
        name = raw[20:276].split(b"\0", 1)[0].decode("utf-8", "replace")
        address = (f"{pci.pciDomain:04x}:{pci.pciBus:02x}:{pci.pciDevice:02x}.{pci.pciFunction:x}"
                   if has_pci else "-")
        print(f"{i}\t{address}\t{types.get(dev_type, 'other')}\t{name}")
finally:
    vk.vkDestroyInstance(instance, None)
PY
}

# Print the Environment= lines that restrict llama-server to the selected GPUs.
gpu_environment() {
  local PLAMO3INS_b=${PLAMO3INS_VAL[BACKEND]} PLAMO3INS_map PLAMO3INS_p PLAMO3INS_id PLAMO3INS_var PLAMO3INS_ids=()
  case $PLAMO3INS_b in cuda12|cuda13) echo "Environment=CUDA_DEVICE_ORDER=PCI_BUS_ID" ;; esac
  [[ $PLAMO3INS_b != cpu && ${PLAMO3INS_VAL[GPUS]} != all ]] || return 0
  case $PLAMO3INS_b in
    cuda12|cuda13) PLAMO3INS_var=CUDA_VISIBLE_DEVICES; PLAMO3INS_map=$(cuda_devices) ;;
    rocm) PLAMO3INS_var=ROCR_VISIBLE_DEVICES; PLAMO3INS_map=$(rocm_devices) ;;
    vulkan) PLAMO3INS_var=GGML_VK_VISIBLE_DEVICES
            PLAMO3INS_map=$(vulkan_devices) || die "cannot list the Vulkan devices; re-run with --gpus all" ;;
  esac
  for PLAMO3INS_p in ${PLAMO3INS_VAL[GPUS]//,/ }; do
    PLAMO3INS_id=$(awk -F '\t' -v p="$PLAMO3INS_p" '$2 == p {print $1; exit}' <<<"$PLAMO3INS_map")
    [[ -n $PLAMO3INS_id ]] || die "GPU $PLAMO3INS_p was not found by the $PLAMO3INS_b backend; re-run with --gpus all"
    PLAMO3INS_ids+=("$PLAMO3INS_id")
  done
  echo "Environment=$PLAMO3INS_var=$(IFS=,; echo "${PLAMO3INS_ids[*]}")"
}

gpu_label() {
  local PLAMO3INS_n
  [[ ${PLAMO3INS_VAL[BACKEND]} != cpu ]] || { echo "none (cpu backend)"; return 0; }
  if [[ ${PLAMO3INS_VAL[GPUS]} == all ]]; then
    PLAMO3INS_n=$(gpu_devices | grep -c . || true)
    echo "all ($PLAMO3INS_n detected)"
  else
    echo "${PLAMO3INS_VAL[GPUS]//,/, }"
  fi
}

# ------------------------------------------------------- network interfaces
#
# nginx and llama-server cannot bind to an interface, so the selected interfaces are
# turned into their current addresses when the configuration is written (re-run the
# installer if an address changes).  127.0.0.1 (and ::1) are always included so that
# local clients and the smoke test keep working.  ufw rules are limited with "in on IF".

# Print "interface<TAB>address address ..." for each interface with a global address
# (container and VM bridges excluded; temporary/deprecated IPv6 addresses skipped).
net_interfaces() {
  local PLAMO3INS_out PLAMO3INS_ifc PLAMO3INS_fam PLAMO3INS_addr PLAMO3INS_rest PLAMO3INS_order=()
  local -A PLAMO3INS_addrs=()
  PLAMO3INS_out=$(ip -o addr show scope global 2>/dev/null || true)
  while read -r _ PLAMO3INS_ifc PLAMO3INS_fam PLAMO3INS_addr PLAMO3INS_rest; do
    [[ -n $PLAMO3INS_ifc && ( $PLAMO3INS_fam == inet || $PLAMO3INS_fam == inet6 ) ]] || continue
    [[ $PLAMO3INS_rest == *temporary* || $PLAMO3INS_rest == *deprecated* || $PLAMO3INS_rest == *tentative* ]] && continue
    PLAMO3INS_ifc=${PLAMO3INS_ifc%%@*}
    case $PLAMO3INS_ifc in lo|docker*|br-*|veth*|virbr*|lxdbr*|cni*) continue ;; esac
    [[ -n ${PLAMO3INS_addrs[$PLAMO3INS_ifc]+x} ]] || PLAMO3INS_order+=("$PLAMO3INS_ifc")
    PLAMO3INS_addrs[$PLAMO3INS_ifc]+="${PLAMO3INS_addrs[$PLAMO3INS_ifc]:+ }${PLAMO3INS_addr%/*}"
  done <<<"$PLAMO3INS_out"
  for PLAMO3INS_ifc in "${PLAMO3INS_order[@]}"; do
    printf '%s\t%s\n' "$PLAMO3INS_ifc" "${PLAMO3INS_addrs[$PLAMO3INS_ifc]}"
  done
}

# Print the addresses of the selected interfaces, one per line (nothing for "all").
listen_addresses() {
  local PLAMO3INS_list PLAMO3INS_ifc PLAMO3INS_addr_list=()
  [[ ${PLAMO3INS_VAL[INTERFACES]} != all ]] || return 0
  PLAMO3INS_list=$(net_interfaces)
  for PLAMO3INS_ifc in ${PLAMO3INS_VAL[INTERFACES]//,/ }; do
    read -r -a PLAMO3INS_addr_list <<<"$(awk -F '\t' -v i="$PLAMO3INS_ifc" '$1 == i {print $2}' <<<"$PLAMO3INS_list")"
    ((${#PLAMO3INS_addr_list[@]} == 0)) || printf '%s\n' "${PLAMO3INS_addr_list[@]}"
  done
}

interfaces_label() {
  local PLAMO3INS_list PLAMO3INS_ifc PLAMO3INS_out=""
  if [[ ${PLAMO3INS_VAL[INTERFACES]} == all ]]; then echo "all"; return 0; fi
  PLAMO3INS_list=$(net_interfaces)
  for PLAMO3INS_ifc in ${PLAMO3INS_VAL[INTERFACES]//,/ }; do
    PLAMO3INS_out+="${PLAMO3INS_out:+, }$PLAMO3INS_ifc ($(awk -F '\t' -v i="$PLAMO3INS_ifc" '$1 == i {gsub(/ /, ", ", $2); print $2}' <<<"$PLAMO3INS_list"))"
  done
  echo "$PLAMO3INS_out (and 127.0.0.1)"
}

validate_interfaces() {
  local PLAMO3INS_v=${PLAMO3INS_VAL[INTERFACES]} PLAMO3INS_list PLAMO3INS_ifc PLAMO3INS_out=()
  if [[ -z $PLAMO3INS_v || ${PLAMO3INS_v,,} == all ]]; then PLAMO3INS_VAL[INTERFACES]=all; return 0; fi
  PLAMO3INS_list=$(net_interfaces | cut -f1)
  for PLAMO3INS_ifc in ${PLAMO3INS_v//,/ }; do
    [[ $PLAMO3INS_ifc =~ ^[A-Za-z0-9_.:-]{1,15}$ ]] || die "invalid interface name: $PLAMO3INS_ifc"
    if ! grep -qxF "$PLAMO3INS_ifc" <<<"$PLAMO3INS_list"; then
      if [[ -n ${PLAMO3INS_FROM_USER[INTERFACES]:-} ]]; then
        die "interface $PLAMO3INS_ifc has no global address (available: $(paste -sd' ' <<<"$PLAMO3INS_list"))"
      fi
      warn "the saved interface selection ($PLAMO3INS_v) does not match this machine; listening on all interfaces"
      PLAMO3INS_VAL[INTERFACES]=all; return 0
    fi
    [[ " ${PLAMO3INS_out[*]} " == *" $PLAMO3INS_ifc "* ]] || PLAMO3INS_out+=("$PLAMO3INS_ifc")
  done
  PLAMO3INS_VAL[INTERFACES]=$(IFS=,; echo "${PLAMO3INS_out[*]}")
}

# Ask on which interfaces to accept connections when two or more have addresses.
prompt_interfaces() {
  local PLAMO3INS_list PLAMO3INS_names=() PLAMO3INS_ifc PLAMO3INS_addrs PLAMO3INS_i PLAMO3INS_default="" PLAMO3INS_answer PLAMO3INS_tok PLAMO3INS_sel=() PLAMO3INS_ok PLAMO3INS_what="the web server"
  [[ -z ${PLAMO3INS_FROM_USER[INTERFACES]:-} && $PLAMO3INS_INTERACTIVE == yes ]] || return 0
  PLAMO3INS_list=$(net_interfaces)
  [[ -n $PLAMO3INS_list ]] || return 0
  while IFS=$'\t' read -r PLAMO3INS_ifc PLAMO3INS_addrs; do PLAMO3INS_names+=("$PLAMO3INS_ifc"); done <<<"$PLAMO3INS_list"
  ((${#PLAMO3INS_names[@]} >= 2)) || return 0
  [[ ${PLAMO3INS_VAL[EXPOSE_LLAMA]} != yes ]] || PLAMO3INS_what="the web server and llama-server"
  echo "Network interfaces on which $PLAMO3INS_what accept connections from other hosts"
  echo "(127.0.0.1 is always available on this machine):"
  PLAMO3INS_i=0
  while IFS=$'\t' read -r PLAMO3INS_ifc PLAMO3INS_addrs; do
    PLAMO3INS_i=$((PLAMO3INS_i + 1))
    printf '  %d) %-12s %s\n' "$PLAMO3INS_i" "$PLAMO3INS_ifc" "${PLAMO3INS_addrs// /, }"
  done <<<"$PLAMO3INS_list"
  if [[ ${PLAMO3INS_VAL[INTERFACES]} == all ]]; then
    PLAMO3INS_default=all
  else
    for PLAMO3INS_i in "${!PLAMO3INS_names[@]}"; do
      [[ ",${PLAMO3INS_VAL[INTERFACES]}," == *",${PLAMO3INS_names[$PLAMO3INS_i]},"* ]] && PLAMO3INS_default+="${PLAMO3INS_default:+,}$((PLAMO3INS_i + 1))"
    done
  fi
  while :; do
    read -r -p "Interfaces (all, or numbers such as 1,2) [$PLAMO3INS_default]: " PLAMO3INS_answer || die "no input"
    PLAMO3INS_answer=${PLAMO3INS_answer:-$PLAMO3INS_default}
    if [[ ${PLAMO3INS_answer,,} == all ]]; then PLAMO3INS_VAL[INTERFACES]=all; return 0; fi
    PLAMO3INS_sel=(); PLAMO3INS_ok=yes
    for PLAMO3INS_tok in ${PLAMO3INS_answer//,/ }; do
      if [[ $PLAMO3INS_tok =~ ^[0-9]+$ ]] && ((PLAMO3INS_tok >= 1 && PLAMO3INS_tok <= ${#PLAMO3INS_names[@]})); then
        PLAMO3INS_ifc=${PLAMO3INS_names[$((PLAMO3INS_tok - 1))]}
        [[ " ${PLAMO3INS_sel[*]} " == *" $PLAMO3INS_ifc "* ]] || PLAMO3INS_sel+=("$PLAMO3INS_ifc")
      else
        PLAMO3INS_ok=no
      fi
    done
    if [[ $PLAMO3INS_ok == yes && ${#PLAMO3INS_sel[@]} -gt 0 ]]; then
      PLAMO3INS_VAL[INTERFACES]=$(IFS=,; echo "${PLAMO3INS_sel[*]}")
      return 0
    fi
    warn "answer all, or numbers between 1 and ${#PLAMO3INS_names[@]} separated by commas"
  done
}

# ------------------------------------------------------------------ prompts

prompt_values() {
  local PLAMO3INS_vendors PLAMO3INS_b PLAMO3INS_list=""
  [[ $PLAMO3INS_INTERACTIVE == yes ]] || return 0
  ask DESTDIR "Install directory"
  ask USER "Service user"
  ask MODEL "Model size (0.8b, 2b, 8b, 31b)"
  ask QUANT "Quantization (Q2_K, Q3_K_M, Q4_K_M; Q4_0 for 0.8b/2b only)"
  PLAMO3INS_vendors=$(gpu_vendors | paste -sd, -)
  if [[ $PLAMO3INS_vendors == *nvidia* && -z $(nvidia_driver_major) ]]; then
    warn "an NVIDIA GPU was found but nvidia-smi does not work; install the NVIDIA driver to use CUDA"
  fi
  for PLAMO3INS_b in $PLAMO3INS_BACKENDS; do PLAMO3INS_list+=$(printf '  %-7s %s' "$PLAMO3INS_b" "${PLAMO3INS_BACKEND_DESC[$PLAMO3INS_b]}")$'\n'; done
  ask BACKEND "llama.cpp backend" "Detected GPUs: ${PLAMO3INS_vendors:-none}.  Available llama.cpp backends:"$'\n'"${PLAMO3INS_list%$'\n'}"
  ask CTX_SIZE "Context size (auto = model maximum $PLAMO3INS_NATIVE_CTX, reduced to fit the memory; or 512-$PLAMO3INS_NATIVE_CTX)"
  ask WEB_PORT "Web server port"
  ask LLAMA_PORT "llama-server port"
  ask EXPOSE_LLAMA "Expose llama-server to other hosts (API key required)? (yes/no)"
  local PLAMO3INS_e; PLAMO3INS_e=$(yesno "${PLAMO3INS_VAL[EXPOSE_LLAMA]}")
  [[ -n $PLAMO3INS_e ]] || die "answer yes or no for exposing llama-server"
  PLAMO3INS_VAL[EXPOSE_LLAMA]=$PLAMO3INS_e
}

validate() {
  local PLAMO3INS_d=${PLAMO3INS_VAL[DESTDIR]} PLAMO3INS_p
  [[ $PLAMO3INS_d == /* ]] || die "destdir must be an absolute path: $PLAMO3INS_d"
  [[ $PLAMO3INS_d =~ ^/[A-Za-z0-9._/-]+$ && $PLAMO3INS_d != *//* && $PLAMO3INS_d != */./* && $PLAMO3INS_d != */../* && $PLAMO3INS_d != */. && $PLAMO3INS_d != */.. ]] \
    || die "destdir may contain only letters, digits and . _ - / : $PLAMO3INS_d"
  PLAMO3INS_d=${PLAMO3INS_d%/}; PLAMO3INS_VAL[DESTDIR]=$PLAMO3INS_d
  case $PLAMO3INS_d in
    ""|/bin|/boot|/dev|/etc|/home|/lib|/lib64|/media|/mnt|/opt|/proc|/root|/run|/sbin|/srv|/sys|/tmp|/usr|/usr/*|/var|/var/lib|/etc/*|/proc/*|/sys/*|/dev/*|/run/*)
      die "destdir must not be a system directory: $PLAMO3INS_d" ;;
  esac
  [[ ${PLAMO3INS_VAL[USER]} =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die "invalid user name: ${PLAMO3INS_VAL[USER]}"
  [[ ${PLAMO3INS_VAL[USER]} != root ]] || die "the service user must not be root"
  PLAMO3INS_VAL[MODEL]=${PLAMO3INS_VAL[MODEL],,}
  [[ " $PLAMO3INS_MODELS " == *" ${PLAMO3INS_VAL[MODEL]} "* ]] || die "model must be one of: $PLAMO3INS_MODELS"
  [[ " $PLAMO3INS_QUANTS " == *" ${PLAMO3INS_VAL[QUANT]} "* ]] || die "quantization must be one of: $PLAMO3INS_QUANTS"
  [[ -n ${PLAMO3INS_GGUF[${PLAMO3INS_VAL[MODEL]}-${PLAMO3INS_VAL[QUANT]}]:-} ]] \
    || die "${PLAMO3INS_VAL[QUANT]} is available only for the 0.8b and 2b models"
  PLAMO3INS_VAL[BACKEND]=${PLAMO3INS_VAL[BACKEND],,}
  [[ " $PLAMO3INS_BACKENDS " == *" ${PLAMO3INS_VAL[BACKEND]} "* ]] || die "backend must be one of: $PLAMO3INS_BACKENDS"
  PLAMO3INS_VAL[CTX_SIZE]=${PLAMO3INS_VAL[CTX_SIZE],,}
  if [[ ${PLAMO3INS_VAL[CTX_SIZE]} != auto ]]; then
    [[ ${PLAMO3INS_VAL[CTX_SIZE]} =~ ^[0-9]{1,7}$ ]] || die "context size must be auto or an integer: ${PLAMO3INS_VAL[CTX_SIZE]}"
    PLAMO3INS_VAL[CTX_SIZE]=$((10#${PLAMO3INS_VAL[CTX_SIZE]}))
    ((PLAMO3INS_VAL[CTX_SIZE] >= 512 && PLAMO3INS_VAL[CTX_SIZE] <= PLAMO3INS_NATIVE_CTX)) \
      || die "context size must be auto or between 512 and $PLAMO3INS_NATIVE_CTX"
  fi
  for PLAMO3INS_p in WEB_PORT LLAMA_PORT; do
    [[ ${PLAMO3INS_VAL[$PLAMO3INS_p]} =~ ^[0-9]{1,5}$ ]] || die "invalid port number: ${PLAMO3INS_VAL[$PLAMO3INS_p]}"
    PLAMO3INS_VAL[$PLAMO3INS_p]=$((10#${PLAMO3INS_VAL[$PLAMO3INS_p]}))
    ((PLAMO3INS_VAL[$PLAMO3INS_p] >= 1 && PLAMO3INS_VAL[$PLAMO3INS_p] <= 65535)) || die "invalid port number: ${PLAMO3INS_VAL[$PLAMO3INS_p]}"
  done
  ((PLAMO3INS_VAL[WEB_PORT] != PLAMO3INS_VAL[LLAMA_PORT])) || die "the web server and llama-server ports must differ"
  validate_gpus
  validate_interfaces
}

validate_gpus() {
  local PLAMO3INS_v=${PLAMO3INS_VAL[GPUS],,} PLAMO3INS_list PLAMO3INS_p PLAMO3INS_a PLAMO3INS_out=()
  if [[ -z $PLAMO3INS_v || $PLAMO3INS_v == all ]]; then PLAMO3INS_VAL[GPUS]=all; return 0; fi
  if [[ ${PLAMO3INS_VAL[BACKEND]} == cpu ]]; then
    [[ -z ${PLAMO3INS_FROM_USER[GPUS]:-} ]] || warn "--gpus is ignored with the cpu backend"
    PLAMO3INS_VAL[GPUS]=all; return 0
  fi
  PLAMO3INS_list=$(gpu_devices | cut -f1)
  for PLAMO3INS_p in ${PLAMO3INS_v//,/ }; do
    PLAMO3INS_a=$(normalize_pci "$PLAMO3INS_p")
    [[ -n $PLAMO3INS_a ]] || die "invalid PCI address in --gpus: $PLAMO3INS_p (use e.g. 0000:03:00.0, or all)"
    if ! grep -qx "$PLAMO3INS_a" <<<"$PLAMO3INS_list"; then
      if [[ -n ${PLAMO3INS_FROM_USER[GPUS]:-} ]]; then
        die "GPU $PLAMO3INS_a is not available for the ${PLAMO3INS_VAL[BACKEND]} backend (available: $(paste -sd' ' <<<"$PLAMO3INS_list"))"
      fi
      warn "the saved GPU selection ($PLAMO3INS_v) does not match this machine; using all GPUs"
      PLAMO3INS_VAL[GPUS]=all; return 0
    fi
    [[ " ${PLAMO3INS_out[*]} " == *" $PLAMO3INS_a "* ]] || PLAMO3INS_out+=("$PLAMO3INS_a")
  done
  PLAMO3INS_VAL[GPUS]=$(IFS=,; echo "${PLAMO3INS_out[*]}")
}

# Ask which GPUs to use when the backend sees two or more.
prompt_gpus() {
  local PLAMO3INS_list PLAMO3INS_pcis=() PLAMO3INS_pci PLAMO3INS_desc PLAMO3INS_i PLAMO3INS_default="" PLAMO3INS_answer PLAMO3INS_tok PLAMO3INS_sel=() PLAMO3INS_ok
  [[ ${PLAMO3INS_VAL[BACKEND]} != cpu && -z ${PLAMO3INS_FROM_USER[GPUS]:-} && $PLAMO3INS_INTERACTIVE == yes ]] || return 0
  PLAMO3INS_list=$(gpu_devices)
  [[ -n $PLAMO3INS_list ]] || return 0
  while IFS=$'\t' read -r PLAMO3INS_pci PLAMO3INS_desc; do PLAMO3INS_pcis+=("$PLAMO3INS_pci"); done <<<"$PLAMO3INS_list"
  ((${#PLAMO3INS_pcis[@]} >= 2)) || return 0
  echo "GPUs available to the ${PLAMO3INS_VAL[BACKEND]} backend:"
  PLAMO3INS_i=0
  while IFS=$'\t' read -r PLAMO3INS_pci PLAMO3INS_desc; do
    PLAMO3INS_i=$((PLAMO3INS_i + 1))
    printf '  %d) %s  %s\n' "$PLAMO3INS_i" "$PLAMO3INS_pci" "$PLAMO3INS_desc"
  done <<<"$PLAMO3INS_list"
  if [[ ${PLAMO3INS_VAL[GPUS]} == all ]]; then
    PLAMO3INS_default=all
  else
    for PLAMO3INS_i in "${!PLAMO3INS_pcis[@]}"; do
      [[ ",${PLAMO3INS_VAL[GPUS]}," == *",${PLAMO3INS_pcis[$PLAMO3INS_i]},"* ]] && PLAMO3INS_default+="${PLAMO3INS_default:+,}$((PLAMO3INS_i + 1))"
    done
  fi
  while :; do
    read -r -p "GPUs to use (all, or numbers such as 1,2) [$PLAMO3INS_default]: " PLAMO3INS_answer || die "no input"
    PLAMO3INS_answer=${PLAMO3INS_answer:-$PLAMO3INS_default}
    if [[ ${PLAMO3INS_answer,,} == all ]]; then PLAMO3INS_VAL[GPUS]=all; return 0; fi
    PLAMO3INS_sel=(); PLAMO3INS_ok=yes
    for PLAMO3INS_tok in ${PLAMO3INS_answer//,/ }; do
      if [[ $PLAMO3INS_tok =~ ^[0-9]+$ ]] && ((PLAMO3INS_tok >= 1 && PLAMO3INS_tok <= ${#PLAMO3INS_pcis[@]})); then
        PLAMO3INS_pci=${PLAMO3INS_pcis[$((PLAMO3INS_tok - 1))]}
        [[ " ${PLAMO3INS_sel[*]} " == *" $PLAMO3INS_pci "* ]] || PLAMO3INS_sel+=("$PLAMO3INS_pci")
      else
        PLAMO3INS_ok=no
      fi
    done
    if [[ $PLAMO3INS_ok == yes && ${#PLAMO3INS_sel[@]} -gt 0 ]]; then
      PLAMO3INS_VAL[GPUS]=$(IFS=,; echo "${PLAMO3INS_sel[*]}")
      return 0
    fi
    warn "answer all, or numbers between 1 and ${#PLAMO3INS_pcis[@]} separated by commas"
  done
}

confirm_license() {
  [[ $PLAMO3INS_ACCEPT_LICENSE == yes ]] && { info "PLaMo Community License accepted (--accept-license)"; return 0; }
  [[ $PLAMO3INS_INTERACTIVE == yes ]] || die "non-interactive installation requires --accept-license (see $PLAMO3INS_LICENSE_URL)"
  cat <<EOF

PLaMo 3 Translate is distributed under the PLaMo Community License.
  $PLAMO3INS_LICENSE_URL

  - Personal and non-commercial use is free.
  - Commercial use requires registration with Preferred Networks (PFN).
  - Read the full license text at the URL above before using the model.

EOF
  local PLAMO3INS_answer
  read -r -p "Type 'yes' to accept the license: " PLAMO3INS_answer || die "no input"
  [[ $PLAMO3INS_answer == yes ]] || die "the license was not accepted"
}

show_summary() {
  local PLAMO3INS_f; PLAMO3INS_f=$(gguf_name "${PLAMO3INS_VAL[MODEL]}" "${PLAMO3INS_VAL[QUANT]}")
  cat <<EOF

Installation settings:
  Install directory : ${PLAMO3INS_VAL[DESTDIR]}
  Service user      : ${PLAMO3INS_VAL[USER]}
  Model             : $PLAMO3INS_f
  llama.cpp backend : ${PLAMO3INS_VAL[BACKEND]} (${PLAMO3INS_BACKEND_DESC[${PLAMO3INS_VAL[BACKEND]}]})
  GPUs              : $(gpu_label)
  Context size      : $(ctx_label)
  Listen on         : $(interfaces_label)
  Open ports in ufw : $(ufw_label)
  Web server        : port ${PLAMO3INS_VAL[WEB_PORT]}
  llama-server      : port ${PLAMO3INS_VAL[LLAMA_PORT]}, $([[ ${PLAMO3INS_VAL[EXPOSE_LLAMA]} == yes ]] && echo "exposed like the web server (API key required)" || echo "127.0.0.1 only")

EOF
  if [[ $PLAMO3INS_INTERACTIVE == yes && $PLAMO3INS_ASSUME_YES != yes ]]; then
    confirm "Proceed with the installation?" || die "aborted"
  fi
}

# -------------------------------------------------------------- preflight

check_platform() {
  [[ $EUID -eq 0 ]] || die "run as root (e.g. sudo bash $0)"
  [[ $(uname -m) == x86_64 ]] || die "only x86_64 is supported (found $(uname -m))"
  [[ -r /etc/os-release ]] || die "cannot read /etc/os-release"
  local PLAMO3INS_id PLAMO3INS_version
  # Parse instead of sourcing, so that os-release cannot clash with our variables.
  PLAMO3INS_id=$(sed -n 's/^ID=//p' /etc/os-release | tr -d '"')
  PLAMO3INS_version=$(sed -n 's/^VERSION_ID=//p' /etc/os-release | tr -d '"')
  [[ $PLAMO3INS_id == ubuntu && $PLAMO3INS_version == 26.04 ]] || die "only Ubuntu 26.04 is supported (found ${PLAMO3INS_id:-?} ${PLAMO3INS_version:-?})"
  command -v systemctl >/dev/null || die "systemd is required"
}

# Is TCP port $1 used by a process other than the existing installation?
port_in_use_by_others() {
  local PLAMO3INS_port=$1 PLAMO3INS_listeners
  PLAMO3INS_listeners=$(ss -Hltnp "sport = :$PLAMO3INS_port" 2>/dev/null) || PLAMO3INS_listeners=""
  [[ -n $PLAMO3INS_listeners ]] || return 1
  # Ports of the existing installation are reused.
  if [[ $PLAMO3INS_port == "${PLAMO3INS_SAVED[WEB_PORT]:-}" ]] && ! grep -qv 'nginx' <<<"$PLAMO3INS_listeners"; then return 1; fi
  if [[ $PLAMO3INS_port == "${PLAMO3INS_SAVED[LLAMA_PORT]:-}" ]] && ! grep -qv 'llama-server' <<<"$PLAMO3INS_listeners"; then return 1; fi
  return 0
}

existing_dir() {  # nearest existing ancestor of $1
  local PLAMO3INS_d=$1
  while [[ ! -d $PLAMO3INS_d ]]; do PLAMO3INS_d=$(dirname "$PLAMO3INS_d"); done
  echo "$PLAMO3INS_d"
}

preflight() {
  local PLAMO3INS_p PLAMO3INS_gguf PLAMO3INS_size PLAMO3INS_need PLAMO3INS_avail PLAMO3INS_mem_kb PLAMO3INS_mem PLAMO3INS_need_mem PLAMO3INS_min_mem PLAMO3INS_ctx PLAMO3INS_per_token PLAMO3INS_major PLAMO3INS_file PLAMO3INS_fsize
  info "Checking prerequisites"
  for PLAMO3INS_p in WEB_PORT LLAMA_PORT; do
    if port_in_use_by_others "${PLAMO3INS_VAL[$PLAMO3INS_p]}"; then
      die "TCP port ${PLAMO3INS_VAL[$PLAMO3INS_p]} is already in use: $(ss -Hltnp "sport = :${PLAMO3INS_VAL[$PLAMO3INS_p]}" | head -n1)"
    fi
  done

  # Existing destdir must be empty or a previous installation (uninstall removes it).
  if [[ -d ${PLAMO3INS_VAL[DESTDIR]} && ! -e ${PLAMO3INS_VAL[DESTDIR]}/$PLAMO3INS_MARKER ]] && [[ -n $(ls -A "${PLAMO3INS_VAL[DESTDIR]}") ]]; then
    die "${PLAMO3INS_VAL[DESTDIR]} exists and is not empty; choose another directory"
  fi

  # Disk space: GGUF (unless already present) + llama.cpp archives and extracted files.
  PLAMO3INS_gguf=$(gguf_name "${PLAMO3INS_VAL[MODEL]}" "${PLAMO3INS_VAL[QUANT]}")
  read -r _ PLAMO3INS_size <<<"${PLAMO3INS_GGUF[${PLAMO3INS_VAL[MODEL]}-${PLAMO3INS_VAL[QUANT]}]}"
  PLAMO3INS_need=0
  [[ -f ${PLAMO3INS_VAL[DESTDIR]}/models/$PLAMO3INS_gguf ]] || PLAMO3INS_need=$PLAMO3INS_size
  while read -r PLAMO3INS_file _ PLAMO3INS_fsize; do
    [[ -n $PLAMO3INS_file ]] && PLAMO3INS_need=$((PLAMO3INS_need + PLAMO3INS_fsize * 4))
  done <<<"${PLAMO3INS_LLAMA_ASSETS[${PLAMO3INS_VAL[BACKEND]}]}"
  PLAMO3INS_need=$((PLAMO3INS_need + 512 * 1024 * 1024))
  PLAMO3INS_avail=$(($(df --output=avail -k "$(existing_dir "${PLAMO3INS_VAL[DESTDIR]}")" | tail -n1) * 1024))
  if ((PLAMO3INS_avail < PLAMO3INS_need)); then
    warn_continue "not enough free disk space in $(existing_dir "${PLAMO3INS_VAL[DESTDIR]}"): $(human "$PLAMO3INS_avail") available, about $(human "$PLAMO3INS_need") needed"
  fi

  # Memory: model + KV cache + compute buffer (about 1 KiB per token) + 1 GiB margin.
  # With --ctx-size auto, llama.cpp reduces the context (down to 4096) to fit the memory,
  # so only the minimum is required; otherwise the given context size is.
  PLAMO3INS_mem_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
  PLAMO3INS_mem=$((PLAMO3INS_mem_kb * 1024))
  PLAMO3INS_ctx=${PLAMO3INS_VAL[CTX_SIZE]}
  [[ $PLAMO3INS_ctx == auto ]] && PLAMO3INS_ctx=$PLAMO3INS_NATIVE_CTX
  PLAMO3INS_per_token=$((PLAMO3INS_KV_BYTES[${PLAMO3INS_VAL[MODEL]}] + 1024))
  PLAMO3INS_need_mem=$((PLAMO3INS_size + PLAMO3INS_ctx * PLAMO3INS_per_token + 1024 * 1024 * 1024))
  PLAMO3INS_min_mem=$((PLAMO3INS_size + 4096 * PLAMO3INS_per_token + 1024 * 1024 * 1024))
  case ${PLAMO3INS_VAL[BACKEND]} in
    cpu)
      if [[ ${PLAMO3INS_VAL[CTX_SIZE]} != auto ]] && ((PLAMO3INS_mem < PLAMO3INS_need_mem)); then
        warn_continue "$PLAMO3INS_gguf with context size $PLAMO3INS_ctx may not fit in memory: $(human "$PLAMO3INS_mem") installed, about $(human "$PLAMO3INS_need_mem") needed"
      elif ((PLAMO3INS_mem < PLAMO3INS_min_mem)); then
        warn_continue "$PLAMO3INS_gguf may not fit in memory: $(human "$PLAMO3INS_mem") installed, about $(human "$PLAMO3INS_min_mem") needed"
      elif ((PLAMO3INS_mem < PLAMO3INS_need_mem)); then
        info "The full context ($PLAMO3INS_NATIVE_CTX) needs about $(human "$PLAMO3INS_need_mem"); llama.cpp will reduce it to fit $(human "$PLAMO3INS_mem")"
      fi ;;
    cuda12|cuda13)
      PLAMO3INS_major=$(nvidia_driver_major)
      [[ -n $PLAMO3INS_major ]] || die "nvidia-smi does not work; install the NVIDIA driver first (e.g. sudo ubuntu-drivers install), reboot and re-run"
      if [[ ${PLAMO3INS_VAL[BACKEND]} == cuda13 && $PLAMO3INS_major -lt 580 ]]; then
        warn_continue "CUDA 13.5 needs NVIDIA driver 580 or later (found $PLAMO3INS_major); consider --backend cuda12"
      elif [[ ${PLAMO3INS_VAL[BACKEND]} == cuda12 && $PLAMO3INS_major -lt 570 ]]; then
        warn_continue "CUDA 12.8 needs NVIDIA driver 570 or later (found $PLAMO3INS_major)"
      fi
      local PLAMO3INS_vram
      PLAMO3INS_vram=0
      local PLAMO3INS_bus PLAMO3INS_mib
      while IFS=', ' read -r PLAMO3INS_bus PLAMO3INS_mib; do
        [[ $PLAMO3INS_mib =~ ^[0-9]+$ ]] || continue
        [[ ${PLAMO3INS_VAL[GPUS]} == all || ",${PLAMO3INS_VAL[GPUS]}," == *",$(normalize_pci "$PLAMO3INS_bus"),"* ]] || continue
        PLAMO3INS_vram=$((PLAMO3INS_vram + PLAMO3INS_mib * 1024 * 1024))
      done <<<"$(nvidia-smi --query-gpu=pci.bus_id,memory.total --format=csv,noheader,nounits 2>/dev/null || true)"
      ((PLAMO3INS_vram > 0)) || PLAMO3INS_vram=""
      if [[ -n $PLAMO3INS_vram ]] && ((PLAMO3INS_vram < PLAMO3INS_need_mem)); then
        if [[ ${PLAMO3INS_VAL[CTX_SIZE]} == auto ]] && ((PLAMO3INS_vram >= PLAMO3INS_min_mem)); then
          info "The full context ($PLAMO3INS_NATIVE_CTX) needs about $(human "$PLAMO3INS_need_mem"); llama.cpp will reduce it to fit $(human "$PLAMO3INS_vram") of GPU memory"
        else
          warn "$PLAMO3INS_gguf may not fit in GPU memory ($(human "$PLAMO3INS_vram"), about $(human "$PLAMO3INS_need_mem") needed); llama.cpp will keep some layers on the CPU"
        fi
      fi ;;
    vulkan|rocm)
      [[ -e /dev/dri ]] || warn_continue "no GPU device (/dev/dri) found for the ${PLAMO3INS_VAL[BACKEND]} backend"
      [[ ${PLAMO3INS_VAL[BACKEND]} != rocm || -e /dev/kfd ]] || warn_continue "/dev/kfd not found; the amdgpu kernel driver is needed for ROCm" ;;
  esac
}

# ---------------------------------------------------------------- install

install_packages() {
  local PLAMO3INS_pkgs="$PLAMO3INS_BASE_PACKAGES ${PLAMO3INS_BACKEND_PACKAGES[${PLAMO3INS_VAL[BACKEND]}]}" PLAMO3INS_missing=() PLAMO3INS_p
  for PLAMO3INS_p in $PLAMO3INS_pkgs; do
    [[ $(dpkg-query -W -f='${Status}' "$PLAMO3INS_p" 2>/dev/null || true) == "install ok installed" ]] || PLAMO3INS_missing+=("$PLAMO3INS_p")
  done
  if ((${#PLAMO3INS_missing[@]} == 0)); then
    info "Required packages are already installed"
    return 0
  fi
  info "Installing packages: ${PLAMO3INS_missing[*]}"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends "${PLAMO3INS_missing[@]}"
}

ensure_user() {
  local PLAMO3INS_u=${PLAMO3INS_VAL[USER]}
  if id -u "$PLAMO3INS_u" >/dev/null 2>&1; then
    info "Using existing user $PLAMO3INS_u"
  else
    info "Creating system user $PLAMO3INS_u"
    useradd --system --user-group --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin "$PLAMO3INS_u"
  fi
}

# download_verified URL DEST SHA256 SIZE: download with resume and verify; reuse a verified file.
download_verified() {
  local PLAMO3INS_url=$1 PLAMO3INS_dest=$2 PLAMO3INS_sha=$3 PLAMO3INS_size=$4 PLAMO3INS_part="$2.part"
  if [[ -f $PLAMO3INS_dest ]]; then
    info "Verifying existing $(basename "$PLAMO3INS_dest")"
    if [[ $(stat -c %s "$PLAMO3INS_dest") == "$PLAMO3INS_size" && $(sha256_of "$PLAMO3INS_dest") == "$PLAMO3INS_sha" ]]; then
      info "Reusing $(basename "$PLAMO3INS_dest")"
      return 0
    fi
    warn "$(basename "$PLAMO3INS_dest") does not match the expected checksum; downloading it again"
    rm -f "$PLAMO3INS_dest"
  fi
  if [[ -f $PLAMO3INS_part ]] && (($(stat -c %s "$PLAMO3INS_part") > PLAMO3INS_size)); then rm -f "$PLAMO3INS_part"; fi
  if [[ ! -f $PLAMO3INS_part ]] || (($(stat -c %s "$PLAMO3INS_part") < PLAMO3INS_size)); then
    info "Downloading $(basename "$PLAMO3INS_dest") ($(human "$PLAMO3INS_size"))"
    curl --fail --location --retry 5 --retry-delay 5 --retry-all-errors \
      --continue-at - --output "$PLAMO3INS_part" "$PLAMO3INS_url" \
      || die "download failed: $PLAMO3INS_url (re-run the installer to resume)"
  fi
  info "Verifying $(basename "$PLAMO3INS_dest")"
  if [[ $(sha256_of "$PLAMO3INS_part") != "$PLAMO3INS_sha" ]]; then
    rm -f "$PLAMO3INS_part"
    die "checksum mismatch for $(basename "$PLAMO3INS_dest"); the file was removed, re-run the installer to retry"
  fi
  mv -f "$PLAMO3INS_part" "$PLAMO3INS_dest"
}

prepare_destdir() {
  install -d -m 0755 "${PLAMO3INS_VAL[DESTDIR]}" "${PLAMO3INS_VAL[DESTDIR]}/llama.cpp" "${PLAMO3INS_VAL[DESTDIR]}/models" "${PLAMO3INS_VAL[DESTDIR]}/app"
  touch "${PLAMO3INS_VAL[DESTDIR]}/$PLAMO3INS_MARKER"
}

install_llama() {
  local PLAMO3INS_backend=${PLAMO3INS_VAL[BACKEND]} PLAMO3INS_top="${PLAMO3INS_VAL[DESTDIR]}/llama.cpp"
  local PLAMO3INS_dir="$PLAMO3INS_top/$PLAMO3INS_LLAMA_TAG-$PLAMO3INS_backend" PLAMO3INS_dl="$PLAMO3INS_top/.download" PLAMO3INS_stamp PLAMO3INS_file PLAMO3INS_sha PLAMO3INS_size
  PLAMO3INS_stamp=$(printf '%s\n' "${PLAMO3INS_LLAMA_ASSETS[$PLAMO3INS_backend]}")
  if [[ -x $PLAMO3INS_dir/llama-server && -f $PLAMO3INS_dir/.installed && $(<"$PLAMO3INS_dir/.installed") == "$PLAMO3INS_stamp" ]]; then
    info "llama.cpp $PLAMO3INS_LLAMA_TAG ($PLAMO3INS_backend) is already installed"
  else
    install -d -m 0755 "$PLAMO3INS_dl"
    rm -rf "$PLAMO3INS_dir.tmp"
    install -d -m 0755 "$PLAMO3INS_dir.tmp"
    while read -r PLAMO3INS_file PLAMO3INS_sha PLAMO3INS_size; do
      [[ -n $PLAMO3INS_file ]] || continue
      download_verified "$PLAMO3INS_LLAMA_BASE_URL/$PLAMO3INS_file" "$PLAMO3INS_dl/$PLAMO3INS_file" "$PLAMO3INS_sha" "$PLAMO3INS_size"
      info "Extracting $PLAMO3INS_file"
      tar -xzf "$PLAMO3INS_dl/$PLAMO3INS_file" -C "$PLAMO3INS_dir.tmp" --strip-components=1 --no-same-owner
    done <<<"${PLAMO3INS_LLAMA_ASSETS[$PLAMO3INS_backend]}"
    [[ -x $PLAMO3INS_dir.tmp/llama-server ]] || die "llama-server not found in the llama.cpp archive"
    printf '%s\n' "$PLAMO3INS_stamp" > "$PLAMO3INS_dir.tmp/.installed"
    rm -rf "$PLAMO3INS_dir"
    mv "$PLAMO3INS_dir.tmp" "$PLAMO3INS_dir"
    rm -rf "$PLAMO3INS_dl"
  fi
  ln -sfn "$PLAMO3INS_LLAMA_TAG-$PLAMO3INS_backend" "$PLAMO3INS_top/current"
  # Remove builds for other backends.
  local PLAMO3INS_other
  for PLAMO3INS_other in $PLAMO3INS_BACKENDS; do
    [[ $PLAMO3INS_other == "$PLAMO3INS_backend" ]] || rm -rf "${PLAMO3INS_top:?}/$PLAMO3INS_LLAMA_TAG-$PLAMO3INS_other" "${PLAMO3INS_top:?}/$PLAMO3INS_LLAMA_TAG-$PLAMO3INS_other.tmp"
  done
  # Capture first: with pipefail, "cmd | grep -q" can fail when grep exits early (SIGPIPE).
  local PLAMO3INS_ldd
  PLAMO3INS_ldd=$(ldd "$PLAMO3INS_top/current/llama-server" 2>&1 || true)
  if [[ $PLAMO3INS_ldd == *"not found"* ]]; then
    warn "llama-server has missing libraries:"
    grep 'not found' <<<"$PLAMO3INS_ldd" >&2 || true
  fi
}

install_model() {
  local PLAMO3INS_m=${PLAMO3INS_VAL[MODEL]} PLAMO3INS_q=${PLAMO3INS_VAL[QUANT]} PLAMO3INS_f PLAMO3INS_sha PLAMO3INS_size
  PLAMO3INS_f=$(gguf_name "$PLAMO3INS_m" "$PLAMO3INS_q")
  read -r PLAMO3INS_sha PLAMO3INS_size <<<"${PLAMO3INS_GGUF[$PLAMO3INS_m-$PLAMO3INS_q]}"
  download_verified "https://huggingface.co/pfnet/plamo-3-translate-$PLAMO3INS_m-GGUF/resolve/${PLAMO3INS_MODEL_REVISION[$PLAMO3INS_m]}/$PLAMO3INS_f" \
    "${PLAMO3INS_VAL[DESTDIR]}/models/$PLAMO3INS_f" "$PLAMO3INS_sha" "$PLAMO3INS_size"
  chmod 0644 "${PLAMO3INS_VAL[DESTDIR]}/models/$PLAMO3INS_f"
}

install_app() {
  [[ -f $PLAMO3INS_SCRIPT_DIR/$PLAMO3INS_SERVER_PY ]] || die "$PLAMO3INS_SERVER_PY not found next to the installer ($PLAMO3INS_SCRIPT_DIR)"
  install -m 0644 "$PLAMO3INS_SCRIPT_DIR/$PLAMO3INS_SERVER_PY" "${PLAMO3INS_VAL[DESTDIR]}/app/$PLAMO3INS_SERVER_PY"
}

# Keep the API key across re-runs so that clients keep working.
write_env_file() {
  local PLAMO3INS_key=""
  install -d -m 0755 "$PLAMO3INS_CONF_DIR"
  if [[ ${PLAMO3INS_VAL[EXPOSE_LLAMA]} == yes ]]; then
    if [[ -f $PLAMO3INS_ENV_FILE ]]; then
      PLAMO3INS_key=$(sed -n 's/^LLAMA_API_KEY=//p;T;q' "$PLAMO3INS_ENV_FILE")
    fi
    [[ $PLAMO3INS_key =~ ^[0-9a-f]{64}$ ]] || PLAMO3INS_key=$(od -An -tx1 -N32 /dev/urandom | tr -d ' \n')
    ( umask 027
      printf 'LLAMA_API_KEY=%s\nPLAMO3_LLAMA_API_KEY=%s\n' "$PLAMO3INS_key" "$PLAMO3INS_key" > "$PLAMO3INS_ENV_FILE.tmp" )
    chown "root:${PLAMO3INS_VAL[USER]}" "$PLAMO3INS_ENV_FILE.tmp"
    chmod 0640 "$PLAMO3INS_ENV_FILE.tmp"
    mv -f "$PLAMO3INS_ENV_FILE.tmp" "$PLAMO3INS_ENV_FILE"
  else
    rm -f "$PLAMO3INS_ENV_FILE"
  fi
}

# Common systemd sandboxing.
hardening() {
  cat <<'EOF'
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=read-only
PrivateTmp=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
ProtectClock=yes
ProtectHostname=yes
RestrictSUIDSGID=yes
RestrictRealtime=yes
RestrictNamespaces=yes
LockPersonality=yes
SystemCallArchitectures=native
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK
EOF
}

write_units() {
  local PLAMO3INS_u=${PLAMO3INS_VAL[USER]} PLAMO3INS_d=${PLAMO3INS_VAL[DESTDIR]} PLAMO3INS_host=127.0.0.1 PLAMO3INS_groups="" PLAMO3INS_g
  local PLAMO3INS_gguf; PLAMO3INS_gguf=$(gguf_name "${PLAMO3INS_VAL[MODEL]}" "${PLAMO3INS_VAL[QUANT]}")
  if [[ ${PLAMO3INS_VAL[EXPOSE_LLAMA]} == yes ]]; then
    if [[ ${PLAMO3INS_VAL[INTERFACES]} == all ]]; then
      PLAMO3INS_host=0.0.0.0
    else
      PLAMO3INS_host="127.0.0.1$(listen_addresses | sed 's/^/,/' | tr -d '\n')"
    fi
  fi
  # Without -c, llama-server uses the model maximum and reduces it to fit the memory (--fit).
  local PLAMO3INS_ctx_opt=""
  [[ ${PLAMO3INS_VAL[CTX_SIZE]} == auto ]] || PLAMO3INS_ctx_opt=" -c ${PLAMO3INS_VAL[CTX_SIZE]}"
  if [[ ${PLAMO3INS_VAL[BACKEND]} != cpu ]]; then
    for PLAMO3INS_g in video render; do getent group "$PLAMO3INS_g" >/dev/null && PLAMO3INS_groups+=" $PLAMO3INS_g"; done
  fi
  local PLAMO3INS_gpu_env
  PLAMO3INS_gpu_env=$(gpu_environment)
  info "Writing systemd units and uWSGI configuration"

  cat > "$PLAMO3INS_UNIT_DIR/$PLAMO3INS_LLAMA_UNIT" <<EOF
# Generated by install-plamo-3-translate.sh; changes are overwritten on re-run.
[Unit]
Description=PLaMo 3 Translate llama-server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$PLAMO3INS_u
Group=$PLAMO3INS_u
${PLAMO3INS_groups:+SupplementaryGroups=${PLAMO3INS_groups# }
}EnvironmentFile=-$PLAMO3INS_ENV_FILE
Environment=XDG_CACHE_HOME=/var/cache/$PLAMO3INS_APP_NAME
${PLAMO3INS_gpu_env:+$PLAMO3INS_gpu_env
}CacheDirectory=$PLAMO3INS_APP_NAME
RuntimeDirectory=$PLAMO3INS_APP_NAME-llama
RuntimeDirectoryMode=0750
ExecStartPre=/usr/bin/rm -f $PLAMO3INS_LLAMA_SOCKET
ExecStart=$PLAMO3INS_d/llama.cpp/current/llama-server --model $PLAMO3INS_d/models/$PLAMO3INS_gguf --host $PLAMO3INS_host,$PLAMO3INS_LLAMA_SOCKET --port ${PLAMO3INS_VAL[LLAMA_PORT]}${PLAMO3INS_ctx_opt} --jinja --no-prefill-assistant --alias $PLAMO3INS_MODEL_ALIAS
Restart=on-failure
RestartSec=5
TimeoutStartSec=infinity
$(hardening)

[Install]
WantedBy=multi-user.target
EOF

  local PLAMO3INS_timeout=3600
  # die-on-term: SIGTERM (systemd's default KillSignal) stops uWSGI.  Do not set
  # KillSignal=SIGQUIT: with die-on-term, SIGQUIT reloads uWSGI and the stop times out.
  cat > "$PLAMO3INS_UWSGI_INI" <<EOF
# Generated by install-plamo-3-translate.sh; changes are overwritten on re-run.
[uwsgi]
strict = true
plugins = python3
master = true
processes = 2
threads = 4
need-app = true
wsgi-file = $PLAMO3INS_d/app/$PLAMO3INS_SERVER_PY
socket = $PLAMO3INS_SOCKET
chown-socket = $PLAMO3INS_u:www-data
chmod-socket = 660
vacuum = true
die-on-term = true
harakiri = $((PLAMO3INS_timeout + 30))
buffer-size = 32768
post-buffering = 65536
disable-logging = true
log-4xx = true
log-5xx = true
EOF

  cat > "$PLAMO3INS_UNIT_DIR/$PLAMO3INS_UWSGI_UNIT" <<EOF
# Generated by install-plamo-3-translate.sh; changes are overwritten on re-run.
[Unit]
Description=PLaMo 3 Translate web application (uWSGI)
After=network.target $PLAMO3INS_LLAMA_UNIT
Wants=$PLAMO3INS_LLAMA_UNIT

[Service]
Type=notify
NotifyAccess=all
User=$PLAMO3INS_u
Group=$PLAMO3INS_u
SupplementaryGroups=www-data
RuntimeDirectory=$PLAMO3INS_APP_NAME
RuntimeDirectoryMode=0755
EnvironmentFile=-$PLAMO3INS_ENV_FILE
Environment=PLAMO3_LLAMA_URL=unix:$PLAMO3INS_LLAMA_SOCKET
Environment=PLAMO3_LLAMA_TIMEOUT=$PLAMO3INS_timeout
ExecStart=/usr/bin/uwsgi --ini $PLAMO3INS_UWSGI_INI
Restart=on-failure
RestartSec=5
PrivateDevices=yes
MemoryDenyWriteExecute=yes
$(hardening)

[Install]
WantedBy=multi-user.target
EOF
  chmod 0644 "$PLAMO3INS_UNIT_DIR/$PLAMO3INS_LLAMA_UNIT" "$PLAMO3INS_UNIT_DIR/$PLAMO3INS_UWSGI_UNIT" "$PLAMO3INS_UWSGI_INI"
}

write_nginx() {
  local PLAMO3INS_listen="" PLAMO3INS_a PLAMO3INS_port=${PLAMO3INS_VAL[WEB_PORT]}
  if [[ ${PLAMO3INS_VAL[INTERFACES]} == all ]]; then
    PLAMO3INS_listen="    listen $PLAMO3INS_port;"$'\n'"    listen [::]:$PLAMO3INS_port;"
  else
    PLAMO3INS_listen="    listen 127.0.0.1:$PLAMO3INS_port;"
    [[ -e /proc/net/if_inet6 ]] && PLAMO3INS_listen+=$'\n'"    listen [::1]:$PLAMO3INS_port;"
    while read -r PLAMO3INS_a; do
      [[ -n $PLAMO3INS_a ]] || continue
      if [[ $PLAMO3INS_a == *:* ]]; then PLAMO3INS_listen+=$'\n'"    listen [$PLAMO3INS_a]:$PLAMO3INS_port;"
      else PLAMO3INS_listen+=$'\n'"    listen $PLAMO3INS_a:$PLAMO3INS_port;"; fi
    done <<<"$(listen_addresses)"
  fi
  info "Writing nginx site configuration"
  cat > "$PLAMO3INS_NGINX_SITE" <<EOF
# Generated by install-plamo-3-translate.sh; changes are overwritten on re-run.
server {
$PLAMO3INS_listen
    server_name _;

    client_max_body_size 8m;

    location / {
        include uwsgi_params;
        uwsgi_pass unix:$PLAMO3INS_SOCKET;
        uwsgi_read_timeout 3660s;
        uwsgi_send_timeout 3660s;
    }
}
EOF
  ln -sfn "$PLAMO3INS_NGINX_SITE" "$PLAMO3INS_NGINX_LINK"
  nginx -t 2>&1 || die "nginx configuration test failed"
}

start_services() {
  info "Starting services"
  systemctl daemon-reload
  systemctl enable "$PLAMO3INS_LLAMA_UNIT" "$PLAMO3INS_UWSGI_UNIT" nginx.service
  systemctl restart "$PLAMO3INS_LLAMA_UNIT"
  systemctl restart "$PLAMO3INS_UWSGI_UNIT" || {
    journalctl -u "$PLAMO3INS_UWSGI_UNIT" -n 30 --no-pager >&2 || true
    die "failed to start $PLAMO3INS_UWSGI_UNIT"
  }
  if systemctl is-active --quiet nginx.service; then
    systemctl reload nginx.service
  else
    systemctl start nginx.service
  fi
}

ufw_active() {
  local PLAMO3INS_status
  command -v ufw >/dev/null 2>&1 || return 1
  PLAMO3INS_status=$(ufw status 2>/dev/null) || return 1
  grep -q '^Status: active$' <<<"$PLAMO3INS_status"
}

# Print the ufw rules needed (web server; llama-server too if exposed): PORT, or
# PORT@INTERFACE when the interfaces are restricted.
ufw_wanted_rules() {
  local PLAMO3INS_p PLAMO3INS_ifc PLAMO3INS_ports=${PLAMO3INS_VAL[WEB_PORT]}
  [[ ${PLAMO3INS_VAL[EXPOSE_LLAMA]} == yes ]] && PLAMO3INS_ports+=" ${PLAMO3INS_VAL[LLAMA_PORT]}"
  for PLAMO3INS_p in $PLAMO3INS_ports; do
    if [[ ${PLAMO3INS_VAL[INTERFACES]} == all ]]; then
      echo "$PLAMO3INS_p"
    else
      for PLAMO3INS_ifc in ${PLAMO3INS_VAL[INTERFACES]//,/ }; do echo "$PLAMO3INS_p@$PLAMO3INS_ifc"; done
    fi
  done
}

# Print the wanted rules that ufw does not allow yet (a rule for all interfaces covers
# every interface).
ufw_closed_ports() {
  local PLAMO3INS_status PLAMO3INS_r PLAMO3INS_p PLAMO3INS_ifc
  PLAMO3INS_status=$(ufw status 2>/dev/null || true)
  while read -r PLAMO3INS_r; do
    [[ -n $PLAMO3INS_r ]] || continue
    PLAMO3INS_p=${PLAMO3INS_r%%@*}
    grep -Eq "^$PLAMO3INS_p(/tcp)?[[:space:]]+ALLOW" <<<"$PLAMO3INS_status" && continue
    if [[ $PLAMO3INS_r == *@* ]]; then
      PLAMO3INS_ifc=${PLAMO3INS_r#*@}
      grep -Eq "^$PLAMO3INS_p(/tcp)? on ${PLAMO3INS_ifc//./\\.}[[:space:]]+ALLOW" <<<"$PLAMO3INS_status" && continue
    fi
    echo "$PLAMO3INS_r"
  done <<<"$(ufw_wanted_rules)"
}

# Human-readable form of rules: "18080/tcp, 28080/tcp on bond0".
ufw_rules_text() {
  local PLAMO3INS_r PLAMO3INS_text=""
  for PLAMO3INS_r in "$@"; do
    if [[ $PLAMO3INS_r == *@* ]]; then PLAMO3INS_text+="${PLAMO3INS_text:+, }${PLAMO3INS_r%%@*}/tcp on ${PLAMO3INS_r#*@}"
    else PLAMO3INS_text+="${PLAMO3INS_text:+, }$PLAMO3INS_r/tcp"; fi
  done
  echo "$PLAMO3INS_text"
}

# ufw arguments for a rule (used with "ufw" and "ufw delete").
ufw_rule_args() {
  if [[ $1 == *@* ]]; then
    echo "allow in on ${1#*@} to any port ${1%%@*} proto tcp"
  else
    echo "allow ${1}/tcp"
  fi
}

# Ask about ufw together with the other questions.  configure_ufw asks again only if
# this was not answered (e.g. ufw was enabled after the questions).
prompt_ufw() {
  local PLAMO3INS_ports
  [[ -z $PLAMO3INS_OPEN_PORTS && $PLAMO3INS_INTERACTIVE == yes && $PLAMO3INS_ASSUME_YES != yes ]] || return 0
  ufw_active || return 0
  PLAMO3INS_ports=$(ufw_closed_ports | paste -sd' ' -)
  [[ -n $PLAMO3INS_ports ]] || return 0
  # shellcheck disable=SC2086
  if confirm "ufw is active. Allow incoming $(ufw_rules_text $PLAMO3INS_ports)?"; then
    PLAMO3INS_OPEN_PORTS=yes
  else
    PLAMO3INS_OPEN_PORTS=no
  fi
}

ufw_label() {
  local PLAMO3INS_ports
  if ! ufw_active; then echo "no (ufw is not active)"; return 0; fi
  PLAMO3INS_ports=$(ufw_closed_ports | paste -sd' ' -)
  # shellcheck disable=SC2086
  PLAMO3INS_ports=$(ufw_rules_text $PLAMO3INS_ports)
  if [[ -z $PLAMO3INS_ports ]]; then echo "no (already allowed)"
  elif [[ $PLAMO3INS_OPEN_PORTS == yes || ( -z $PLAMO3INS_OPEN_PORTS && $PLAMO3INS_ASSUME_YES == yes ) ]]; then echo "yes ($PLAMO3INS_ports)"
  elif [[ $PLAMO3INS_OPEN_PORTS == no ]]; then echo "no ($PLAMO3INS_ports stay closed)"
  else echo "ask later ($PLAMO3INS_ports)"
  fi
}

configure_ufw() {
  local PLAMO3INS_ports PLAMO3INS_p PLAMO3INS_wanted PLAMO3INS_kept=""
  PLAMO3INS_UFW_RULES=${PLAMO3INS_SAVED[UFW_RULES]:-${PLAMO3INS_SAVED[UFW_PORTS]:-}}
  ufw_active || return 0
  # Remove rules this installer added earlier that are no longer wanted (other ports,
  # or a rule for all interfaces after restricting the interfaces).
  PLAMO3INS_wanted=" $(ufw_wanted_rules | paste -sd' ' -) "
  for PLAMO3INS_p in $PLAMO3INS_UFW_RULES; do
    if [[ $PLAMO3INS_wanted == *" $PLAMO3INS_p "* ]]; then
      PLAMO3INS_kept+="${PLAMO3INS_kept:+ }$PLAMO3INS_p"
    else
      # shellcheck disable=SC2046
      ufw delete $(ufw_rule_args "$PLAMO3INS_p") >/dev/null 2>&1 || true
      info "Removed the ufw rule for $(ufw_rules_text "$PLAMO3INS_p") added by a previous installation"
    fi
  done
  PLAMO3INS_UFW_RULES=$PLAMO3INS_kept
  PLAMO3INS_ports=$(ufw_closed_ports | paste -sd' ' -)
  if [[ -z $PLAMO3INS_ports ]]; then
    info "ufw already allows the required port(s)"
    return 0
  fi
  # shellcheck disable=SC2086
  if [[ $PLAMO3INS_OPEN_PORTS == yes ]] ||
     { [[ -z $PLAMO3INS_OPEN_PORTS ]] && confirm "ufw is active. Allow incoming $(ufw_rules_text $PLAMO3INS_ports)?"; }; then
    for PLAMO3INS_p in $PLAMO3INS_ports; do
      # shellcheck disable=SC2046
      ufw $(ufw_rule_args "$PLAMO3INS_p") comment "$PLAMO3INS_APP_NAME" >/dev/null
      [[ " $PLAMO3INS_UFW_RULES " == *" $PLAMO3INS_p "* ]] || PLAMO3INS_UFW_RULES=${PLAMO3INS_UFW_RULES:+$PLAMO3INS_UFW_RULES }$PLAMO3INS_p
    done
    # shellcheck disable=SC2086
    info "Allowed $(ufw_rules_text $PLAMO3INS_ports) in ufw"
  else
    # shellcheck disable=SC2086
    warn "ufw is active and $(ufw_rules_text $PLAMO3INS_ports) were not allowed; other hosts cannot connect"
  fi
}

save_config() {
  local PLAMO3INS_key
  install -d -m 0755 "$PLAMO3INS_CONF_DIR"
  {
    echo "# Written by install-plamo-3-translate.sh; used as defaults on re-run and by --uninstall."
    for PLAMO3INS_key in $PLAMO3INS_KEYS; do printf "%s='%s'\n" "$PLAMO3INS_key" "${PLAMO3INS_VAL[$PLAMO3INS_key]}"; done
    printf "UFW_RULES='%s'\n" "$PLAMO3INS_UFW_RULES"
  } > "$PLAMO3INS_CONF_FILE.tmp"
  chmod 0644 "$PLAMO3INS_CONF_FILE.tmp"
  mv -f "$PLAMO3INS_CONF_FILE.tmp" "$PLAMO3INS_CONF_FILE"
}

wait_health() {
  local PLAMO3INS_url="http://127.0.0.1:${PLAMO3INS_VAL[LLAMA_PORT]}/health" PLAMO3INS_limit=${PLAMO3INS_HEALTH_TIMEOUT[${PLAMO3INS_VAL[MODEL]}]} PLAMO3INS_start PLAMO3INS_code
  info "Waiting for llama-server to load the model (up to ${PLAMO3INS_limit}s)"
  PLAMO3INS_start=$SECONDS
  while :; do
    PLAMO3INS_code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$PLAMO3INS_url" || true)
    [[ $PLAMO3INS_code == 200 ]] && break
    # Restart=on-failure would hide a crash; any restart or inactive state is a failure.
    if [[ $(systemctl show -p ActiveState --value "$PLAMO3INS_LLAMA_UNIT") != active ||
          $(systemctl show -p NRestarts --value "$PLAMO3INS_LLAMA_UNIT") != 0 ]]; then
      journalctl -u "$PLAMO3INS_LLAMA_UNIT" -n 40 --no-pager >&2 || true
      die "llama-server is not running (see journalctl -u $PLAMO3INS_LLAMA_UNIT)"
    fi
    if ((SECONDS - PLAMO3INS_start > PLAMO3INS_limit)); then
      journalctl -u "$PLAMO3INS_LLAMA_UNIT" -n 40 --no-pager >&2 || true
      die "llama-server did not become ready within ${PLAMO3INS_limit}s (last HTTP status: ${PLAMO3INS_code:-none})"
    fi
    sleep 1
  done
  info "llama-server is ready ($((SECONDS - PLAMO3INS_start))s)"
  local PLAMO3INS_auth=()
  [[ -f $PLAMO3INS_ENV_FILE ]] && PLAMO3INS_auth=(-H "Authorization: Bearer $(sed -n 's/^LLAMA_API_KEY=//p;T;q' "$PLAMO3INS_ENV_FILE")")
  PLAMO3INS_N_CTX=$(curl -s --max-time 10 "${PLAMO3INS_auth[@]}" "http://127.0.0.1:${PLAMO3INS_VAL[LLAMA_PORT]}/props" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["default_generation_settings"]["n_ctx"])' 2>/dev/null || true)
  info "Context size: ${PLAMO3INS_N_CTX:-unknown}"
  report_gpus
}

# Show the GPUs llama-server uses ("using device ... (<PCI address>)" in its log) and
# compare them with the selection.
report_gpus() {
  local PLAMO3INS_pid PLAMO3INS_lines PLAMO3INS_line PLAMO3INS_used PLAMO3INS_expected
  [[ ${PLAMO3INS_VAL[BACKEND]} != cpu ]] || return 0
  PLAMO3INS_pid=$(systemctl show -p MainPID --value "$PLAMO3INS_LLAMA_UNIT")
  PLAMO3INS_lines=$(journalctl -u "$PLAMO3INS_LLAMA_UNIT" "_PID=$PLAMO3INS_pid" -o cat --no-pager 2>/dev/null | grep -o 'using device .*' || true)
  if [[ -z $PLAMO3INS_lines ]]; then
    warn "llama-server does not use any GPU (no \"using device\" in journalctl -u $PLAMO3INS_LLAMA_UNIT); it runs on the CPU"
    return 0
  fi
  while IFS= read -r PLAMO3INS_line; do info "llama-server is $PLAMO3INS_line"; done <<<"$PLAMO3INS_lines"
  [[ ${PLAMO3INS_VAL[GPUS]} != all ]] || return 0
  PLAMO3INS_used=$(sed -nE 's/.*\(([0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-7])\) - .*/\1/p' <<<"$PLAMO3INS_lines" | sort -u | paste -sd, -)
  PLAMO3INS_expected=$(tr , '\n' <<<"${PLAMO3INS_VAL[GPUS]}" | sort -u | paste -sd, -)
  [[ $PLAMO3INS_used == "$PLAMO3INS_expected" ]] \
    || warn "llama-server uses GPU(s) ${PLAMO3INS_used:-unknown}, but ${PLAMO3INS_expected//,/, } were selected"
}

smoke_test() {
  local PLAMO3INS_out PLAMO3INS_code PLAMO3INS_translation
  wait_health
  info "Translating a test sentence through the web server"
  PLAMO3INS_out=$(curl -s -w '\n%{http_code}' --max-time 120 -H 'Content-Type: application/json' \
    -d '{"text": "こんにちは", "target_lang": "en"}' \
    "http://127.0.0.1:${PLAMO3INS_VAL[WEB_PORT]}/api/translate") || die "cannot connect to the web server on port ${PLAMO3INS_VAL[WEB_PORT]}"
  PLAMO3INS_code=${PLAMO3INS_out##*$'\n'}; PLAMO3INS_out=${PLAMO3INS_out%$'\n'*}
  [[ $PLAMO3INS_code == 200 ]] || die "translation test failed (HTTP $PLAMO3INS_code): $PLAMO3INS_out"
  PLAMO3INS_translation=$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("translation", ""))' <<<"$PLAMO3INS_out")
  [[ -n ${PLAMO3INS_translation//[[:space:]]/} ]] || die "translation test returned an empty result: $PLAMO3INS_out"
  info "Translation test passed: こんにちは -> $PLAMO3INS_translation"
  if [[ ${PLAMO3INS_VAL[EXPOSE_LLAMA]} == yes ]]; then
    PLAMO3INS_code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://127.0.0.1:${PLAMO3INS_VAL[LLAMA_PORT]}/v1/models" || true)
    [[ $PLAMO3INS_code == 401 ]] || die "llama-server accepted a request without the API key (HTTP $PLAMO3INS_code)"
    info "llama-server rejects requests without the API key"
  fi
}

# Offer to delete GGUF files of other models/quantizations.
cleanup_old_models() {
  local PLAMO3INS_current PLAMO3INS_f
  PLAMO3INS_current=$(gguf_name "${PLAMO3INS_VAL[MODEL]}" "${PLAMO3INS_VAL[QUANT]}")
  for PLAMO3INS_f in "${PLAMO3INS_VAL[DESTDIR]}"/models/plamo-3-translate-*.gguf "${PLAMO3INS_VAL[DESTDIR]}"/models/plamo-3-translate-*.gguf.part; do
    [[ -e $PLAMO3INS_f && $(basename "$PLAMO3INS_f") != "$PLAMO3INS_current" ]] || continue
    if confirm "Delete the unused model file $(basename "$PLAMO3INS_f") ($(human "$(stat -c %s "$PLAMO3INS_f")"))?"; then
      rm -f "$PLAMO3INS_f"
      info "Deleted $(basename "$PLAMO3INS_f")"
    fi
  done
}

finish() {
  local PLAMO3INS_ip
  PLAMO3INS_ip=$(listen_addresses | sed -n '1p')
  [[ -n $PLAMO3INS_ip ]] || PLAMO3INS_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  [[ $PLAMO3INS_ip != *:* ]] || PLAMO3INS_ip="[$PLAMO3INS_ip]"
  cat <<EOF

PLaMo 3 Translate is installed.
  Web UI   : http://${PLAMO3INS_ip:-<this host>}:${PLAMO3INS_VAL[WEB_PORT]}/
  JSON API : curl -H 'Content-Type: application/json' \\
               -d '{"text": "こんにちは", "target_lang": "en"}' \\
               http://${PLAMO3INS_ip:-<this host>}:${PLAMO3INS_VAL[WEB_PORT]}/api/translate
  Services : $PLAMO3INS_LLAMA_UNIT, $PLAMO3INS_UWSGI_UNIT, nginx.service
  Settings : $PLAMO3INS_CONF_FILE
  Context  : ${PLAMO3INS_N_CTX:-unknown} tokens
EOF
  if [[ ${PLAMO3INS_VAL[EXPOSE_LLAMA]} == yes ]]; then
    cat <<EOF
  llama-server : http://${PLAMO3INS_ip:-<this host>}:${PLAMO3INS_VAL[LLAMA_PORT]}/ (model "$PLAMO3INS_MODEL_ALIAS")
  API key      : stored in $PLAMO3INS_ENV_FILE (LLAMA_API_KEY)
EOF
  fi
  echo
  warn_small_context
}

# Warn when the context is too small for plamo-3-translate-client.py with its defaults.
warn_small_context() {
  local PLAMO3INS_chunk
  [[ $PLAMO3INS_N_CTX =~ ^[0-9]+$ ]] && ((PLAMO3INS_N_CTX < PLAMO3INS_CLIENT_CTX)) || return 0
  PLAMO3INS_chunk=$((PLAMO3INS_N_CTX * PLAMO3INS_CLIENT_CHUNK_CHARS / PLAMO3INS_CLIENT_CTX / 100 * 100))
  ((PLAMO3INS_chunk >= 100)) || PLAMO3INS_chunk=100
  warn "the context size ($PLAMO3INS_N_CTX tokens) is smaller than plamo-3-translate-client.py may need for long documents with its default --chunk-chars $PLAMO3INS_CLIENT_CHUNK_CHARS (about $PLAMO3INS_CLIENT_CTX tokens); requests may fail. Use --chunk-chars $PLAMO3INS_chunk or less with the client."
  if [[ ${PLAMO3INS_VAL[CTX_SIZE]} == auto ]]; then
    warn "llama.cpp reduced the context to fit the memory; a smaller model or quantization, or more GPU memory, gives a larger context."
  else
    warn "the context size was set with --ctx-size ${PLAMO3INS_VAL[CTX_SIZE]}; re-run the installer with --ctx-size auto or a larger value for a larger context."
  fi
  echo >&2
}

do_install() {
  load_saved_config
  resolve_values
  prompt_values
  validate
  prompt_gpus
  prompt_interfaces
  prompt_ufw
  confirm_license
  show_summary
  preflight
  install_packages
  ensure_user
  prepare_destdir
  install_llama
  install_model
  install_app
  write_env_file
  write_units
  write_nginx
  [[ -n ${PLAMO3INS_SAVED[DESTDIR]:-} && ${PLAMO3INS_SAVED[DESTDIR]} != "${PLAMO3INS_VAL[DESTDIR]}" ]] \
    && warn "the previous installation directory ${PLAMO3INS_SAVED[DESTDIR]} is no longer used; remove it manually if not needed"
  start_services
  configure_ufw
  save_config
  smoke_test
  cleanup_old_models
  finish
}

# -------------------------------------------------------------- uninstall

do_uninstall() {
  local PLAMO3INS_destdir PLAMO3INS_p
  load_saved_config
  PLAMO3INS_destdir=${PLAMO3INS_ARG[DESTDIR]:-${PLAMO3_DESTDIR:-${PLAMO3INS_SAVED[DESTDIR]:-${PLAMO3INS_DEFAULT[DESTDIR]}}}}
  PLAMO3INS_destdir=${PLAMO3INS_destdir%/}
  cat <<EOF
This will stop and remove the PLaMo 3 Translate services and delete:
  $PLAMO3INS_UNIT_DIR/$PLAMO3INS_LLAMA_UNIT
  $PLAMO3INS_UNIT_DIR/$PLAMO3INS_UWSGI_UNIT
  $PLAMO3INS_NGINX_SITE (and the link in sites-enabled)
  $PLAMO3INS_CONF_DIR
  $PLAMO3INS_destdir
EOF
  confirm "Uninstall PLaMo 3 Translate?" || die "aborted (use --yes to uninstall non-interactively)"

  info "Stopping services"
  for PLAMO3INS_p in "$PLAMO3INS_UWSGI_UNIT" "$PLAMO3INS_LLAMA_UNIT"; do
    if service_exists "$PLAMO3INS_p"; then
      systemctl disable --now "$PLAMO3INS_p" 2>/dev/null || true
      rm -f "${PLAMO3INS_UNIT_DIR:?}/$PLAMO3INS_p"
    fi
  done
  systemctl daemon-reload
  systemctl reset-failed "$PLAMO3INS_UWSGI_UNIT" "$PLAMO3INS_LLAMA_UNIT" 2>/dev/null || true

  info "Removing nginx site"
  rm -f "$PLAMO3INS_NGINX_LINK" "$PLAMO3INS_NGINX_SITE"
  if command -v nginx >/dev/null && systemctl is-active --quiet nginx.service; then
    if nginx -t >/dev/null 2>&1; then
      systemctl reload nginx.service
    else
      warn "nginx configuration test failed; nginx was not reloaded"
    fi
  fi

  local PLAMO3INS_rules=${PLAMO3INS_SAVED[UFW_RULES]:-${PLAMO3INS_SAVED[UFW_PORTS]:-}}
  if [[ -n $PLAMO3INS_rules ]] && command -v ufw >/dev/null; then
    for PLAMO3INS_p in $PLAMO3INS_rules; do
      # shellcheck disable=SC2046
      if ufw delete $(ufw_rule_args "$PLAMO3INS_p") >/dev/null 2>&1; then
        info "Removed the ufw rule for $(ufw_rules_text "$PLAMO3INS_p")"
      fi
    done
  fi

  if [[ -d $PLAMO3INS_destdir ]]; then
    if [[ -e $PLAMO3INS_destdir/$PLAMO3INS_MARKER ]]; then
      info "Removing $PLAMO3INS_destdir"
      rm -rf --one-file-system "${PLAMO3INS_destdir:?}"
    else
      warn "$PLAMO3INS_destdir does not look like a PLaMo 3 Translate installation; not removed"
    fi
  fi
  rm -rf "${PLAMO3INS_CONF_DIR:?}" "/var/cache/$PLAMO3INS_APP_NAME"

  cat <<EOF

PLaMo 3 Translate was uninstalled.
The apt packages (nginx-full, uwsgi, ...) and the service user ${PLAMO3INS_SAVED[USER]:-${PLAMO3INS_DEFAULT[USER]}} were kept.
Remove them manually if they are no longer needed, e.g.:
  sudo userdel ${PLAMO3INS_SAVED[USER]:-${PLAMO3INS_DEFAULT[USER]}}
EOF
}

main() {
  parse_args "$@"
  check_platform
  if [[ $PLAMO3INS_ACTION == uninstall ]]; then
    do_uninstall
  else
    do_install
  fi
}

main "$@"
