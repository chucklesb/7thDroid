#!/usr/bin/env python3
"""Redacts secrets and personal details from a log, as DroidDeck does before sharing its own logs.

    redact.py FILE        the redacted text of FILE, on stdout

A port of DroidDeck's LogRedactor.redact, redactForShare and scrubForShare, and SecretScrub.scrub
(app/src/main/java/com/droiddeck/launcher/core/, Droid-Deck/DroidDeck commit 7c89c14a, GPL-3.0): the
same rules in the same order, the same markers. Removed: tokens, passwords and other secret values,
JWTs, API keys, Steam Guard codes, account names (also those learned from Steam's loginusers.vdf),
emails, SteamIDs (masked), GUIDs, MAC addresses, serials and Android IDs, this device's public
addresses and LAN addresses, and token-bearing URL parts and headers.

learn_from_runtime(ROOT) learns account names and the device's own addresses as DroidDeck does, from
ROOT (/ inside DroidDeck's Linux, or REDACT_ROOT).

One addition to DroidDeck's rules: the account IDs of the SteamIDs in loginusers.vdf (the number in
Steam's userdata/<id> folders, "for user <id>", "Account ID: <id>") are masked like SteamID3s, since
Steam's own logs are full of them.
"""
import codecs
import os
import re
import sys

MAX_LINE_LENGTH = 64 * 1024
OVERSIZED_LINE = "<oversized log line withheld>"
UNSUPPORTED_LINE = "<unsupported or oversized line withheld>"
UNSUPPORTED_FILE = "<unsupported encoding; file withheld>"
FAILED_LINE = "<redaction failed; line withheld>"
MAX_LEARN_INPUT_BYTES = 2 * 1024 * 1024
MAX_LEARNED_ACCOUNTS = 2048
MAX_LEARNED_ADDRESSES = 1024
MAX_ACCOUNT_LENGTH = 256

# Java's regexes are ASCII unless told otherwise: \d, \s, \b and case folding alike.
A = re.ASCII

EMAIL = re.compile(r"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}", A)
HIDL_SHARED_LIBRARY = re.compile(
    r"(?:android\.(?:hardware|frameworks|hidl|system)|vendor\.[A-Za-z0-9_]+\.hardware)"
    r"(?:\.[A-Za-z0-9_]+)+@[0-9]+\.[0-9]+(?:-[A-Za-z0-9_]+)*\.so", A)
JWT_LABELLED = re.compile(r"(?i)(\bJWT[\s=:]+)(\d{8,})", A)
JWT_BASE64 = re.compile(r"ey[A-Za-z0-9_\-]{6,}\.[A-Za-z0-9_\-]{6,}\.[A-Za-z0-9_\-]{6,}", A)
GUID = re.compile(r"\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\b", A)
SECRET_KV = re.compile(
    r"(?i)(\b(?:access[_-]?token|refresh[_-]?token|auth[_-]?token|authtoken|token|authcode|"
    r"auth[_-]?ticket|ticket|sessionid|steamloginsecure|webapikey|api[_-]?key|"
    r"machine[_-]?auth(?:[_-]?token)?|machineauth|password|passwd|pwd|secret)[\"']?\s*[=:]\s*)"
    r"(?:([\"'])((?:\\.|(?!\2)[^\\\r\n]){4,})\2|([^\s\"'<>&;,]{4,}))", A)
