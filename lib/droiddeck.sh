# shellcheck shell=bash
# Everything that talks to DroidDeck's own helpers. Each path can be overridden from the environment,
# so a renamed or moved helper in a future DroidDeck build is a one-variable fix.

STEAM_ROOT=${STEAM_ROOT:-$HOME/.local/share/Steam}
PROTON_RUN=${DROIDDECK_PROTON_RUN:-$(command -v droiddeck-proton-run 2>/dev/null || echo /usr/local/bin/droiddeck-proton-run)}
INNOEXTRACT=${DROIDDECK_INNOEXTRACT:-$(command -v droiddeck-innoextract 2>/dev/null || command -v innoextract 2>/dev/null || echo /usr/local/bin/droiddeck-innoextract)}
MSITOOLS_DIR=${DROIDDECK_MSITOOLS:-/usr/local/lib/droiddeck-msitools}
# DroidDeck's Python helpers, which 7thDroid loads to ask DroidDeck's own code rather than copy it.
DROIDDECK_BIN=${DROIDDECK_BIN:-/usr/local/bin}
SHORTCUTS_TOOL=${DROIDDECK_STEAM_SHORTCUTS:-$DROIDDECK_BIN/droiddeck-steam-shortcuts}
PROTON_EXTRA=${DROIDDECK_PROTON_EXTRA:-$DROIDDECK_BIN/droiddeck-proton-extra}
STEAM_LAUNCH=${DROIDDECK_STEAM_LAUNCH:-$DROIDDECK_BIN/droiddeck-steam-launch}
APPS_DIR=${DROIDDECK_APPS_DIR:-/opt/droiddeck-apps}
EXTRA_LIBRARIES=(/mnt/droiddeck-sd /mnt/droiddeck)

# The FEX settings DroidDeck's droiddeck-game-env gives .NET programs (DOTNET_FEX). x87 full precision
# is also what keeps InnoSetup installers from aborting with "File not fpund".
DOTNET_FEX=(
  FEX_TSOENABLED=1
  FEX_VECTORTSOENABLED=1
  FEX_MEMCPYSETTSOENABLED=1
  FEX_HALFBARRIERTSOENABLED=1
  FEX_X87REDUCEDPRECISION=0
  FEX_MULTIBLOCK=0
)

HAVE_INNOEXTRACT=0
HAVE_7Z=0
HAVE_SHORTCUTS_TOOL=0
HAVE_APPS_DIR=0

