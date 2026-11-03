# shellcheck shell=bash
# FINAL FANTASY VII from a path the user gives: an installed folder, a GOG installer, or the 1998 CD-ROM
# release as disc images or copied disc folders.
#
# manual_source sets SOURCE_KIND and, depending on it:
#   folder      GAME_DIR, GAME_EXE
#   gog-setup   GOG_SETUP (and GAME_DIR once unpacked)
#   cd          CD_DISCS (folders, disc 1 first)

FF7_CD_LABELS=(FF7DISC1 FF7DISC2 FF7DISC3)

is_iso() { [[ ${1,,} == *.iso ]]; }
is_exe() { [[ ${1,,} == *.exe ]]; }

# A folder holding a 1998 disc: its root has an installer and an FF7 data folder.
is_cd_folder() {
  local dir=$1
  compgen -G "$dir/[Ss][Ee][Tt][Uu][Pp].[Ee][Xx][Ee]" >/dev/null \
    || compgen -G "$dir/[Ff][Ff]7*/" >/dev/null
}

# pick_source ARRAY - the same choices as a typed path, with a file picker that starts in Downloads.
pick_source() {
  local -n __paths=$1
  local kind reply
  choose kind "Where is your copy of FINAL FANTASY VII?" \
    "An installed game folder (copied from a PC or another launcher)" \
    "A GOG installer (setup_final_fantasy_vii_....exe)" \
    "1998 CD-ROM disc images (.iso)" \
    "Folders copied from the 1998 CD-ROMs"
  case $kind in
    0) ui_paths reply "Choose the folder that holds FF7's .exe" folder ;;
    1) ui_paths reply "Choose the GOG installer" file "GOG installer | *.exe *.EXE" ;;
    2) ui_paths reply "Choose the disc images (select all discs)" files "Disc images | *.iso *.ISO" ;;
    3) ui_paths reply "Choose the disc folders (select all discs)" folders ;;
  esac
  mapfile -t __paths <<< "$reply"
  [ -n "${__paths[0]:-}" ] || __paths=()
}

