#!/usr/bin/env python3
"""Fail when the repository would record private values. This repository and its history are public.

    python3 scripts/privacy_check.py                       # tracked files (content and paths)
    python3 scripts/privacy_check.py --staged              # what `git commit` is about to record
    python3 scripts/privacy_check.py --staged --commit-msg .git/COMMIT_EDITMSG   # plus the commit message
    python3 scripts/privacy_check.py --range origin/main..HEAD   # what those commits change, and their messages
    python3 scripts/privacy_check.py --range <base>..<head> --message <file>     # plus text such as a squash message

What counts as private comes from the machine, never from the repository:

- `~/.config/refract/private-words.txt` (or `$REFRACT_CONFIG_DIR/private-words.txt`): one word per line, `#` starts a
  comment. Internal project names, company names, people, host names, anything else.
- `CLAUDE.local.md`'s `code spans` (machine-specific notes for Agents; never committed).
- The home directory and the login name.

On top of that, on every machine: private IPv4 addresses (10/8, 172.16/12, 192.168/16, 100.64/10), email addresses
outside the example domains (RFC 2606 / RFC 6761) and GitHub's noreply domain, and BANNED_NAMES.

A hit names the kind of value and where the rule comes from, never the value itself, so the report can be pasted.
Install the hooks with `git config core.hooksPath scripts/hooks`.
"""
import getpass, ipaddress, os, re, subprocess, sys

ROOT = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True,
                      check=True, cwd=os.path.dirname(os.path.abspath(__file__))).stdout.strip()
HOME = os.path.expanduser("~")
CONFIG_DIR = os.environ.get("REFRACT_CONFIG_DIR") or os.path.join(HOME, ".config", "refract")
# This file spells the patterns it looks for.
SKIP_FILES = {"scripts/privacy_check.py"}
# Values too generic to search for even when a machine's config holds them.
IGNORE = {"darwin", "linux", "local", "ssh", "true", "false", "server", "localhost", "root", "user", "admin", "runner"}
# Internal or vendor names that never appear here, in any spelling. Matched case-insensitively.
BANNED_NAMES = re.compile(r"aster[-_ ]?gate|open[-_ ]?lark|open[-_ ]?wechat|extensions[-_ ]?internal|corp[-_ ]?link",
                          re.IGNORECASE)
EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@((?:[A-Za-z0-9-]+\.)+[A-Za-z]{2,})")
PUBLIC_EMAIL_DOMAINS = ("example.com", "example.net", "example.org", "example", "users.noreply.github.com",
                        "noreply.github.com")
PUBLIC_EMAIL_TLDS = (".test", ".invalid", ".localhost", ".example")
IPV4 = re.compile(r"(?<![\d.])((?:\d{1,3}\.){3}\d{1,3})(?![\d.])")
PRIVATE_NETS = [ipaddress.ip_network(n) for n in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "100.64.0.0/10")]


def git(*args, check=True):
    return subprocess.run(["git", "-C", ROOT, *args], capture_output=True, check=check).stdout


def private_words():
    """{word: source}. Sources are names of rules, never values."""
    out = {}
    path = os.path.join(CONFIG_DIR, "private-words.txt")
    if os.path.exists(path):
        for line in open(path, encoding="utf-8"):
            w = line.split("#", 1)[0].strip()
            if len(w) >= 3 and w.lower() not in IGNORE:
                out.setdefault(w, "private-words.txt")
    local = os.path.join(ROOT, "CLAUDE.local.md")
    if os.path.exists(local):
        for span in re.findall(r"`([^`\n]+)`", open(local, encoding="utf-8").read()):
            span = span.strip()
            # Spans that only name repository files or commands are not private.
            if len(span) >= 4 and span.lower() not in IGNORE and not os.path.exists(os.path.join(ROOT, span)):
                out.setdefault(span, "CLAUDE.local.md")
    if len(HOME) > 1:
        out.setdefault(HOME, "the home directory")
    try:
        user = getpass.getuser()
    except Exception:
        user = ""
    if len(user) >= 4 and user.lower() not in IGNORE:
        out.setdefault(user, "the login name")
    return out


