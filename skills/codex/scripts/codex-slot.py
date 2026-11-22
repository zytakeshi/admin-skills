#!/usr/bin/env python3
"""codex-slot.py — per-account concurrency cap for Codex calls and sessions (founder 2026-10-25:
"Codex accounts are sensitive to high concurrency … 5 concurrent session/call for each account,
and use the next account or priority lane if exceeded").

Usage:
  codex-slot.py run <account> [--next TEXT] [--force] -- <cmd> [args...]
      Take a slot, then exec <cmd> in the same process, so the slot belongs to the process that
      runs codex and frees itself when that process exits. Exit 98 when the account is full.
  codex-slot.py check <account>     exit 0 when a slot is free, 98 when full (takes no slot)
  codex-slot.py status [account]    print "<account> <used>/<cap>" and the holders

Cap: $CODEX_SLOT_CAP, else ~/.config/review-lanes/codex-max-concurrent, else 5.
Break-glass: CODEX_SLOT_FORCE=1 (or --force) takes a slot even when full; it still counts.
Exit 98 = account at its cap. Exit 2 = bad usage or bad cap value.

How it counts: one file per slot (slot-N) holding "pid|process start time". A slot is live while
that pid exists with the same start time, so a crashed holder or a reused pid frees itself. All
reads and writes of an account's slots run under an flock, which the OS drops on a crash.
No slot file is ever deleted: a stale one is overwritten.
"""
import fcntl
import glob
import os
import subprocess
import sys

ACCOUNTS = ("viraltech", "zyvista")
FULL = 98
STATE = os.environ.get("CODEX_SLOT_DIR") or os.path.expanduser("~/.local/state/review-lanes/slots")
CAP_FILE = os.path.expanduser("~/.config/review-lanes/codex-max-concurrent")


def die(msg, code=2):
    print(f"codex-slot: {msg}", file=sys.stderr)
    sys.exit(code)


def cap():
    raw = os.environ.get("CODEX_SLOT_CAP")
    if raw is None:
        try:
            raw = open(CAP_FILE).read().split()[0]
        except (OSError, IndexError):
            raw = "5"
    if not raw.isdigit() or int(raw) < 1:
        die(f"cap '{raw}' is not a positive integer (CODEX_SLOT_CAP or {CAP_FILE})")
    return int(raw)


def started(pid):
    try:
        out = subprocess.run(["ps", "-o", "lstart=", "-p", str(pid)], capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.TimeoutExpired) as e:
        die(f"cannot run ps: {e}")
    return out.stdout.strip() if out.returncode == 0 else ""


def holder(path):
    """Return (pid, lstart) when the slot file names a live process, else None."""
    try:
        pid, lstart = open(path).read().strip().split("|", 1)
    except (OSError, ValueError):
        return None
    return (pid, lstart) if lstart and started(pid) == lstart else None


def live_slots(acct_dir):
    held = {}
    for path in sorted(glob.glob(os.path.join(acct_dir, "slot-*"))):
        h = holder(path)
        if h:
            held[path] = h
    return held


class Locked:
    def __init__(self, acct):
        self.dir = os.path.join(STATE, acct)
        os.makedirs(self.dir, exist_ok=True)
        self.fd = os.open(os.path.join(self.dir, "lock"), os.O_RDWR | os.O_CREAT, 0o644)

    def __enter__(self):
        fcntl.flock(self.fd, fcntl.LOCK_EX)
        return self.dir

    def __exit__(self, *exc):
        fcntl.flock(self.fd, fcntl.LOCK_UN)
        os.close(self.fd)


def parse_account(argv):
    if not argv or argv[0] not in ACCOUNTS:
        die(f"account must be one of {', '.join(ACCOUNTS)}")
    return argv[0]


def cmd_run(argv):
    acct = parse_account(argv)
    rest, nxt, force = argv[1:], "the next lane", os.environ.get("CODEX_SLOT_FORCE") == "1"
    while rest and rest[0] != "--":
        if rest[0] == "--force":
            force, rest = True, rest[1:]
        elif rest[0] == "--next" and len(rest) > 1:
            nxt, rest = rest[1], rest[2:]
        else:
            die(f"unknown option '{rest[0]}'")
    if len(rest) < 2:
        die("run needs '-- <cmd> [args...]'")
    command, limit = rest[1:], cap()
    with Locked(acct) as d:
        held = live_slots(d)
        if len(held) >= limit and not force:
            who = ", ".join(pid for pid, _ in held.values())
            print(f"codex-slot: account {acct} at its cap {len(held)}/{limit} (pids {who}) — skipping to {nxt}",
                  file=sys.stderr)
            sys.exit(FULL)
        n = next(i for i in range(1, 1000) if os.path.join(d, f"slot-{i}") not in held)
        me = os.getpid()
        with open(os.path.join(d, f"slot-{n}"), "w") as f:
            f.write(f"{me}|{started(me)}\n")
    print(f"codex-slot: account={acct} slot={len(held) + 1}/{limit}", file=sys.stderr)
    try:
        os.execvp(command[0], command)
    except OSError as e:
        die(f"cannot run '{command[0]}': {e}", 127)


def cmd_check(argv):
    acct, limit = parse_account(argv), cap()
    with Locked(acct) as d:
        used = len(live_slots(d))
    if used >= limit:
        print(f"codex-slot: account {acct} at its cap {used}/{limit}", file=sys.stderr)
        sys.exit(FULL)
    print(f"{acct} {used}/{limit}")


def cmd_status(argv):
    limit = cap()
    for acct in (argv[:1] or ACCOUNTS):
        parse_account([acct])
        with Locked(acct) as d:
            held = live_slots(d)
        print(f"{acct} {len(held)}/{limit}" + "".join(f"  pid={p} since {s}" for p, s in held.values()))


def main():
    cmds = {"run": cmd_run, "check": cmd_check, "status": cmd_status}
    if len(sys.argv) < 2 or sys.argv[1] not in cmds:
        die("usage: codex-slot.py run|check|status …")
    cmds[sys.argv[1]](sys.argv[2:])


main()
