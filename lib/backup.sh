# shellcheck shell=bash
# Backups of 7th Heaven: FF7's saves, 7th Heaven's settings and profiles, FFNx's settings and, if
# wanted, the mods. Each is one .tar in Android's Documents folder, so it outlives 7th Heaven's prefix,
# 7thDroid's own data and DroidDeck itself. Restoring keeps this install's game and library paths.

backup_dir() {
  if [ -n "${SEVENTHDROID_BACKUP_DIR:-}" ]; then
    printf '%s\n' "$SEVENTHDROID_BACKUP_DIR"
  elif [ -d /root/Storage ]; then
    printf '%s\n' "/root/Storage/Documents/$APP_NAME Backups"
  else
    printf '%s\n' "$HOME/$APP_NAME Backups"
  fi
}

seventh_workshop() { printf '%s\n' "$COMPATDATA/pfx/drive_c/7th Heaven/7thWorkshop"; }

# The mod library 7th Heaven's settings name, or its default.
seventh_library() {
  python "$LIB_DIR/ffnx.py" path "$(ffnx_settings_xml "$COMPATDATA")" "$COMPATDATA/pfx/drive_c" LibraryLocation 2>/dev/null \
    || printf '%s\n' "$COMPATDATA/pfx/drive_c/7th Heaven/mods"
}

