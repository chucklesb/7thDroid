# shellcheck shell=bash
# Starting 7th Heaven: the launcher script 7thDroid's menu runs, and the Steam library entry behind
# "Launch 7th Heaven with Steam" (Steam copies only). 7thDroid adds no other shortcuts.

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
# What 7th Heaven and Proton print goes to the launch log; the previous launch's is kept beside it.
log=$(printf '%q' "$STATE_DIR/launch.log")
mkdir -p "\${log%/*}"
[ -f "\$log" ] && mv -f -- "\$log" "\$log.1"
exec >>"\$log" 2>&1
how="from $APP_NAME or a shell"
[ -n "\${SteamGameId:-}" ] && how="by Steam (game \$SteamGameId)"
echo "== \$(date '+%Y-%m-%d %H:%M:%S') 7th Heaven started \$how"
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

# add_steam_shortcut [ask] - Steam rewrites its shortcuts when it exits, so it has to be closed. With
# "ask", a running Steam is a question to close it and retry; without, the entry is left for later.
add_steam_shortcut() {
  [ "$HAVE_SHORTCUTS_TOOL" = 1 ] || { warn "droiddeck-steam-shortcuts is missing; skipping the Steam shortcut."; return 1; }
  while steam_running; do
    if [ "${1:-}" != ask ]; then
      info "Steam is running, so 7th Heaven's Steam entry is added the first time you choose \"Launch 7th Heaven with Steam\" in $APP_NAME."
      return 1
    fi
    warn "Steam is running. It rewrites its shortcuts when it exits, so it has to be closed first."
    if [ "$ASSUME_YES" = 1 ] || ! ask_yn "Close Steam now, then answer yes to retry (no skips this step)" y; then
      info "Skipped."
      return 1
    fi
  done
  info "Steam: non-Steam game \"$LAUNCHER_NAME\""
  [ "$DRY_RUN" = 1 ] && return 0
  local id
  id=$(python "$LIB_DIR/steam_shortcut.py" add "$SHORTCUTS_TOOL" "$STEAM_ROOT" "$LAUNCHER_NAME" "$LAUNCHER" "$DATA_DIR" "$ICON") \
    || { warn "Could not add the Steam shortcut."; return 1; }
  debug "Steam shortcut id $id"
  info "If Steam starts it with Proton, turn off Properties > Compatibility for \"$LAUNCHER_NAME\": it is a Linux script."
}

# The DroidDeck app tile and KDE menu entry earlier versions added; launching is from the menu now.
remove_old_entries() {
  local desktop=${XDG_DATA_HOME:-$HOME/.local/share}/applications/7th-heaven.desktop
  if [ -f "$APPS_DIR/$APP_ENTRY_ID/entry" ] && [ "$(readlink "$APPS_DIR/$APP_ENTRY_ID/files")" = "$DATA_DIR" ]; then
    remove_tree "$APPS_DIR/$APP_ENTRY_ID"
  fi
  if grep -qsF "$LAUNCHER" "$desktop"; then
    info "Removing $desktop"
    run rm -f -- "$desktop"
  fi
  return 0
}

want_entry() {
  case ${!1} in
    1) return 0 ;;
    0) return 1 ;;
  esac
  ask_yn "$2" "${3:-y}"
}
