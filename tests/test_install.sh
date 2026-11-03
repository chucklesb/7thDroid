#!/bin/bash
# End-to-end runs of install.sh against fixture trees. DroidDeck's own Python helpers come from a
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

# fixture NAME -> sets T (a fresh fake home) and the environment install.sh reads
fixture() {
  T=$(mktemp -d)
  export HOME=$T XDG_CONFIG_HOME=$T/.config XDG_DATA_HOME=$T/.local/share XDG_CACHE_HOME=$T/.cache XDG_STATE_HOME=$T/.local/state
  export STEAM_ROOT=$T/.local/share/Steam STUB_LOG=$T/stub.log
  export DROIDDECK_PROTON_RUN=$REPO/tests/stubs/droiddeck-proton-run
  export DROIDDECK_INNOEXTRACT=$T/none DROIDDECK_MSITOOLS=$T/none
  export DROIDDECK_APPS_DIR=$T/opt/droiddeck-apps
  export DROIDDECK_BIN=$DD_BIN DROIDDECK_PROTON_EXTRA=$REPO/tests/stubs/droiddeck-proton-extra
  export SEVENTH_API=file://$REPO/tests/fixtures/7th-heaven
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

installer() { bash "$REPO/install.sh" --yes --version stable "$@" > "$T/out.log" 2>&1; }
settings() { cat "$1/pfx/drive_c/7th Heaven/7thWorkshop/settings.xml"; }

echo "Steam 2026 release in a second library"
fixture
mkdir -p "$T/sd"
printf '"libraryfolders"\n{\n\t"0"\n\t{\n\t\t"path"\t\t"%s"\n\t}\n\t"1"\n\t{\n\t\t"path"\t\t"%s"\n\t}\n}\n' "$STEAM_ROOT" "$T/sd" > "$STEAM_ROOT/steamapps/libraryfolders.vdf"
steam_game "$T/sd" 3837340 "FINAL FANTASY VII" FFVII.exe
before=$(other_prefixes)
check "installer succeeds" installer --no-steam
CD=$(own_prefix)
check "Steam's FF7 prefix untouched" test "$(other_prefixes)" = "$before"
check "installers ran in 7thDroid's own prefix" grep -q $'run\t'"${CD##*/}"$'\t7thHeaven-v4.6.0.0_Release.exe\t0' "$STUB_LOG"
check "nothing ran in another prefix" bash -c "! cut -f2 '$STUB_LOG' | grep -vqx '${CD##*/}'"
check "installers ran with full x87 precision" bash -c "! cut -f4 '$STUB_LOG' | grep -vqx 0"
check "DroidDeck-Proton pinned to the prefix" grep -q "${CD##*/}" "$T/.local/share/droiddeck-compat/games.json"
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
check "app entry" test "$(cat "$T/opt/droiddeck-apps/7thheaven/entry")" = "7th Heaven.sh"
check "KDE entry" test -f "$T/.local/share/applications/7th-heaven.desktop"
check "second run skips finished steps" bash -c "cp '$STUB_LOG' '$T/first.log'; bash '$REPO/install.sh' --yes --version stable --no-steam >/dev/null 2>&1 && cmp -s '$STUB_LOG' '$T/first.log'"
cleanup

echo "Steam 2013 release, launch entries declined"
fixture
steam_game "$STEAM_ROOT" 39140 "FINAL FANTASY VII" ff7_en.exe
before=$(other_prefixes)
check "installer succeeds" installer --no-app-entry --no-steam --no-desktop
CD=$(own_prefix)
check "Steam's FF7 prefix untouched" test "$(other_prefixes)" = "$before"
check "Z: path to ff7_en.exe" grep -qF "<FF7Exe>Z:${STEAM_ROOT//\//\\}\steamapps\common\FINAL FANTASY VII\ff7_en.exe</FF7Exe>" <(settings "$CD")
check "version Steam" grep -q '<FF7InstalledVersion>Steam</FF7InstalledVersion>' <(settings "$CD")
check "launcher reports app 39140" grep -qFe "--options 'SteamAppId=39140 %command%'" "$T/.local/share/7thdroid/7th Heaven.sh"
check "user slot" test -d "$CD/pfx/drive_c/users/steamuser/Documents/Square Enix/FINAL FANTASY VII Steam/user_12345678"
check "no app entry" test ! -e "$T/opt/droiddeck-apps/7thheaven"
check "no KDE entry" test ! -e "$T/.local/share/applications/7th-heaven.desktop"
cleanup

echo "GOG through Heroic (Flatpak)"
fixture
mkdir -p "$T/Games/Heroic/FINAL FANTASY VII" "$T/.var/app/com.heroicgameslauncher.hgl/config/heroic/gog_store"
touch "$T/Games/Heroic/FINAL FANTASY VII/FFVII.exe"
printf '{"installed":[{"appName":"1698970154","install_path":"%s","platform":"windows"}]}' "$T/Games/Heroic/FINAL FANTASY VII" \
  > "$T/.var/app/com.heroicgameslauncher.hgl/config/heroic/gog_store/installed.json"
check "installer succeeds" installer --no-steam
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
check "installer succeeds" installer --no-steam
check "DroidDeck store found" grep -q "GOG via the DroidDeck app" "$T/out.log"
check "Lutris found, game folder inside its prefix" grep -qF "GOG via Lutris (native/AppImage) - $T/Games/final-fantasy-vii/drive_c/GOG Games/FF7" "$T/out.log"
cleanup

echo "GOG installer, run because innoextract is missing"
fixture
mkdir -p "$T/Download"
echo stub > "$T/Download/setup_final_fantasy_vii_2.0_(gog).exe"
check "installer succeeds" installer --no-steam --source "$T/Download/setup_final_fantasy_vii_2.0_(gog).exe" --game-dir "$T/Games/FF7"
check "GOG installer ran with full x87 precision" grep -q $'\tsetup_final_fantasy_vii_2.0_(gog).exe\t0\t' "$STUB_LOG"
check "game installed where asked" test -f "$T/Games/FF7/FFVII.exe"
cleanup

echo "GOG installer unpacked with innoextract"
fixture
export DROIDDECK_INNOEXTRACT=$REPO/tests/stubs/innoextract
mkdir -p "$T/Download" "$T/Games/FF7"
echo stub > "$T/Download/setup_final_fantasy_vii_2.0_(gog).exe"
touch "$T/Games/FF7/webcache.zip"   # left by an earlier, failed unpack
check "installer succeeds" installer --no-steam --source "$T/Download/setup_final_fantasy_vii_2.0_(gog).exe" --game-dir "$T/Games/FF7"
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
check "installer succeeds" installer --no-steam --source "$T/Download/setup_final_fantasy_vii_2.0_(gog).exe" --game-dir "$T/Games/FF7"
check "game moved out of app/" test -f "$T/Games/FF7/FFVII.exe" -a -f "$T/Games/FF7/goggame-1698970154.ico"
check "no tmp/ folder" test ! -e "$T/Games/FF7/tmp"
cleanup

echo "GOG installer whose unpacked files have no game"
fixture
export DROIDDECK_INNOEXTRACT=$REPO/tests/stubs/innoextract STUB_INNO_LAYOUT=empty
mkdir -p "$T/Download"
echo stub > "$T/Download/setup_final_fantasy_vii_2.0_(gog).exe"
check "installer succeeds" installer --no-steam --source "$T/Download/setup_final_fantasy_vii_2.0_(gog).exe" --game-dir "$T/Games/FF7"
check "the GOG installer was run instead" grep -q $'\tsetup_final_fantasy_vii_2.0_(gog).exe\t0\t' "$STUB_LOG"
check "the unpacked files are listed in the log" grep -q "goggame-1698970154.ico" "$T/.local/state/7thdroid/install.log"
cleanup

echo ".NET in the x64-native layout is recognised"
fixture
mkdir -p "$T/FF7" "$(own_prefix)/pfx/drive_c/Program Files/dotnet/shared/Microsoft.WindowsDesktop.App/10.0.5"
touch "$T/FF7/FFVII.exe"
check "installer succeeds" installer --no-steam --source "$T/FF7"
check "the x64 runtime was not installed again" bash -c "! grep -q 'win-x64' '$STUB_LOG'"
cleanup

echo "1998 CD-ROM from disc folders"
fixture
mkdir -p "$T/cd1/FF7" "$T/cd2/FF7"
echo stub > "$T/cd1/SETUP.EXE"
check "installer succeeds" installer --no-steam --source "$T/cd1" --source "$T/cd2"
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

echo "Steam shortcut (DroidDeck's shortcuts.vdf code)"
fixture
steam_game "$STEAM_ROOT" 39140 "FINAL FANTASY VII" ff7_en.exe
check "installer succeeds" installer --steam
check "shortcut readable by DroidDeck and untagged" python3 - "$DD_BIN/droiddeck-steam-shortcuts" "$STEAM_ROOT/userdata/12345/config/shortcuts.vdf" "$T/.local/share/7thdroid/7th Heaven.sh" <<'EOF'
import runpy, sys
tool = runpy.run_path(sys.argv[1])
items = list(tool["parse"](open(sys.argv[2], "rb").read())["shortcuts"].values())
assert len(items) == 1 and items[0]["Exe"] == '"%s"' % sys.argv[3] and items[0]["tags"] == {}, items
EOF
check "re-adding replaces it" bash -c "bash '$REPO/install.sh' --yes --shortcuts-only --steam --no-app-entry --no-desktop >/dev/null 2>&1 && python3 - <<'EOF'
import runpy
tool = runpy.run_path('$DD_BIN/droiddeck-steam-shortcuts')
assert len(tool['parse'](open('$STEAM_ROOT/userdata/12345/config/shortcuts.vdf', 'rb').read())['shortcuts']) == 1
EOF"
check "the shortcut is found" python3 "$REPO/lib/steam_shortcut.py" has "$DD_BIN/droiddeck-steam-shortcuts" "$STEAM_ROOT" "$T/.local/share/7thdroid/7th Heaven.sh"
check "--shortcuts-only keeps the Steam app id" grep -qFe "--options 'SteamAppId=39140 %command%'" "$T/.local/share/7thdroid/7th Heaven.sh"
cleanup

echo "DroidDeck-Proton missing: installed when accepted"
fixture no-proton
steam_game "$STEAM_ROOT" 39140 "FINAL FANTASY VII" ff7_en.exe
check "installer succeeds" installer --no-steam
check "DroidDeck-Proton installed and registered" test -f "$STEAM_ROOT/compatibilitytools.d/DroidDeck-Proton-11-11.9/droiddeck-proton-wrap"
check "7th Heaven installed" test -f "$(own_prefix)/pfx/drive_c/7th Heaven/7th Heaven.exe"
check "DroidDeck made it the default, so no per-game pin" test ! -e "$T/.local/share/droiddeck-compat/games.json"
cleanup

echo "DroidDeck-Proton missing: install fails"
fixture no-proton
steam_game "$STEAM_ROOT" 39140 "FINAL FANTASY VII" ff7_en.exe
export STUB_PROTON_EXTRA_FAIL=1
check "stops" bash -c "! bash '$REPO/install.sh' --yes --version stable --no-steam >'$T/out.log' 2>&1"
check "explains how to install it" grep -q 'droiddeck-proton-extra .* droiddeck' "$T/out.log"
check "no prefix made" test ! -e "$(own_prefix)"
cleanup

echo "Valve Proton kept as the user's default: only 7thDroid's prefix is pinned"
fixture
python3 "$REPO/tests/stubs/fake_proton.py" prefer-valve "$T"
check "installer succeeds" installer --no-steam --source "$REPO/tests/fixtures/game"
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
check "installer succeeds" installer --no-steam
check "says the old prefix is left alone" grep -qF "older 7thDroid installed 7th Heaven into $STEAM_ROOT/steamapps/compatdata/39140" "$T/out.log"
check "old prefix untouched" test "$(other_prefixes)" = "$before"
cleanup

echo "7th Heaven canary build"
fixture
check "installer succeeds" bash -c "bash '$REPO/install.sh' --yes --version canary --no-steam --source '$REPO/tests/fixtures/game' > '$T/out.log' 2>&1"
CD=$(own_prefix)
check "the canary asset, kept apart by its date" grep -q $'\tcanary-202611011640-7thHeaven-v4.6.0.1_Release.exe\t' "$STUB_LOG"
check "update channels set to Canary" grep -q '<AppUpdateChannel>Canary</AppUpdateChannel>' <(settings "$CD")
check ".NET 10 installed" test -d "$CD/pfx/drive_c/Program Files (x86)/dotnet/shared/Microsoft.WindowsDesktop.App/10.0.14"
cleanup

echo "The retired pinned build"
fixture
check "is refused" bash -c "! bash '$REPO/install.sh' --yes --version pinned --no-steam --source '$REPO/tests/fixtures/game' > '$T/out.log' 2>&1"
check "names the builds offered" grep -q "use stable or canary" "$T/out.log"
check "no prefix made" test ! -e "$(own_prefix)"
cleanup

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

echo "Windows instead of a terminal (AppImage), then its menu"
fixture
heroic_game
ARGS=(--version stable)
check "installer succeeds" windowed install.sh 0 yes cancel yes
CD=$(own_prefix)
check "copies offered in a list" grep -q '^list .*--radiolist' "$T/zenity.log"
check "progress window shows the steps" grep -q '^progress-line # Installing 7th Heaven' "$T/zenity.log"
check "app tile is opt-in from the AppImage" bash -c "grep '^question' '$T/zenity.log' | grep -F 'separate\\ 7th\\ Heaven\\ tile' | grep -q -- --default-cancel"
check "app tile added when answered yes" test -f "$T/opt/droiddeck-apps/7thheaven/entry"
check "Steam shortcut skipped when answered no" test ! -e "$STEAM_ROOT/userdata/12345/config/shortcuts.vdf"
check "KDE entry added" test -f "$T/.local/share/applications/7th-heaven.desktop"
check "says it is done" grep -q '^info .*is installed for GOG' "$T/zenity.log"
ARGS=()
: > "$STUB_LOG"
check "menu: launch" windowed menu.sh 0
check "menu launched 7th Heaven in its prefix" grep -q $'^waitforexitandrun\t'"${CD##*/}"$'\t7th Heaven.exe' "$STUB_LOG"
check "menu: uninstall declined" windowed menu.sh 4 cancel 5
check "declining keeps everything" test -f "$CD/pfx/drive_c/7th Heaven/7th Heaven.exe"
before=$(other_prefixes)
check "menu: uninstall" windowed menu.sh 4 yes
check "prefix removed" test ! -e "$CD"
check "launcher and state removed" test ! -e "$T/.local/share/7thdroid"
check "downloads removed" test ! -e "$T/.cache/7thdroid"
check "app tile removed" test ! -e "$T/opt/droiddeck-apps/7thheaven"
check "KDE entry removed" test ! -e "$T/.local/share/applications/7th-heaven.desktop"
check "game files kept" test -f "$T/Games/Heroic/FINAL FANTASY VII/FFVII.exe"
check "other prefixes untouched" test "$(other_prefixes)" = "$before"
check "DroidDeck's Proton choice for the prefix removed" bash -c "! grep -qs '${CD##*/}' '$T/.local/share/droiddeck-compat/games.json'"
cleanup

echo "Windows: picking a GOG installer"
fixture
mkdir -p "$T/Download"
echo stub > "$T/Download/setup_final_fantasy_vii_2.0_(gog).exe"
ARGS=(--version stable --no-app-entry --no-steam --no-desktop)
check "installer succeeds" windowed install.sh 1 "$T/Download/setup_final_fantasy_vii_2.0_(gog).exe" "$T/Games/FF7"
check "file picker filtered to installers" grep -q '^file-selection .*--file-filter=GOG\\ installer' "$T/zenity.log"
check "game installed where chosen" test -f "$T/Games/FF7/FFVII.exe"
cleanup

echo "Windows: cancelling"
fixture
heroic_game
ARGS=(--version stable)
windowed install.sh cancel
check "cancel stops the installer" test $? -eq 130
check "no prefix made" test ! -e "$(own_prefix)"
cleanup

echo "Typed answers: a path to an installed game"
fixture
mkdir -p "$T/My FF7"
touch "$T/My FF7/FFVII.exe" "$T/My FF7/goggame-1698970154.info"
check "installer succeeds" bash -c "printf '%s\n' \"'$T/My FF7'\" | UI_MODE=tty timeout 300 bash '$REPO/install.sh' --version stable --no-app-entry --no-steam --no-desktop > '$T/out.log' 2>&1"
check "uses the typed folder" grep -qF "Game: $T/My FF7/FFVII.exe" "$T/out.log"
cleanup

echo "No terminal and no windows"
fixture
heroic_game
check "refuses instead of taking defaults" bash -c "! bash '$REPO/install.sh' --version stable < /dev/null > '$T/out.log' 2>&1"
check "says why" grep -q "no terminal or window to ask in" "$T/out.log"
check "no prefix made" test ! -e "$(own_prefix)"
cleanup

echo "DroidDeck older than 0.6.7: asks for an update"
fixture
mkdir -p "$T/ddbin"
cp "$DD_BIN"/* "$T/ddbin/" 2>/dev/null
sed -i 's/^def build_key(/def _old_build_key(/' "$T/ddbin/steam-compatibility"
export DROIDDECK_BIN=$T/ddbin DROIDDECK_PROTON_EXTRA=$T/must-not-run
check "stops" bash -c "! bash '$REPO/install.sh' --yes --version stable --no-steam >'$T/out.log' 2>&1"
check "asks for DroidDeck 0.6.7 or newer" grep -q "needs DroidDeck 0.6.7 or newer" "$T/out.log"
check "the missing piece is in the log" grep -q "steam-compatibility: build_key" "$T/.local/state/7thdroid/install.log"
check "nothing downloaded or made" test ! -e "$(own_prefix)"
cleanup

echo "Error windows name the log once"
fixture
export DROIDDECK_PROTON_RUN=$T/none
windowed install.sh
check "installer stops" test $? -ne 0
check "the log is named once" test "$(grep '^error' "$T/zenity.log" | grep -o 'install\.log' | wc -l)" -le 1
cleanup

echo "Missing DroidDeck"
fixture
export DROIDDECK_PROTON_RUN=$T/none
check "names what is missing" bash -c "! bash '$REPO/install.sh' --yes >'$T/out.log' 2>&1 && grep -q 'droiddeck-proton-run' '$T/out.log'"
cleanup

printf '\n%d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
