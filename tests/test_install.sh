#!/bin/bash
# End-to-end runs of 7thdroid.sh against fixture trees. DroidDeck's own Python helpers come from a
# DroidDeck checkout (DROIDDECK_SRC); tests/stubs/droiddeck-proton-run stands in for running Wine.
set -u
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DROIDDECK_SRC=${DROIDDECK_SRC:-}
DD_BIN=$DROIDDECK_SRC/tools/linuxfs/overlay/usr/local/bin
[ -n "$DROIDDECK_SRC" ] && [ -f "$DD_BIN/steam-compatibility" ] \
  || { echo "Set DROIDDECK_SRC to a DroidDeck checkout (https://github.com/Droid-Deck/DroidDeck)." >&2; exit 2; }
FAILED=0 PASSED=0

pass() { PASSED=$((PASSED + 1)); printf '  ok   %s\n' "$1"; }
fail() { FAILED=$((FAILED + 1)); printf '  FAIL %s\n' "$1"; }
check() { local name=$1; shift; if "$@"; then pass "$name"; else fail "$name"; fi; }

# Removes the current fixture home, which is always a mktemp directory. KEEP=1 leaves it for debugging.
cleanup() {
  [ -n "${KEEP:-}" ] && { echo "  kept $T"; return; }
  case ${T:-} in
    "${TMPDIR:-/tmp}"/tmp.?*) rm -rf -- "$T" ;;
  esac
}

# fixture NAME -> sets T (a fresh fake home) and the environment 7thdroid.sh reads
fixture() {
  T=$(mktemp -d)
  export HOME=$T XDG_CONFIG_HOME=$T/.config XDG_DATA_HOME=$T/.local/share XDG_CACHE_HOME=$T/.cache XDG_STATE_HOME=$T/.local/state
  export STEAM_ROOT=$T/.local/share/Steam STUB_LOG=$T/stub.log
  export DROIDDECK_PROTON_RUN=$REPO/tests/stubs/droiddeck-proton-run
  export DROIDDECK_INNOEXTRACT=$T/none DROIDDECK_MSITOOLS=$T/none
  export DROIDDECK_APPS_DIR=$T/opt/droiddeck-apps
  export DROIDDECK_BIN=$DD_BIN DROIDDECK_PROTON_EXTRA=$REPO/tests/stubs/droiddeck-proton-extra
  export SEVENTH_API=file://$REPO/tests/fixtures/7th-heaven FFNX_API=file://$REPO/tests/fixtures/ffnx
  export SEVENTHDROID_BACKUP_DIR=$T/backups SEVENTHDROID_LOGS_DIR=$T/logs DROIDDECK_LOG_DIR=$T/ddlogs REDACT_ROOT=$T
  unset STUB_PROTON_EXTRA_FAIL DROIDDECK_STEAM_SHORTCUTS STUB_INNO_LAYOUT
  mkdir -p "$STEAM_ROOT/steamapps" "$DROIDDECK_APPS_DIR" "$STEAM_ROOT/config" "$STEAM_ROOT/userdata/12345/config"
  cp "$REPO/tests/fixtures/config.vdf" "$STEAM_ROOT/config/config.vdf"
  printf '"users"\n{\n\t"76561197960278073"\n\t{\n\t\t"MostRecent"\t"1"\n\t}\n}\n' > "$STEAM_ROOT/config/loginusers.vdf"
  # cached downloads, so no test touches the network
  mkdir -p "$XDG_CACHE_HOME/7thdroid"
  for f in 7thHeaven-v4.6.0.0_Release.exe canary-202611011640-7thHeaven-v4.6.0.1_Release.exe windowsdesktop-runtime-10.0-win-{x64,x86}.exe; do
    echo stub > "$XDG_CACHE_HOME/7thdroid/$f"
  done
  : > "$STUB_LOG"
  if [ "${1:-}" = no-proton ]; then
    python3 "$DD_BIN/steam-compatibility" "$STEAM_ROOT" > /dev/null
  else
    droiddeck_proton
  fi
}

# A DroidDeck-Proton build, registered by DroidDeck's steam-compatibility as on a device.
droiddeck_proton() {
  python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); from fake_proton import make_tool; make_tool(sys.argv[2], "DroidDeck-Proton-11-11.9")' \
    "$REPO/tests/stubs" "$STEAM_ROOT/compatibilitytools.d"
  python3 "$DD_BIN/steam-compatibility" "$STEAM_ROOT" > /dev/null
}

# 7thDroid's prefix for this fixture home
own_prefix() {
  printf '%s/steamapps/compatdata/%s\n' "$STEAM_ROOT" \
    "$(python3 "$REPO/lib/steam_shortcut.py" appid "$T/.local/share/7thdroid/7th Heaven.sh" "7th Heaven")"
}

# A checksum of every prefix but 7thDroid's, to show none was touched.
other_prefixes() {
  find "$STEAM_ROOT/steamapps/compatdata" "$T/sd/steamapps/compatdata" -mindepth 1 -path "$(own_prefix)" -prune -o -print 2>/dev/null \
    | sort | while IFS= read -r f; do printf '%s ' "$f"; [ -f "$f" ] && md5sum < "$f" || echo; done | md5sum
}

steam_game() { # LIBRARY APPID INSTALLDIR EXE
  mkdir -p "$1/steamapps/common/$3" "$1/steamapps/compatdata/$2/pfx/drive_c/users/steamuser/Documents"
  touch "$1/steamapps/common/$3/$4"
  printf 'WINE REGISTRY Version 2\n' > "$1/steamapps/compatdata/$2/pfx/system.reg"
  printf 'WINE REGISTRY Version 2\n\n#arch=win64\n' > "$1/steamapps/compatdata/$2/pfx/user.reg"
  printf '"AppState"\n{\n\t"appid"\t\t"%s"\n\t"StateFlags"\t\t"4"\n\t"installdir"\t\t"%s"\n}\n' "$2" "$3" > "$1/steamapps/appmanifest_$2.acf"
}

installer() { bash "$REPO/7thdroid.sh" --install --yes --version stable --no-copy-game "$@" > "$T/out.log" 2>&1; }
settings() { cat "$1/pfx/drive_c/7th Heaven/7thWorkshop/settings.xml"; }

# old_ffnx DIR - FFNx 1.24 as 7th Heaven 4.5 installed it on the first Play: steam_api.dll, not
# FFNx_steam_api.dll. Also puts FFNx 1.25.2 (the fixture's newest) in the download cache.
old_ffnx() {
  rm -f "$1/FFNx_steam_api.dll"
  echo old > "$1/AF3DN.P"
  touch "$1/steam_api.dll"
  printf 'renderer_backend = 5\nenable_steam_achievements = false\n' > "$1/FFNx.toml"
  python3 -c '
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w") as z:
    z.writestr("AF3DN.P", "FFNx 1.25.2")
    z.writestr("FFNx_steam_api.dll", "api")
    z.writestr("shaders/a.bin", "shader")
    z.writestr("FFNx.toml", "# FFNx config file\r\nrenderer_backend = 0\r\nenable_steam_achievements = false\r\nnew_key = true\r\n")
' "$XDG_CACHE_HOME/7thdroid/FFNx-Steam-v1.25.2.0.zip" || exit 2
}