GUARD_CODE = re.compile(r"(?i)((?:steam\s*)?guard\s*code[\s:=]*|two[\s-]?factor[\s:=]*|2fa[\s:=]*)([A-Za-z0-9]{5})", A)
WEBAPI_KEY = re.compile(r"\b[0-9A-Fa-f]{32}\b", A)
RESIDUAL = re.compile(r"(?i)\b(jwt|token|ticket|sessionid|steamloginsecure|machineauth)\b[\s=:]*([A-Za-z0-9+/=_\-]{12,})", A)
LONG_TOKEN = re.compile(r"[A-Za-z0-9_\-]{88,}", A)
STEAMID64 = re.compile(r"\b(76561)(\d{8})(\d{4})\b", A)
STEAMID3 = re.compile(r"\[U:1:(\d+)]", A)
EXTERNAL_ADDR = re.compile(r"(?i)(external\s+(?:ip\s+)?address\s*[:=]?\s*|external\s+ip\s*[:=]?\s*)([0-9A-Fa-f:.]{7,})", A)
IPV4 = re.compile(r"(?<![0-9.])(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})(?![0-9.])", A)
IPV6 = re.compile(r"(?<![0-9A-Za-z:])[0-9A-Fa-f]{0,4}(?::[0-9A-Fa-f]{0,4}){2,7}(?:%[A-Za-z0-9_.]+)?(?![0-9A-Za-z:])", A)
MAC = re.compile(r"(?i)(?<![0-9a-z:-])[0-9a-f]{2}([:-])(?:[0-9a-f]{2}\1){4}[0-9a-f]{2}(?![0-9a-z:-])", A)
MAC_FIELD = re.compile(
    r"(?i)(\bmac(?:[_ ]?address)?[\"']?\s*[:=]\s*[\"']?)[0-9a-f]{2}([:-])"
    r"(?:[0-9a-f]{2}\2){4}[0-9a-f]{2}(?![0-9a-z:-])", A)
DEVICE_IDENTIFIER = re.compile(
    r"(?i)(\b(?:android[_ ]?id|(?:device|controller)[_ ]?serial|serial(?:[_ ]?number)?|build\.serial)"
    r"[\"']?\s*[:=]\s*)(\"[^\"\r\n<>]+\"|'[^'\r\n<>]+'|[^\s\"'<>&;,\[\]{}]+)", A)
LOGIN_STATE = re.compile(r"(?i)(OnLoginStateChange:? )([^\s<]\S*)", A)
LOGIN_USERS = re.compile(r"(OnLoginUsersChanged )(\S.*)$", A)
ACCOUNT_VALUE = r"(\"[^\"<\r\n]+\"|'[^'<\r\n]+'|[^\s\"'<>&;,}]+)"
ACCOUNT_KV = re.compile(
    r"(?i)(?<![A-Za-z0-9_])(account[_-]?name|account[_-]?id|user[_-]?name|epicusername)"
    r"([\"']?\s*[=:]\s*|[\"']\s+)" + ACCOUNT_VALUE, A)
LOGIN_KV = re.compile(r"(?i)(?<![A-Za-z0-9_])(login)(\s*=\s*|[\"']\s*[=:]\s*|[\"']\s+)" + ACCOUNT_VALUE, A)
LAN_IPV4 = re.compile(r"(?<![\d.])(?:10\.\d{1,3}|192\.168|172\.(?:1[6-9]|2\d|3[01])|169\.254)\.\d{1,3}\.\d{1,3}(?!\.?\d)", A)
ACCOUNT_FIELD = re.compile(r"\"(AccountName|PersonaName)\"\s+\"([^\"]*)\"", A)
STEAMID64_KEY = re.compile(r"\"(7656119\d{10})\"", A)
STEAMID64_BASE = 76561197960265728

# SecretScrub
URL = re.compile(r"[A-Za-z][A-Za-z0-9+.\-]*://[^\s\"'<>]+", A)
TOKEN_SEGMENT = re.compile(r"(?i)(token|hdnts|hmac|signature|sig|exp)=", A)
TOKEN = re.compile(r"(?i)(?<![A-Za-z0-9_])(__token__|f_token|hdnts|access_token|refresh_token|id_token|token)([\"']?\s*[=:]\s*[\"']?)[^\s&;,\"'<>}]+", A)
GRANT_CODE = re.compile(r"(?i)(?<![A-Za-z0-9_])(exchange_code|authorization_?code)([\"']?\s*=\s*[\"']?)[^\s&;,\"'<>}]{4,}", A)
CODE = re.compile(r"(?i)(?<![A-Za-z0-9_])(code)([\"']?\s*=\s*[\"']?)([^\s&;,\"'<>}]{4,})", A)
OAUTH_CONTEXT = re.compile(r"(?i)(?<![A-Za-z0-9_])(client_id|client_secret|redirect_uri|state|grant_type|response_type|access_token|refresh_token|id_token)[\"']?\s*[=:]", A)
STATUS_CODE = re.compile(r"(?i)(0x)?[0-9a-f]{8}", A)
HEADER = re.compile(r"(?i)\b(authorization|cookie|set-cookie)(\s*[:=]\s*).+", A)
SHARE_MARK = "<redacted:token>"


