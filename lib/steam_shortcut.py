#!/usr/bin/env python3
"""Steam non-Steam-game shortcuts, using DroidDeck's own shortcuts.vdf reader and writer.

    steam_shortcut.py appid EXE NAME
    steam_shortcut.py gameid EXE NAME
    steam_shortcut.py has TOOL STEAM_ROOT EXE
    steam_shortcut.py add TOOL STEAM_ROOT NAME EXE START_DIR [ICON]
    steam_shortcut.py remove TOOL STEAM_ROOT EXE

appid prints the id Steam gives a shortcut to EXE named NAME (the same CRC droiddeck-proton-run uses).
gameid prints the 64-bit id steam://rungameid/ takes to start that shortcut.
has succeeds when the most recent account's shortcuts.vdf has a shortcut to EXE.
add writes the shortcut into the most recent account's shortcuts.vdf, replacing an earlier one for
the same program, and prints its id. Steam must be closed: it rewrites the file when it exits.
The entry carries no droiddeck-app tag, so droiddeck-steam-shortcuts keeps it as the user's own.
"""
import os
import runpy
import shutil
import sys
import zlib

SHORTCUT_BIT = 0x80000000
SHORTCUT_GAME = 0x02000000


def appid(exe, name):
    return zlib.crc32(('"%s"%s' % (exe, name)).encode("utf-8")) | SHORTCUT_BIT


def gameid(exe, name):
    return appid(exe, name) << 32 | SHORTCUT_GAME


def read(tool, steam_root):
    account = tool["account_dir"](steam_root)
    if not account:
        raise SystemExit("steam_shortcut.py: no Steam account found; sign in to Steam once first")
    path = os.path.join(account, "config", "shortcuts.vdf")
    shortcuts = {}
    if os.path.exists(path):
        with open(path, "rb") as f:
            data = f.read()
        if data:
            shortcuts = tool["parse"](data).get("shortcuts", {})
    return path, shortcuts


def load(tool, steam_root):
    path, shortcuts = read(tool, steam_root)
    if os.path.exists(path):
        shutil.copy2(path, path + ".7thdroid.bak")
    return path, shortcuts


def entries(shortcuts):
    return [value for value in shortcuts.values() if isinstance(value, dict)]


def others(shortcuts, exe, number=None):
    """The shortcuts that are not 7thDroid's launcher."""
    kept = []
    for value in entries(shortcuts):
        same = value.get("Exe", value.get("exe", "")).strip('"') == exe
        if same or number is not None and (value.get("appid", value.get("AppId", 0)) or 0) & 0xFFFFFFFF == number:
            continue
        kept.append(value)
    return kept


def save(tool, path, kept):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "wb") as f:
        f.write(tool["write"]({"shortcuts": {str(i): v for i, v in enumerate(kept)}}))
    os.replace(tmp, path)


def add(tool_path, steam_root, name, exe, start, icon=""):
    tool = runpy.run_path(tool_path)
    path, shortcuts = load(tool, steam_root)
    number = appid(exe, name)
    entry = tool["shortcut"]({"appid": number, "name": name, "exe": exe, "dir": start,
                              "art": {"icon": icon}}, launch_options="")
    entry["tags"] = {}
    save(tool, path, others(shortcuts, exe, number) + [entry])
    return number


def remove(tool_path, steam_root, exe):
    tool = runpy.run_path(tool_path)
    path, shortcuts = load(tool, steam_root)
    kept = others(shortcuts, exe)
    if len(kept) != len(entries(shortcuts)):
        save(tool, path, kept)


def has(tool_path, steam_root, exe):
    _, shortcuts = read(runpy.run_path(tool_path), steam_root)
    return len(others(shortcuts, exe)) != len(entries(shortcuts))


def main(argv):
    if len(argv) == 3 and argv[0] == "appid":
        print(appid(argv[1], argv[2]))
        return 0
    if len(argv) == 3 and argv[0] == "gameid":
        print(gameid(argv[1], argv[2]))
        return 0
    if len(argv) == 4 and argv[0] == "has":
        return 0 if has(*argv[1:]) else 1
    if len(argv) in (6, 7) and argv[0] == "add":
        print(add(*argv[1:]))
        return 0
    if len(argv) == 4 and argv[0] == "remove":
        remove(*argv[1:])
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