# tar_names FILE -> the entries of a backup, one per line
tar_names() { python3 -c 'import sys, tarfile; print("\n".join(tarfile.open(sys.argv[1]).getnames()))' "$1"; }
backups() { find "$T/backups" -maxdepth 1 -name '7thDroid-*.tar' 2>/dev/null | sort; }
# has_entries NAME... - each NAME is an entry of the backup listed in NAMES
has_entries() { local n; for n in "$@"; do grep -qxF "$n" <<< "$NAMES" || return 1; done; }

# tar_text FILE -> every entry of a tar, name line then contents, for searching
tar_text() { python3 -c 'import sys, tarfile
t = tarfile.open(sys.argv[1])
for m in t.getmembers():
    if m.isfile():
        print("== " + m.name)
        print(t.extractfile(m).read().decode("utf-8", "replace"))' "$1"; }
log_bundles() { find "$T/logs" -maxdepth 1 -name '7thDroid-logs-*.tar' 2>/dev/null | sort; }

# windowed SCRIPT ANSWER... -> runs SCRIPT (with ARGS) as the AppImage does: no terminal, the zenity stub
windowed() {
  local script=$1
  shift
  printf '%s\n' "$@" > "$T/answers"
  rm -f "$T/answers.n"
  : > "$T/zenity.log"
  UI_ZENITY=$REPO/tests/stubs/zenity STUB_ZENITY_LOG=$T/zenity.log STUB_ZENITY_ANSWERS=$T/answers SEVENTHDROID_APPIMAGE=1 \
    timeout 300 bash "$REPO/$script" "${ARGS[@]}" < /dev/null > "$T/out.log" 2>&1
}

heroic_game() {
  mkdir -p "$T/Games/Heroic/FINAL FANTASY VII" "$T/.config/heroic/gog_store"
  touch "$T/Games/Heroic/FINAL FANTASY VII/FFVII.exe"
  printf '{"installed":[{"appName":"1698970154","install_path":"%s"}]}' "$T/Games/Heroic/FINAL FANTASY VII" \
    > "$T/.config/heroic/gog_store/installed.json"
}

echo "Steam 2026 release in a second library"
fixture
mkdir -p "$T/sd"
printf '"libraryfolders"\n{\n\t"0"\n\t{\n\t\t"path"\t\t"%s"\n\t}\n\t"1"\n\t{\n\t\t"path"\t\t"%s"\n\t}\n}\n' "$STEAM_ROOT" "$T/sd" > "$STEAM_ROOT/steamapps/libraryfolders.vdf"
steam_game "$T/sd" 3837340 "FINAL FANTASY VII" FFVII.exe
before=$(other_prefixes)
check "installer succeeds" installer
CD=$(own_prefix)
check "Steam's FF7 prefix untouched" test "$(other_prefixes)" = "$before"
check "installers ran in 7thDroid's own prefix" grep -q $'run\t'"${CD##*/}"$'\t7thHeaven-v4.6.0.0_Release.exe\t0' "$STUB_LOG"
check "nothing ran in another prefix" bash -c "! cut -f2 '$STUB_LOG' | grep -vqx '${CD##*/}'"
check "installers ran with full x87 precision" bash -c "! cut -f4 '$STUB_LOG' | grep -vqx 0"
# Pinned, or already DroidDeck's default (newer DroidDecks make it so); the Valve-default case tests the pin.
check "the prefix runs with DroidDeck-Proton" grep -q "Prefix ${CD##*/} runs with DroidDeck-Proton" "$T/.local/state/7thdroid/install.log"
check ".NET 10 x64 (ARM64 layout)" test -d "$CD/pfx/drive_c/Program Files/dotnet/x64/shared/Microsoft.WindowsDesktop.App/10.0.14"
check ".NET 10 x86" test -d "$CD/pfx/drive_c/Program Files (x86)/dotnet/shared/Microsoft.WindowsDesktop.App/10.0.14"
check ".NET installed before 7th Heaven" bash -c "grep -n . '$STUB_LOG' | grep -m1 -q '^1:.*windowsdesktop-runtime-10.0-win-x64'"
check "Avalon.Graphics in user.reg" grep -q '"DisableHWAcceleration"=dword:00000001' "$CD/pfx/user.reg"
check "dinput override in user.reg" grep -q '"dinput"="native,builtin"' "$CD/pfx/user.reg"
check "FF7Exe is the game's FFVII.exe" grep -qF "<FF7Exe>Z:${T//\//\\}\\sd\\steamapps\\common\\FINAL FANTASY VII\\FFVII.exe</FF7Exe>" <(settings "$CD")
check "version SteamReRelease" grep -q '<FF7InstalledVersion>SteamReRelease</FF7InstalledVersion>' <(settings "$CD")
check "timeout.exe" test -f "$CD/pfx/drive_c/windows/system32/timeout.exe"
check "launcher runs the prefix's 7th Heaven" grep -qF "$CD/pfx/drive_c/7th\\ Heaven/7th\\ Heaven.exe" "$T/.local/share/7thdroid/7th Heaven.sh"
check "launcher reports FF7's Steam app id" grep -qFe "--options 'SteamAppId=3837340 %command%'" "$T/.local/share/7thdroid/7th Heaven.sh"
check "no app tile or KDE entry" test ! -e "$T/opt/droiddeck-apps/7thheaven" -a ! -e "$T/.local/share/applications/7th-heaven.desktop"
check "Steam entry added for a Steam copy" python3 "$REPO/lib/steam_shortcut.py" has "$DD_BIN/droiddeck-steam-shortcuts" "$STEAM_ROOT" "$T/.local/share/7thdroid/7th Heaven.sh"
check "second run skips finished steps" bash -c "cp '$STUB_LOG' '$T/first.log'; bash '$REPO/7thdroid.sh' --install --yes --version stable --no-copy-game >/dev/null 2>&1 && cmp -s '$STUB_LOG' '$T/first.log'"
cleanup

echo "Steam 2013 release"
fixture
steam_game "$STEAM_ROOT" 39140 "FINAL FANTASY VII" ff7_en.exe
before=$(other_prefixes)
check "installer succeeds" installer
CD=$(own_prefix)
check "Steam's FF7 prefix untouched" test "$(other_prefixes)" = "$before"
check "Z: path to ff7_en.exe" grep -qF "<FF7Exe>Z:${STEAM_ROOT//\//\\}\steamapps\common\FINAL FANTASY VII\ff7_en.exe</FF7Exe>" <(settings "$CD")
check "version Steam" grep -q '<FF7InstalledVersion>Steam</FF7InstalledVersion>' <(settings "$CD")
check "launcher reports app 39140" grep -qFe "--options 'SteamAppId=39140 %command%'" "$T/.local/share/7thdroid/7th Heaven.sh"
check "user slot" test -d "$CD/pfx/drive_c/users/steamuser/Documents/Square Enix/FINAL FANTASY VII Steam/user_12345678"
cleanup

echo "Steam 2013 release copied into the prefix"
fixture
steam_game "$STEAM_ROOT" 39140 "FINAL FANTASY VII" ff7_en.exe
check "installer succeeds" installer --copy-game
CD=$(own_prefix)
COPY="$CD/pfx/drive_c/FINAL FANTASY VII"
check "game copied into the prefix" test -f "$COPY/ff7_en.exe"
check "FF7Exe is the copy, on C:" grep -qF '<FF7Exe>C:\FINAL FANTASY VII\ff7_en.exe</FF7Exe>' <(settings "$CD")
check "still the Steam release" grep -q '<FF7InstalledVersion>Steam</FF7InstalledVersion>' <(settings "$CD")
check "launcher still reports app 39140" grep -qFe "--options 'SteamAppId=39140 %command%'" "$T/.local/share/7thdroid/7th Heaven.sh"
check "the copy is in the saved state" grep -qx 'GAME_COPY=1' "$T/.local/share/7thdroid/install.env"
check "original game folder unchanged" test "$(ls -A "$STEAM_ROOT/steamapps/common/FINAL FANTASY VII")" = ff7_en.exe
touch "$COPY/modded"
check "a re-run reuses the copy" bash -c "bash '$REPO/7thdroid.sh' --install --yes --version stable >/dev/null 2>&1 && test -f '$COPY/modded' && grep -qF 'C:\\FINAL FANTASY VII' '$CD/pfx/drive_c/7th Heaven/7thWorkshop/settings.xml'"
check "--no-copy-game goes back to the original" bash -c "bash '$REPO/7thdroid.sh' --install --yes --version stable --no-copy-game >/dev/null 2>&1 && grep -qF 'steamapps\\common\\FINAL FANTASY VII\\ff7_en.exe' '$CD/pfx/drive_c/7th Heaven/7thWorkshop/settings.xml'"
cleanup

echo "GOG through Heroic (Flatpak)"
fixture
mkdir -p "$T/Games/Heroic/FINAL FANTASY VII" "$T/.var/app/com.heroicgameslauncher.hgl/config/heroic/gog_store"
touch "$T/Games/Heroic/FINAL FANTASY VII/FFVII.exe"
printf '{"installed":[{"appName":"1698970154","install_path":"%s","platform":"windows"}]}' "$T/Games/Heroic/FINAL FANTASY VII" \
  > "$T/.var/app/com.heroicgameslauncher.hgl/config/heroic/gog_store/installed.json"
check "installer succeeds" installer
check "detected as Heroic Flatpak" grep -q "GOG via Heroic (Flatpak)" "$T/out.log"
ID=$(python3 "$REPO/lib/steam_shortcut.py" appid "$T/.local/share/7thdroid/7th Heaven.sh" "7th Heaven")
check "dedicated prefix named after the shortcut id" test -f "$STEAM_ROOT/steamapps/compatdata/$ID/pfx/drive_c/7th Heaven/7th Heaven.exe"
check "first run used --prefix" grep -q $'run\t'"$ID"$'\twindowsdesktop-runtime-10.0-win-x64.exe' "$STUB_LOG"
check "version GOG" grep -q '<FF7InstalledVersion>GOG</FF7InstalledVersion>' <(settings "$STEAM_ROOT/steamapps/compatdata/$ID")
check "no Steam app id for GOG" bash -c "! grep -q SteamAppId '$T/.local/share/7thdroid/7th Heaven.sh'"
check "drive label" test "$(cat "$STEAM_ROOT/steamapps/compatdata/$ID/pfx/drive_c/.windows-label")" = FF7DISC1
cleanup

echo "GOG through Lutris and through the DroidDeck app"
fixture
mkdir -p "$T/Games/final-fantasy-vii/drive_c/GOG Games/FF7" "$T/.local/share/lutris" "$T/Games/Stores/GOG/FINAL FANTASY VII"
touch "$T/Games/final-fantasy-vii/drive_c/GOG Games/FF7/FFVII.exe" "$T/Games/Stores/GOG/FINAL FANTASY VII/FFVII.exe"
python3 -c "
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute('CREATE TABLE games (id INTEGER, slug TEXT, directory TEXT, installed INTEGER, service TEXT, service_id TEXT)')
con.execute('INSERT INTO games VALUES (1, ?, ?, 1, ?, ?)', ('final-fantasy-vii', sys.argv[2], 'gog', '1698970154'))
con.commit()" "$T/.local/share/lutris/pga.db" "$T/Games/final-fantasy-vii"
printf '{"version":1,"store":"gog","id":"1698970154","title":"FINAL FANTASY VII","exe":"FFVII.exe"}' > "$T/Games/Stores/GOG/FINAL FANTASY VII/.droiddeck-store.json"
check "installer succeeds" installer
check "DroidDeck store found" grep -q "GOG via the DroidDeck app" "$T/out.log"
check "Lutris found, game folder inside its prefix" grep -qF "GOG via Lutris (native/AppImage) - $T/Games/final-fantasy-vii/drive_c/GOG Games/FF7" "$T/out.log"
cleanup

echo "GOG installer, run because innoextract is missing"
fixture
mkdir -p "$T/Download"
echo stub > "$T/Download/setup_final_fantasy_vii_2.0_(gog).exe"
check "installer succeeds" installer --source "$T/Download/setup_final_fantasy_vii_2.0_(gog).exe" --game-dir "$T/Games/FF7"
check "GOG installer ran with full x87 precision" grep -q $'\tsetup_final_fantasy_vii_2.0_(gog).exe\t0\t' "$STUB_LOG"
check "game installed where asked" test -f "$T/Games/FF7/FFVII.exe"
cleanup

echo "GOG installer unpacked with innoextract"
fixture
export DROIDDECK_INNOEXTRACT=$REPO/tests/stubs/innoextract
mkdir -p "$T/Download" "$T/Games/FF7"
echo stub > "$T/Download/setup_final_fantasy_vii_2.0_(gog).exe"
touch "$T/Games/FF7/webcache.zip"   # left by an earlier, failed unpack
check "installer succeeds" installer --source "$T/Download/setup_final_fantasy_vii_2.0_(gog).exe" --game-dir "$T/Games/FF7"
check "the GOG installer was not run" bash -c "! grep -q setup_final_fantasy '$STUB_LOG'"
check "game at the top of the folder" test -f "$T/Games/FF7/FFVII.exe" -a -f "$T/Games/FF7/data/movies.lgp"
check "GOG support files merged in" test -f "$T/Games/FF7/goggame-1698970154.ico" -a -f "$T/Games/FF7/webcache.zip"
check "no app/ or tmp/ folder" test ! -e "$T/Games/FF7/app" -a ! -e "$T/Games/FF7/tmp"
check "no staging folder left" bash -c "! compgen -G '$T/Games/FF7.*'"
check "FF7Exe is the unpacked FFVII.exe" grep -qF "<FF7Exe>Z:${T//\//\\}\\Games\\FF7\\FFVII.exe</FF7Exe>" <(settings "$(own_prefix)")
cleanup

echo "GOG installer unpacked with the game under app/"
fixture
export DROIDDECK_INNOEXTRACT=$REPO/tests/stubs/innoextract STUB_INNO_LAYOUT=app
mkdir -p "$T/Download"
echo stub > "$T/Download/setup_final_fantasy_vii_2.0_(gog).exe"
check "installer succeeds" installer --source "$T/Download/setup_final_fantasy_vii_2.0_(gog).exe" --game-dir "$T/Games/FF7"
check "game moved out of app/" test -f "$T/Games/FF7/FFVII.exe" -a -f "$T/Games/FF7/goggame-1698970154.ico"
check "no tmp/ folder" test ! -e "$T/Games/FF7/tmp"
cleanup

echo "GOG installer whose unpacked files have no game"
fixture
export DROIDDECK_INNOEXTRACT=$REPO/tests/stubs/innoextract STUB_INNO_LAYOUT=empty
mkdir -p "$T/Download"
echo stub > "$T/Download/setup_final_fantasy_vii_2.0_(gog).exe"
check "installer succeeds" installer --source "$T/Download/setup_final_fantasy_vii_2.0_(gog).exe" --game-dir "$T/Games/FF7"
check "the GOG installer was run instead" grep -q $'\tsetup_final_fantasy_vii_2.0_(gog).exe\t0\t' "$STUB_LOG"
check "the unpacked files are listed in the log" grep -q "goggame-1698970154.ico" "$T/.local/state/7thdroid/install.log"
cleanup

echo ".NET in the x64-native layout is recognised"
fixture
mkdir -p "$T/FF7" "$(own_prefix)/pfx/drive_c/Program Files/dotnet/shared/Microsoft.WindowsDesktop.App/10.0.5"
touch "$T/FF7/FFVII.exe"
check "installer succeeds" installer --source "$T/FF7"
check "the x64 runtime was not installed again" bash -c "! grep -q 'win-x64' '$STUB_LOG'"
cleanup

echo "1998 CD-ROM from disc folders"
fixture
mkdir -p "$T/cd1/FF7" "$T/cd2/FF7"
echo stub > "$T/cd1/SETUP.EXE"
check "installer succeeds" installer --source "$T/cd1" --source "$T/cd2"
ID=$(python3 "$REPO/lib/steam_shortcut.py" appid "$T/.local/share/7thdroid/7th Heaven.sh" "7th Heaven")
PFX=$STEAM_ROOT/steamapps/compatdata/$ID/pfx
check "disc 2 mapped to e: through a link folder" test "$(readlink "$PFX/dosdevices/e:")" = "$T/.local/share/7thdroid/cd/drive2"
check "link folder reaches the disc" test "$(readlink "$T/.local/share/7thdroid/cd/drive2/FF7")" = "$T/cd2/FF7"
check "disc labels" test "$(cat "$T/.local/share/7thdroid/cd/drive2/.windows-label")" = FF7DISC2
check "the user's disc folders were not written to" test -z "$(find "$T/cd1" "$T/cd2" -name '.windows-*')"
check "CD drive type" grep -q '"e:"="cdrom"' "$PFX/system.reg"
check "version Original98" grep -q '<FF7InstalledVersion>Original98</FF7InstalledVersion>' <(settings "${PFX%/pfx}")
check "no Steam app id for the CD-ROM" bash -c "! grep -q SteamAppId '$T/.local/share/7thdroid/7th Heaven.sh'"
cleanup

echo "Steam entry (DroidDeck's shortcuts.vdf code) and Launch with Steam"
fixture
steam_game "$STEAM_ROOT" 39140 "FINAL FANTASY VII" ff7_en.exe
check "installer succeeds" installer
check "entry readable by DroidDeck and untagged" python3 - "$DD_BIN/droiddeck-steam-shortcuts" "$STEAM_ROOT/userdata/12345/config/shortcuts.vdf" "$T/.local/share/7thdroid/7th Heaven.sh" <<'EOF'
import runpy, sys
tool = runpy.run_path(sys.argv[1])
items = list(tool["parse"](open(sys.argv[2], "rb").read())["shortcuts"].values())
assert len(items) == 1 and items[0]["Exe"] == '"%s"' % sys.argv[3] and items[0]["tags"] == {}, items
EOF
check "re-adding replaces it" bash -c "bash '$REPO/7thdroid.sh' --yes --steam-shortcut >/dev/null 2>&1 && python3 - <<'EOF'
import runpy
tool = runpy.run_path('$DD_BIN/droiddeck-steam-shortcuts')
assert len(tool['parse'](open('$STEAM_ROOT/userdata/12345/config/shortcuts.vdf', 'rb').read())['shortcuts']) == 1
EOF"
check "--steam-shortcut keeps the Steam app id" grep -qFe "--options 'SteamAppId=39140 %command%'" "$T/.local/share/7thdroid/7th Heaven.sh"
GAME="$STEAM_ROOT/steamapps/common/FINAL FANTASY VII"
cat > "$T/steam-launch" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$STUB_LOG"
EOF
chmod +x "$T/steam-launch"
export DROIDDECK_STEAM_LAUNCH=$T/steam-launch
ARGS=()
check "menu before the first play: Quit" windowed 7thdroid.sh 7
check "no Launch with Steam before FFNx exists" bash -c "grep -m1 '^list' '$T/zenity.log' | grep -vqF 'with\\ Steam\\ FALSE'"
check "the menu says to play once first" bash -c "grep -m1 '^list' '$T/zenity.log' | grep -q 'appears.*here.*after.*that'"
printf 'renderer_backend = 5\nenable_steam_achievements = false\n' > "$GAME/FFNx.toml"
: > "$STUB_LOG"
check "menu: launch with Steam, once FFNx exists" windowed 7thdroid.sh 1
check "Steam asked to start the entry" grep -q 'steam://rungameid/' "$STUB_LOG"
check "Steam Compatibility on for a Steam launch" grep -qx 'enable_steam_achievements = true' "$GAME/FFNx.toml"
check "a chosen Graphics API is kept" grep -qx 'renderer_backend = 5' "$GAME/FFNx.toml"
check "menu: launch" windowed 7thdroid.sh 0
check "Steam Compatibility off without Steam" grep -qx 'enable_steam_achievements = false' "$GAME/FFNx.toml"
unset DROIDDECK_STEAM_LAUNCH
cleanup

echo "Steam running: the Steam entry waits, without a question"
fixture
steam_game "$STEAM_ROOT" 39140 "FINAL FANTASY VII" ff7_en.exe
# DroidDeck only applies the prefix's Proton choice with Steam closed, so a first install comes before
check "first install succeeds" installer
rm -f "$STEAM_ROOT/userdata/12345/config/shortcuts.vdf"
# a process named steam, as steam_running looks for
printf '#!/bin/bash\nwhile :; do sleep 1; done\n' > "$T/steam"
chmod +x "$T/steam"
"$T/steam" &
STEAM_PID=$!
check "update with Steam running succeeds" installer
kill "$STEAM_PID" 2>/dev/null; wait "$STEAM_PID" 2>/dev/null
check "entry left for Launch with Steam" grep -qF 'added the first time you choose "Launch 7th Heaven with Steam"' "$T/out.log"
check "no entry written" test ! -e "$STEAM_ROOT/userdata/12345/config/shortcuts.vdf"
cleanup

echo "Update removes the app tile and KDE entry earlier versions added"
fixture
mkdir -p "$T/FF7"
touch "$T/FF7/FFVII.exe"
check "installer succeeds" installer --source "$T/FF7"
mkdir -p "$DROIDDECK_APPS_DIR/7thheaven" "$T/.local/share/applications"
ln -s "$T/.local/share/7thdroid" "$DROIDDECK_APPS_DIR/7thheaven/files"
echo "7th Heaven.sh" > "$DROIDDECK_APPS_DIR/7thheaven/entry"
printf '[Desktop Entry]\nExec=bash "%s"\n' "$T/.local/share/7thdroid/7th Heaven.sh" > "$T/.local/share/applications/7th-heaven.desktop"
mkdir -p "$DROIDDECK_APPS_DIR/someone-else"
echo x > "$DROIDDECK_APPS_DIR/someone-else/entry"
check "update succeeds" installer --source "$T/FF7"
check "old app tile removed" test ! -e "$DROIDDECK_APPS_DIR/7thheaven"
check "old KDE entry removed" test ! -e "$T/.local/share/applications/7th-heaven.desktop"
check "other apps' tiles kept" test -f "$DROIDDECK_APPS_DIR/someone-else/entry"
cleanup

echo "DroidDeck-Proton missing: installed when accepted"
fixture no-proton
steam_game "$STEAM_ROOT" 39140 "FINAL FANTASY VII" ff7_en.exe
check "installer succeeds" installer
check "DroidDeck-Proton installed and registered" test -f "$STEAM_ROOT/compatibilitytools.d/DroidDeck-Proton-11-11.9/droiddeck-proton-wrap"
check "7th Heaven installed" test -f "$(own_prefix)/pfx/drive_c/7th Heaven/7th Heaven.exe"
check "DroidDeck made it the default, so no per-game pin" test ! -e "$T/.local/share/droiddeck-compat/games.json"
cleanup

echo "DroidDeck-Proton missing: install fails"
fixture no-proton
steam_game "$STEAM_ROOT" 39140 "FINAL FANTASY VII" ff7_en.exe
export STUB_PROTON_EXTRA_FAIL=1
check "stops" bash -c "! bash '$REPO/7thdroid.sh' --install --yes --version stable >'$T/out.log' 2>&1"
check "explains how to install it" grep -q 'droiddeck-proton-extra .* droiddeck' "$T/out.log"
check "no prefix made" test ! -e "$(own_prefix)"
cleanup

echo "Valve Proton kept as the user's default: only 7thDroid's prefix is pinned"
fixture
python3 "$REPO/tests/stubs/fake_proton.py" prefer-valve "$T"
check "installer succeeds" installer --source "$REPO/tests/fixtures/game"
ID=$(basename "$(own_prefix)")
check "games.json asks for DroidDeck-Proton for the prefix" python3 -c '
import json, sys
games = json.load(open(sys.argv[1]))["games"]
assert games == {sys.argv[2]: {"valve": False, "dir": "DroidDeck-Proton-11-11.9"}}, games' \
  "$T/.local/share/droiddeck-compat/games.json" "$ID"
check "CompatToolMapping for the prefix" bash -c "grep -A2 '\"$ID\"' '$STEAM_ROOT/config/config.vdf' | grep -q DroidDeck-Proton-11-11.9"
check "user's default still Valve Proton" bash -c "grep -A2 '\"0\"' '$STEAM_ROOT/config/config.vdf' | grep -q droiddeck-proton-arm64"
cleanup

echo "Re-run after an older 7thDroid installed into Steam's FF7 prefix"
fixture
steam_game "$STEAM_ROOT" 39140 "FINAL FANTASY VII" ff7_en.exe
mkdir -p "$T/.local/share/7thdroid"
printf 'COMPATDATA=%q\n' "$STEAM_ROOT/steamapps/compatdata/39140" > "$T/.local/share/7thdroid/install.env"
before=$(other_prefixes)
check "installer succeeds" installer
check "says the old prefix is left alone" grep -qF "older 7thDroid installed 7th Heaven into $STEAM_ROOT/steamapps/compatdata/39140" "$T/out.log"
check "old prefix untouched" test "$(other_prefixes)" = "$before"
cleanup

echo "An FFNx too old for 7th Heaven 4.6 is updated"
fixture
mkdir -p "$T/FF7"
touch "$T/FF7/FFVII.exe"
check "installer succeeds" installer --source "$T/FF7"
check "no FFNx yet: nothing to update" bash -c "! grep -q 'Updating FFNx' '$T/out.log'"
old_ffnx "$T/FF7"
check "Update or repair succeeds" installer --source "$T/FF7"
check "says why it updates FFNx" grep -q 'older than 7th Heaven needs (FFNx 1.25 or newer)' "$T/out.log"
check "FFNx_steam_api.dll installed" test -f "$T/FF7/FFNx_steam_api.dll"
check "the driver replaced" grep -qx 'FFNx 1.25.2' "$T/FF7/AF3DN.P"
check "subfolders unpacked" test -f "$T/FF7/shaders/a.bin"
check "the FFNx settings kept" grep -q '^renderer_backend = 5' "$T/FF7/FFNx.toml"
check "new FFNx options added" grep -q '^new_key = true' "$T/FF7/FFNx.toml"
check "the old FFNx.toml kept beside it" test -f "$T/FF7/FFNx.toml.7thdroid-bak"
check "a current FFNx is left alone" bash -c "bash '$REPO/7thdroid.sh' --install --yes --version stable --no-copy-game --source '$T/FF7' > '$T/out.log' 2>&1 && ! grep -q 'Updating FFNx' '$T/out.log'"
old_ffnx "$T/FF7"
ARGS=()
: > "$STUB_LOG"
check "menu: launch with an old FFNx" windowed 7thdroid.sh 0
check "FFNx updated before the launch" test -f "$T/FF7/FFNx_steam_api.dll"
check "then 7th Heaven started" grep -q $'^waitforexitandrun\t.*\t7th Heaven.exe' "$STUB_LOG"
old_ffnx "$T/FF7"
rm -f "$XDG_CACHE_HOME/7thdroid/FFNx-Steam-v1.25.2.0.zip"
export FFNX_API=file://$T/nowhere
: > "$STUB_LOG"
check "menu: launch when FFNx can't be updated" windowed 7thdroid.sh 0
check "says how to update it in 7th Heaven" grep -qF 'FFNx:\ Check\ for\ Updates' "$T/zenity.log"
check "7th Heaven not started into the error" bash -c "! grep -q '7th Heaven.exe' '$STUB_LOG'"
cleanup

echo "Backup and restore: 2026 release copied into the prefix, with mods"
fixture
steam_game "$STEAM_ROOT" 3837340 "FINAL FANTASY VII" FFVII.exe
mkdir -p "$STEAM_ROOT/steamapps/common/FINAL FANTASY VII/ff7/workingdir"
check "installer succeeds" installer --copy-game
CD=$(own_prefix)
WD="$CD/pfx/drive_c/FINAL FANTASY VII/ff7/workingdir"
WS="$CD/pfx/drive_c/7th Heaven/7thWorkshop"
MODS="$CD/pfx/drive_c/7th Heaven/mods"
mkdir -p "$WD/save" "$WS/profiles" "$MODS/Mod A" "$MODS/temp"
echo slot1 > "$WD/save/save00.ff7"
printf 'renderer_backend = 5\n' > "$WD/FFNx.toml"
echo '<Profile/>' > "$WS/profiles/Favourite.xml"
echo '<Library>A</Library>' > "$WS/library.xml"
echo mod > "$MODS/Mod A/mod.xml"
echo junk > "$MODS/temp/junk"
sed -i 's#<AppLanguage>en</AppLanguage>#<AppLanguage>de</AppLanguage>#' "$WS/settings.xml"
check "--backup with mods" bash -c "bash '$REPO/7thdroid.sh' --backup --yes --mods > '$T/out.log' 2>&1"
B=$(backups | tail -n1)
check "one backup in the backup folder" test "$(backups | wc -l)" -eq 1
NAMES=$(tar_names "$B")
check "the backup has saves, settings, profiles, FFNx.toml and mods" has_entries manifest.env workshop/settings.xml workshop/library.xml \
  workshop/profiles/Favourite.xml saves/save00.ff7 game/FFNx.toml "mods/Mod A/mod.xml"
check "7th Heaven's temp folder left out" bash -c "! grep -q '^mods/temp' <<< '$NAMES'"
check "the manifest names the release" bash -c "python3 '$REPO/lib/backup.py' manifest '$B' | grep -qx 'FF7_VERSION=SteamReRelease'"
ARGS=(--uninstall)
# back up first: yes; include the mods: yes; remove: yes
check "uninstall, backing up first" windowed 7thdroid.sh yes yes yes
check "the backup and mods questions come first" bash -c "grep '^question' '$T/zenity.log' | head -n 2 | tail -n 1 | grep -q 'Include.*your.*mods'"
check "a second backup" test "$(backups | wc -l)" -eq 2
check "the done text names it" grep -q "Your.*backup.*is.*$T/backups/7thDroid-" "$T/zenity.log"
check "prefix removed" test ! -e "$CD"
check "backups kept" test -f "$B"
ARGS=(--install --version stable --copy-game)
# warning: Continue; the Steam copy; restore: the older backup (the list is newest first after "Don't restore")
check "reinstall with a restore" windowed 7thdroid.sh yes 0 2
check "the restore was offered" grep -qF "Don\\'t\\ restore" "$T/zenity.log"
check "saves restored into workingdir" grep -qx slot1 "$WD/save/save00.ff7"
check "profiles restored" test -f "$WS/profiles/Favourite.xml"
check "7th Heaven settings restored" grep -q '<AppLanguage>de</AppLanguage>' "$WS/settings.xml"
check "FF7Exe still this install's" grep -qF '<FF7Exe>C:\FINAL FANTASY VII\FFVII.exe</FF7Exe>' "$WS/settings.xml"
check "mods restored" grep -qx mod "$MODS/Mod A/mod.xml"
check "the mod list restored" grep -qF '<Library>A</Library>' "$WS/library.xml"
check "FFNx settings wait for FFNx" test -f "$WD/FFNx.toml.7thdroid-restore" -a ! -e "$WD/FFNx.toml"
printf 'renderer_backend = 0\nnew_key = 1\n' > "$WD/FFNx.toml"
ARGS=()
check "menu: launch" windowed 7thdroid.sh 0
check "the FFNx settings merged in once FFNx exists" grep -qx 'renderer_backend = 5' "$WD/FFNx.toml"
check "FFNx's new options kept" grep -qx 'new_key = 1' "$WD/FFNx.toml"
check "nothing left pending" test ! -e "$WD/FFNx.toml.7thdroid-restore"
cleanup

echo "Backup and restore: Steam 2013 release, without mods"
fixture
steam_game "$STEAM_ROOT" 39140 "FINAL FANTASY VII" ff7_en.exe
check "installer succeeds" installer
CD=$(own_prefix)
SAVE="$CD/pfx/drive_c/users/steamuser/Documents/Square Enix/FINAL FANTASY VII Steam/user_12345678"
WS="$CD/pfx/drive_c/7th Heaven/7thWorkshop"
MODS="$CD/pfx/drive_c/7th Heaven/mods"
echo slot1 > "$SAVE/save00.ff7"
mkdir -p "$MODS/Mine"
echo '<Library>mine</Library>' > "$WS/library.xml"
check "Update or repair with --yes backs up first" installer
check "the backup is made before anything else" bash -c "a=\$(grep -n 'Backed up to' '$T/out.log' | cut -d: -f1); b=\$(grep -n 'Choosing the Proton prefix' '$T/out.log' | cut -d: -f1); [ -n \"\$a\" ] && [ \"\$a\" -lt \"\$b\" ]"
check "--no-backup skips it" bash -c "n=\$(find '$T/backups' -name '*.tar' | wc -l); bash '$REPO/7thdroid.sh' --install --yes --version stable --no-copy-game --no-backup >/dev/null 2>&1 && [ \$(find '$T/backups' -name '*.tar' | wc -l) -eq \$n ]"
rm -f "$T/backups"/*.tar
check "--backup --no-mods" bash -c "bash '$REPO/7thdroid.sh' --backup --yes --no-mods > '$T/out.log' 2>&1"
B=$(backups | tail -n1)
NAMES=$(tar_names "$B")
check "the saves come from the prefix's Documents" has_entries saves/user_12345678/save00.ff7
check "no mods in it" bash -c "! grep -q '^mods' <<< '$NAMES'"
rm -f "$SAVE/save00.ff7"
echo new > "$MODS/Mine/new"
echo '<Library>current</Library>' > "$WS/library.xml"
check "--restore FILE" bash -c "bash '$REPO/7thdroid.sh' --restore '$B' --yes > '$T/out.log' 2>&1"
check "the save is back" grep -qx slot1 "$SAVE/save00.ff7"
check "a backup without mods keeps the current mods" test -f "$MODS/Mine/new"
check "and the current mod list" grep -qF '<Library>current</Library>' "$WS/library.xml"
# a backup from another FF7 release: its saves are left out unless asked for
printf 'BACKUP_DATE=2026-11-01 10:00\nFF7_VERSION=SteamReRelease\nPARTS=workshop saves game\nMODS_KB=\n' > "$T/manifest"
mkdir -p "$T/other/save"
echo other > "$T/other/save/save00.ff7"
python3 "$REPO/lib/backup.py" create "$T/backups/7thDroid-2026-11-01_100000.tar" "$T/manifest" "workshop/settings.xml=$WS/settings.xml" "saves=$T/other/save"
check "restore from another release" bash -c "bash '$REPO/7thdroid.sh' --restore '$T/backups/7thDroid-2026-11-01_100000.tar' --yes > '$T/out.log' 2>&1"
check "its saves were left out" grep -qx slot1 "$SAVE/save00.ff7"
check "says why" grep -q 'saves are from the SteamReRelease release' "$T/out.log"
rm -f "$SAVE/save00.ff7"
ARGS=()
# menu: Restore a backup; the newest backup (the Steam 2013 one); restore: yes
check "menu: restore a backup" windowed 7thdroid.sh 3 0 yes
check "the backups listed newest first" bash -c "grep '^list' '$T/zenity.log' | sed -n 2p | grep -q 'TRUE 0 [^F]*without.*mods FALSE 1 2026-11-01'"
check "the save is back from the menu" grep -qx slot1 "$SAVE/save00.ff7"
cleanup

echo "Uninstall stops when the backup fails"
fixture
steam_game "$STEAM_ROOT" 39140 "FINAL FANTASY VII" ff7_en.exe
check "installer succeeds" installer
touch "$T/not-a-folder"
export SEVENTHDROID_BACKUP_DIR=$T/not-a-folder/backups
ARGS=(--uninstall)
windowed 7thdroid.sh yes yes
check "uninstall stops" test $? -ne 0
check "says so" grep -q 'The backup failed, so nothing was removed' "$T/out.log"
check "nothing removed" test -f "$(own_prefix)/pfx/drive_c/7th Heaven/7th Heaven.exe"
cleanup

echo "Save logs: every log, redacted"
fixture
steam_game "$STEAM_ROOT" 39140 "FINAL FANTASY VII" ff7_en.exe
ARGS=()
# the Install-only menu: Save logs
check "menu: save logs before installing" windowed 7thdroid.sh 1
check "a bundle without an install" bash -c "tar_text() { python3 -c 'import sys, tarfile; t = tarfile.open(sys.argv[1]); print(t.extractfile(\"info.txt\").read().decode())' \"\$1\"; }; tar_text \"\$(find '$T/logs' -name '*.tar' | head -n1)\" | grep -q '7th Heaven is not installed'"
rm -f "$T/logs"/*.tar
check "installer succeeds" installer
check "a second run keeps the first run's log" bash -c "bash '$REPO/7thdroid.sh' --install --yes --version stable --no-copy-game --no-backup >/dev/null 2>&1 && test -f '$T/.local/state/7thdroid/install.log.1'"
check "a third keeps two" bash -c "bash '$REPO/7thdroid.sh' --install --yes --version stable --no-copy-game --no-backup >/dev/null 2>&1 && test -f '$T/.local/state/7thdroid/install.log.2' -a ! -e '$T/.local/state/7thdroid/install.log.3'"
CD=$(own_prefix)
GAME="$STEAM_ROOT/steamapps/common/FINAL FANTASY VII"
mkdir -p "$T/ddlogs/2026-11-09-01-desktop" "$T/ddlogs/2026-11-09-02-steam/steam" "$T/ddlogs/tools" "$T/ddlogs/not-a-session" \
  "$T/root/.local/share/Steam/config"
echo "start access_token=abcdef123456 for maskedplayer" > "$T/ddlogs/2026-11-09-01-desktop/session.log"
printf '\177ELF\0\0\0' > "$T/ddlogs/2026-11-09-01-desktop/core"
echo "SteamUI: OnLoginStateChange someone 2 1 0 0" > "$T/ddlogs/2026-11-09-02-steam/steam/connection_log.txt"
echo "tool ran" > "$T/ddlogs/tools/droiddeck-epic.log"
echo "not a session" > "$T/ddlogs/not-a-session/x.log"
printf '"users" { "76561198000000001" { "AccountName" "maskedplayer" } }' > "$T/root/.local/share/Steam/config/loginusers.vdf"
echo "7th Heaven started, password=hunter2hunter2" > "$CD/pfx/drive_c/7th Heaven/7thWorkshop/applog.txt"
echo "FFNx 1.25.2 started, user 76561198012341234" > "$GAME/FFNx.log"
: > "$STUB_LOG"
check "menu: launch" windowed 7thdroid.sh 0
check "menu: launch again" windowed 7thdroid.sh 0
check "the launch log, with the previous one kept" test -f "$T/.local/state/7thdroid/launch.log" -a -f "$T/.local/state/7thdroid/launch.log.1"
check "the launch log says how 7th Heaven was started" grep -q '7th Heaven started from 7thDroid or a shell' "$T/.local/state/7thdroid/launch.log"
# menu: Save logs (after Launch, Update or repair, Back up, Restore, Show the last log)
check "menu: save logs" windowed 7thdroid.sh 5
L=$(log_bundles | tail -n1)
check "one bundle in Documents' 7thDroid Logs" test "$(log_bundles | wc -l)" -eq 1
NAMES=$(tar_names "$L")
check "it has 7thDroid's, 7th Heaven's, FFNx's and DroidDeck's logs" has_entries info.txt index.txt 7thdroid/install.log \
  7thdroid/install.log.1 7thdroid/launch.log 7thdroid/launch.log.1 7thdroid/install.env 7th-heaven/applog.txt \
  7th-heaven/settings.xml game/FFNx.log droiddeck/2026-11-09-01-desktop/session.log \
  droiddeck/2026-11-09-02-steam/steam/connection_log.txt droiddeck/tools/droiddeck-epic.log
check "only DroidDeck's session folders" bash -c "! grep -q not-a-session <<< '$NAMES'"
TEXT=$(tar_text "$L")
check "binaries left out, and listed" grep -q $'droiddeck/2026-11-09-01-desktop/core\t7\tleft out: binary' <<< "$TEXT"
check "no token, password, account name or Steam ID left" bash -c "! grep -qE 'abcdef123456|hunter2|maskedplayer|someone 2|76561198012341234' <<< \"\$1\"" _ "$TEXT"
check "redacted, not dropped" grep -q 'access_token=<redacted:token> for <redacted:account>' <<< "$TEXT"
check "info.txt describes the install" grep -q '^7th Heaven: 4.6.0 (stable)' <<< "$TEXT"
check "save logs keeps its own log" test -f "$T/.local/state/7thdroid/save-logs.log"
cleanup

echo "7th Heaven canary build"
fixture
check "installer succeeds" bash -c "bash '$REPO/7thdroid.sh' --install --yes --version canary --source '$REPO/tests/fixtures/game' > '$T/out.log' 2>&1"
CD=$(own_prefix)
check "the canary asset, kept apart by its date" grep -q $'\tcanary-202611011640-7thHeaven-v4.6.0.1_Release.exe\t' "$STUB_LOG"
check "update channels set to Canary" grep -q '<AppUpdateChannel>Canary</AppUpdateChannel>' <(settings "$CD")
check ".NET 10 installed" test -d "$CD/pfx/drive_c/Program Files (x86)/dotnet/shared/Microsoft.WindowsDesktop.App/10.0.14"
cleanup

echo "The retired pinned build"
fixture
check "is refused" bash -c "! bash '$REPO/7thdroid.sh' --install --yes --version pinned --source '$REPO/tests/fixtures/game' > '$T/out.log' 2>&1"
check "names the builds offered" grep -q "use stable or canary" "$T/out.log"
check "no prefix made" test ! -e "$(own_prefix)"
cleanup

echo "Windows instead of a terminal (AppImage): the menu installs, then offers the rest"
fixture
heroic_game
ARGS=(--version stable)
# menu: Install; warning: Continue; the Heroic copy; copy the game: yes; menu: closed
check "installer succeeds" windowed 7thdroid.sh 0 yes 0 yes
CD=$(own_prefix)
check "the menu offered only Install" bash -c "grep -m1 '^list' '$T/zenity.log' | grep -F 'Install\\ 7th\\ Heaven' | grep -vqF 'Launch'"
check "the warning comes first" bash -c "grep -m1 '^question' '$T/zenity.log' | grep -F 'THIS SOFTWARE IS EXPERIMENTAL' | grep -qF -- '--ok-label=Continue'"
check "copies offered in a list" grep -q '^list .*--radiolist' "$T/zenity.log"
check "progress window shows the steps" grep -q '^progress-line # Installing 7th Heaven' "$T/zenity.log"
check "backslashes reach zenity escaped" grep -qF 'to C:\\7th Heaven.' "$T/zenity.log"
check "no 'close it to continue' note" bash -c "! grep -q 'close it to continue' '$T/zenity.log'"
check "game copied into the prefix" test -f "$CD/pfx/drive_c/FINAL FANTASY VII/FFVII.exe"
check "every question before any work" bash -c "awk '/^proton-run/ { work = 1 } work && /^(question|list|entry|file-selection) / { bad = 1 } /^info / { exit } END { exit bad || !work }' '$T/zenity.log'"
check "FF7Exe is the copy, on C:" grep -qF '<FF7Exe>C:\FINAL FANTASY VII\FFVII.exe</FF7Exe>' <(settings "$CD")
check "no shortcuts asked or added" test ! -e "$T/opt/droiddeck-apps/7thheaven" -a ! -e "$T/.local/share/applications/7th-heaven.desktop"
check "no Steam entry for a GOG copy" test ! -e "$STEAM_ROOT/userdata/12345/config/shortcuts.vdf"
check "says it is done" grep -qF 'info --title=7thDroid --info --no-markup --width=700 --text=7th\ Heaven\ 4.6.0\ is\ installed\ for\ GOG' "$T/zenity.log"
check "back to the full menu" bash -c "grep '^list\|^info' '$T/zenity.log' | tail -n 1 | grep -qF 'Uninstall\ 7th\ Heaven'"
check "no shortcuts item" bash -c "! grep -q 'recreate\\ shortcuts' '$T/zenity.log'"
ARGS=()
: > "$STUB_LOG"
check "menu: launch" windowed 7thdroid.sh 0
check "menu launched 7th Heaven in its prefix" grep -q $'^waitforexitandrun\t'"${CD##*/}"$'\t7th Heaven.exe' "$STUB_LOG"
check "no FFNx.toml yet: settings apply next time" grep -q 'apply from the next launch' "$T/out.log"
printf 'renderer_backend = 0\nenable_steam_achievements = true\n' > "$CD/pfx/drive_c/FINAL FANTASY VII/FFNx.toml"
check "menu: launch again" windowed 7thdroid.sh 0
check "Direct3D 11 in place of Auto" grep -qx 'renderer_backend = 3' "$CD/pfx/drive_c/FINAL FANTASY VII/FFNx.toml"
check "Steam Compatibility off" grep -qx 'enable_steam_achievements = false' "$CD/pfx/drive_c/FINAL FANTASY VII/FFNx.toml"
check "menu: uninstall declined" windowed 7thdroid.sh 6 cancel cancel 7
check "declining keeps everything" test -f "$CD/pfx/drive_c/7th Heaven/7th Heaven.exe"
check "the uninstall warning" grep -qF 'WARNING: THIS WILL PERMANENTLY DELETE ANY FF7 SAVES IN THE 7TH HEAVEN PREFIX.' "$T/zenity.log"
before=$(other_prefixes)
check "menu: uninstall, backing up first" windowed 7thdroid.sh 6 yes yes
check "back to a menu with only Install" bash -c "grep '^list' '$T/zenity.log' | tail -n 1 | grep -F 'Install\\ 7th\\ Heaven' | grep -vqF 'Launch'"
check "prefix removed" test ! -e "$CD"
check "launcher and state removed" test ! -e "$T/.local/share/7thdroid"
check "downloads removed" test ! -e "$T/.cache/7thdroid"
check "game files kept" test -f "$T/Games/Heroic/FINAL FANTASY VII/FFVII.exe"
check "other prefixes untouched" test "$(other_prefixes)" = "$before"
check "DroidDeck's Proton choice for the prefix removed" bash -c "! grep -qs '${CD##*/}' '$T/.local/share/droiddeck-compat/games.json'"
cleanup