class Learned:
    def __init__(self, regex, needs, mark="<redacted:account>"):
        self.regex, self.needs, self.mark = regex, needs, mark


def masked(digits):
    """Masks all but the last 4 digits, as DroidDeck masks a SteamID3's account number."""
    return "*" * (len(digits) - 4) + digits[-4:] if len(digits) > 4 else digits


accounts = []
own = []


def bounded_text(path):
    """The file's text when it is at most MAX_LEARN_INPUT_BYTES, else None."""
    try:
        with open(path, "rb") as f:
            data = f.read(MAX_LEARN_INPUT_BYTES + 1)
    except OSError:
        return None
    if len(data) > MAX_LEARN_INPUT_BYTES:
        return None
    return data.decode("utf-8", errors="replace")


def learn_accounts(*login_users):
    global accounts
    names, ids, unread = [], [], False
    for path in login_users:
        if not os.path.isfile(path):
            continue
        text = bounded_text(path)
        if text is None:
            unread = True
            continue
        for match in ACCOUNT_FIELD.finditer(text):
            name = match.group(2).strip()
            if len(name) < 3:
                continue
            if len(name) > MAX_ACCOUNT_LENGTH or len(names) >= MAX_LEARNED_ACCOUNTS:
                unread = True
                break
            if name not in names:
                names.append(name)
        for match in STEAMID64_KEY.finditer(text):
            account_id = str(int(match.group(1)) - STEAMID64_BASE)
            if len(account_id) < 5:
                continue
            if len(ids) >= MAX_LEARNED_ACCOUNTS:
                unread = True
                break
            if account_id not in ids:
                ids.append(account_id)
    learned = [Learned(re.compile(r"(?i)(?<![A-Za-z0-9_])" + re.escape(name) + r"(?![A-Za-z0-9_])", A),
                       name.lower() if all(ord(c) < 0x80 for c in name) else None) for name in names]
    learned += [Learned(re.compile(r"(?<![0-9])" + i + r"(?![0-9])", A), i, masked(i)) for i in ids]
    if unread:
        seen, merged = set(), []
        for item in learned + accounts:
            if item.regex.pattern not in seen:
                seen.add(item.regex.pattern)
                merged.append(item)
        accounts = merged[:MAX_LEARNED_ACCOUNTS]
    else:
        accounts = learned
    return not unread


def expand6(address):
    a = address.split("%", 1)[0]
    if ":" not in a or a.count(":") > 7 or ":::" in a:
        return None
    if not all(c.isdigit() or c in "abcdefABCDEF:" for c in a):
        return None
    if "::" in a:
        head, tail = a.split("::", 1)
        h = head.split(":") if head else []
        t = tail.split(":") if tail else []
        if len(h) + len(t) > 7:
            return None
        parts = h + ["0"] * (8 - len(h) - len(t)) + t
    else:
        parts = a.split(":")
    if len(parts) != 8 or any(not p or len(p) > 4 for p in parts):
        return None
    return [p.lower() for p in parts]


