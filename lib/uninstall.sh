# shellcheck shell=bash
# Removing what 7thDroid made, and nothing else: its prefix (7th Heaven, its mods and FF7 saves made
# through it), its launcher, its Steam entry, the tile and KDE entry earlier versions added, and its
# downloads. Game files are never touched.

# remove_tree PATH - only paths 7thDroid owns get here; refuse anything that is not one of them.
remove_tree() {
  local path=$1
  case $path in
    "$DATA_DIR" | "$CACHE_DIR" | "$APPS_DIR/$APP_ENTRY_ID") ;;
    "$STEAM_ROOT/steamapps/compatdata/$PREFIX_ID") check_compatdata "$path" ;;
    *) die "Internal error: refusing to remove '$path'" ;;
  esac
  [ -e "$path" ] || [ -L "$path" ] || return 0
  info "Removing $path"
  run rm -rf -- "$path"
}

uninstall() {
  step "Uninstalling 7th Heaven"
  local prefix=$STEAM_ROOT/steamapps/compatdata/$PREFIX_ID
  if load_state 2>/dev/null && [ -n "${COMPATDATA:-}" ] && [ "$COMPATDATA" != "$prefix" ]; then
    info "An older $APP_NAME installed into $COMPATDATA. That prefix is not removed; delete it yourself if you no longer need it."
  fi
  ask_yn "Remove 7th Heaven, its mods, and any game saves made with it?

WARNING: THIS WILL PERMANENTLY DELETE ANY FF7 SAVES IN THE 7TH HEAVEN PREFIX." n \
    || { info "Nothing was removed."; return 1; }

  remove_old_entries
  if [ "$HAVE_SHORTCUTS_TOOL" = 1 ]; then
    if steam_running; then
      warn "Steam is running, so its \"$LAUNCHER_NAME\" shortcut was left. Remove it in Steam."
    else
      run python "$LIB_DIR/steam_shortcut.py" remove "$SHORTCUTS_TOOL" "$STEAM_ROOT" "$LAUNCHER" \
        || warn "Could not remove the Steam shortcut; remove it in Steam."
    fi
  fi
  run python "$LIB_DIR/proton_tool.py" forget "$DROIDDECK_BIN" "$PREFIX_ID" || true
  wait_prefix_idle "$prefix" 60 || die "Something is still running in 7th Heaven's prefix. Close 7th Heaven and FF7 first."
  remove_tree "$prefix"
  remove_tree "$CACHE_DIR"
  remove_tree "$DATA_DIR"
  ok "7th Heaven is uninstalled."
}