echo "Windows: picking a GOG installer"
fixture
mkdir -p "$T/Download"
echo stub > "$T/Download/setup_final_fantasy_vii_2.0_(gog).exe"
ARGS=(--install --version stable)
check "installer succeeds" windowed 7thdroid.sh yes 1 "$T/Download/setup_final_fantasy_vii_2.0_(gog).exe" "$T/Games/FF7"
check "no copy offered for a game it installed" bash -c "! grep -q 'Copy\\\\ FINAL' '$T/zenity.log'"
check "file picker filtered to installers" grep -q '^file-selection .*--file-filter=GOG\\ installer' "$T/zenity.log"
check "game installed where chosen" test -f "$T/Games/FF7/FFVII.exe"
cleanup

echo "Windows: Quit at the warning"
fixture
heroic_game
ARGS=(--install --version stable)
windowed 7thdroid.sh cancel
check "Quit stops the installer" test $? -eq 130
check "no prefix made" test ! -e "$(own_prefix)"
ARGS=(--version stable)
check "from the menu, the menu comes back" windowed 7thdroid.sh 0 cancel
check "it showed the menu twice" test "$(grep -c '^list' "$T/zenity.log")" -eq 2
check "still no prefix" test ! -e "$(own_prefix)"
cleanup

echo "Typed answers: a path to an installed game"
fixture
mkdir -p "$T/My FF7"
touch "$T/My FF7/FFVII.exe" "$T/My FF7/goggame-1698970154.info"
check "installer succeeds" bash -c "printf '%s\n' \"'$T/My FF7'\" | UI_MODE=tty timeout 300 bash '$REPO/7thdroid.sh' --install --version stable > '$T/out.log' 2>&1"
check "uses the typed folder" grep -qF "Game: $T/My FF7/FFVII.exe" "$T/out.log"
cleanup

