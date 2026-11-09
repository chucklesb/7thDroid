# shellcheck shell=bash
# FFNx, the game driver 7th Heaven installs into the FF7 folder on the first Play. 7th Heaven 4.6 needs
# FFNx 1.25 or newer (it checks FFNx_steam_api.dll before every launch), but updating 7th Heaven leaves
# an older FFNx in place, so 7thDroid updates one that is too old.

FFNX_API=${FFNX_API:-https://api.github.com/repos/julianxhokaxhiu/FFNx}

ffnx_settings_xml() { printf '%s\n' "$1/pfx/drive_c/7th Heaven/7thWorkshop/settings.xml"; }

# ffnx_state COMPATDATA -> none, old or current (nothing when 7th Heaven has no settings yet)
ffnx_state() {
  local settings
  settings=$(ffnx_settings_xml "$1")
  [ -f "$settings" ] || return 0
  python "$LIB_DIR/ffnx.py" driver "$settings" "$1/pfx/drive_c" 2>/dev/null | cut -f2
}

# update_old_ffnx COMPATDATA - installs the newest FFNx of 7th Heaven's FFNx channel over one that is too
# old, keeping its FFNx.toml settings. Returns non-zero only when an old FFNx could not be updated.
update_old_ffnx() {
  local compatdata=$1 settings line folder state channel prefix api tag name url stamp archive
  settings=$(ffnx_settings_xml "$compatdata")
  [ -f "$settings" ] || return 0
  line=$(python "$LIB_DIR/ffnx.py" driver "$settings" "$compatdata/pfx/drive_c") || return 0
  IFS=$'\t' read -r folder state channel prefix <<< "$line"
  [ "$state" = old ] || return 0

  step "Updating FFNx"
  info "FFNx in $folder is older than 7th Heaven needs (FFNx 1.25 or newer)."
  [ "$channel" = Canary ] && api=releases/tags/canary || api=releases/latest
  line=$(curl -fsSL --retry 3 -H 'Accept: application/vnd.github+json' "$FFNX_API/$api" | python -c '
import json, re, sys
release = json.load(sys.stdin)
zips = [a for a in release.get("assets", []) if a["name"].startswith(sys.argv[1] + "-") and a["name"].lower().endswith(".zip")]
if zips:
    a = zips[0]
    stamp = re.sub(r"[^0-9]", "", a.get("updated_at", ""))[:12]
    print("\t".join((release.get("tag_name", ""), a["name"], a["browser_download_url"], stamp)))
' "$prefix") || true
  if [ -z "$line" ]; then
    warn "Could not look up the newest FFNx ($channel) on GitHub."
    return 1
  fi
  IFS=$'\t' read -r tag name url stamp <<< "$line"
  # canary keeps its tag across builds; the asset date keeps cached copies apart
  [ "$channel" = Canary ] && name=ffnx-canary-$stamp-$name
  archive=$(download "$url" "$name") || { warn "Could not download FFNx $tag."; return 1; }
  if [ "$DRY_RUN" = 1 ]; then
    info "Would install FFNx $tag into $folder."
    return 0
  fi
  wait_prefix_idle "$compatdata" 60 || { warn "Something is still running in 7th Heaven's prefix. Close 7th Heaven and FF7 first."; return 1; }
  run python "$LIB_DIR/ffnx.py" install "$archive" "$folder" || { warn "Could not install FFNx $tag into $folder."; return 1; }
  ok "Updated FFNx in $folder to $tag, keeping its settings."
}
