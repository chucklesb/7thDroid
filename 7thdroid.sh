#!/bin/bash
# 7thDroid: installs the 7th Heaven mod manager for FINAL FANTASY VII on DroidDeck, then offers a menu to
# launch 7th Heaven (with or without Steam), update or repair it, read the log or uninstall it.
# Run it as: bash 7thdroid.sh   (Android shared storage is mounted noexec)

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SELF=$ROOT_DIR/7thdroid.sh
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
# shellcheck source=lib/installer.sh
. "$LIB_DIR/installer.sh"
# shellcheck source=lib/menu.sh
. "$LIB_DIR/menu.sh"

usage() {
  cat <<EOF
Usage: bash 7thdroid.sh [task] [options]

With no task, 7thDroid shows its menu: Install 7th Heaven until it is installed, then launching,
updating, the log and uninstalling. A task runs on its own instead:

  --install                        Install 7th Heaven, or update or repair it (--yes implies this)
  --steam-shortcut                 Add 7th Heaven's Steam entry, for "Launch 7th Heaven with Steam"
  --uninstall                      Remove 7th Heaven's prefix, launcher, Steam entry and downloads

Options:
  --version stable|canary          7th Heaven build: the newest release, or the newest development build
                                   (asked when not given)
  --source PATH                    Use this game instead of searching: an installed FF7 folder, a GOG
                                   installer, CD images (.iso) or disc folders. Repeat for several discs.
  --game-dir DIR                   Where a GOG installer puts the game (default ~/Games/FINAL FANTASY VII)
  --copy-game / --no-copy-game     Copy (or don't) an installed game into 7th Heaven's prefix, so the
                                   original is never changed (asked when not given)
  --winetricks-dinput              Also run winetricks' dinput verb, when a Proton with protonfixes exists
  --reinstall                      Run every step again, even ones that look done
  --yes                            Accept every default without asking
  --dry-run                        Print what would run without changing anything
  -h, --help                       Show this help
EOF
}

TASK='' ARGS=("$@")
SEVENTH_CHANNEL='' SOURCES=() GAME_DIR='' REINSTALL=0 WINETRICKS_DINPUT=0
WANT_GAME_COPY=''
CD_DISCS=() CD_DRIVES=()

# shellcheck disable=SC2034 # WANT_GAME_COPY is read by name in want_entry
while [ $# -gt 0 ]; do
  case $1 in
    --install) TASK=install ;;
    --steam-shortcut) TASK=steam-shortcut ;;
    --uninstall) TASK=uninstall ;;
    --version) SEVENTH_CHANNEL=${2:?--version needs a value}; shift ;;
    --version=*) SEVENTH_CHANNEL=${1#*=} ;;
    --source) SOURCES+=("${2:?--source needs a path}"); shift ;;
    --source=*) SOURCES+=("${1#*=}") ;;
    --game-dir) GAME_DIR=${2:?--game-dir needs a path}; shift ;;
    --game-dir=*) GAME_DIR=${1#*=} ;;
    --copy-game) WANT_GAME_COPY=1 ;;
    --no-copy-game) WANT_GAME_COPY=0 ;;
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
# A menu can't take its defaults, so --yes on its own means installing.
[ -z "$TASK" ] && [ "$ASSUME_YES" = 1 ] && TASK=install

ui_init
if [ -z "$TASK" ]; then
  run_menu
  exit 0
fi

start_log
ui_progress_start
trap 'ui_progress_stop; finish_log' EXIT
printf '%s%s%s - 7th Heaven for FINAL FANTASY VII on DroidDeck\n' "$C_BOLD" "$APP_NAME" "$C_RESET"
[ "$TASK" = install ] && show_warning
info "Log: $LOG_FILE"
[ "$DRY_RUN" = 1 ] && info "Dry run: nothing will be changed."

step "Checking the environment"
preflight

PREFIX_ID=$(dedicated_prefix_id) || die "Could not work out 7thDroid's prefix id."
DEDICATED=$(compatdata_for "$PREFIX_ID")

case $TASK in
  uninstall)
    uninstall && ui_done "7th Heaven is uninstalled. Your FF7 game files were not touched." ;;
  steam-shortcut)
    load_state || die "No earlier install found ($STATE_FILE). Run the full installer first."
    [ "$COMPATDATA" = "$DEDICATED" ] || die "The last install was made by an older $APP_NAME. Run the full installer once."
    write_launcher "$(seventh_exe "$COMPATDATA")" "$(ff7_steam_appid)"
    step "Adding 7th Heaven to Steam"
    add_steam_shortcut ask || exit 1 ;;
  install)
    run_install ;;
esac
exit 0