echo "No terminal and no windows"
fixture
heroic_game
check "refuses instead of taking defaults" bash -c "! bash '$REPO/7thdroid.sh' --version stable < /dev/null > '$T/out.log' 2>&1"
check "says why" grep -q "no terminal or window to ask in" "$T/out.log"
check "no prefix made" test ! -e "$(own_prefix)"
cleanup

echo "DroidDeck older than 0.6.7: asks for an update"
fixture
mkdir -p "$T/ddbin"
cp "$DD_BIN"/* "$T/ddbin/" 2>/dev/null
sed -i 's/^def build_key(/def _old_build_key(/' "$T/ddbin/steam-compatibility"
export DROIDDECK_BIN=$T/ddbin DROIDDECK_PROTON_EXTRA=$T/must-not-run
check "stops" bash -c "! bash '$REPO/7thdroid.sh' --install --yes --version stable >'$T/out.log' 2>&1"
check "asks for DroidDeck 0.6.7 or newer" grep -q "needs DroidDeck 0.6.7 or newer" "$T/out.log"
check "the missing piece is in the log" grep -q "steam-compatibility: build_key" "$T/.local/state/7thdroid/install.log"
check "nothing downloaded or made" test ! -e "$(own_prefix)"
cleanup

echo "Error windows name the log once"
fixture
export DROIDDECK_PROTON_RUN=$T/none
ARGS=(--install)
windowed 7thdroid.sh yes
check "installer stops" test $? -ne 0
check "the log is named once" test "$(grep '^error' "$T/zenity.log" | grep -o 'install\.log' | wc -l)" -le 1
cleanup

echo "Missing DroidDeck"
fixture
export DROIDDECK_PROTON_RUN=$T/none
check "names what is missing" bash -c "! bash '$REPO/7thdroid.sh' --yes >'$T/out.log' 2>&1 && grep -q 'droiddeck-proton-run' '$T/out.log'"
cleanup

printf '\n%d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
