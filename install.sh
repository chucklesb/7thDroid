#!/bin/bash
# 7thDroid: installs the 7th Heaven mod manager for FINAL FANTASY VII on DroidDeck.
# Run it as: bash install.sh   (Android shared storage is mounted noexec)

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LIB_DIR=$ROOT_DIR/lib
ASSETS_DIR=$ROOT_DIR/assets

# shellcheck source=lib/common.sh
. "$LIB_DIR/common.sh"
# shellcheck source=lib/droiddeck.sh
. "$LIB_DIR/droiddeck.sh"
# shellcheck source=lib/sources.sh
. "$LIB_DIR/sources.sh"
# shellcheck source=lib/game_import.sh
. "$LIB_DIR/game_import.sh"
# shellcheck source=lib/prefix.sh
. "$LIB_DIR/prefix.sh"
# shellcheck source=lib/seventh_heaven.sh
. "$LIB_DIR/seventh_heaven.sh"
# shellcheck source=lib/shortcuts.sh
. "$LIB_DIR/shortcuts.sh"
# shellcheck source=lib/uninstall.sh
. "$LIB_DIR/uninstall.sh"

usage() {
  cat <<EOF
Usage: bash install.sh [options]

  --version stable|canary          7th Heaven build: the newest release, or the newest development build
                                   (asked when not given)
  --source PATH                    Use this game instead of searching: an installed FF7 folder, a GOG
                                   installer, CD images (.iso) or disc folders. Repeat for several discs.
  --game-dir DIR                   Where a GOG installer puts the game (default ~/Games/FINAL FANTASY VII)
  --app-entry / --no-app-entry     Add (or skip) the DroidDeck app Desktop page entry
  --steam / --no-steam             Add (or skip) the Steam non-Steam-game shortcut
  --desktop / --no-desktop         Add (or skip) the KDE menu entry
  --shortcuts-only                 Only (re)create the launcher and shortcuts for the last install
  --uninstall                      Remove 7th Heaven's prefix, launcher, shortcuts and downloads
  --winetricks-dinput              Also run winetricks' dinput verb, when a Proton with protonfixes exists
  --reinstall                      Run every step again, even ones that look done
  --yes                            Accept every default without asking
  --dry-run                        Print what would run without changing anything
  -h, --help                       Show this help
EOF
}

SEVENTH_CHANNEL='' SOURCES=() GAME_DIR='' REINSTALL=0 SHORTCUTS_ONLY=0 UNINSTALL=0 WINETRICKS_DINPUT=0
WANT_APP_ENTRY='' WANT_STEAM='' WANT_DESKTOP=''
CD_DISCS=() CD_DRIVES=()

# shellcheck disable=SC2034 # WANT_* are read by name in want_entry
while [ $# -gt 0 ]; do
  case $1 in
    --version) SEVENTH_CHANNEL=${2:?--version needs a value}; shift ;;
    --version=*) SEVENTH_CHANNEL=${1#*=} ;;
    --source) SOURCES+=("${2:?--source needs a path}"); shift ;;
    --source=*) SOURCES+=("${1#*=}") ;;
    --game-dir) GAME_DIR=${2:?--game-dir needs a path}; shift ;;
    --game-dir=*) GAME_DIR=${1#*=} ;;
    --app-entry) WANT_APP_ENTRY=1 ;;
    --no-app-entry) WANT_APP_ENTRY=0 ;;
    --steam) WANT_STEAM=1 ;;
    --no-steam) WANT_STEAM=0 ;;
    --desktop) WANT_DESKTOP=1 ;;
    --no-desktop) WANT_DESKTOP=0 ;;
    --shortcuts-only) SHORTCUTS_ONLY=1 ;;
    --uninstall) UNINSTALL=1 ;;
    --winetricks-dinput) WINETRICKS_DINPUT=1 ;;
    --reinstall) REINSTALL=1 ;;
    --yes|-y) ASSUME_YES=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "Unknown option $1" ;;
  esac
  shift
done
case $SEVENTH_CHANNEL in
  ''|stable|latest|canary) ;;
  *) die "Unknown 7th Heaven version '$SEVENTH_CHANNEL' (use stable or canary)." ;;
esac

ui_init
start_log
ui_progress_start
trap 'ui_progress_stop; finish_log' EXIT
printf '%s%s%s - 7th Heaven for FINAL FANTASY VII on DroidDeck\n' "$C_BOLD" "$APP_NAME" "$C_RESET"
info "Log: $LOG_FILE"
[ "$DRY_RUN" = 1 ] && info "Dry run: nothing will be changed."

step "Checking the environment"
preflight

PREFIX_ID=$(dedicated_prefix_id) || die "Could not work out 7thDroid's prefix id."
DEDICATED=$(compatdata_for "$PREFIX_ID")

if [ "$UNINSTALL" = 1 ]; then
  uninstall && ui_done "7th Heaven is uninstalled. Your FF7 game files were not touched."
  exit 0
fi

if [ "$SHORTCUTS_ONLY" = 1 ]; then
  load_state || die "No earlier install found ($STATE_FILE). Run the full installer first."
  [ "$COMPATDATA" = "$DEDICATED" ] || die "The last install was made by an older $APP_NAME. Run the full installer once."
  write_launcher "$(seventh_exe "$COMPATDATA")" "$(ff7_steam_appid)"
  offer_shortcuts
  ui_done "The 7th Heaven shortcuts are up to date."
  exit 0
fi

ensure_droiddeck_proton

step "Finding FINAL FANTASY VII"
APPID=''
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

if [ "$SOURCE_KIND" = gog-setup ] || [ "$SOURCE_KIND" = cd ]; then
  step "Installing FINAL FANTASY VII"
  install_pending_game "$COMPATDATA"
fi
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
[ "$DRY_RUN" = 1 ] || save_state SOURCE_KIND APPID GAME_DIR GAME_EXE COMPATDATA FF7_VERSION SEVENTH_CHANNEL SEVENTH_TAG
offer_shortcuts

step "Done"
ok "7th Heaven $SEVENTH_TAG is installed for $FF7_VERSION FINAL FANTASY VII."
info "Start it with: bash \"$LAUNCHER\" (or the shortcuts you added)."
steam_note=''
if [ -n "$(ff7_steam_appid)" ]; then
  steam_note="

For Steam achievements, turn on Steam Compatibility in 7th Heaven (Settings > Game Driver > Advanced), then start 7th Heaven with Steam: \"Launch 7th Heaven with Steam\" in 7thDroid, or the \"$LAUNCHER_NAME\" shortcut in Steam. With that setting on, FF7 only starts while Steam is running."
  info "${steam_note#$'\n\n'}"
fi
info "Prefix: $COMPATDATA"
info "Log: $LOG_FILE"
ui_done "7th Heaven $SEVENTH_TAG is installed for $FF7_VERSION FINAL FANTASY VII.

Open 7thDroid again to launch it.$steam_note"
