#!/usr/bin/env python3
"""FFNx, the game driver 7th Heaven installs into the FF7 folder it uses.

    ffnx.py settings SETTINGS_XML DRIVE_C STEAM
    ffnx.py exists SETTINGS_XML DRIVE_C
    ffnx.py driver SETTINGS_XML DRIVE_C
    ffnx.py install ZIP FOLDER
    ffnx.py merge NEW OLD
    ffnx.py path SETTINGS_XML DRIVE_C TAG

SETTINGS_XML is 7th Heaven's settings.xml; its FF7Exe names the game folder, which holds FFNx and
FFNx.toml. DRIVE_C is the prefix's drive_c; other drive letters go through the prefix's dosdevices.

settings - 7thDroid's FFNx options, just before a launch (STEAM is 1 when Steam starts 7th Heaven):
  renderer_backend Auto (0) becomes Direct3D 11 (3), a backend chosen in 7th Heaven is kept, and
  enable_steam_achievements (7th Heaven's Steam Compatibility) is on only for a Steam launch. Like
  7th Heaven, only lines already in the file are changed. Exits 3 when there is no FFNx.toml yet:
  7th Heaven installs FFNx, and writes a fresh FFNx.toml, on the first Play.
exists - only checks for that FFNx.toml (exit 0, or 3).
driver - prints FOLDER, STATE, CHANNEL and ASSET_PREFIX, tab-separated. STATE is none (no FFNx yet),
  old (no FFNx_steam_api.dll: FFNx 1.24 or older, which 7th Heaven 4.6 refuses to launch) or current.
  CHANNEL is 7th Heaven's FFNx update channel; ASSET_PREFIX names the FFNx release zip that fits.
install - unpacks an FFNx release into FOLDER as 7th Heaven's updater does, then gives the new
  FFNx.toml the values the old one had, for every key both have. The old file is kept beside it.
merge - gives NEW (an FFNx.toml) the values of OLD in the same way.
path - prints the Linux path of a path setting in settings.xml, such as LibraryLocation.
"""
import os
import re
import sys
import zipfile
import xml.etree.ElementTree as ET

LINE = re.compile(r"^(\s*)([A-Za-z0-9_]+)(\s*=\s*)([^#\r\n]*?)(\s*(?:#[^\r\n]*)?)(\r?\n?)$")
KEY = re.compile(r"^(\s*)([A-Za-z0-9_]+)(\s*=\s*)(.*?)(\r?\n?)$", re.S)
STEAM_API = "FFNx_steam_api.dll"


def read_settings(settings, tags=("FF7Exe", "FF7InstalledVersion", "FFNxUpdateChannel")):
    root = ET.parse(settings).getroot()
    return {tag: (root.findtext(tag) or "").strip() for tag in tags}


def windows_to_linux(path, drive_c):
    match = re.match(r"^([A-Za-z]):\\(.*)$", path)
    if not match:
        return None
    letter = match.group(1).lower()
    link = os.path.join(os.path.dirname(drive_c), "dosdevices", letter + ":")
    if os.path.exists(link):
        root = os.path.realpath(link)
    else:
        root = {"c": drive_c, "z": "/"}.get(letter)
    if root is None:
        return None
    return os.path.join(root, *[p for p in match.group(2).split("\\") if p])


def game_folder(settings, drive_c):
    """FF7Exe's folder, or ff7/workingdir in it: the 2026 and GOG releases' FFVII.exe is a launcher, and
    7th Heaven moves FF7Exe to ff7/workingdir only on the next Play (after a fresh install or an update)."""
    exe = windows_to_linux(read_settings(settings)["FF7Exe"], drive_c)
    if not exe:
        return None
    folder = os.path.dirname(exe)
    working = os.path.join(folder, "ff7", "workingdir")
    return working if os.path.isdir(working) else folder


def update(text, steam):
    out = []
    for line in text.splitlines(keepends=True):
        match = LINE.match(line)
        if match:
            indent, key, eq, value, comment, end = match.groups()
            if key == "renderer_backend" and value == "0":
                value = "3"
            elif key == "enable_steam_achievements":
                value = "true" if steam else "false"
            line = indent + key + eq + value + comment + end
        out.append(line)
    return "".join(out)