def kind(address):
    a = address.split("%", 1)[0]
    m = IPV4.fullmatch(a)
    if m:
        o = [int(g) for g in m.groups()]
        if any(x > 255 for x in o):
            return None
        if o[0] == 127:
            return "loopback IPv4"
        if o[0] == 10 or (o[0] == 172 and 16 <= o[1] <= 31) or (o[0] == 192 and o[1] == 168):
            return "private IPv4"
        if o[0] == 169 and o[1] == 254:
            return "link-local IPv4"
        if o[0] == 100 and 64 <= o[1] <= 127:
            return "carrier-NAT IPv4"
        return "public IPv4"
    g = expand6(a)
    if g is None:
        return None
    first = int(g[0], 16)
    if all(int(x, 16) == 0 for x in g) or (all(int(x, 16) == 0 for x in g[:7]) and int(g[7], 16) == 1):
        return "loopback IPv6"
    if first & 0xffc0 == 0xfe80:
        return "link-local IPv6"
    if first & 0xfe00 == 0xfc00:
        return "private IPv6"
    return "public IPv6"


def learn_own_addresses(link_file):
    global own
    found = []
    if os.path.isfile(link_file):
        text = bounded_text(link_file)
        if text is None:
            return False
    else:
        text = ""
    for line in text.splitlines():
        line = line.strip()
        if not line.startswith("addr "):
            continue
        fields = line.split()
        if len(fields) < 2:
            continue
        addr = fields[1]
        if len(found) >= MAX_LEARNED_ADDRESSES:
            return False
        k = kind(addr)
        if k == "public IPv6":
            groups = expand6(addr)[:4]
            prefix = ":".join("0{0,3}" + re.escape(x.lstrip("0") or "0") for x in groups)
            found.append(Learned(re.compile(r"(?i)(?<![0-9A-Fa-f:])" + prefix + r"(?::[0-9A-Fa-f]{0,4}){1,4}(?:%[A-Za-z0-9_.]+)?", A),
                                 groups[0].lstrip("0") or "0"))
        elif k == "public IPv4":
            found.append(Learned(re.compile(r"(?<![0-9.])" + re.escape(addr) + r"(?![0-9.])", A), addr))
    own = found
    return True


def learn_from_runtime(root):
    addresses = learn_own_addresses(os.path.join(root, "etc/droiddeck-net"))
    names = learn_accounts(os.path.join(root, "root/.local/share/Steam/config/loginusers.vdf"),
                           os.path.join(root, "root/.droiddeck-x64/.local/share/Steam/config/loginusers.vdf"))
    return addresses and names


class Line:
    def __init__(self, text):
        self.text = text
        self.unfolded = any(ord(c) >= 0x80 for c in text)
        self.lower = None

    def has(self, *words):
        if self.unfolded:
            return True
        if self.lower is None:
            self.lower = self.text.lower()
        return any(w in self.lower for w in words)

    def set(self, new):
        if new != self.text:
            self.text = new
            self.lower = None

    def holds(self, c, times):
        return self.text.count(c) >= times

    def has_run(self, length, in_run):
        n = 0
        for ch in self.text:
            if not in_run(ch):
                n = 0
            else:
                n += 1
                if n >= length:
                    return True
        return False


def is_hex(c):
    return c in "0123456789abcdefABCDEF"


def is_token_char(c):
    return ("a" <= c <= "z") or ("A" <= c <= "Z") or ("0" <= c <= "9") or c in "_-"


def is_word(c):
    return c.isalnum() or c == "_"


def is_hidl_loader_diagnostic(text, m):
    if not HIDL_SHARED_LIBRARY.fullmatch(m.group()):
        return False
    start, end = m.start(), m.end()
    prefix, suffix = 'library "', '" not found'
    earliest = max(start - 4096, 0)
    quote = start - 1
    while quote >= earliest and text[quote] != '"':
        ch = text[quote]
        if not (ch.isalnum() or ch in "/._-"):
            return False
        quote -= 1
    if quote < earliest:
        return False
    path_start = quote + 1
    if path_start < start and (text[start - 1] != "/" or
                               not (text.startswith("/vendor/", path_start) or text.startswith("/system/", path_start))):
        return False
    prefix_start = quote - len(prefix) + 1
    suffix_end = end + len(suffix)
    return (prefix_start >= 0 and suffix_end <= len(text)
            and text[prefix_start:prefix_start + len(prefix)].lower() == prefix
            and text[end:suffix_end].lower() == suffix
            and (prefix_start == 0 or not is_word(text[prefix_start - 1]))
            and (suffix_end == len(text) or not is_word(text[suffix_end])))


