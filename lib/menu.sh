# shellcheck shell=bash
# 7thDroid's menu, which the AppImage opens: Install 7th Heaven until it is installed, then launching,
# updating or repairing, backing up and restoring, the logs and uninstalling. Each task runs as its own 7thdroid.sh, so
# a task that fails or is cancelled ends there and the menu comes back.

installed() {
  load_state 2>/dev/null && [ -f "$LAUNCHER" ] && [ -f "$COMPATDATA/pfx/drive_c/7th Heaven/7th Heaven.exe" ]
}

# run_task OPTION... - one task, with the options 7thDroid was started with
run_task() {
  bash "$SELF" "$@" "${ARGS[@]}"
}

# Steam starts 7th Heaven through its non-Steam shortcut, so the Steam API sees FF7 (with FFNx's Steam
# Compatibility turned on first) and the overlay and Steam Input apply. Steam copies of FF7 only.
launch_with_steam() {
  if [ ! -x "$STEAM_LAUNCH" ]; then
    pause "This DroidDeck has no droiddeck-steam-launch ($STEAM_LAUNCH). Start \"$LAUNCHER_NAME\" from Steam's library instead."
    return
  fi
  if ! has_steam_shortcut; then
    ask_yn "Steam starts 7th Heaven through its \"$LAUNCHER_NAME\" shortcut, which isn't in Steam yet. Add it now? (Steam has to be closed for that.)" y \
      || return
    run_task --steam-shortcut
    has_steam_shortcut || { pause "The Steam shortcut wasn't added, so 7th Heaven can't be started with Steam yet."; return; }
  fi
  ready_to_launch || return
  apply_ffnx_settings 1
  info "Starting \"$LAUNCHER_NAME\" with Steam."
  steam_launch_shortcut && exit 0
  pause "Steam could not be asked to start 7th Heaven. Start \"$LAUNCHER_NAME\" from Steam's library instead."
}

# apply_ffnx_settings STEAM - FFNx's Graphics API (Direct3D 11 in place of Auto) and Steam Compatibility
# (on only when Steam starts 7th Heaven), set in FFNx.toml just before launching. 7th Heaven installs FFNx
# on the first Play, resetting FFNx.toml, so until then there is nothing to set.
apply_ffnx_settings() {
  local status=0
  python "$LIB_DIR/ffnx.py" settings "$(ffnx_settings_xml "$COMPATDATA")" "$COMPATDATA/pfx/drive_c" "$1" \
    || status=$?
  case $status in
    0) ;;
    3) info "FFNx is installed the first time you play; $APP_NAME's FFNx settings apply from the next launch." ;;
    *) warn "Could not update FFNx.toml; 7th Heaven starts with its current FFNx settings." ;;
  esac
  return 0
}

# Has FF7 been played through 7th Heaven yet? Until then there is no FFNx, so no Steam Compatibility to
# turn on, and a Steam launch would start FF7 without achievements.
ffnx_installed() {
  python "$LIB_DIR/ffnx.py" exists "$(ffnx_settings_xml "$COMPATDATA")" "$COMPATDATA/pfx/drive_c" 2>/dev/null
}

# ready_to_launch - an FFNx too old for 7th Heaven is updated first; 7th Heaven would refuse to start FF7.
# FFNx settings restored before FFNx was installed are merged in once it is.
ready_to_launch() {
  finish_ffnx_restore
  [ "$(ffnx_state "$COMPATDATA")" = old ] || return 0
  run_task --update-ffnx && return 0
  pause "FFNx could not be updated, and 7th Heaven won't start FF7 with the old one. See the log. In 7th Heaven, Settings > General Settings > FFNx: Check for Updates updates it too."
  return 1
}

run_menu() {
  local labels actions pick action note
  can_ask
  # Closing the menu is how you leave it.
  UI_CANCEL_STATUS=0
  while true; do
    COMPATDATA='' SOURCE_KIND='' SEVENTH_TAG='' FF7_VERSION=''
    if ! installed; then
      choose pick "7th Heaven is not installed yet." "Install 7th Heaven" "Save logs" "Quit"
      case $pick in
        0) run_task --install ;;
        1) run_task --save-logs ;;
        *) exit 0 ;;
      esac
      continue
    fi
    labels=("Launch 7th Heaven") actions=(launch) note=''
    if [ "$SOURCE_KIND" = steam ]; then
      if ffnx_installed; then
        labels+=("Launch 7th Heaven with Steam") actions+=(steam)
      else
        note="

Launch 7th Heaven and play FF7 once first: 7th Heaven sets up its game driver then, and \"Launch 7th Heaven with Steam\" appears here after that."
      fi
    fi
    labels+=("Update or repair 7th Heaven" "Back up 7th Heaven" "Restore a backup" "Show the last log" "Save logs" "Uninstall 7th Heaven" "Quit")
    actions+=(update backup restore log logs uninstall quit)
    choose pick "7th Heaven ${SEVENTH_TAG:+$SEVENTH_TAG }is installed for ${FF7_VERSION:-FINAL FANTASY VII}.$note" "${labels[@]}"
    action=${actions[$pick]}
    case $action in
      launch)
        ready_to_launch || continue
        apply_ffnx_settings 0
        exec bash "$LAUNCHER" ;;
      steam) launch_with_steam ;;
      update) run_task --install ;;
      backup) run_task --backup ;;
      restore)
        if [ -z "$(list_backups)" ]; then
          pause "There are no backups in $(backup_dir) yet. \"Back up 7th Heaven\" makes one."
        else
          run_task --restore
        fi ;;
      log)
        if [ "$UI_MODE" = zenity ]; then
          zen --text-info --width=1000 --height=700 --filename="$LOG_FILE" || true
        else
          less "$LOG_FILE" 2>/dev/null || cat "$LOG_FILE"
        fi ;;
      logs) run_task --save-logs ;;
      uninstall) run_task --uninstall ;;
      *) exit 0 ;;
    esac
  done
}
