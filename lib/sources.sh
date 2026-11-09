# shellcheck shell=bash
# Finding FINAL FANTASY VII. Each detector prints one line per install found:
#   kind <TAB> appid <TAB> game folder <TAB> compatdata (Steam only) <TAB> label

FF7_STEAM_2013=39140
FF7_STEAM_2026=3837340
FF7_GOG=1698970154

HEROIC_CONFIGS=(
  "${XDG_CONFIG_HOME:-$HOME/.config}/heroic"
  "$HOME/.var/app/com.heroicgameslauncher.hgl/config/heroic"
)
LUTRIS_DATA=(
  "${XDG_DATA_HOME:-$HOME/.local/share}/lutris"
  "$HOME/.var/app/net.lutris.Lutris/data/lutris"
)
DROIDDECK_STORE_GLOBS=(
  "$HOME/Games/Stores/GOG/*"
  "/root/Games/Stores/GOG/*"
  "/mnt/droiddeck-sd/Games/GOG/*"
  "/mnt/droiddeck-stores/*/GOG/*"
)

# find_game_exe DIR -> the game's executable. 7th Heaven's own ff7/workingdir copy is never picked.
find_game_exe() {
  python - "$1" <<'EOF'
import os, sys
root = sys.argv[1]
rank = {"ffvii.exe": 0, "ff7_en.exe": 1, "ff7.exe": 2}
best = None
for folder, dirs, files in os.walk(root):
    depth = os.path.relpath(folder, root).count(os.sep) + (folder != root)
    dirs[:] = [d for d in dirs if d.lower() not in ("workingdir", "7thworkshop", "mods", "resources", "7th heaven", "windows")] if depth < 4 else []
    for name in files:
        if name.lower() in rank:
            key = (depth, rank[name.lower()])
            if best is None or key < best[0]:
                best = (key, os.path.join(folder, name))
if best:
    print(best[1])
EOF
}

detect_steam() {
  local appid found lib dir label
  for appid in $FF7_STEAM_2013 $FF7_STEAM_2026; do
    found=$(steam_app_installed "$appid") || continue
    lib=${found%%$'\t'*}
    dir=${found#*$'\t'}
    [ "$appid" = $FF7_STEAM_2013 ] && label="Steam (2013 release)" || label="Steam (2026 release)"
    printf 'steam\t%s\t%s\t%s\t%s\n' "$appid" "$dir" "$lib/steamapps/compatdata/$appid" "$label - $dir"
  done
}

detect_droiddeck_gog() {
  local pattern folder
  for pattern in "${DROIDDECK_STORE_GLOBS[@]}"; do
    for folder in $pattern; do
      [ -f "$folder/.droiddeck-store.json" ] || continue
      python - "$folder/.droiddeck-store.json" "$FF7_GOG" <<'EOF' || continue
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
ok = str(data.get("store", "")).lower() == "gog" and str(data.get("id")) == sys.argv[2] and not data.get("state")
sys.exit(0 if ok else 1)
EOF
      printf 'gog\t%s\t%s\t\t%s\n' "$FF7_GOG" "$folder" "GOG via the DroidDeck app - $folder"
    done
  done | sort -u
}

detect_heroic() {
  local config flavor
  for config in "${HEROIC_CONFIGS[@]}"; do
    [ -d "$config" ] || continue
    case $config in */.var/app/*) flavor=Flatpak ;; *) flavor="AppImage/native" ;; esac
    python - "$config" "$FF7_GOG" <<'EOF' | while IFS= read -r dir; do
import json, os, sys
config, appid = sys.argv[1], sys.argv[2]
found = None
try:
    with open(os.path.join(config, "gog_store", "installed.json"), encoding="utf-8") as f:
        data = json.load(f)
    for game in data.get("installed", []) if isinstance(data, dict) else data:
        if str(game.get("appName")) == appid and game.get("install_path"):
            found = game["install_path"]
except (OSError, ValueError, AttributeError):
    pass
if found and os.path.isdir(found):
    print(found)
EOF
      printf 'gog\t%s\t%s\t\t%s\n' "$FF7_GOG" "$dir" "GOG via Heroic ($flavor) - $dir"
    done
  done
}

detect_lutris() {
  local data flavor
  for data in "${LUTRIS_DATA[@]}"; do
    [ -f "$data/pga.db" ] || continue
    case $data in */.var/app/*) flavor=Flatpak ;; *) flavor="native/AppImage" ;; esac
    python - "$data/pga.db" "$FF7_GOG" <<'EOF' | while IFS= read -r dir; do
import os, sqlite3, sys
db, appid = sys.argv[1], sys.argv[2]
try:
    con = sqlite3.connect("file:%s?mode=ro" % db, uri=True)
    cols = {row[1] for row in con.execute("PRAGMA table_info(games)")}
    where = "(slug LIKE 'final-fantasy-vii%' AND slug NOT LIKE '%remake%')"
    if {"service", "service_id"} <= cols:
        where = "((service = 'gog' AND service_id = ?) OR %s)" % where
        rows = con.execute("SELECT directory FROM games WHERE installed = 1 AND " + where, (appid,))
    else:
        rows = con.execute("SELECT directory FROM games WHERE installed = 1 AND " + where)
    for (directory,) in rows:
        if directory and os.path.isdir(directory):
            print(directory)
except sqlite3.Error:
    pass
EOF
      # Lutris's directory may be a Wine prefix with the game inside; point at the executable's folder.
      local exe
      exe=$(find_game_exe "$dir")
      [ -n "$exe" ] || continue
      printf 'gog\t%s\t%s\t\t%s\n' "$FF7_GOG" "${exe%/*}" "GOG via Lutris ($flavor) - ${exe%/*}"
    done
  done
}

detect_all() {
  { detect_steam; detect_droiddeck_gog; detect_heroic; detect_lutris; } | awk -F'\t' '!seen[$3]++'
}

# ff7_release_label VERSION -> how a person names that release (VERSION is 7th Heaven's FF7InstalledVersion)
ff7_release_label() {
  case $1 in
    Steam) echo "Steam (2013 release)" ;;
    SteamReRelease) echo "Steam (2026 release)" ;;
    GOG) echo GOG ;;
    Original98) echo "1998 PC release" ;;
    *) echo "$1" ;;
  esac
}

# ff7_version_for APPID EXE -> the FF7InstalledVersion 7th Heaven expects
ff7_version_for() {
  local appid=$1 exe=$2 dir
  dir=${exe%/*}
  case $appid in
    "$FF7_STEAM_2013") echo Steam; return ;;
    "$FF7_STEAM_2026") echo SteamReRelease; return ;;
    "$FF7_GOG") echo GOG; return ;;
  esac
  case ${exe##*/} in
    [Ff][Ff]7_[Ee][Nn].[Ee][Xx][Ee]) echo Steam ;;
    [Ff][Ff]7.[Ee][Xx][Ee]) echo Original98 ;;
    *)
      if compgen -G "$dir/goggame-*.info" >/dev/null; then echo GOG
      elif grep -qs "$FF7_STEAM_2026" "$dir/steam_appid.txt"; then echo SteamReRelease
      else echo ""
      fi ;;
  esac
}
