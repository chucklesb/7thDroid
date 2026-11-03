# shellcheck shell=bash
# The install task: finding FF7, preparing 7th Heaven's prefix, installing and configuring 7th Heaven,
# its launcher and its shortcuts. Running it again updates or repairs the install.

# The README's warning, before anything is done: a window to confirm, or text in a terminal.
show_warning() {
  local text
  text=$(cat "$ASSETS_DIR/WARNING.txt")
  if [ "$UI_MODE" = zenity ] && [ "$ASSUME_YES" != 1 ]; then
    ui_warning "$text"
  else
    printf '\n%s%s%s\n' "$C_BOLD" "$(fold -s -w 100 <<< "$text")" "$C_RESET"
  fi
}

run_install() {
  local labels line pick previous steam_note
  ensure_droiddeck_proton

  step "Finding FINAL FANTASY VII"
  APPID='' GAME_COPY=0
  if [ ${#SOURCES[@]} -gt 0 ]; then
    manual_source "${SOURCES[@]}"
  else
    mapfile -t FOUND < <(detect_all)
    if [ ${#FOUND[@]} -eq 0 ]; then
      manual_source
    else
      labels=()
      for line in "${FOUND[@]}"; do labels+=("$(cut -f5 <<< "$line")"); done
      labels+=("Somewhere else (enter a path)")
      choose pick "Which copy of FINAL FANTASY VII should 7th Heaven use?" "${labels[@]}"
      if [ "$pick" -eq ${#FOUND[@]} ]; then
        manual_source
      else
        IFS=$'\t' read -r SOURCE_KIND APPID GAME_DIR _ _ <<< "${FOUND[$pick]}"
        GAME_EXE=$(find_game_exe "$GAME_DIR")
        [ -n "$GAME_EXE" ] || die "No FF7 executable found in $GAME_DIR. Is the game fully installed?"
      fi
    fi
  fi
  if [ "$SOURCE_KIND" = gog-setup ]; then
    APPID=$FF7_GOG
    unpack_gog_setup || true
  fi
  case $SOURCE_KIND in
    steam|folder|gog) ok "Game: $GAME_EXE" ;;
    gog-setup) ok "Game: GOG installer ${GOG_SETUP##*/}, installing to $GAME_DIR" ;;
    cd) ok "Game: 1998 CD-ROM release, ${#CD_DISCS[@]} disc(s)" ;;
  esac

  step "Choosing the Proton prefix"
  # 7th Heaven always gets a prefix of its own, made by DroidDeck-Proton. The game is reached through
  # Z: (Proton maps it to /), so no other prefix - Steam's FF7 prefix included - is ever touched.
  COMPATDATA=$DEDICATED
  info "7th Heaven's own prefix: $COMPATDATA"
  previous=$(load_state 2>/dev/null && printf '%s' "$COMPATDATA")
  if [ -n "$previous" ] && [ "$previous" != "$COMPATDATA" ]; then
    info "An older $APP_NAME installed 7th Heaven into $previous. That prefix is left as it is."
    info "If it is a Steam game's prefix and the game misbehaves, delete that folder and Steam recreates it."
  fi
  pin_proton "$PREFIX_ID"

  select_seventh_heaven

  check_compatdata "$COMPATDATA"

  step "Preparing the prefix"
  info "7th Heaven needs the .NET Desktop Runtime $DOTNET_CHANNEL"
  install_dotnet "$COMPATDATA"
  [ "$DRY_RUN" = 1 ] || [ -f "$COMPATDATA/pfx/user.reg" ] || die "The prefix was not created. See $LOG_FILE."
  [ "$SOURCE_KIND" = cd ] && map_cd_drives "$COMPATDATA"
  apply_registry "$COMPATDATA"
  [ "$WINETRICKS_DINPUT" = 1 ] && winetricks_dinput "$COMPATDATA"

  case $SOURCE_KIND in
    gog-setup|cd)
      step "Installing FINAL FANTASY VII"
      install_pending_game "$COMPATDATA" ;;
    steam|gog|folder)
      offer_game_copy "$COMPATDATA" ;;
  esac
  prefix_extras "$COMPATDATA" "$APPID"

  step "Installing 7th Heaven"
  install_seventh_heaven "$COMPATDATA"
  FF7_VERSION=$(ff7_version_for "$APPID" "$GAME_EXE")
  if [ -z "$FF7_VERSION" ]; then
    choose pick "Which release of FF7 is in $GAME_DIR?" "GOG" "Steam (2026 release)"
    [ "$pick" = 0 ] && FF7_VERSION=GOG || FF7_VERSION=SteamReRelease
  fi
  configure_seventh_heaven "$COMPATDATA" "$GAME_EXE" "$FF7_VERSION"

  write_launcher "$(seventh_exe "$COMPATDATA")" "$(ff7_steam_appid)"
  [ "$DRY_RUN" = 1 ] || save_state SOURCE_KIND APPID GAME_DIR GAME_EXE GAME_COPY COMPATDATA FF7_VERSION SEVENTH_CHANNEL SEVENTH_TAG
  offer_shortcuts

  step "Done"
  ok "7th Heaven $SEVENTH_TAG is installed for $FF7_VERSION FINAL FANTASY VII."
  info "Start it from $APP_NAME's menu, or with: bash \"$LAUNCHER\" (or the shortcuts you added)."
  steam_note=''
  if [ -n "$(ff7_steam_appid)" ]; then
    steam_note="

For Steam achievements, turn on Steam Compatibility in 7th Heaven (Settings > Game Driver > Advanced), then start 7th Heaven with Steam: \"Launch 7th Heaven with Steam\" in 7thDroid, or the \"$LAUNCHER_NAME\" shortcut in Steam. With that setting on, FF7 only starts while Steam is running."
    info "${steam_note#$'\n\n'}"
  fi
  info "Prefix: $COMPATDATA"
  info "Log: $LOG_FILE"
  ui_done "7th Heaven $SEVENTH_TAG is installed for $FF7_VERSION FINAL FANTASY VII.$steam_note"
}
