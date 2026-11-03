# shellcheck shell=bash
# Ways to start 7th Heaven: the launcher script itself, the DroidDeck app's Desktop page, Steam and KDE.

LAUNCHER_NAME="7th Heaven"
LAUNCHER=$DATA_DIR/$LAUNCHER_NAME.sh
ICON=$DATA_DIR/7th-heaven.png
APP_ENTRY_ID=7thheaven

# The id of the prefix for a game that is not from Steam: the id Steam gives a shortcut to the launcher,
# so the prefix and the shortcut share compatdata/<id> as they would for any non-Steam game.
dedicated_prefix_id() {
  python "$LIB_DIR/steam_shortcut.py" appid "$LAUNCHER" "$LAUNCHER_NAME"
}

# The Steam app id of the FF7 copy 7th Heaven uses, when it is one from Steam; nothing otherwise.
ff7_steam_appid() {
  [ "${SOURCE_KIND:-}" = steam ] && [ -n "${APPID:-}" ] && printf '%s\n' "$APPID"
  return 0
}

# write_launcher EXE [STEAM_APPID]
write_launcher() {
  local exe=$1 steam_appid=${2:-} options='' why=''
  info "Launcher: $LAUNCHER"
  if [ -n "$steam_appid" ]; then
    [[ $steam_appid =~ ^[1-9][0-9]*$ ]] || die "Internal error: '$steam_appid' is not a Steam app id"
    # droiddeck-proton-run tells Steam a non-Steam prefix's programs are app 0; FFNx's Steam
    # Compatibility setting needs FF7's own id, and ff7.exe inherits it from 7th Heaven.
    options="--options 'SteamAppId=$steam_appid %command%' "
    why="
# FF7 is the Steam copy (app $steam_appid): the Steam API is told so, for achievements."
    info "FF7 is a Steam copy: 7th Heaven starts as Steam app $steam_appid."
  fi
  [ "$DRY_RUN" = 1 ] && return 0
  mkdir -p "$DATA_DIR"
  cp -f "$ASSETS_DIR/7th-heaven.png" "$ICON"
  cat > "$LAUNCHER" <<EOF
#!/bin/bash
# Starts 7th Heaven in its Proton prefix. Written by $APP_NAME; re-running the installer replaces it.
# 7th Heaven loads mods through a dinput.dll beside the game, which Wine must prefer to its own.$why
export WINEDLLOVERRIDES="dinput=n,b\${WINEDLLOVERRIDES:+;\$WINEDLLOVERRIDES}"
proton_run=\$(command -v droiddeck-proton-run || echo $(printf '%q' "$PROTON_RUN"))
exec "\$proton_run" $options$(printf '%q' "$exe") "\$@"
EOF
  chmod +x "$LAUNCHER"
}

# Is 7th Heaven in Steam as a non-Steam game?
has_steam_shortcut() {
  [ -f "$SHORTCUTS_TOOL" ] && python "$LIB_DIR/steam_shortcut.py" has "$SHORTCUTS_TOOL" "$STEAM_ROOT" "$LAUNCHER" 2>/dev/null
}

# Starts 7th Heaven's Steam shortcut through Steam, as DroidDeck's own desktop entries start games:
# the desktop's Steam client on the KDE desktop, Steam's Big Picture otherwise.
steam_launch_shortcut() {
  local ui=bigpicture id
  [ "${BL_DESKTOP:-}" = 1 ] && ui=desktop
  id=$(python "$LIB_DIR/steam_shortcut.py" gameid "$LAUNCHER" "$LAUNCHER_NAME") || return 1
  "$STEAM_LAUNCH" "$ui" "steam://rungameid/$id"
}

add_app_entry() {
  local dir=$APPS_DIR/$APP_ENTRY_ID
  [ "$HAVE_APPS_DIR" = 1 ] || { warn "$APPS_DIR is missing; skipping the DroidDeck app entry."; return; }
  info "DroidDeck app: Desktop page entry $dir"
  [ "$DRY_RUN" = 1 ] && return 0
  mkdir -p "$dir"
  ln -sfn "$DATA_DIR" "$dir/files"
  printf '%s\n' "$LAUNCHER_NAME.sh" > "$dir/entry"
  printf '%s\n' "$LAUNCHER_NAME" > "$dir/name"
  printf 'off\n' > "$dir/fex"
  cp -f "$ASSETS_DIR/7th-heaven.png" "$dir/icon.png"
}

add_desktop_entry() {
  local apps=${XDG_DATA_HOME:-$HOME/.local/share}/applications
  info "KDE menu: $apps/7th-heaven.desktop"
  [ "$DRY_RUN" = 1 ] && return 0
  mkdir -p "$apps"
  cat > "$apps/7th-heaven.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$LAUNCHER_NAME
Comment=Final Fantasy VII mod manager
Exec=bash "$LAUNCHER"
Path=$DATA_DIR
Icon=$ICON
Categories=Game;
Terminal=false
EOF
  have update-desktop-database && update-desktop-database "$apps" >/dev/null 2>&1 || true
}

add_steam_shortcut() {
  [ "$HAVE_SHORTCUTS_TOOL" = 1 ] || { warn "droiddeck-steam-shortcuts is missing; skipping the Steam shortcut."; return; }
  while steam_running; do
    warn "Steam is running. It rewrites its shortcuts when it exits, so it has to be closed first."
    if [ "$ASSUME_YES" = 1 ] || ! ask_yn "Close Steam now, then answer yes to retry (no skips this step)" y; then
      info "Skipped. Later, with Steam closed, choose \"Add or recreate shortcuts\" in $APP_NAME."
      return
    fi
  done
  info "Steam: non-Steam game \"$LAUNCHER_NAME\""
  [ "$DRY_RUN" = 1 ] && return 0
  local id
  id=$(python "$LIB_DIR/steam_shortcut.py" add "$SHORTCUTS_TOOL" "$STEAM_ROOT" "$LAUNCHER_NAME" "$LAUNCHER" "$DATA_DIR" "$ICON") \
    || { warn "Could not add the Steam shortcut."; return; }
  debug "Steam shortcut id $id"
  info "If Steam starts it with Proton, turn off Properties > Compatibility for \"$LAUNCHER_NAME\": it is a Linux script."
}

# offer_shortcuts - each entry is optional, asked in one list; flags preset the answer.
offer_shortcuts() {
  step "Adding shortcuts"
  # The 7thDroid AppImage's own tile already launches 7th Heaven, so a second one is opt-in there.
  local app_default=1
  [ -n "${SEVENTHDROID_APPIMAGE:-}" ] && app_default=0
  ask_checklist "Which shortcuts to 7th Heaven should $APP_NAME add?" \
    WANT_APP_ENTRY "A separate 7th Heaven tile on the DroidDeck app's Desktop page" "$app_default" \
    WANT_STEAM "7th Heaven in Steam, as a non-Steam game" 1 \
    WANT_DESKTOP "7th Heaven in the KDE desktop's application menu" 1
  [ "$WANT_APP_ENTRY" = 1 ] && add_app_entry
  [ "$WANT_STEAM" = 1 ] && add_steam_shortcut
  [ "$WANT_DESKTOP" = 1 ] && add_desktop_entry
  return 0
}

want_entry() {
  case ${!1} in
    1) return 0 ;;
    0) return 1 ;;
  esac
  ask_yn "$2" "${3:-y}"
}
