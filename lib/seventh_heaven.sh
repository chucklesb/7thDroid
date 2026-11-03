# shellcheck shell=bash
# Getting, installing and configuring 7th Heaven.

SEVENTH_REPO=tsunamods-codes/7th-Heaven
SEVENTH_API=${SEVENTH_API:-https://api.github.com/repos/$SEVENTH_REPO}
SEVENTH_DIR_WIN='C:\7th Heaven'

# select_seventh_heaven -> SEVENTH_CHANNEL, SEVENTH_TAG, SEVENTH_URL, SEVENTH_FILE (downloaded later)
select_seventh_heaven() {
  step "Choosing the 7th Heaven version"
  if [ -z "$SEVENTH_CHANNEL" ]; then
    local pick
    choose pick "Which 7th Heaven build?" \
      "Stable (newest release)" \
      "Canary (newest development build)"
    SEVENTH_CHANNEL=$(printf 'stable\ncanary\n' | sed -n "$((pick + 1))p")
  fi
  [ "$SEVENTH_CHANNEL" = latest ] && SEVENTH_CHANNEL=stable
  case $SEVENTH_CHANNEL in
    stable|canary)
      local api line
      [ "$SEVENTH_CHANNEL" = stable ] && api=releases/latest || api=releases/tags/canary
      line=$(curl -fsSL --retry 3 -H 'Accept: application/vnd.github+json' "$SEVENTH_API/$api" | python -c '
import json, re, sys
release = json.load(sys.stdin)
exes = [a for a in release.get("assets", []) if a["name"].lower().endswith(".exe")]
exes.sort(key=lambda a: (not re.search(r"_(release|canary)\.exe$", a["name"], re.I), a["name"]))
if exes:
    a = exes[0]
    stamp = re.sub(r"[^0-9]", "", a.get("updated_at", ""))[:12]
    print("\t".join((release.get("tag_name", ""), a["name"], a["browser_download_url"], stamp)))
') || true
      [ -n "$line" ] || die "Could not look up the $SEVENTH_CHANNEL 7th Heaven release on GitHub."
      IFS=$'\t' read -r SEVENTH_TAG SEVENTH_FILE SEVENTH_URL stamp <<< "$line"
      # canary keeps its tag and file name across builds; the asset date keeps cached copies apart
      [ "$SEVENTH_CHANNEL" = canary ] && SEVENTH_FILE=canary-$stamp-$SEVENTH_FILE ;;
    *) die "Unknown 7th Heaven version '$SEVENTH_CHANNEL' (use stable or canary)." ;;
  esac
  ok "7th Heaven $SEVENTH_TAG ($SEVENTH_CHANNEL)"
}

seventh_exe() { printf '%s\n' "$1/pfx/drive_c/7th Heaven/7th Heaven.exe"; }

# ask_seventh_install COMPATDATA -> SEVENTH_RUN: 1 to run 7th Heaven's installer, 0 to keep what is there
ask_seventh_install() {
  SEVENTH_RUN=1
  if [ -f "$(seventh_exe "$1")" ] && [ "$REINSTALL" != 1 ] \
     && ! ask_yn "7th Heaven is already installed in this prefix. Run its installer again (update or repair)?" n; then
    SEVENTH_RUN=0
  fi
  return 0
}

install_seventh_heaven() {
  local compatdata=$1 exe
  exe=$(seventh_exe "$compatdata")
  if [ "$SEVENTH_RUN" != 1 ]; then
    info "Keeping the 7th Heaven already installed."
    return 0
  fi
  SEVENTH_INSTALLER=$(download "$SEVENTH_URL" "$SEVENTH_FILE")
  info "Installing 7th Heaven to $SEVENTH_DIR_WIN."
  fex_run "$compatdata" "$SEVENTH_INSTALLER" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- \
    /DIR="$SEVENTH_DIR_WIN" /LOG="C:\\$APP_ID-7thHeaven-install.log" || warn "The 7th Heaven installer reported an error."
  [ "$DRY_RUN" = 1 ] || [ -f "$exe" ] \
    || die "7th Heaven did not install. Its log is $compatdata/pfx/drive_c/$APP_ID-7thHeaven-install.log"
  ok "7th Heaven installed."
}

# configure_seventh_heaven COMPATDATA GAME_EXE FF7_VERSION
configure_seventh_heaven() {
  local compatdata=$1 game_exe=$2 version=$3 workshop channel=Stable
  workshop=$compatdata/pfx/drive_c/7th\ Heaven/7thWorkshop
  [ "$SEVENTH_CHANNEL" = canary ] && channel=Canary
  info "Pointing 7th Heaven at $game_exe ($version)"
  [ "$DRY_RUN" = 1 ] && return 0
  mkdir -p "$workshop/profiles" "$compatdata/pfx/drive_c/7th Heaven/mods"
  python - "$ASSETS_DIR/settings.xml.in" "$workshop/settings.xml" "$(prefix_winpath "$compatdata" "$game_exe")" "$version" \
    "$SEVENTH_DIR_WIN\\mods" "$channel" <<'EOF'
import os, re, sys
template, target, exe, version, library, channel = sys.argv[1:]
values = {"FF7Exe": exe, "FF7InstalledVersion": version}
if os.path.exists(target):
    with open(target, encoding="utf-8-sig") as f:
        text = f.read()
else:
    with open(template, encoding="utf-8") as f:
        text = f.read()
    values.update(LibraryLocation=library, FFNxUpdateChannel=channel, AppUpdateChannel=channel)
for tag, value in values.items():
    value = value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    if re.search(r"<%s>.*?</%s>|<%s\s*/>" % (tag, tag, tag), text, re.S):
        text = re.sub(r"<%s>.*?</%s>|<%s\s*/>" % (tag, tag, tag), lambda m: "<%s>%s</%s>" % (tag, value, tag), text, count=1, flags=re.S)
    else:
        text = text.replace("</Settings>", "  <%s>%s</%s>\n</Settings>" % (tag, value, tag))
with open(target, "w", encoding="utf-8") as f:
    f.write(text)
EOF
}