def public_email(domain):
    d = domain.lower()
    return d in PUBLIC_EMAIL_DOMAINS or any(d.endswith("." + p) for p in PUBLIC_EMAIL_DOMAINS) \
        or d.endswith(PUBLIC_EMAIL_TLDS)


def problems(text, words):
    """[(kind, source)] for one line."""
    found = []
    low = text.lower()
    for w, source in words.items():
        wl = w.lower()
        if len(w) < 6 and w.isalnum():
            if re.search(r"(?<![a-z0-9])" + re.escape(wl) + r"(?![a-z0-9])", low):
                found.append(("private word", source))
        elif wl in low:
            found.append(("private word", source))
    if BANNED_NAMES.search(text):
        found.append(("banned name", "BANNED_NAMES"))
    for m in EMAIL.finditer(text):
        if not public_email(m.group(1)):
            found.append(("email address", "not an example or noreply domain"))
    for m in IPV4.finditer(text):
        try:
            ip = ipaddress.ip_address(m.group(1))
        except ValueError:
            continue
        if any(ip in n for n in PRIVATE_NETS):
            found.append(("private IPv4 address", "private range"))
    return found


def scan_text(label, text, words, report):
    for i, line in enumerate(text.splitlines(), 1):
        for kind, source in problems(line, words):
            report.append("%s:%d: %s (%s)" % (label, i, kind, source))


def scan_blob(path, data, words, report):
    if path in SKIP_FILES:
        return
    scan_text("path " + path, path, words, report)
    if b"\0" in data[:8192]:
        return  # binary
    scan_text(path, data.decode("utf-8", "replace"), words, report)


def message_lines(path):
    """The lines git records from a commit message file: no comments, nothing below the scissors line."""
    lines = []
    for line in open(path, encoding="utf-8", errors="replace"):
        if line.startswith("# ------------------------ >8"):
            break
        if not line.startswith("#"):
            lines.append(line)
    return "".join(lines)


def main(argv):
    words = private_words()
    report = []
    args = list(argv)
    msg = None
    if "--commit-msg" in args:
        i = args.index("--commit-msg"); msg = message_lines(args[i + 1]); del args[i:i + 2]
    if "--message" in args:
        i = args.index("--message"); msg = open(args[i + 1], encoding="utf-8", errors="replace").read(); del args[i:i + 2]
    if args[:1] == ["--staged"]:
        names = git("diff", "--cached", "--name-only", "-z", "--diff-filter=ACMRT").split(b"\0")
        for name in filter(None, names):
            path = name.decode()
            scan_blob(path, git("show", ":" + path), words, report)
    elif args[:1] == ["--range"] and len(args) == 2 and ".." in args[1]:
        base, head = args[1].split("..", 1)
        shared = subprocess.run(["git", "-C", ROOT, "merge-base", base, head], capture_output=True).returncode == 0
        if shared:
            names = git("diff", "--name-only", "-z", "--diff-filter=ACMRT", base, head).split(b"\0")
            log = git("log", "--format=%B", "%s..%s" % (base, head))
        else:  # no shared history: everything in head
            names = git("ls-tree", "-r", "-z", "--name-only", head).split(b"\0")
            log = git("log", "--format=%B", head)
        for name in filter(None, names):
            path = name.decode()
            scan_blob(path, git("show", "%s:%s" % (head, path)), words, report)
        scan_text("commit messages", log.decode("utf-8", "replace"), words, report)
    elif not args:
        for name in filter(None, git("ls-files", "-z").split(b"\0")):
            path = name.decode()
            full = os.path.join(ROOT, path)
            data = open(full, "rb").read() if os.path.isfile(full) and not os.path.islink(full) \
                else git("show", ":" + path, check=False)
            scan_blob(path, data, words, report)
    else:
        print(__doc__, file=sys.stderr)
        return 2
    if msg is not None:
        scan_text("message", msg, words, report)
    if report:
        print("privacy_check: private values found (values are not printed):", file=sys.stderr)
        for line in report:
            print("  " + line, file=sys.stderr)
        print("Replace them with placeholders such as <host> or me@example.com.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
