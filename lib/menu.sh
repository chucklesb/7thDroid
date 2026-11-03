# shellcheck shell=bash
# 7thDroid's menu, which the AppImage opens: Install 7th Heaven until it is installed, then launching,
# updating or repairing, shortcuts, the log and uninstalling. Each task runs as its own 7thdroid.sh, so
# a task that fails or is cancelled ends there and the menu comes back.

installed() {
  load_state 2>/dev/null && [ -f "$LAUNCHER" ] && [ -f "$COMPATDATA/pfx/drive_c/7th Heaven/7th Heaven.exe" ]
}

# run_task OPTION... - one task, with the options 7thDroid was started with
run_task() {
  bash "$SELF" "$@" "${ARGS[@]}"
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
    run_task --shortcuts-only --steam --no-app-entry --no-desktop
    has_steam_shortcut || { pause "The Steam shortcut wasn't added, so 7th Heaven can't be started with Steam yet."; return; }
  fi
  info "Starting \"$LAUNCHER_NAME\" with Steam. For FF7's achievements, turn on Steam Compatibility in 7th Heaven's Game Driver settings (Advanced)."
  steam_launch_shortcut && exit 0
  pause "Steam could not be asked to start 7th Heaven. Start \"$LAUNCHER_NAME\" from Steam's library instead."
}

run_menu() {
  local labels actions pick action
  can_ask
  # Closing the menu is how you leave it.
  UI_CANCEL_STATUS=0
  while true; do
    COMPATDATA='' SOURCE_KIND='' SEVENTH_TAG='' FF7_VERSION=''
    if ! installed; then
      choose pick "7th Heaven is not installed yet." "Install 7th Heaven" "Quit"
      [ "$pick" = 0 ] || exit 0
      run_task --install
      continue
    fi
    labels=("Launch 7th Heaven") actions=(launch)
    if [ "$SOURCE_KIND" = steam ]; then
      labels+=("Launch 7th Heaven with Steam") actions+=(steam)
    fi
    labels+=("Update or repair 7th Heaven" "Add or recreate shortcuts" "Show the last log" "Uninstall 7th Heaven" "Quit")
    actions+=(update shortcuts log uninstall quit)
    choose pick "7th Heaven ${SEVENTH_TAG:+$SEVENTH_TAG }is installed for ${FF7_VERSION:-FINAL FANTASY VII}." "${labels[@]}"
    action=${actions[$pick]}
    case $action in
      launch) exec bash "$LAUNCHER" ;;
      steam) launch_with_steam ;;
      update) run_task --install ;;
      shortcuts) run_task --shortcuts-only ;;
      log)
        if [ "$UI_MODE" = zenity ]; then
          zen --text-info --width=1000 --height=700 --filename="$LOG_FILE" || true
        else
          less "$LOG_FILE" 2>/dev/null || cat "$LOG_FILE"
        fi ;;
      uninstall) run_task --uninstall ;;
      *) exit 0 ;;
    esac
  done
}