def split_value(rest):
    """VALUE and the trailing comment of what follows a key's '=': a # inside quotes is not a comment."""
    quote, i = None, 0
    while i < len(rest):
        c = rest[i]
        if quote:
            if c == "\\" and quote == '"':
                i += 2
                continue
            if c == quote:
                quote = None
        elif c in "\"'":
            quote = c
        elif c == "#":
            value = rest[:i].rstrip()
            return value, rest[len(value):]
        i += 1
    value = rest.rstrip()
    return value, rest[len(value):]


def values(text):
    found = {}
    for line in text.splitlines():
        match = KEY.match(line)
        if match and not line.lstrip().startswith("#"):
            found.setdefault(match.group(2), split_value(match.group(4))[0])
    return found


def merge(new_text, old_text):
    old = values(old_text)
    out = []
    for line in new_text.splitlines(keepends=True):
        match = KEY.match(line)
        if match and not line.lstrip().startswith("#") and match.group(2) in old:
            indent, key, eq, rest, end = match.groups()
            _, comment = split_value(rest)
            line = indent + key + eq + old[key] + comment + end
        out.append(line)
    return "".join(out)


def write(path, text):
    with open(path + ".7thdroid", "w", encoding="utf-8", newline="") as f:
        f.write(text)
    os.replace(path + ".7thdroid", path)


def install(archive, folder):
    toml = os.path.join(folder, "FFNx.toml")
    old = None
    if os.path.isfile(toml):
        with open(toml, encoding="utf-8", errors="replace", newline="") as f:
            old = f.read()
    top = os.path.realpath(folder)
    with zipfile.ZipFile(archive) as z:
        entries = z.infolist()
        for entry in entries:
            target = os.path.realpath(os.path.join(top, entry.filename))
            if os.path.isabs(entry.filename) or not (target == top or target.startswith(top + os.sep)):
                print("%s: %s is outside the game folder" % (archive, entry.filename), file=sys.stderr)
                return 1
        for entry in entries:
            target = os.path.join(top, entry.filename)
            if entry.is_dir():
                os.makedirs(target, exist_ok=True)
                continue
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with z.open(entry) as src, open(target + ".7thdroid", "wb") as dst:
                while True:
                    chunk = src.read(1 << 20)
                    if not chunk:
                        break
                    dst.write(chunk)
            os.replace(target + ".7thdroid", target)
    if old is not None and os.path.isfile(toml):
        write(toml + ".7thdroid-bak", old)
        with open(toml, encoding="utf-8", errors="replace", newline="") as f:
            new = f.read()
        write(toml, merge(new, old))
    return 0


def main(argv):
    command, args = (argv[1:2] or [""])[0], argv[2:]
    if command == "install":
        return install(*args[:2])
    if command == "merge":
        new, old = args[:2]
        with open(new, encoding="utf-8", errors="replace", newline="") as f:
            new_text = f.read()
        with open(old, encoding="utf-8", errors="replace", newline="") as f:
            old_text = f.read()
        write(new, merge(new_text, old_text))
        return 0
    if command == "path":
        settings, drive_c, tag = args[:3]
        path = windows_to_linux(read_settings(settings, (tag,))[tag], drive_c)
        if not path:
            return 1
        print(path)
        return 0
    if command not in ("settings", "exists", "driver"):
        print(__doc__, file=sys.stderr)
        return 2
    settings, drive_c = args[:2]
    folder = game_folder(settings, drive_c)
    if folder is None:
        print("FF7Exe in %s is not on a drive of this prefix" % settings, file=sys.stderr)
        return 1
    if command == "driver":
        info = read_settings(settings)
        original98 = info["FF7InstalledVersion"] == "Original98"
        driver = "FFNx.dll" if original98 else "AF3DN.P"
        if not os.path.isfile(os.path.join(folder, driver)):
            state = "none"
        elif not os.path.isfile(os.path.join(folder, STEAM_API)):
            state = "old"
        else:
            state = "current"
        print("\t".join((folder, state, info["FFNxUpdateChannel"] or "Stable",
                         "FFNx-FF7_1998" if original98 else "FFNx-Steam")))
        return 0
    path = os.path.join(folder, "FFNx.toml")
    if not os.path.isfile(path):
        return 3
    if command == "exists":
        return 0
    with open(path, encoding="utf-8", newline="") as f:
        text = f.read()
    new = update(text, args[2] == "1")
    if new != text:
        write(path, new)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
