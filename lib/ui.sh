# shellcheck shell=bash
# The installer's questions as windows, for when it runs without a terminal: from the AppImage, a tile
# on DroidDeck's Desktop page runs full screen under gamescope with nothing to type into.
#
# UI_MODE is tty (typed answers, the default in a terminal), zenity (UI_ZENITY is the bundled zenity),
# or none (no way to ask; only --yes runs work).

UI_ZENITY=${UI_ZENITY:-}
UI_PROGRESS_FD=''
UI_STEP=''
DOWNLOADS_DIR=${DOWNLOADS_DIR:-/root/Storage/Download}

# Decided before start_log, which turns stdout into a pipe.
ui_init() {
  if [ -n "${UI_MODE:-}" ]; then
    :
  elif [ -t 0 ] && [ -t 1 ]; then
    UI_MODE=tty
  elif [ -n "$UI_ZENITY" ] && [ -x "$UI_ZENITY" ]; then
    UI_MODE=zenity
  else
    UI_MODE=none
  fi
}

zen() {
  "$UI_ZENITY" --title="$APP_NAME" "$@" 2>/dev/null
}

# zenity reads backslash escapes (g_strcompress) in markup text and progress lines, so C:\7th Heaven
# would show \7 as a control character. --no-markup message windows take their text as it is.
zen_text() {
  printf '%s' "${1//\\/\\\\}"
}

# zenity reads --text as Pango markup; paths with & or < must not be taken for it.
markup() {
  local text
  text=$(zen_text "$1")
  text=${text//&/&amp;}
  text=${text//</&lt;}
  printf '%s' "${text//>/&gt;}"
}

# A cancelled window ends the run; nothing is half-asked. Closing the menu is not an error.
UI_CANCEL_STATUS=130
ui_cancelled() {
  ui_progress_stop
  printf '\n%s\n' "Cancelled." >&2
  exit "$UI_CANCEL_STATUS"
}

ui_warning() {
  zen --question --no-markup --width=700 --text="$1" --ok-label=Continue --cancel-label=Quit || ui_cancelled
}

ui_ask() {
  local __var=$1 __reply
  __reply=$(zen --entry --width=700 --text="$(markup "$2")" --entry-text="${3:-}") || ui_cancelled
  printf -v "$__var" '%s' "${__reply:-${3:-}}"
}

ui_ask_yn() {
  local args=(--question --no-markup --width=600 --text="$1" --ok-label=Yes --cancel-label=No)
  [ "${2:-y}" = n ] && args+=(--default-cancel)
  zen "${args[@]}"
}

ui_choose() {
  local __var=$1 question=$2 rows=() i=0 option __reply
  shift 2
  for option in "$@"; do
    [ $i -eq 0 ] && rows+=(TRUE) || rows+=(FALSE)
    rows+=("$i" "$option")
    i=$((i + 1))
  done
  __reply=$(zen --list --radiolist --width=900 --height=$((200 + 60 * $#)) --text="$(markup "$question")" \
    --column=" " --column=n --column="Option" --hide-column=2 --print-column=2 --hide-header "${rows[@]}") || ui_cancelled
  printf -v "$__var" '%s' "${__reply:-0}"
}

ui_pause() {
  zen --info --no-markup --width=600 --text="$*" || true
}

# ui_paths VAR "Title" file|files|folder|folders [pattern] -> VAR gets the chosen paths, one per line
ui_paths() {
  local __var=$1 title=$2 kind=$3 pattern=${4:-} args=(--file-selection --title="$title") start __reply
  start=$DOWNLOADS_DIR
  [ -d "$start" ] || start=$HOME
  args+=(--filename="$start/")
  case $kind in
    files|folders) args+=(--multiple --separator=$'\n') ;;
  esac
  case $kind in
    folder|folders) args+=(--directory) ;;
  esac
  [ -n "$pattern" ] && args+=(--file-filter="$pattern")
  __reply=$("$UI_ZENITY" "${args[@]}" 2>/dev/null) || ui_cancelled
  printf -v "$__var" '%s' "$__reply"
}

ui_progress_start() {
  [ "$UI_MODE" = zenity ] || return 0
  local fifo
  fifo=$(mktemp -u "${TMPDIR:-/tmp}/$APP_ID-progress.XXXXXX")
  mkfifo "$fifo" || return 0
  zen --progress --pulsate --no-cancel --auto-close --width=700 --text="Starting..." < "$fifo" &
  exec {UI_PROGRESS_FD}> "$fifo"
  rm -f "$fifo"
}

ui_progress() {
  [ -n "$UI_PROGRESS_FD" ] || return 0
  printf '# %s\n' "$(zen_text "${*//$'\n'/ }")" >&"$UI_PROGRESS_FD" 2>/dev/null || true
}

ui_progress_stop() {
  [ -n "$UI_PROGRESS_FD" ] || return 0
  printf '100\n' >&"$UI_PROGRESS_FD" 2>/dev/null || true
  exec {UI_PROGRESS_FD}>&-
  UI_PROGRESS_FD=''
}

ui_error() {
  ui_progress_stop
  [ "$UI_MODE" = zenity ] || return 0
  local text=$1
  [[ $text == *"$LOG_FILE"* ]] || text="$text

The log is $LOG_FILE
For a bug report, \"Save logs\" in $APP_NAME's menu collects every log, redacted."
  zen --error --no-markup --width=800 --text="$text" || true
}

ui_done() {
  ui_progress_stop
  [ "$UI_MODE" = zenity ] || return 0
  zen --info --no-markup --width=700 --text="$*" || true
}