manual_source() {
  local paths=("$@") path exe isos=() dirs=()
  while [ ${#paths[@]} -eq 0 ]; do
    if [ "$UI_MODE" = zenity ] && [ "$ASSUME_YES" != 1 ]; then
      pick_source paths
      continue
    fi
    info "No installed copy of FINAL FANTASY VII was found automatically."
    info "Enter the path to one of the following (Android's Downloads folder is /root/Storage/Download):"
    info "  - an installed FF7 folder (from a PC, a store, etc.)"
    info "  - a GOG installer (setup_final_fantasy_vii_*.exe)"
    info "  - 1998 CD-ROM images (.iso), a folder of them, or folders copied from the discs"
    local reply
    ask reply "Path(s), separated by spaces if more than one (quote paths with spaces)"
    [ -n "$reply" ] || { [ "$ASSUME_YES" = 1 ] && die "No game source given (use --source)."; continue; }
    eval "paths=($reply)" 2>/dev/null || { warn "Could not read that; check the quoting."; paths=(); }
  done

  for path in "${paths[@]}"; do
    path=${path/#\~/$HOME}
    [ -e "$path" ] || die "$path does not exist."
    path=$(readlink -f "$path")
    if [ -d "$path" ]; then
      if exe=$(find_game_exe "$path") && [ -n "$exe" ]; then
        SOURCE_KIND=folder GAME_EXE=$exe GAME_DIR=${exe%/*}
        return
      fi
      if is_cd_folder "$path"; then
        dirs+=("$path")
        continue
      fi
      local iso
      while IFS= read -r iso; do isos+=("$iso"); done < <(find "$path" -maxdepth 1 -type f -iname '*.iso' | sort)
      [ ${#isos[@]} -gt 0 ] || die "$path has no FF7 executable, disc images or disc contents."
    elif is_iso "$path"; then
      isos+=("$path")
    elif is_exe "$path"; then
      SOURCE_KIND=gog-setup GOG_SETUP=$path
      return
    else
      die "$path is not a folder, a disc image or an installer."
    fi
  done

  if [ ${#isos[@]} -gt 0 ]; then
    [ "$HAVE_7Z" = 1 ] || die "Unpacking .iso files needs DroidDeck's 7z ($MSITOOLS_DIR/7z). Extract the discs to folders and give those instead."
    local i=1 iso dest
    for iso in "${isos[@]}"; do
      dest=$DATA_DIR/cd/disc$i
      if [ -d "$dest" ] && [ "$(cat "$dest/.$APP_ID-source" 2>/dev/null)" = "$iso" ]; then
        info "Disc $i already unpacked."
      else
        info "Unpacking ${iso##*/} (disc $i)"
        run rm -rf "$dest"
        run mkdir -p "$dest"
        run sevenzip x -y -o"$dest" "$iso" >/dev/null || die "Could not unpack $iso."
        [ "$DRY_RUN" = 1 ] || printf '%s\n' "$iso" > "$dest/.$APP_ID-source"
      fi
      dirs+=("$dest")
      i=$((i + 1))
    done
  fi
  [ ${#dirs[@]} -le 3 ] || die "FF7 has three discs; ${#dirs[@]} were given."
  SOURCE_KIND=cd CD_DISCS=("${dirs[@]}")
}

# The GOG installer is InnoSetup: innoextract unpacks it without Wine, and so without the FEX x87
# problem. Running it is the fallback; that needs the prefix, so it happens in install_pending_game.
unpack_gog_setup() {
  local exe
  ask GAME_DIR "Folder to put the game in" "${GAME_DIR:-$HOME/Games/FINAL FANTASY VII}"
  [ -n "$GAME_DIR" ] || die "No folder given."
  GAME_DIR=${GAME_DIR/#\~/$HOME}
  if exe=$(find_game_exe "$GAME_DIR" 2>/dev/null) && [ -n "$exe" ]; then
    info "The game is already in $GAME_DIR."
    GAME_EXE=$exe
    SOURCE_KIND=folder
    return 0
  fi
  [ "$HAVE_INNOEXTRACT" = 1 ] || return 1
  local staging=$GAME_DIR.$APP_ID-unpack
  info "Unpacking ${GOG_SETUP##*/} with innoextract"
  run rm -rf "$staging"
  run mkdir -p "$staging"
  if ! run "$INNOEXTRACT" --gog --exclude-temp --silent --progress -d "$staging" "$GOG_SETUP"; then
    warn "innoextract could not unpack this installer; it will be run instead."
    run rm -rf "$staging"
    return 1
  fi
  if [ "$DRY_RUN" = 1 ]; then
    GAME_EXE=$GAME_DIR/FFVII.exe
  else
    move_unpacked_game "$staging" || return 1
  fi
  SOURCE_KIND=folder
  ok "Unpacked to $GAME_DIR"
}

# move_unpacked_game STAGING - innoextract strips {app}, so the game lands at the top of STAGING, while
# GOG's own support files (goggame-*.ico, webcache.zip) land in app/. Like DroidDeck's GOG store, the
# two are merged into GAME_DIR, and the folders for other Windows locations (tmp, ...) are left out.
move_unpacked_game() {
  local staging=$1 exe root entry
  exe=$(find_game_exe "$staging")
  if [ -z "$exe" ]; then
    warn "The unpacked files have no FF7 executable; the installer will be run instead."
    debug "Unpacked files:"$'\n'"$(cd "$staging" && find . -maxdepth 2 | sort | head -n 60)"
    debug "Installer contents:"$'\n'"$("$INNOEXTRACT" --list "$GOG_SETUP" 2>&1 | head -n 40)"
    rm -rf -- "$staging"
    return 1
  fi
  root=$staging
  [[ $exe == "$staging/app/"* ]] && root=$staging/app
  mkdir -p "$GAME_DIR" || die "Could not create $GAME_DIR."
  for entry in "$root"/* "$root"/.[!.]*; do
    [ -e "$entry" ] || continue
    if [ "$root" = "$staging" ]; then
      case ${entry##*/} in app|tmp|commonappdata|userappdata|localappdata) continue ;; esac
    fi
    rm -rf -- "${GAME_DIR:?}/${entry##*/}"
    mv -- "$entry" "$GAME_DIR/" || die "Could not move the game into $GAME_DIR."
  done
  if [ "$root" = "$staging" ] && [ -d "$staging/app" ]; then
    for entry in "$staging"/app/* "$staging"/app/.[!.]*; do
      [ -e "$entry" ] && [ ! -e "$GAME_DIR/${entry##*/}" ] && mv -- "$entry" "$GAME_DIR/"
    done
  fi
  rm -rf -- "$staging"
  GAME_EXE=$(find_game_exe "$GAME_DIR")
  [ -n "$GAME_EXE" ] || die "The game was unpacked, but no FF7 executable is in $GAME_DIR."
}

# Wine CD drives for the discs: d:, e:, f:, each with the label FF7 checks for.
map_cd_drives() {
  local compatdata=$1 i letters=(d e f) disc drive entry
  CD_DRIVES=()
  for i in "${!CD_DISCS[@]}"; do
    disc=${CD_DISCS[$i]}
    drive=$disc
    # A folder the user gave is never written to: the drive is a folder of links to its contents,
    # which can carry the label. Discs 7thDroid unpacked itself get the label directly.
    if [[ $disc != "$DATA_DIR/cd/"* ]]; then
      drive=$DATA_DIR/cd/drive$((i + 1))
      if [ "$DRY_RUN" != 1 ]; then
        rm -rf -- "$drive"
        mkdir -p "$drive"
        for entry in "$disc"/* "$disc"/.[!.]*; do
          [ -e "$entry" ] || continue
          case ${entry##*/} in .windows-label|.windows-serial) continue ;; esac
          ln -s "$entry" "$drive/${entry##*/}"
        done
      fi
      CD_DISCS[$i]=$drive
    fi
    run ln -sfn "$drive" "$compatdata/pfx/dosdevices/${letters[$i]}:"
    [ "$DRY_RUN" = 1 ] || {
      printf '%s\n' "${FF7_CD_LABELS[$i]}" > "$drive/.windows-label"
      printf '%s\n' "4400000$i" > "$drive/.windows-serial"
    }
    CD_DRIVES+=("${letters[$i]}:")
  done
}

# Runs whatever installer the source still needs, now that the prefix exists.
install_pending_game() {
  local compatdata=$1 setup
  case $SOURCE_KIND in
    gog-setup)
      info "Running the GOG installer. Accept the defaults, or install anywhere you like."
      fex_run "$compatdata" "$GOG_SETUP" /DIR="$(winpath "$GAME_DIR")" \
        || warn "The installer reported an error."
      ;;
    cd)
      setup=$(find -L "${CD_DISCS[0]}" -maxdepth 1 -type f \( -iname 'setup.exe' -o -iname 'install.exe' \) | head -n1)
      [ -n "$setup" ] || die "Disc 1 has no setup.exe."
      info "Running the CD installer from drive d:. Choose a full install if it asks."
      fex_run "$compatdata" "$setup" || warn "The installer reported an error."
      GAME_DIR=$compatdata/pfx/drive_c
      ;;
    *) return 0 ;;
  esac
  [ "$DRY_RUN" = 1 ] && { GAME_EXE=$GAME_DIR/FFVII.exe; return; }
  GAME_EXE=$(find_game_exe "$GAME_DIR")
  [ -n "$GAME_EXE" ] || die "The installer finished, but no FF7 executable was found in $GAME_DIR."
  GAME_DIR=${GAME_EXE%/*}
  ok "FINAL FANTASY VII installed at $GAME_DIR"
}

game_copy_dir() { printf '%s\n' "$1/pfx/drive_c/FINAL FANTASY VII"; }

# ask_game_copy COMPATDATA -> GAME_COPY_ACTION: copy, reuse (a copy already in the prefix) or none.
# 7th Heaven writes into the game folder (its patched exe, workingdir); a copy inside its prefix keeps
# the original untouched. The prefix may not exist yet, so free space is checked where it will be.
ask_game_copy() {
  local compatdata=$1 dest need free size where
  dest=$(game_copy_dir "$compatdata")
  GAME_COPY_ACTION=none
  case $GAME_DIR in "$compatdata"/*) return 0 ;; esac
  if [ -n "$(find_game_exe "$dest" 2>/dev/null)" ]; then
    want_entry WANT_GAME_COPY "7th Heaven's prefix already has a copy of FINAL FANTASY VII. Keep using that copy, so the original game files are never changed?" \
      && GAME_COPY_ACTION=reuse
    return 0
  fi
  need=$(du -sk "$GAME_DIR" 2>/dev/null | cut -f1)
  size=$(awk -v k="${need:-0}" 'BEGIN { printf "%.1f", k / 1048576 }')
  want_entry WANT_GAME_COPY "Copy FINAL FANTASY VII ($size GB) into 7th Heaven's prefix, so 7th Heaven never changes the original game files?" \
    || return 0
  where=$compatdata
  while [ ! -d "$where" ] && [ "$where" != / ]; do where=$(dirname "$where"); done
  free=$(df -Pk "$where" 2>/dev/null | awk 'NR == 2 { print $4 }')
  if [ -n "$free" ] && [ "$free" -lt $((${need:-0} + 512 * 1024)) ]; then
    warn "There isn't room for a $size GB copy next to 7th Heaven's prefix."
    ask_yn "Use the original game files instead?" y || die "Not enough space to copy the game. Free some space and try again."
    return 0
  fi
  GAME_COPY_SIZE=$size
  GAME_COPY_ACTION=copy
}

# copy_game COMPATDATA - carries out ask_game_copy's answer; GAME_DIR and GAME_EXE then point at the copy.
copy_game() {
  local compatdata=$1 dest
  dest=$(game_copy_dir "$compatdata")
  case $GAME_COPY_ACTION in
    reuse) info "Using the copy of the game already in 7th Heaven's prefix." ;;
    copy)
      step "Copying FINAL FANTASY VII"
      info "Copying the game ($GAME_COPY_SIZE GB) to $dest. This takes a few minutes."
      if [ "$DRY_RUN" != 1 ]; then
        rm -rf -- "$dest.part"
        mkdir -p "$dest.part"
        cp -a -- "$GAME_DIR/." "$dest.part/" || { rm -rf -- "$dest.part"; die "Copying the game to $dest failed."; }
        rm -rf -- "$dest"
        mv -- "$dest.part" "$dest" || die "Could not move the copied game to $dest."
      fi
      ok "Copied the game into 7th Heaven's prefix." ;;
    *) return 0 ;;
  esac
  GAME_EXE=$dest/${GAME_EXE#"$GAME_DIR"/}
  GAME_DIR=$dest
  GAME_COPY=1
}
