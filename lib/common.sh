# shellcheck shell=bash
# Logging, prompts, downloads and dry-run plumbing shared by every step.

APP_NAME=7thDroid
APP_ID=7thdroid
CACHE_DIR=${XDG_CACHE_HOME:-$HOME/.cache}/$APP_ID
DATA_DIR=${XDG_DATA_HOME:-$HOME/.local/share}/$APP_ID
STATE_DIR=${XDG_STATE_HOME:-$HOME/.local/state}/$APP_ID
LOG_FILE=$STATE_DIR/install.log
STATE_FILE=$DATA_DIR/install.env

ASSUME_YES=${ASSUME_YES:-0}
DRY_RUN=${DRY_RUN:-0}

if [ -t 1 ]; then
  C_BOLD=$'\e[1m' C_DIM=$'\e[2m' C_RED=$'\e[31m' C_GREEN=$'\e[32m' C_YELLOW=$'\e[33m' C_RESET=$'\e[0m'
else
  C_BOLD='' C_DIM='' C_RED='' C_GREEN='' C_YELLOW='' C_RESET=''
fi

LOG_TEE_PID=''

start_log() {
  mkdir -p "$STATE_DIR"
  # the last three runs' logs are kept
  [ -f "$LOG_FILE.1" ] && mv -f -- "$LOG_FILE.1" "$LOG_FILE.2"
  [ -f "$LOG_FILE" ] && mv -f -- "$LOG_FILE" "$LOG_FILE.1"
  : > "$LOG_FILE"
  exec > >(tee -a "$LOG_FILE") 2>&1
  LOG_TEE_PID=$!
}

# At exit: let tee write out everything before the script is gone, so the log and the screen end with
# the last message (an error, usually) rather than stopping short of it.
finish_log() {
  [ -n "$LOG_TEE_PID" ] || return 0
  exec >&- 2>&-
  wait "$LOG_TEE_PID" 2>/dev/null || true
}

step()  { printf '\n%s==> %s%s\n' "$C_BOLD" "$*" "$C_RESET"; UI_STEP=$*; ui_progress "$*"; }
info()  { printf '    %s\n' "$*"; ui_progress "$UI_STEP: $*"; }
ok()    { printf '    %s%s%s\n' "$C_GREEN" "$*" "$C_RESET"; ui_progress "$UI_STEP: $*"; }
warn()  { printf '    %sWarning:%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
debug() { printf '    %s%s%s\n' "$C_DIM" "$*" "$C_RESET" >> "${LOG_FILE:-/dev/null}"; }
die()   { printf '\n%sError:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; ui_error "$*"; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# Runs a command, or only prints it with --dry-run.
run() {
  if [ "$DRY_RUN" = 1 ]; then
    printf '    %s[dry-run]%s' "$C_DIM" "$C_RESET"
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  debug "+ $(printf '%q ' "$@")"
  "$@"
}

# Asking needs a terminal or zenity; without either only --yes runs can go on.
can_ask() {
  [ "$UI_MODE" != none ] || die "There is no terminal or window to ask in. Run this from a terminal, or use the 7thDroid AppImage."
}

# ask VAR "Question" [default]
ask() {
  local __var=$1 question=$2 default=${3:-} __reply
  if [ "$ASSUME_YES" = 1 ]; then
    printf -v "$__var" '%s' "$default"
    info "$question ${default:+[$default]} (--yes)"
    return
  fi
  can_ask
  if [ "$UI_MODE" = zenity ]; then
    ui_ask "$__var" "$question" "$default"
    return
  fi
  read -r -e -p "    $question${default:+ [$default]}: " __reply || __reply=
  printf -v "$__var" '%s' "${__reply:-$default}"
}

# ask_yn "Question" y|n -> status 0 for yes
ask_yn() {
  local question=$1 default=${2:-y} __reply hint
  [ "$default" = y ] && hint='Y/n' || hint='y/N'
  if [ "$ASSUME_YES" = 1 ]; then
    info "$question [$hint] (--yes: $default)"
    [ "$default" = y ]
    return
  fi
  can_ask
  if [ "$UI_MODE" = zenity ]; then
    ui_ask_yn "$question" "$default"
    return
  fi
  while true; do
    read -r -p "    $question [$hint]: " __reply || __reply=
    case ${__reply:-$default} in
      [Yy]*) return 0 ;;
      [Nn]*) return 1 ;;
    esac
  done
}

