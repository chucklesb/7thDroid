# shellcheck shell=bash
# Save logs: DroidDeck's, 7thDroid's, 7th Heaven's and FFNx's logs in one tar in Android's Documents
# folder, each file redacted by lib/redact.py (a port of DroidDeck's own log redactor) on the way in.

logs_dir() { printf '%s\n' "${SEVENTHDROID_LOGS_DIR:-$(android_documents)/$APP_NAME Logs}"; }

# DroidDeck's session logs: the app's files/logs folder, which the Linux side sees at the same path.
droiddeck_log_dir() {
  if [ -n "${DROIDDECK_LOG_DIR:-}" ]; then
    printf '%s\n' "$DROIDDECK_LOG_DIR"
  elif [ -n "${BL_DEBUG_DIR:-}" ] && [ -d "${BL_DEBUG_DIR%/*}" ]; then
    printf '%s\n' "${BL_DEBUG_DIR%/*}"
  else
    printf '%s\n' /data/user/0/com.droiddeck.launcher/files/logs
  fi
}

# write_log_info FILE - what the logs are about: versions, the install, the environment
write_log_info() {
  local ffnx_log
  {
    printf '%s logs, %s\n\n' "$APP_NAME" "$(date '+%Y-%m-%d %H:%M %Z')"
    printf '7thDroid: %s%s\n' "$(cat "$ROOT_DIR/VERSION" 2>/dev/null || echo '?')" "${SEVENTHDROID_APPIMAGE:+ (AppImage)}"
    printf 'System: %s\n' "$(uname -srm 2>/dev/null)"
    printf 'DroidDeck: see its session logs under droiddeck/\n'
    if [ -n "${COMPATDATA:-}" ]; then
      printf '\nFF7: %s (%s%s)\n' "${FF7_VERSION:-?}" "${SOURCE_KIND:-?}" "${APPID:+, app $APPID}"
      printf 'Game copy in the prefix: %s\n' "$([ "${GAME_COPY:-0}" = 1 ] && echo yes || echo no)"
      printf '7th Heaven: %s (%s)\n' "${SEVENTH_TAG:-?}" "${SEVENTH_CHANNEL:-?}"
      printf 'Proton for the prefix: %s\n' "$(chosen_proton "${COMPATDATA##*/}" 2>/dev/null || echo '?')"
      printf 'FFNx: %s' "$(ffnx_state "$COMPATDATA")"
      ffnx_log="$(ff7_game_dir)/FFNx.log"
      [ -f "$ffnx_log" ] && printf ', %s' "$(head -n1 "$ffnx_log" | cut -c1-120)"
      printf '\n'
      printf 'Free space by the prefix: %s\n' "$(df -Ph "$COMPATDATA" 2>/dev/null | awk 'NR == 2 { print $4 }')"
    else
      printf '\n7th Heaven is not installed.\n'
    fi
    printf 'Steam running: %s\n' "$(steam_running && echo yes || echo no)"
  } > "$1"
}

# save_logs -> LOGS_FILE. Works without an install: then it saves what there is.
save_logs() {
  local dir stamp out info items=() f s d name
  LOGS_FILE=''
  step "Saving logs"
  add() { [ -e "$2" ] && items+=("$1=$2"); return 0; }
  info=$(mktemp) || return 1
  write_log_info "$info"
  items+=("info.txt=$info")
  for f in install.log install.log.1 install.log.2 launch.log launch.log.1; do
    add "7thdroid/$f" "$STATE_DIR/$f"
  done
  add 7thdroid/install.env "$STATE_FILE"
  if [ -n "${COMPATDATA:-}" ]; then
    d=$(seventh_workshop)
    for f in "$d"/applog*.txt; do add "7th-heaven/${f##*/}" "$f"; done
    add 7th-heaven/settings.xml "$d/settings.xml"
    add 7th-heaven/install.log "$COMPATDATA/pfx/drive_c/$APP_ID-7thHeaven-install.log"
    d=$(ff7_game_dir)
    for f in FFNx.log FFNx.toml AppLoader.log; do add "game/$f" "$d/$f"; done
  fi
  # As DroidDeck's own Share logs: its session folders (it keeps three), and recent tool and store logs.
  d=$(droiddeck_log_dir)
  for s in "$d"/*/; do
    name=${s%/}
    name=${name##*/}
    [[ $name =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2,}-. || $name =~ ^session-[0-9]{8}-[0-9]{6} ]] || continue
    add "droiddeck/$name" "${s%/}"
  done
  for s in tools stores; do
    [ -d "$d/$s" ] || continue
    while IFS= read -r f; do add "droiddeck/$s/${f##*/}" "$f"; done \
      < <(find "$d/$s" -maxdepth 1 -type f -mtime -7 | sort)
  done

  dir=$(logs_dir)
  stamp=$(date +%Y-%m-%d_%H%M%S)
  out="$dir/$APP_NAME-logs-$stamp.tar"
  if [ "$DRY_RUN" = 1 ]; then
    info "Would save ${#items[@]} logs to $out"
    rm -f -- "$info"
    return 0
  fi
  mkdir -p "$dir" 2>/dev/null && [ -w "$dir" ] || { rm -f -- "$info"; warn "Can't write logs to $dir."; return 1; }
  info "Redacting and saving $((${#items[@]} - 1)) logs and log folders to $out"
  if ! run python "$LIB_DIR/logs.py" bundle "$out" "${items[@]}"; then
    rm -f -- "$info" "$out.part"
    warn "The logs could not be saved to $out."
    return 1
  fi
  rm -f -- "$info"
  LOGS_FILE=$out
  ok "Logs saved to $out"
}
