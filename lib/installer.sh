# shellcheck shell=bash
# The install task: finding FF7, preparing 7th Heaven's prefix, installing and configuring 7th Heaven,
# its launcher and its Steam entry. Running it again updates or repairs the install.

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

# Every question comes first; once the work starts, only the GOG or CD installer's own windows remain.
run_install() {
  local labels line pick previous steam_note restore_file status installed_for
  ensure_droiddeck_proton

  step "Finding FINAL FANTASY VII"
  APPID='' GAME_COPY=0 GAME_COPY_ACTION=none FF7_VERSION=''
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

  # 7th Heaven always gets a prefix of its own, made by DroidDeck-Proton. The game is reached through
  # Z: (Proton maps it to /), or C: when copied in, so no other prefix - Steam's FF7 prefix included -
  # is ever touched.
  COMPATDATA=$DEDICATED
  select_seventh_heaven
  case $SOURCE_KIND in
    steam|gog|folder)
      ask_game_copy "$COMPATDATA"
      ask_ff7_version ;;
  esac
  ask_seventh_install "$COMPATDATA"
  # An install that is about to change can be backed up first; a fresh one can get a backup restored.
  BACKUP_WANT=0 restore_file=''
  if [ -f "$STATE_FILE" ] && [ -f "$(seventh_exe "$COMPATDATA")" ]; then
    ask_backup
  elif [ "$NO_BACKUP" != 1 ] && [ "$ASSUME_YES" != 1 ]; then
    # checked now, so a damaged backup is found before the install rather than after it
    while choose_backup restore_file "Restore a backup when the install is done?" "Don't restore" \
          && [ -n "$restore_file" ] && ! backup_ok "$restore_file"; do
      pause "That backup is damaged or incomplete, so it can't be restored. Choose another one."
      restore_file=''
    done
  fi

  if [ "$BACKUP_WANT" = 1 ]; then
    make_backup || die "The backup failed, so nothing was changed. See $LOG_FILE, or run again with --no-backup."
  fi

  step "Choosing the Proton prefix"
  info "7th Heaven's own prefix: $COMPATDATA"
  previous=$(load_state 2>/dev/null && printf '%s' "$COMPATDATA")
  if [ -n "$previous" ] && [ "$previous" != "$COMPATDATA" ]; then
    info "An older $APP_NAME installed 7th Heaven into $previous. That prefix is left as it is."
    info "If it is a Steam game's prefix and the game misbehaves, delete that folder and Steam recreates it."
  fi
  pin_proton "$PREFIX_ID"
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
      install_pending_game "$COMPATDATA"
      ask_ff7_version ;;
    *) copy_game "$COMPATDATA" ;;
  esac
  prefix_extras "$COMPATDATA" "$APPID"

  step "Installing 7th Heaven"
  install_seventh_heaven "$COMPATDATA"
  # before configure_seventh_heaven, while settings.xml still names the exe 7th Heaven itself chose
  update_old_ffnx "$COMPATDATA" || warn "FFNx is too old for this 7th Heaven, which won't start FF7 until it's updated: Update or repair again, or use 7th Heaven's FFNx Check for Updates (Settings > General Settings)."
  configure_seventh_heaven "$COMPATDATA" "$GAME_EXE" "$FF7_VERSION"

  write_launcher "$(seventh_exe "$COMPATDATA")" "$(ff7_steam_appid)"
  [ "$DRY_RUN" = 1 ] || save_state SOURCE_KIND APPID GAME_DIR GAME_EXE GAME_COPY COMPATDATA FF7_VERSION SEVENTH_CHANNEL SEVENTH_TAG
  remove_old_entries
  if [ -n "$restore_file" ]; then
    status=0
    restore_backup "$restore_file" || status=$?
    case $status in
      0) ;;
      2) warn "Nothing was restored: the backup is damaged or incomplete. \"Restore a backup\" in $APP_NAME's menu can restore another one." ;;
      *) warn "The backup could not be fully restored; see the log. \"Restore a backup\" in $APP_NAME's menu tries again." ;;
    esac
  fi
  if [ -n "$(ff7_steam_appid)" ]; then
    step "Adding 7th Heaven to Steam"
    add_steam_shortcut || true
  fi

  step "Done"
  installed_for="7th Heaven $SEVENTH_TAG is installed for FINAL FANTASY VII, $(ff7_release_label "$FF7_VERSION")."
  ok "$installed_for"
  info "Start it from $APP_NAME's menu."
  steam_note=''
  if [ -n "$(ff7_steam_appid)" ]; then
    steam_note="

For Steam achievements, choose \"Launch 7th Heaven with Steam\" in $APP_NAME's menu."
    info "${steam_note#$'\n\n'}"
  fi
  info "Prefix: $COMPATDATA"
  info "Log: $LOG_FILE"
  ui_done "$installed_for$steam_note"
}

# Which FF7 release GAME_EXE is, asked only when nothing about the game tells.
ask_ff7_version() {
  local pick
  [ -n "$FF7_VERSION" ] && return 0
  FF7_VERSION=$(ff7_version_for "$APPID" "$GAME_EXE")
  [ -n "$FF7_VERSION" ] && return 0
  choose pick "Which release of FF7 is in $GAME_DIR?" "GOG" "Steam (2026 release)"
  [ "$pick" = 0 ] && FF7_VERSION=GOG || FF7_VERSION=SteamReRelease
}