def quoted(value):
    q = value[0] if value[:1] in ("\"", "'") else ""
    return q + "<redacted:account>" + q


def steamid3(m):
    return "[U:1:%s]" % masked(m.group(1))


def redact(line):
    if not line:
        return line
    if len(line) > MAX_LINE_LENGTH:
        return OVERSIZED_LINE
    try:
        out = Line(line)
        if out.has("mac"):
            out.set(MAC_FIELD.sub(lambda m: m.group(1) + "<redacted:mac>", out.text))
        if out.holds(":", 5) or out.holds("-", 5):
            out.set(MAC.sub("<redacted:mac>", out.text))
        if out.has("serial", "android"):
            def serial(m):
                value = m.group(2)
                q = value[0] if value[0] in "\"'" else ""
                return m.group(1) + q + "<redacted:serial>" + q
            out.set(DEVICE_IDENTIFIER.sub(serial, out.text))
        if out.holds("-", 4):
            out.set(GUID.sub("<redacted:guid>", out.text))
        if out.has("jwt"):
            out.set(JWT_LABELLED.sub(lambda m: m.group(1) + "<redacted:jwt>", out.text))
        if "ey" in out.text:
            out.set(JWT_BASE64.sub("<redacted:jwt>", out.text))
        if out.has("token", "auth", "ticket", "sessionid", "steamloginsecure", "api", "machine", "pass", "pwd", "secret"):
            out.set(SECRET_KV.sub(lambda m: m.group(1) + (m.group(2) or "") + "<redacted:token>" + (m.group(2) or ""), out.text))
        if out.has("guard", "factor", "2fa"):
            out.set(GUARD_CODE.sub(lambda m: m.group(1) + "<redacted:code>", out.text))
        if out.has_run(32, is_hex):
            out.set(WEBAPI_KEY.sub("<redacted:key>", out.text))
        if "76561" in out.text:
            out.set(STEAMID64.sub(lambda m: m.group(1) + "********" + m.group(3), out.text))
        if "[U:1:" in out.text:
            out.set(STEAMID3.sub(steamid3, out.text))
        if out.has("external"):
            out.set(EXTERNAL_ADDR.sub(lambda m: m.group(1) + "<redacted:ip>", out.text))
        for r in own:
            if r.needs is None or out.has(r.needs):
                out.set(r.regex.sub("<redacted:ip>", out.text))
        if out.has("onloginstatechange"):
            out.set(LOGIN_STATE.sub(lambda m: m.group(1) + "<redacted:account>", out.text))
        if "OnLoginUsersChanged " in out.text:
            out.set(LOGIN_USERS.sub(lambda m: m.group(1) + "<redacted:account>", out.text))
        if out.has("account", "user"):
            out.set(ACCOUNT_KV.sub(lambda m: m.group(1) + m.group(2) + quoted(m.group(3)), out.text))
        if out.has("login"):
            out.set(LOGIN_KV.sub(lambda m: m.group(1) + m.group(2) + quoted(m.group(3)), out.text))
        for r in accounts:
            if r.needs is None or out.has(r.needs):
                out.set(r.regex.sub(r.mark, out.text))
        if "@" in out.text:
            text = out.text
            out.set(EMAIL.sub(lambda m: m.group() if is_hidl_loader_diagnostic(text, m) else "<redacted:email>", text))
        if out.has("jwt", "token", "ticket", "sessionid", "steamloginsecure", "machineauth"):
            out.set(RESIDUAL.sub(lambda m: m.group(1) + "=<redacted:token>", out.text))
        if out.has_run(88, is_token_char):
            out.set(LONG_TOKEN.sub("<redacted:token>", out.text))
        return out.text
    except Exception:
        return FAILED_LINE


