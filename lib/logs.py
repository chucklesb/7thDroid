#!/usr/bin/env python3
"""One tar of logs, every file redacted on the way in (redact.py), for a bug report.

    logs.py bundle OUT NAME=PATH...

Each NAME=PATH is a file, or a folder taken with everything in it, stored under NAME. Missing paths,
links and special files are left out; so are binary files (a NUL in the first 4 KiB). A file over
8 MB keeps only its last 8 MB, from a line start, after a note line. index.txt lists every file and
what happened to it. OUT is written as OUT.part, then renamed. REDACT_ROOT (default /) is where the
account names and addresses to redact are learned from, as DroidDeck does.
"""
import io
import os
import sys
import tarfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import redact  # noqa: E402

MAX_BYTES = 8 * 1024 * 1024


def files_of(name, path):
    if os.path.islink(path):
        return
    if os.path.isfile(path):
        yield name, path
        return
    if not os.path.isdir(path):
        return
    for folder, dirs, files in os.walk(path):
        dirs[:] = sorted(d for d in dirs if not os.path.islink(os.path.join(folder, d)))
        rel = os.path.relpath(folder, path)
        for f in sorted(files):
            full = os.path.join(folder, f)
            if os.path.islink(full) or not os.path.isfile(full):
                continue
            yield "/".join(p for p in (name, rel, f) if p != "."), full


def tail_chunks(path, size):
    """The file's bytes, or its last MAX_BYTES from the first line start, with the left-out size."""
    if size <= MAX_BYTES:
        return redact.file_chunks(path), 0
    with open(path, "rb") as f:
        f.seek(size - MAX_BYTES)
        data = f.read()
    cut = data.find(b"\n")
    data = data[cut + 1:] if cut >= 0 else data
    return iter([data]), size - len(data)


def bundle(out, specs):
    redact.learn_from_runtime(os.environ.get("REDACT_ROOT", "/"))
    index = []
    part = out + ".part"
    with tarfile.open(part, "w", format=tarfile.PAX_FORMAT) as tar:
        for spec in specs:
            name, _, path = spec.partition("=")
            for arcname, full in files_of(name, path):
                try:
                    st = os.stat(full)
                    if redact.is_binary(full):
                        index.append("%s\t%d\tleft out: binary" % (arcname, st.st_size))
                        continue
                    chunks, dropped = tail_chunks(full, st.st_size)
                    text = io.StringIO()
                    if dropped:
                        text.write("<7thDroid: the first %d bytes of this log were left out>\n" % dropped)
                    redact.scrub_for_share(chunks, text.write)
                except OSError as e:
                    index.append("%s\t-\tleft out: %s" % (arcname, e.strerror or e))
                    continue
                data = text.getvalue().encode("utf-8")
                info = tarfile.TarInfo(arcname)
                info.size, info.mtime, info.mode = len(data), int(st.st_mtime), 0o644
                tar.addfile(info, io.BytesIO(data))
                index.append("%s\t%d\t%s" % (arcname, st.st_size, "last 8 MB, redacted" if dropped else "redacted"))
        data = ("# 7thDroid logs, %s. Every file is redacted (tokens, passwords, account names, emails,\n"
                "# Steam IDs, network addresses...); look through them before sharing.\n# file\tsize\twhat happened\n"
                % time.strftime("%Y-%m-%d %H:%M") + "\n".join(index) + "\n").encode("utf-8")
        info = tarfile.TarInfo("index.txt")
        info.size, info.mtime, info.mode = len(data), int(time.time()), 0o644
        tar.addfile(info, io.BytesIO(data))
    os.replace(part, out)
    return 0


def main(argv):
    if len(argv) >= 3 and argv[1] == "bundle":
        return bundle(argv[2], argv[3:])
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