# The folder 7th Heaven runs FF7 from: its FF7Exe's, or ff7/workingdir in it (the 2026 and GOG releases,
# before 7th Heaven has switched FF7Exe there).
ff7_game_dir() {
  local exe dir
  exe=$(python "$LIB_DIR/ffnx.py" path "$(ffnx_settings_xml "$COMPATDATA")" "$COMPATDATA/pfx/drive_c" FF7Exe 2>/dev/null) \
    && dir=${exe%/*} || dir=$GAME_DIR
  [ -d "$dir/ff7/workingdir" ] && dir=$dir/ff7/workingdir
  printf '%s\n' "$dir"
}

# Where FF7 keeps its saves: the 2013 Steam release in the prefix's Documents, the others beside the game.
ff7_save_dir() {
  local docs
  if [ "$FF7_VERSION" = Steam ]; then
    for docs in "$COMPATDATA/pfx/drive_c/users/steamuser/Documents" "$COMPATDATA/pfx/drive_c/users/steamuser/My Documents"; do
      [ -d "$docs/Square Enix/FINAL FANTASY VII Steam" ] && { printf '%s\n' "$docs/Square Enix/FINAL FANTASY VII Steam"; return; }
    done
    printf '%s\n' "$COMPATDATA/pfx/drive_c/users/steamuser/Documents/Square Enix/FINAL FANTASY VII Steam"
  else
    printf '%s/save\n' "$(ff7_game_dir)"
  fi
}

# manifest_value FILE KEY - a line KEY=VALUE of a backup's manifest.env, read as text, never run.
manifest_value() {
  python "$LIB_DIR/backup.py" manifest "$1" 2>/dev/null | sed -n "s/^$2=//p" | head -n1
}

# list_backups -> one "FILE<TAB>LABEL" line per backup, newest first
list_backups() {
  local dir file date tag mods label
  dir=$(backup_dir)
  [ -d "$dir" ] || return 0
  while IFS= read -r file; do
    date=$(manifest_value "$file" BACKUP_DATE) || continue
    [ -n "$date" ] || continue
    tag=$(manifest_value "$file" SEVENTH_TAG)
    mods=$(manifest_value "$file" MODS_KB)
    label="$date - 7th Heaven ${tag:-?}"
    if [ -n "$mods" ]; then
      label+=", with mods ($(awk -v k="$mods" 'BEGIN { printf "%.1f", k / 1048576 }') GB)"
    else
      label+=", without mods"
    fi
    printf '%s\t%s\n' "$file" "$label"
  done < <(find "$dir" -maxdepth 1 -type f -name "$APP_NAME-*.tar" | sort -r)
}

# The mods' size in KB, without 7th Heaven's temp folder; nothing when there are none.
mods_kb() {
  local lib kb
  lib=$(seventh_library)
  [ -d "$lib" ] && [ -n "$(find "$lib" -mindepth 1 -maxdepth 1 ! -name temp -print -quit)" ] || return 0
  kb=$(du -sk "$lib" 2>/dev/null | cut -f1)
  [ -d "$lib/temp" ] && kb=$(( ${kb:-0} - $(du -sk "$lib/temp" 2>/dev/null | cut -f1) ))
  printf '%s\n' "${kb:-0}"
}

# ask_backup_mods -> BACKUP_MODS 1 or 0: whether the mods go in too (asked with their size)
ask_backup_mods() {
  local kb
  BACKUP_MODS=0
  kb=$(mods_kb)
  [ -n "$kb" ] || return 0
  want_entry WANT_MODS "Include your mods ($(awk -v k="$kb" 'BEGIN { printf "%.1f", k / 1048576 }') GB) in the backup?" y \
    && BACKUP_MODS=1
  return 0
}

# ask_backup -> BACKUP_WANT and BACKUP_MODS, for an install that is about to change or go
ask_backup() {
  BACKUP_WANT=0 BACKUP_MODS=0
  [ "$NO_BACKUP" = 1 ] && return 0
  ask_yn "Back up 7th Heaven first? Your FF7 saves, 7th Heaven settings and profiles, and FFNx settings go to $(backup_dir)." y \
    || return 0
  BACKUP_WANT=1
  ask_backup_mods
}

# make_backup - backs up the install in STATE_FILE (the one there now, even mid-update) -> BACKUP_FILE.
# The state's variables are made local, so loading it leaves the caller's alone.
make_backup() {
  local COMPATDATA SOURCE_KIND APPID GAME_DIR GAME_EXE GAME_COPY FF7_VERSION SEVENTH_CHANNEL SEVENTH_TAG
  local dir stamp file manifest workshop save game lib specs=() need free parts=(workshop saves game) mods_kb=''
  BACKUP_FILE=''
  load_state || { warn "No 7th Heaven install to back up ($STATE_FILE)."; return 1; }
  step "Backing up 7th Heaven"
  dir=$(backup_dir)
  workshop=$(seventh_workshop) save=$(ff7_save_dir) game=$(ff7_game_dir)
  specs=("workshop/settings.xml=$workshop/settings.xml" "workshop/library.xml=$workshop/library.xml"
         "workshop/profiles=$workshop/profiles" "saves=$save" "game/FFNx.toml=$game/FFNx.toml")
  [ "$FF7_VERSION" = Steam ] || specs+=("game/ff7input.cfg=$game/ff7input.cfg")
  if [ "$BACKUP_MODS" = 1 ]; then
    lib=$(seventh_library)
    mods_kb=$(mods_kb)
    [ -n "$mods_kb" ] && { specs+=("mods=$lib!temp"); parts+=(mods); }
  fi
  stamp=$(date +%Y-%m-%d_%H%M%S)
  file="$dir/$APP_NAME-$stamp.tar"
  if [ "$DRY_RUN" = 1 ]; then
    info "Would back up ${parts[*]} to $file"
    return 0
  fi
  mkdir -p "$dir" 2>/dev/null && [ -w "$dir" ] || { warn "Can't write backups to $dir."; return 1; }
  need=$(du -sck "$workshop/settings.xml" "$workshop/library.xml" "$workshop/profiles" "$save" "$game/FFNx.toml" 2>/dev/null | tail -n1 | cut -f1)
  need=$(( ${need:-0} + ${mods_kb:-0} ))
  free=$(df -Pk "$dir" 2>/dev/null | awk 'NR == 2 { print $4 }')
  if [ -n "$free" ] && [ "$free" -lt $((need + 10240)) ]; then
    warn "There isn't room for a $((need / 1024)) MB backup in $dir."
    return 1
  fi
  wait_prefix_idle "$COMPATDATA" 60 || { warn "Something is still running in 7th Heaven's prefix. Close 7th Heaven and FF7 first."; return 1; }
  manifest=$(mktemp) || return 1
  {
    printf 'BACKUP_DATE=%s\n' "$(date '+%Y-%m-%d %H:%M')"
    printf 'APP_VERSION=%s\n' "$(cat "$ROOT_DIR/VERSION" 2>/dev/null)"
    printf 'FF7_VERSION=%s\nSOURCE_KIND=%s\nAPPID=%s\nSEVENTH_TAG=%s\n' "$FF7_VERSION" "$SOURCE_KIND" "$APPID" "$SEVENTH_TAG"
    printf 'PARTS=%s\nMODS_KB=%s\n' "${parts[*]}" "$mods_kb"
  } > "$manifest"
  info "Backing up ${parts[*]} to $file"
  if ! run python "$LIB_DIR/backup.py" create "$file" "$manifest" "${specs[@]}"; then
    rm -f -- "$manifest" "$file.part"
    warn "The backup could not be written to $file."
    return 1
  fi
  rm -f -- "$manifest"
  BACKUP_FILE=$file
  ok "Backed up to $file"
}

# choose_backup VAR "Question" [none label] -> VAR gets a backup file, or nothing for the none label
choose_backup() {
  local __var=$1 question=$2 none=${3:-} lines=() labels=() line pick
  mapfile -t lines < <(list_backups)
  printf -v "$__var" '%s' ''
  [ ${#lines[@]} -gt 0 ] || return 1
  [ -n "$none" ] && labels+=("$none")
  for line in "${lines[@]}"; do labels+=("${line#*$'\t'}"); done
  choose pick "$question" "${labels[@]}"
  [ -n "$none" ] && { [ "$pick" = 0 ] && return 0; pick=$((pick - 1)); }
  printf -v "$__var" '%s' "${lines[$pick]%%$'\t'*}"
}

# restore_backup FILE - into the install in the current variables (COMPATDATA, FF7_VERSION, GAME_DIR)
restore_backup() {
  local file=$1 parts version workshop lib game save status
  step "Restoring a backup"
  parts=$(manifest_value "$file" PARTS)
  [ -n "$parts" ] || { warn "$file is not a $APP_NAME backup."; return 1; }
  workshop=$(seventh_workshop) game=$(ff7_game_dir) save=$(ff7_save_dir)
  info "Restoring $file"
  [ "$DRY_RUN" = 1 ] && return 0
  wait_prefix_idle "$COMPATDATA" 60 || { warn "Something is still running in 7th Heaven's prefix. Close 7th Heaven and FF7 first."; return 1; }

  python "$LIB_DIR/backup.py" settings "$file" "$(ffnx_settings_xml "$COMPATDATA")" || { warn "Could not restore 7th Heaven's settings."; return 1; }
  status=0
  python "$LIB_DIR/backup.py" extract "$file" workshop/profiles "$workshop/profiles" || status=$?
  [ "$status" = 0 ] || [ "$status" = 3 ] || { warn "Could not restore 7th Heaven's profiles."; return 1; }
  info "7th Heaven settings and profiles restored."

  if [[ " $parts " == *" mods "* ]]; then
    lib=$(seventh_library)
    rm -rf -- "$lib.7thdroid-old"
    [ -e "$lib" ] && { mv -- "$lib" "$lib.7thdroid-old" || { warn "Could not set the current mods aside."; return 1; }; }
    mkdir -p "$lib"
    if python "$LIB_DIR/backup.py" extract "$file" mods "$lib" \
       && python "$LIB_DIR/backup.py" extract "$file" workshop/library.xml "$workshop/library.xml"; then
      rm -rf -- "$lib.7thdroid-old"
      info "Mods restored to $lib"
    else
      rm -rf -- "$lib"
      [ -e "$lib.7thdroid-old" ] && mv -- "$lib.7thdroid-old" "$lib"
      warn "Could not restore the mods; the ones you had are kept."
      return 1
    fi
  else
    info "This backup has no mods; your current mods are kept."
  fi

  version=$(manifest_value "$file" FF7_VERSION)
  if [ -n "$version" ] && [ "$version" != "$FF7_VERSION" ]; then
    warn "This backup's saves are from the $version release of FF7; this install uses $FF7_VERSION."
    if ask_yn "Restore those saves anyway? Saves don't always carry over between releases." n; then version=$FF7_VERSION; fi
  fi
  if [ -z "$version" ] || [ "$version" = "$FF7_VERSION" ]; then
    mkdir -p "$save"
    status=0
    python "$LIB_DIR/backup.py" extract "$file" saves "$save" || status=$?
    case $status in
      0) info "Saves restored to $save" ;;
      3) ;;
      *) warn "Could not restore the saves."; return 1 ;;
    esac
  else
    info "The saves were left out."
  fi

  mkdir -p "$game"
  python "$LIB_DIR/backup.py" extract "$file" game/ff7input.cfg "$game/ff7input.cfg" >/dev/null 2>&1 || true
  if [ -f "$game/FFNx.toml" ]; then
    if python "$LIB_DIR/backup.py" extract "$file" game/FFNx.toml "$game/FFNx.toml.7thdroid-restore" 2>/dev/null; then
      python "$LIB_DIR/ffnx.py" merge "$game/FFNx.toml" "$game/FFNx.toml.7thdroid-restore" && rm -f -- "$game/FFNx.toml.7thdroid-restore"
      info "FFNx settings restored."
    fi
  elif python "$LIB_DIR/backup.py" extract "$file" game/FFNx.toml "$game/FFNx.toml.7thdroid-restore" 2>/dev/null; then
    info "FFNx is installed the first time you play; its restored settings apply from the launch after that."
  fi
  ok "Backup restored."
}

# FFNx settings restored before FFNx was installed: merged in once 7th Heaven has installed it.
finish_ffnx_restore() {
  local dir
  for dir in "$(ff7_game_dir)" "$GAME_DIR"; do
    [ -f "$dir/FFNx.toml.7thdroid-restore" ] && [ -f "$dir/FFNx.toml" ] || continue
    python "$LIB_DIR/ffnx.py" merge "$dir/FFNx.toml" "$dir/FFNx.toml.7thdroid-restore" \
      && rm -f -- "$dir/FFNx.toml.7thdroid-restore"
  done
  return 0
}