def split_url(url):
    scheme_end = url.index("://")
    rest = url[scheme_end + 3:].split("#", 1)[0].split("?", 1)[0]
    slash = rest.find("/")
    authority = (rest[:slash] if slash >= 0 else rest).rsplit("@", 1)[-1]
    return url[:scheme_end], authority, rest[slash + 1:] if slash >= 0 else None


def keep_path(url, mark):
    scheme, authority, path = split_url(url)
    if path is None:
        return "%s://%s" % (scheme, authority)
    clean = "/".join(mark if TOKEN_SEGMENT.search(seg) else seg for seg in path.split("/"))
    return "%s://%s/%s" % (scheme, authority, clean)


def secret_scrub(text, mark=SHARE_MARK):
    out = URL.sub(lambda m: keep_path(m.group(), mark), text)
    out = TOKEN.sub(lambda m: m.group(1) + m.group(2) + mark, out)
    out = GRANT_CODE.sub(lambda m: m.group(1) + m.group(2) + mark, out)
    oauth = OAUTH_CONTEXT.search(text) is not None
    src = out

    def code(m):
        in_query = m.start() > 0 and src[m.start() - 1] in "?&"
        grant = not STATUS_CODE.fullmatch(m.group(3)) and (oauth or in_query)
        return m.group(1) + m.group(2) + mark if grant else m.group()
    out = CODE.sub(code, src)
    return HEADER.sub(lambda m: m.group(1) + m.group(2) + mark, out)


def redact_for_share(line):
    if not line:
        return line
    if len(line) > MAX_LINE_LENGTH:
        return OVERSIZED_LINE
    try:
        return LAN_IPV4.sub("<lan-address>", secret_scrub(redact(line)))
    except Exception:
        return FAILED_LINE


def scrub_for_share(chunks, write):
    """Redacts a log given as byte chunks, line by line, calling write() with the text: UTF-16 and
    undecodable files are withheld whole; lines with NULs or over MAX_LINE_LENGTH are withheld."""
    chunks = iter(chunks)
    first = b""
    for chunk in chunks:
        first += chunk
        if len(first) >= 2:
            break
    if first[:2] in (b"\xff\xfe", b"\xfe\xff"):
        write(UNSUPPORTED_FILE + "\n")
        return
    decoder = codecs.getincrementaldecoder("utf-8")("strict")
    line, withheld, after_cr = [], None, False
    length = 0

    def emit():
        nonlocal withheld, length
        write((withheld if withheld is not None else redact_for_share("".join(line))) + "\n")
        line.clear()
        length = 0
        withheld = None

    def feed(text):
        nonlocal after_cr, withheld, length
        for ch in text:
            if after_cr:
                after_cr = False
                if ch == "\n":
                    continue
            if ch in "\r\n":
                emit()
                after_cr = ch == "\r"
            elif withheld is None:
                if ch == "\0" or length == MAX_LINE_LENGTH:
                    withheld = UNSUPPORTED_LINE if ch == "\0" else OVERSIZED_LINE
                    line.clear()
                    length = 0
                else:
                    line.append(ch)
                    length += 1

    try:
        feed(decoder.decode(first))
        for chunk in chunks:
            feed(decoder.decode(chunk))
        feed(decoder.decode(b"", final=True))
        if withheld is not None or line:
            emit()
    except UnicodeDecodeError:
        write(UNSUPPORTED_FILE + "\n")


def is_binary(path):
    try:
        with open(path, "rb") as f:
            return b"\0" in f.read(4096)
    except OSError:
        return True


def file_chunks(path, size=1 << 16):
    with open(path, "rb") as f:
        while True:
            chunk = f.read(size)
            if not chunk:
                return
            yield chunk


def main(argv):
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    learn_from_runtime(os.environ.get("REDACT_ROOT", "/"))
    scrub_for_share(file_chunks(argv[1]), sys.stdout.write)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
