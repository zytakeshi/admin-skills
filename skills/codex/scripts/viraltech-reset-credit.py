#!/usr/bin/env python3
"""Redeem ONE Codex rate-limit reset credit on the viraltech account (founder 2026-10-19:
"if the viraltech account ran out of rate limit, you are allowed to use a reset — the one
that expires the closest").

Talks to `codex app-server --stdio` with CODEX_HOME = the account home named in
~/.config/review-lanes/codex-viraltech-home (same login check as codex-viraltech.sh), reads
`account/rateLimits/read`, picks the AVAILABLE credit with the earliest `expiresAt` (credits
that never expire go last), and consumes it by id with `account/rateLimitResetCredit/consume`.

Usage: viraltech-reset-credit.py [--dry-run]
  --dry-run  read and print the pick, consume nothing.
Exit codes: 0 = reset done (or dry-run pick printed), 3 = no credit / nothing to reset /
  ordinary usage still allowed (not rate-limited), 95 = wrong login, 97 = home/auth missing,
  1 = protocol or transport error (message on stderr).
"""
import base64, datetime as dt, json, os, subprocess, sys, uuid

CFG = os.path.expanduser("~/.config/review-lanes")


def fail(code, msg):
    print(f"viraltech-reset: {msg}", file=sys.stderr)
    sys.exit(code)


def account_home():
    try:
        home = open(os.path.join(CFG, "codex-viraltech-home")).readline().strip()
        want = open(os.path.join(CFG, "codex-viraltech-email")).readline().strip()
    except OSError as e:
        fail(97, f"missing lane config: {e}")
    try:
        tok = (json.load(open(os.path.join(home, "auth.json"))).get("tokens") or {}).get("id_token") or ""
    except (OSError, ValueError) as e:
        fail(97, f"no readable auth.json in the account home: {e}")
    tok = tok.get("raw_jwt", "") if isinstance(tok, dict) else tok
    try:
        p = tok.split(".")[1]; p += "=" * (-len(p) % 4)
        got = json.loads(base64.urlsafe_b64decode(p)).get("email", "")
    except (IndexError, ValueError) as e:
        fail(95, f"cannot read the login email from auth.json: {e}")
    if got != want:
        fail(95, f"account home is logged in as '{got or 'unknown'}', expected '{want}'")
    return home, got


class AppServer:
    def __init__(self, home):
        env = dict(os.environ, CODEX_HOME=home)
        self.p = subprocess.Popen(["codex", "app-server", "--stdio"], env=env, text=True,
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        self.n = 0

    def send(self, obj):
        self.p.stdin.write(json.dumps(obj) + "\n"); self.p.stdin.flush()

    def call(self, method, params):
        self.n += 1; rid = self.n
        self.send({"jsonrpc": "2.0", "id": rid, "method": method, "params": params})
        for line in self.p.stdout:
            try:
                m = json.loads(line)
            except ValueError:
                continue
            if m.get("id") == rid and "method" not in m:
                if "error" in m:
                    fail(1, f"{method} failed: {json.dumps(m['error'])[:400]}")
                return m.get("result") or {}
        fail(1, f"app-server closed before answering {method}")

    def close(self):
        try:
            self.p.stdin.close(); self.p.wait(timeout=10)
        except Exception:
            self.p.kill()


def ts(sec):
    return "never" if sec is None else dt.datetime.fromtimestamp(sec, dt.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")


def main():
    dry = "--dry-run" in sys.argv[1:]
    home, email = account_home()
    srv = AppServer(home)
    try:
        srv.call("initialize", {"clientInfo": {"name": "viraltech-reset-credit", "version": "1"}})
        srv.send({"jsonrpc": "2.0", "method": "initialized"})
        rl = srv.call("account/rateLimits/read", {})
        summ = rl.get("rateLimitResetCredits") or {}
        avail = [c for c in (summ.get("credits") or []) if c.get("status") == "available"]
        print(f"viraltech-reset: account={email} ordinaryUsageAllowed={rl.get('ordinaryUsageAllowed')} "
              f"availableCount={summ.get('availableCount')} detailRows={len(avail)}", file=sys.stderr)
        for c in sorted(avail, key=lambda c: (c.get("expiresAt") is None, c.get("expiresAt") or 0)):
            print(f"  credit {c['id']} type={c.get('resetType')} expires={ts(c.get('expiresAt'))} "
                  f"title={c.get('title')!r}", file=sys.stderr)
        if not avail:
            fail(3, "no available reset credit with details — nothing redeemed")
        pick = min(avail, key=lambda c: (c.get("expiresAt") is None, c.get("expiresAt") or 0))
        print(f"viraltech-reset: pick {pick['id']} (expires {ts(pick.get('expiresAt'))})", file=sys.stderr)
        if dry:
            return 0
        # Fail closed on "not rate-limited": a credit is only for an exhausted account.
        if rl.get("ordinaryUsageAllowed") is True:
            fail(3, "ordinary usage is still allowed (not rate-limited) — credit NOT redeemed")
        out = srv.call("account/rateLimitResetCredit/consume",
                       {"creditId": pick["id"], "idempotencyKey": str(uuid.uuid4())}).get("outcome")
        after = srv.call("account/rateLimits/read", {"excludeResetCreditDetails": True})
        left = (after.get("rateLimitResetCredits") or {}).get("availableCount")
        print(f"viraltech-reset: outcome={out} ordinaryUsageAllowed(after)={after.get('ordinaryUsageAllowed')} "
              f"creditsLeft={left}", file=sys.stderr)
        return 0 if out == "reset" else 3
    finally:
        srv.close()


if __name__ == "__main__":
    sys.exit(main())
