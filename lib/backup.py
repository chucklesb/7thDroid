#!/usr/bin/env python3
"""7thDroid's backups of 7th Heaven: one uncompressed tar, since Android storage keeps no links or
permissions, and mods are mostly compressed already.

    backup.py create OUT MANIFEST NAME=SOURCE[!EXCLUDE...]...
    backup.py manifest FILE
    backup.py extract FILE NAME DEST
    backup.py settings FILE SETTINGS_XML

create - writes OUT (through OUT.part). MANIFEST becomes manifest.env. Each NAME=SOURCE adds a folder
  under NAME/, leaving out the top-level entries named after !, or a file as NAME. Missing sources,
  links and special files are skipped.
manifest - prints manifest.env.
extract - unpacks NAME (a folder or a file) to DEST, overwriting files of the same name and keeping the
  rest. Entries that would leave DEST, links and special files are refused. Exits 3 when the backup
  has no NAME.
settings - writes the backup's 7th Heaven settings.xml over SETTINGS_XML, but keeps the FF7Exe,
  FF7InstalledVersion and LibraryLocation already there, so it still points at this install.
"""
import os
import re
import sys
import tarfile

KEEP_SETTINGS = ("FF7Exe", "FF7InstalledVersion", "LibraryLocation")


def add_tree(tar, name, source, excludes):
    if os.path.islink(source):
        return
    if os.path.isfile(source):
        tar.add(source, arcname=name, recursive=False)
        return
    if not os.path.isdir(source):
        return
    tar.add(source, arcname=name, recursive=False)
    for folder, dirs, files in os.walk(source):
        rel = os.path.relpath(folder, source)
        if rel == ".":
            dirs[:] = [d for d in dirs if d not in excludes]
            files = [f for f in files if f not in excludes]
        dirs.sort()
        for d in list(dirs):
            path = os.path.join(folder, d)
            if os.path.islink(path):
                dirs.remove(d)
                continue
            tar.add(path, arcname="/".join(p for p in (name, rel, d) if p != "."), recursive=False)
        for f in sorted(files):
            path = os.path.join(folder, f)
            if os.path.islink(path) or not os.path.isfile(path):
                continue
            tar.add(path, arcname="/".join(p for p in (name, rel, f) if p != "."), recursive=False)


def create(out, manifest, specs):
    part = out + ".part"
    with tarfile.open(part, "w", format=tarfile.PAX_FORMAT) as tar:
        tar.add(manifest, arcname="manifest.env", recursive=False)
        for spec in specs:
            name, _, rest = spec.partition("=")
            source, *excludes = rest.split("!")
            add_tree(tar, name, source, set(excludes))
    os.replace(part, out)
    return 0


def read_member(path, name):
    # stops at the first match: the manifest and settings come first, so a large backup isn't read through
    with tarfile.open(path) as tar:
        for member in tar:
            if member.name == name and member.isfile():
                return tar.extractfile(member).read()
    return None


def extract(path, name, dest):
    top = os.path.realpath(dest)
    with tarfile.open(path) as tar:
        members = [m for m in tar.getmembers() if m.name == name or m.name.startswith(name + "/")]
        for m in members:
            rel = m.name[len(name):].lstrip("/")
            target = os.path.realpath(os.path.join(top, rel)) if rel else top
            if (m.name.startswith("/") or ".." in m.name.split("/") or not (m.isfile() or m.isdir())
                    or not (target == top or target.startswith(top + os.sep))):
                print("%s: refusing %s" % (path, m.name), file=sys.stderr)
                return 1
        for m in members:
            rel = m.name[len(name):].lstrip("/")
            target = os.path.join(top, rel) if rel else top
            if m.isdir():
                os.makedirs(target, exist_ok=True)
                continue
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with tar.extractfile(m) as src, open(target + ".7thdroid", "wb") as dst:
                while True:
                    chunk = src.read(1 << 20)
                    if not chunk:
                        break
                    dst.write(chunk)
            os.replace(target + ".7thdroid", target)
            os.utime(target, (m.mtime, m.mtime))
    return 0 if members else 3


def settings(path, current):
    data = read_member(path, "workshop/settings.xml")
    if data is None:
        return 3
    text = data.decode("utf-8-sig")
    with open(current, encoding="utf-8-sig") as f:
        mine = f.read()
    for tag in KEEP_SETTINGS:
        pattern = r"<%s>.*?</%s>|<%s\s*/>" % (tag, tag, tag)
        keep = re.search(pattern, mine, re.S)
        if keep and re.search(pattern, text, re.S):
            text = re.sub(pattern, lambda m: keep.group(0), text, count=1, flags=re.S)
        elif keep:
            text = text.replace("</Settings>", "  %s\n</Settings>" % keep.group(0))
    with open(current + ".7thdroid", "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(current + ".7thdroid", current)
    return 0


def main(argv):
    command, args = (argv[1:2] or [""])[0], argv[2:]
    if command == "create" and len(args) >= 2:
        return create(args[0], args[1], args[2:])
    if command == "manifest" and len(args) == 1:
        data = read_member(args[0], "manifest.env")
        if data is None:
            return 3
        sys.stdout.write(data.decode("utf-8"))
        return 0
    if command == "extract" and len(args) == 3:
        return extract(*args)
    if command == "settings" and len(args) == 2:
        return settings(*args)
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
