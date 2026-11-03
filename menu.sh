#!/bin/bash
# The 7thDroid AppImage's entry point: the installer the first time, then a menu to launch 7th Heaven,
# update or repair it, redo its shortcuts, read the log or uninstall it.

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LIB_DIR=$ROOT_DIR/lib
ASSETS_DIR=$ROOT_DIR/assets

# shellcheck source=lib/common.sh
. "$LIB_DIR/common.sh"
# shellcheck source=lib/droiddeck.sh
. "$LIB_DIR/droiddeck.sh"
# shellcheck source=lib/shortcuts.sh
. "$LIB_DIR/shortcuts.sh"

ui_init
[ "$UI_MODE" = none ] && die "7thDroid needs a terminal or its bundled zenity to ask questions."

COMPATDATA='' SOURCE_KIND='' action='' pick=0

installed() {
  load_state 2>/dev/null && [ -f "$LAUNCHER" ] && [ -f "$COMPATDATA/pfx/drive_c/7th Heaven/7th Heaven.exe" ]
}

installer() {
  bash "$ROOT_DIR/install.sh" "$@"
}

# Steam starts 7th Heaven through its non-Steam shortcut, so the Steam API sees FF7 (with 7th Heaven's
# Steam Compatibility setting on) and the overlay and Steam Input apply. Steam copies of FF7 only.
launch_with_steam() {
  if [ ! -x "$STEAM_LAUNCH" ]; then
    pause "This DroidDeck has no droiddeck-steam-launch ($STEAM_LAUNCH). Start \"$LAUNCHER_NAME\" from Steam's library instead."
    return
  fi
  if ! has_steam_shortcut; then
    ask_yn "Steam starts 7th Heaven through its \"$LAUNCHER_NAME\" shortcut, which isn't in Steam yet. Add it now? (Steam has to be closed for that.)" y \
      || return
    installer --shortcuts-only --steam --no-app-entry --no-desktop
    has_steam_shortcut || { pause "The Steam shortcut wasn't added, so 7th Heaven can't be started with Steam yet."; return; }
  fi
  info "Starting \"$LAUNCHER_NAME\" with Steam. For FF7's achievements, turn on Steam Compatibility in 7th Heaven's Game Driver settings (Advanced)."
  steam_launch_shortcut && exit 0
  pause "Steam could not be asked to start 7th Heaven. Start \"$LAUNCHER_NAME\" from Steam's library instead."
}

installed || exec bash "$ROOT_DIR/install.sh" "$@"

while true; do
  labels=("Launch 7th Heaven") actions=(launch)
  if [ "$SOURCE_KIND" = steam ]; then
    labels+=("Launch 7th Heaven with Steam (achievements)") actions+=(steam)
  fi
  labels+=("Update or repair 7th Heaven" "Add or redo shortcuts" "Show the last log" "Uninstall 7th Heaven" "Quit")
  actions+=(update shortcuts log uninstall quit)
  choose pick "7th Heaven ${SEVENTH_TAG:+$SEVENTH_TAG }is installed for ${FF7_VERSION:-FINAL FANTASY VII}." "${labels[@]}"
  action=${actions[$pick]}
  case $action in
    launch) exec bash "$LAUNCHER" ;;
    steam) launch_with_steam ;;
    update) installer ;;
    shortcuts) installer --shortcuts-only ;;
    log)
      if [ "$UI_MODE" = zenity ]; then
        zen --text-info --width=1000 --height=700 --filename="$LOG_FILE" || true
      else
        less "$LOG_FILE" 2>/dev/null || cat "$LOG_FILE"
      fi ;;
    uninstall) installer --uninstall; installed || exit 0 ;;
    *) exit 0 ;;
  esac
  installed || exit 0
  load_state
done