# choose VAR "Question" option... -> VAR gets the 0-based index; the first option is the default.
choose() {
  local __var=$1 question=$2 i __reply
  shift 2
  info "$question"
  i=1
  local option
  for option in "$@"; do
    info "  $i) $option"
    i=$((i + 1))
  done
  if [ "$ASSUME_YES" = 1 ] || [ $# -eq 1 ]; then
    printf -v "$__var" '%s' 0
    info "Using 1) $1"
    return
  fi
  can_ask
  if [ "$UI_MODE" = zenity ]; then
    ui_choose "$__var" "$question" "$@"
    return
  fi
  while true; do
    read -r -p "    Choose 1-$#: [1] " __reply || __reply=
    __reply=${__reply:-1}
    if [[ $__reply =~ ^[0-9]+$ ]] && [ "$__reply" -ge 1 ] && [ "$__reply" -le $# ]; then
      printf -v "$__var" '%s' $((__reply - 1))
      return
    fi
  done
}

pause() {
  [ "$ASSUME_YES" = 1 ] && return
  can_ask
  [ "$UI_MODE" = zenity ] && { ui_pause "$*"; return; }
  read -r -p "    $* Press Enter to continue... " _ || true
}

# human_size KB -> the size in the largest unit it fills (1024 steps): 207 KB, 4.5 MB, 120 MB, 3.6 GB.
# Sizes come from du -k, so KB is the smallest unit.
human_size() {
  awk -v k="${1:-0}" 'BEGIN {
    split("KB MB GB TB", unit, " "); i = 1
    while (k >= 1024 && i < 4) { k /= 1024; i++ }
    if (i > 1 && k < 10) printf "%.1f %s\n", k, unit[i]; else printf "%d %s\n", k + 0.5, unit[i]
  }'
}

# download URL [file name] -> prints the cached path
download() {
  local url=$1 name=${2:-${1##*/}} dest
  dest=$CACHE_DIR/$name
  mkdir -p "$CACHE_DIR"
  if [ -s "$dest" ]; then
    info "Using cached $name" >&2
  elif [ "$DRY_RUN" = 1 ]; then
    run curl -fL --retry 4 -o "$dest" "$url" >&2
  else
    info "Downloading $name" >&2
    curl -fsSL --retry 4 --retry-delay 2 -o "$dest.part" "$url" >&2 \
      || { rm -f "$dest.part"; die "Download failed: $url"; }
    mv "$dest.part" "$dest"
  fi
  printf '%s\n' "$dest"
}

# Linux path -> Wine Z: path
winpath() {
  local path=$1
  printf 'Z:%s\n' "${path//\//\\}"
}

# prefix_winpath COMPATDATA PATH - PATH as programs in that prefix see it: C: for its own drive_c.
prefix_winpath() {
  local drive=$1/pfx/drive_c path=$2
  case $path in
    "$drive"/*) path=${path#"$drive"}; printf 'C:%s\n' "${path//\//\\}" ;;
    *) winpath "$path" ;;
  esac
}

python() { python3 -I "$@"; }

save_state() {
  mkdir -p "$DATA_DIR"
  local name
  {
    for name in "$@"; do
      printf '%s=%q\n' "$name" "${!name}"
    done
  } > "$STATE_FILE"
}

load_state() {
  [ -f "$STATE_FILE" ] || return 1
  # shellcheck disable=SC1090
  . "$STATE_FILE"
}

# shellcheck source=lib/ui.sh
. "$(dirname "${BASH_SOURCE[0]}")/ui.sh"