preflight() {
  local missing=() line
  [ -x "$PROTON_RUN" ] || missing+=("droiddeck-proton-run (looked for $PROTON_RUN; set DROIDDECK_PROTON_RUN to override)")
  [ -d "$STEAM_ROOT" ] || missing+=("a Steam installation at $STEAM_ROOT (set STEAM_ROOT to override, or open Steam in DroidDeck once)")
  have curl || missing+=("curl")
  have python3 || missing+=("python3")
  local module
  for module in steam-compatibility droiddeck-proton-run; do
    [ -f "$DROIDDECK_BIN/$module" ] || missing+=("$DROIDDECK_BIN/$module (set DROIDDECK_BIN to the folder that has it)")
  done
  if [ ${#missing[@]} -gt 0 ]; then
    printf '    Missing: %s\n' "${missing[@]}" >&2
    die "$APP_NAME needs the pieces above. It is meant to run inside DroidDeck's Linux environment."
  fi
  local outdated
  if ! outdated=$(python "$LIB_DIR/proton_tool.py" check "$DROIDDECK_BIN" 2>&1); then
    debug "DroidDeck's helpers lack what $APP_NAME uses:"
    while IFS= read -r line; do debug "  $line"; done <<< "$outdated"
    die "This DroidDeck is too old for $APP_NAME, which needs DroidDeck 0.6.7 or newer (its DroidDeck-Proton support).
Update the DroidDeck app, then open $APP_NAME again."
  fi
  debug "droiddeck-proton-run: $PROTON_RUN"
  debug "Steam root: $STEAM_ROOT"

  [ -x "$INNOEXTRACT" ] && HAVE_INNOEXTRACT=1
  [ -x "$MSITOOLS_DIR/7z" ] && HAVE_7Z=1
  [ -f "$SHORTCUTS_TOOL" ] && HAVE_SHORTCUTS_TOOL=1
  [ -d "$APPS_DIR" ] && [ -w "$APPS_DIR" ] && HAVE_APPS_DIR=1
  if [ "$HAVE_INNOEXTRACT" = 1 ]; then debug "innoextract: $INNOEXTRACT"; else info "innoextract not found: installers will be run instead of unpacked."; fi
  if [ "$HAVE_7Z" = 1 ]; then debug "7z: $MSITOOLS_DIR/7z"; else info "7z not found: CD images (.iso) cannot be unpacked; extracted disc folders still work."; fi
  if [ "$HAVE_SHORTCUTS_TOOL" = 1 ]; then debug "steam shortcuts tool: $SHORTCUTS_TOOL"; else info "droiddeck-steam-shortcuts not found: adding to Steam is unavailable."; fi
  if [ "$HAVE_APPS_DIR" = 1 ]; then debug "app entries: $APPS_DIR"; else info "$APPS_DIR not found: adding to the DroidDeck app is unavailable."; fi
  ok "DroidDeck helpers found."
}

sevenzip() {
  LD_LIBRARY_PATH=$MSITOOLS_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH} "$MSITOOLS_DIR/7z" "$@"
}

# Steam library roots (folders that hold steamapps/), each once.
steam_libraries() {
  python - "$STEAM_ROOT" "${EXTRA_LIBRARIES[@]}" <<'EOF'
import os, re, sys
root, extra = sys.argv[1], sys.argv[2:]
candidates = [root]
for vdf in ("steamapps/libraryfolders.vdf", "config/libraryfolders.vdf"):
    try:
        with open(os.path.join(root, vdf), encoding="utf-8", errors="replace") as f:
            candidates += [m.replace("\\\\", "\\") for m in re.findall(r'"path"\s+"([^"]+)"', f.read())]
    except OSError:
        pass
seen = set()
for lib in candidates + extra:
    try:
        st = os.stat(os.path.join(lib, "steamapps"))
    except OSError:
        continue
    if (st.st_dev, st.st_ino) not in seen:
        seen.add((st.st_dev, st.st_ino))
        print(lib)
EOF
}

# acf_value FILE KEY
acf_value() {
  sed -n 's/^[[:space:]]*"'"$2"'"[[:space:]]*"\(.*\)"[[:space:]]*$/\1/Ip' "$1" 2>/dev/null | head -n1
}

# steam_app_installed APPID -> prints "library<TAB>install dir" when fully installed
steam_app_installed() {
  local appid=$1 lib manifest dir flags
  while IFS= read -r lib; do
    manifest=$lib/steamapps/appmanifest_$appid.acf
    [ -f "$manifest" ] || continue
    flags=$(acf_value "$manifest" StateFlags)
    dir=$(acf_value "$manifest" installdir)
    [[ $flags =~ ^[0-9]+$ ]] && [ $((flags & 4)) -ne 0 ] || continue
    [ -n "$dir" ] && [ -d "$lib/steamapps/common/$dir" ] || continue
    printf '%s\t%s\n' "$lib" "$lib/steamapps/common/$dir"
    return 0
  done < <(steam_libraries)
  return 1
}

# The newest DroidDeck-Proton build DroidDeck has adopted -> "name<TAB>dir"
droiddeck_proton() {
  proton_tool find "$DROIDDECK_BIN" "$STEAM_ROOT"
}

# The tool droiddeck-proton-run will start PREFIX_ID's programs with.
chosen_proton() {
  proton_tool chosen "$DROIDDECK_BIN" "$STEAM_ROOT" "$1"
}

# proton_tool ARGS... - lib/proton_tool.py, with anything it reports (such as a DroidDeck helper that
# differs from the one 7thDroid was written against) kept in the log.
proton_tool() {
  local err rc line
  err=$(mktemp)
  python "$LIB_DIR/proton_tool.py" "$@" 2>"$err"
  rc=$?
  if [ -s "$err" ]; then
    debug "proton_tool.py $1 said:"
    while IFS= read -r line; do debug "  $line"; done < "$err"
  fi
  rm -f "$err"
  return $rc
}

# The DroidDeck-Proton folders in compatibilitytools.d, whatever DroidDeck made of them.
droiddeck_proton_folders() {
  local folder
  for folder in "$STEAM_ROOT"/compatibilitytools.d/DroidDeck-Proton*/; do
    [ -f "$folder/toolmanifest.vdf" ] && printf '%s\n' "$(basename "$folder")"
  done
}

# DroidDeck registers (adopts) the tools in compatibilitytools.d and applies per-game choices to
# Steam's CompatToolMapping. droiddeck-proton-extra runs this itself after an install.
steam_compatibility() {
  run python "$DROIDDECK_BIN/steam-compatibility" "$STEAM_ROOT" >> "$LOG_FILE" 2>&1
}

# ensure_droiddeck_proton -> PROTON_NAME, PROTON_DIR. 7th Heaven is only run with DroidDeck-Proton.
ensure_droiddeck_proton() {
  step "Checking for DroidDeck-Proton"
  local found free
  found=$(droiddeck_proton)
  if [ -z "$found" ] && [ -n "$(droiddeck_proton_folders)" ]; then
    info "DroidDeck-Proton is installed but not registered yet; registering it."
    steam_compatibility
    found=$(droiddeck_proton)
    # It is on disk: downloading it again would not help, so say what was found instead.
    [ -n "$found" ] || [ "$DRY_RUN" = 1 ] || die "DroidDeck-Proton is installed ($(droiddeck_proton_folders | paste -sd, -)), but 7thDroid could not use it.
Please report this with the log: $LOG_FILE"
  fi
  if [ -z "$found" ]; then
    [ "$DRY_RUN" = 1 ] && { warn "DroidDeck-Proton is not installed (continuing because of --dry-run)."; PROTON_NAME=DroidDeck-Proton PROTON_DIR=DroidDeck-Proton; return; }
    warn "DroidDeck-Proton is not installed. 7th Heaven needs it."
    free=$(df -Pk "$STEAM_ROOT" 2>/dev/null | awk 'NR == 2 { print $4 * 1024 }')
    info "It is downloaded from github.com/Droid-Deck/DroidDeck-Proton (several hundred MB) and needs about 4 GB free${free:+; $((free / 1073741824)) GB is free}."
    if [ ! -f "$PROTON_EXTRA" ] || ! ask_yn "Install the newest DroidDeck-Proton now?" y \
       || ! run python "$PROTON_EXTRA" "$STEAM_ROOT" droiddeck; then
      die "DroidDeck-Proton is required. Install it from the DroidDeck app's Proton settings, or run:
    droiddeck-proton-extra $STEAM_ROOT droiddeck
and then run this installer again."
    fi
    found=$(droiddeck_proton)
    [ -n "$found" ] || die "DroidDeck-Proton was downloaded but DroidDeck did not register it. See $LOG_FILE."
  fi
  IFS=$'\t' read -r PROTON_NAME PROTON_DIR <<< "$found"
  ok "Using $PROTON_DIR"
}

# pin_proton PREFIX_ID - make droiddeck-proton-run start this prefix's programs with DroidDeck-Proton,
# through the same per-game choice the DroidDeck app writes. Nothing else's choice is changed.
pin_proton() {
  local id=$1 chosen
  [ "$DRY_RUN" = 1 ] && { info "Would make sure prefix $id runs with $PROTON_DIR."; return 0; }
  chosen=$(chosen_proton "$id")
  if [ "$chosen" = "$PROTON_NAME" ]; then
    ok "Prefix $id runs with $PROTON_DIR."
    return 0
  fi
  info "Prefix $id would run with ${chosen:-nothing}; asking DroidDeck to use $PROTON_DIR for it."
  python "$LIB_DIR/proton_tool.py" request "$DROIDDECK_BIN" "$id" "$PROTON_DIR" \
    || die "Could not write DroidDeck's per-game Proton choice (~/.local/share/droiddeck-compat/games.json)."
  while true; do
    if ! steam_running; then
      steam_compatibility
    fi
    chosen=$(chosen_proton "$id")
    [ "$chosen" = "$PROTON_NAME" ] && { ok "Prefix $id runs with $PROTON_DIR."; return 0; }
    if steam_running && [ "$ASSUME_YES" != 1 ] \
       && ask_yn "Steam keeps its Proton choices while it runs. Close Steam, then answer yes to retry" y; then
      continue
    fi
    die "droiddeck-proton-run would still use ${chosen:-no Proton} for prefix $id, not $PROTON_DIR.
DroidDeck applies the choice when Steam is closed: close Steam (or restart the DroidDeck session) and run this installer again."
  done
}

# Is a wineserver running for this compatdata's prefix?
prefix_busy() {
  local pfx=${1%/}/pfx p comm
  for p in /proc/[0-9]*; do
    comm=$(cat "$p/comm" 2>/dev/null) || continue
    [[ $comm == wineserver* ]] || continue
    tr '\0' '\n' < "$p/environ" 2>/dev/null | grep -Fxq -e "WINEPREFIX=$pfx" -e "WINEPREFIX=$pfx/" && return 0
  done
  return 1
}

# wait_prefix_idle COMPATDATA [timeout seconds]
wait_prefix_idle() {
  local compatdata=$1 limit=${2:-3600} waited=0
  [ "$DRY_RUN" = 1 ] && return 0
  sleep 2
  while prefix_busy "$compatdata"; do
    if [ $waited -eq 0 ]; then info "Waiting for Windows programs in the prefix to finish..."; fi
    sleep 3
    waited=$((waited + 3))
    [ $waited -ge "$limit" ] && { warn "Still busy after ${limit}s; continuing."; return 1; }
  done
  return 0
}

# proton_run COMPATDATA PROGRAM [ARGS...] - a normal launch: the user's game environment applies.
proton_run() {
  local compatdata=$1 program=$2
  shift 2
  check_compatdata "$compatdata"
  run "$PROTON_RUN" --prefix "${compatdata##*/}" "$program" "$@"
}

# fex_run COMPATDATA PROGRAM [ARGS...] - for installers. The run verb keeps droiddeck-game-env from
# applying the user's FEX preset, so the DOTNET_FEX values set here are the ones FEX sees.
fex_run() {
  local compatdata=$1 program=$2 rc
  shift 2
  check_compatdata "$compatdata"
  run env "${DOTNET_FEX[@]}" "$PROTON_RUN" --verb run --prefix "${compatdata##*/}" "$program" "$@"
  rc=$?
  wait_prefix_idle "$compatdata"
  return $rc
}

# droiddeck-proton-run --prefix ID always uses the client's own steamapps/compatdata/ID.
compatdata_for() {
  [[ $1 =~ ^[1-9][0-9]*$ ]] || die "Not a prefix id: '$1'"
  printf '%s\n' "$STEAM_ROOT/steamapps/compatdata/$1"
}

# 7thDroid only ever runs programs in, or writes to, its own prefix: one under the client's own
# steamapps/compatdata. Anything else is a bug, and must never reach another game's prefix.
check_compatdata() {
  local id=${1##*/}
  [[ $id =~ ^[1-9][0-9]*$ ]] && [ "$1" = "$STEAM_ROOT/steamapps/compatdata/$id" ] \
    || die "Internal error: refusing to use prefix '$1'"
  [ "$id" = "${PREFIX_ID:-$id}" ] || die "Internal error: '$1' is not 7thDroid's prefix"
}

steam_running() {
  local p comm
  for p in /proc/[0-9]*; do
    comm=$(cat "$p/comm" 2>/dev/null) || continue
    case $comm in steam|steamwebhelper) return 0 ;; esac
  done
  return 1
}
