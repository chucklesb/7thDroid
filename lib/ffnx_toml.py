#!/usr/bin/env python3
"""Sets 7thDroid's FFNx options in the FFNx.toml 7th Heaven uses, just before a launch.

    ffnx_toml.py SETTINGS_XML DRIVE_C STEAM
    ffnx_toml.py --exists SETTINGS_XML DRIVE_C

SETTINGS_XML is 7th Heaven's settings.xml; its FF7Exe names the game folder, which holds FFNx.toml.
DRIVE_C is the prefix's drive_c. STEAM is 1 when Steam starts 7th Heaven, else 0.

- renderer_backend: Auto (0) becomes Direct3D 11 (3); a backend chosen in 7th Heaven is kept.
- enable_steam_achievements (7th Heaven's Steam Compatibility): on only for a Steam launch.

Like 7th Heaven, only lines already in the file are changed. Exits 3 when there is no FFNx.toml yet:
7th Heaven installs FFNx, and writes a fresh FFNx.toml, on the first Play. --exists only checks for it.
"""
import os
import re
import sys
import xml.etree.ElementTree as ET

LINE = re.compile(r"^(\s*)([A-Za-z0-9_]+)(\s*=\s*)([^#\r\n]*?)(\s*(?:#[^\r\n]*)?)(\r?\n?)$")


def game_folder(settings, drive_c):
    exe = (ET.parse(settings).getroot().findtext("FF7Exe") or "").strip()
    match = re.match(r"^([A-Za-z]):\\(.*)$", exe)
    if not match:
        return None
    root = {"c": drive_c, "z": "/"}.get(match.group(1).lower())
    if root is None:
        return None
    parts = [p for p in match.group(2).split("\\") if p]
    return os.path.dirname(os.path.join(root, *parts))


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


def main(argv):
    check = argv[1:2] == ["--exists"]
    if check:
        argv = argv[1:] + ["0"]
    settings, drive_c, steam = argv[1:4]
    folder = game_folder(settings, drive_c)
    if folder is None:
        print("FF7Exe in %s is not on C: or Z:" % settings, file=sys.stderr)
        return 1
    path = os.path.join(folder, "FFNx.toml")
    if not os.path.isfile(path):
        return 3
    if check:
        return 0
    with open(path, encoding="utf-8", newline="") as f:
        text = f.read()
    new = update(text, steam == "1")
    if new != text:
        with open(path + ".7thdroid", "w", encoding="utf-8", newline="") as f:
            f.write(new)
        os.replace(path + ".7thdroid", path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
