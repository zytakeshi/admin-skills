#!/usr/bin/env python3
"""Hourly nerf canary for the viraltech Codex account (founder 2026-10-09).

"If it's not being normal for several hours, consider it nerfed": launchd runs this every hour.
Each run asks the candy question (expected 21) through codex-viraltech.sh with memories and the
shell tool off (with memories on, the model reads the old answer 21 from the account's memory
files = a fake pass). Every run appends one JSONL row; then the state file is recomputed:
  nerfed  <- every judged run in the last WINDOW_H hours answered wrong (>= MIN_RUNS runs, spanning
             >= MIN_SPAN_H hours)
  healthy <- the last CLEAR_PASSES runs all passed
  otherwise the previous state holds (one lucky pass after idle is not a recovery).
codex-viraltech.sh reads the state file and exits 94 while nerfed, so /codex goes to lane 2.
viraltech marks fast (founder 2026-10-20: "when this happens we should mark that account as nerfed
until it is not" — a wrong answer, or "Selected model is at capacity" on viraltech while zyvista
answered the same model 11/11): one run with a wrong answer or a capacity error marks it nerfed at
once, and one all-correct run clears it. This replaces, for viraltech only, the 10-19 rule that
capacity does not count. zyvista keeps the old rule: only answers judge it, and a run that ended in an error — capacity, timeout, or a local config error such as
Daybreak left on (verdict config_error, named in the Telegram DM) — is not judged; it counts toward
neither a nerf nor a clear. The state is replayed from the whole log on every run, so a change in
this rule also corrects a state that older rows set.
Usage: viraltech-nerf-canary.py            (one canary run + state update)
       viraltech-nerf-canary.py --state-only  (recompute the state from the log, no request)
       viraltech-nerf-canary.py --account zyvista  (founder 2026-10-10: same canary on the default
         ~/.codex login; codex-zyvista.sh reads its state and skips lane 2 while nerfed. Model and effort come from
         ~/.config/review-lanes/zyvista-canary-model ("<model> <effort>"); the login must be the email
         in ~/.config/review-lanes/codex-zyvista-email, else the row is an error and no request is sent.)
"""
import datetime as dt
import json
import os
import re
import subprocess
import sys
import tempfile
import time

STATE_DIR = os.environ.get("VT_CANARY_STATE_DIR") or os.path.expanduser("~/.local/state/review-lanes")
ACCOUNT = sys.argv[sys.argv.index("--account") + 1] if "--account" in sys.argv else "viraltech"
if ACCOUNT not in ("viraltech", "zyvista"):
    sys.exit(f"viraltech-nerf-canary: unknown account {ACCOUNT!r}")
LOG = os.path.join(STATE_DIR, f"{ACCOUNT}-canary.jsonl")
STATE = os.path.join(STATE_DIR, f"{ACCOUNT}-nerf-state.json")
CFG = os.path.expanduser("~/.config/review-lanes")
WRAPPER = os.path.expanduser("~/.claude/skills/codex/scripts/codex-viraltech.sh")
WINDOW_H, MIN_RUNS, MIN_SPAN_H = 7, 3, 5  # fits the 3h launchd interval (quiet mode, 2026-10-10)
# zyvista runs twice a day (09:05 and 21:05 JST), so 3 runs never fit in 7 h and it could never be
# marked nerfed. Founder 2026-10-13: pause a nerfed account from the review lanes — zyvista is
# nerfed after 2 failed runs in a row (about 12 h); codex-zyvista.sh then skips lane 2. The band is
# wide because launchd fires a slot late after sleep (01:11Z on 10-11 for the 00:05Z slot): a run up
# to ~5 h late still pairs with its neighbour; the 6 h span keeps two catch-up runs from counting.
if ACCOUNT == "zyvista":
    WINDOW_H, MIN_RUNS, MIN_SPAN_H = 18, 2, 6
# viraltech: one all-correct run clears the nerf (founder 2026-10-11); zyvista keeps 2 passes in a row.
CLEAR_PASSES = 1 if ACCOUNT == "viraltech" else 2
# viraltech (founder 2026-10-20): one failed run marks it nerfed at once; a capacity error is a fail.
FAST_NERF = ACCOUNT == "viraltech"
CAPACITY_RE = re.compile(r"at capacity", re.I)
TIMEOUT_S = 600
# Back-to-back questions per run; see run_canary. viraltech 12 (founder 2026-10-11): 3-question bursts
# passed 3/3 at 11:41 and 13:58 UTC on 10-10, while the 15:07 run and a manual run right after it
# (6 of 6) answered 29.
# viraltech is strict: stop at the first answer that is not 21, pass only if all BURST answer 21.
# viraltech 12 -> 6 (founder 2026-10-20, after the 10-20 nerf): the canary was ~221 identical requests
# a day on an account that serves only code reviews; half the burst halves that load.
STRICT = ACCOUNT == "viraltech"
BURST = int(os.environ.get("VT_CANARY_BURST", "6" if ACCOUNT == "viraltech" else "3"))
WARMUP_GAP_S = int(os.environ.get("VT_CANARY_WARMUP_GAP_S", "360"))  # wait after the warm-up question
# Pause between burst questions (founder 2026-10-12: too many requests at once may nerf an account, so
# the questions are spaced, never back to back). Sequential already; this adds the quiet time between them.
BURST_GAP_S = int(os.environ.get("VT_CANARY_BURST_GAP_S", "60"))

# Errors that come from this machine's codex setup, not from the account: Daybreak on for a model
# that has none, a model the ChatGPT login cannot use, the wrong login, or the viraltech wrapper's
# own config exits (93 daybreak model, 95 wrong email, 97 home/auth missing).
CONFIG_ERROR_RE = re.compile(
    r"Daybreak is unavailable|choose a compatible model|not supported when using Codex with a ChatGPT account"
    r"|default ~/\.codex login is|^rc=9[357]:", re.I)



PROMPT = ("在一个黑色的袋子里放有三种口味的糖果，每种糖果有两种不同的形状（圆形和五角星形，不同的形状靠手感可以分辨）。"
          "现已知不同口味的糖和不同形状的数量统计如下表。参赛者需要在活动前决定摸出的糖果数目，那么，最少取出多少个糖果"
          "才能保证手中同时拥有不同形状的苹果味和桃子味的糖？（同时手中有圆形苹果味匹配五角星桃子味糖果，或者有圆形桃子味"
          "匹配五角星苹果味糖果都满足要求）\n苹果味 桃子味 西瓜味\n圆形 7 9 8\n五角星形 7 6 4"
          "\n\n只输出最终整数，不要解释。")


def now():
    return dt.datetime.now(dt.timezone.utc)


def login_email(auth_path):
    import base64
    try:
        t = (json.load(open(auth_path)).get("tokens") or {}).get("id_token") or ""
        t = t.get("raw_jwt", "") if isinstance(t, dict) else t
        p = t.split(".")[1]; p += "=" * (-len(p) % 4)
        return json.loads(base64.urlsafe_b64decode(p)).get("email", "")
    except Exception as e:
        return f"unreadable: {type(e).__name__}"


def run_canary():
    t0 = time.time()
    row = {"ts": now().isoformat(timespec="seconds")}
    flags = ["--disable", "memories", "--disable", "shell_tool", "--ephemeral", "--skip-git-repo-check",
             "-s", "read-only", "--json"]
    if ACCOUNT == "zyvista":
        want = open(os.path.join(CFG, "codex-zyvista-email")).read().split()[0]
        model, effort = open(os.path.join(CFG, "zyvista-canary-model")).read().split()[:2]
        got = login_email(os.path.expanduser("~/.codex/auth.json"))
        row.update(account=got, model=model, effort=effort)
        if got != want:
            row.update(verdict="config_error", error=f"default ~/.codex login is {got!r}, expected {want!r} — not run")
            return row
    # Burst, not one request (founder 2026-10-10): a nerfed account answers the first request or two
    # after idle normally, then goes shallow (relay 09-30: 3/3 then 0/7; every mixed relay hour is
    # passes-first). A run therefore asks BURST questions back to back and passes on a majority.
    # The first answers after idle can be good for a few minutes (founder 2026-10-10; relay hours
    # showed up to 5 passes in the first ~4 min, viraltech passed at 13:16 and failed at 13:22). So
    # one warm-up question is logged but not judged, then we wait WARMUP_GAP_S, then the burst counts.
    zm, ze = (model, effort) if ACCOUNT == "zyvista" else (None, None)
    # viraltech (founder 2026-10-23): ~/.config/review-lanes/viraltech-canary-model holds
    # "<model> <effort> [<fallback model>]"; medium is enough for the check, and a request that hits
    # "at capacity" is asked again once on the fallback model. No file = the wrapper's review profile.
    fb = None
    if ACCOUNT == "viraltech" and os.path.exists(os.path.join(CFG, "viraltech-canary-model")):
        parts = open(os.path.join(CFG, "viraltech-canary-model")).read().split()
        zm, ze, fb = parts[0], parts[1], (parts[2] if len(parts) > 2 else None)

    def ask(fl):
        one = ask_once(zm, ze, fl)
        if fb and CAPACITY_RE.search(one.get("error") or ""):
            one = dict(ask_once(fb, ze, fl), fell_back_from=zm)
        return one

    warm = ask(flags)
    row["warmup"] = {"answer": warm.get("answer"), "reasoning_tokens": warm.get("reasoning_tokens"),
                     "error": warm.get("error"), "model": warm.get("model")}
    time.sleep(WARMUP_GAP_S)
    answers, tokens, errors = [], [], []
    for i in range(BURST):
        if i:
            time.sleep(BURST_GAP_S)
        one = ask(flags)
        if one.get("fell_back_from"):
            row["fell_back_from"] = one["fell_back_from"]
        answers.append(one.get("answer")); tokens.append(one.get("reasoning_tokens"))
        if one.get("error"):
            errors.append(one["error"])
        for k in ("account", "model", "effort"):
            if one.get(k):
                row[k] = one[k]
        if STRICT and one.get("answer") != "21":
            break  # first wrong answer or error ends the run: fewer requests on a nerfed account
    row.update(secs=round(time.time() - t0, 1), answers=answers, reasoning_tokens=tokens)
    # zyvista: majority, not unanimity — a healthy account at medium effort still misses about 1 in 10
    # (zyvista 21/21/29 on 2026-10-10), while nerfed bursts score 0 of 3.
    good = sum(a == "21" for a in answers)
    wrong = [a for a in answers if a is not None and a != "21"]
    if STRICT:
        passed = good == BURST
    else:
        passed = good * 2 > BURST
    if passed:
        row["verdict"], row["answer"] = "pass", "21"
    elif wrong:
        row["verdict"], row["answer"] = "fail", wrong[0]
    else:
        err = (errors[-1] if errors else "no answer")[:300]
        if FAST_NERF and CAPACITY_RE.search(err):
            row["verdict"], row["answer"], row["error"] = "fail", "capacity", err
        else:
            row["verdict"], row["error"] = ("config_error" if CONFIG_ERROR_RE.search(err) else "error"), err
    return row


def ask_once(model, effort, flags):
    one = {}
    with tempfile.TemporaryDirectory(prefix=f"{ACCOUNT}-canary-") as d:
        out = os.path.join(d, "answer.txt")
        if ACCOUNT == "zyvista":
            cmd = ["codex", "exec", "-m", model, "-c", f"model_reasoning_effort={effort}", *flags, "-C", d, "-o", out, PROMPT]
            env = {k: v for k, v in os.environ.items() if k != "CODEX_HOME"}
        else:
            pick = ["-m", model, "-c", f"model_reasoning_effort={effort}"] if model else []
            cmd = ["bash", WRAPPER, "exec", *pick, *flags, "-C", d, "-o", out, PROMPT]
            env = dict(os.environ, CODEX_VT_CANARY="1")  # the wrapper skips its own nerf-state check
        try:
            p = subprocess.run(cmd, stdin=subprocess.DEVNULL, capture_output=True, text=True,
                               timeout=TIMEOUT_S, env=env)
            rc, events = p.returncode, p.stdout + p.stderr
        except subprocess.TimeoutExpired as e:
            out_ = e.stdout or ""
            rc, events = "timeout", out_.decode("utf-8", "replace") if isinstance(out_, bytes) else out_
        answer = open(out).read().strip() if os.path.exists(out) else ""
    m = re.findall(r'"reasoning_output_tokens":(\d+)', events)
    if m:
        one["reasoning_tokens"] = int(m[-1])
    acct = re.search(r"codex-viraltech: account=(\S+) model=(\S+) effort=(\S+)", events)
    if acct:
        one["account"], one["model"], one["effort"] = acct.groups()
    if model:  # the wrapper logs a caller -m/-c as "caller-override"; record what was asked
        one["model"], one["effort"] = model, effort
    # (?:\\.|[^"\\])* keeps an escaped quote inside the message; [^"]* cut nested-JSON errors to "{\\".
    failed = re.findall(r'"type":"turn\.failed","error":\{"message":"((?:\\.|[^"\\])*)"', events)
    nums = re.findall(r"\d+", answer)
    if rc == 0 and nums:
        one["answer"] = nums[-1]
    else:
        tail = [l for l in events.strip().splitlines() if l.strip()][-1:] or [""]
        one["error"] = (failed[-1] if failed else f"rc={rc}: {tail[0]}")[:300]
    return one


def read_log():
    rows = []
    try:
        with open(LOG) as f:
            for line in f:
                line = line.strip()
                if line:
                    rows.append(json.loads(line))
    except FileNotFoundError:
        pass
    return rows


def judged_verdict(r):
    """Older viraltech rows logged a capacity error as verdict 'error'; replay them as a fail."""
    v = r.get("verdict")
    if FAST_NERF and v == "error" and CAPACITY_RE.search(r.get("error") or ""):
        return "fail"
    return v


def compute_state(rows, prev, t=None):
    t = t or now()
    recent = [r for r in rows if t - dt.datetime.fromisoformat(r["ts"]) <= dt.timedelta(hours=WINDOW_H)]
    last = rows[-CLEAR_PASSES:]
    nerfed, reason = prev.get("nerfed", False), "unchanged"
    if len(last) == CLEAR_PASSES and all(judged_verdict(r) == "pass" for r in last):
        nerfed, reason = False, f"last {CLEAR_PASSES} runs passed"
    elif FAST_NERF and rows and judged_verdict(rows[-1]) == "fail":
        r = rows[-1]
        nerfed, reason = True, f"run at {r['ts']} failed: {r.get('answer') or 'capacity'}"
    elif len(recent) >= MIN_RUNS and all(judged_verdict(r) == "fail" for r in recent):
        span = dt.datetime.fromisoformat(recent[-1]["ts"]) - dt.datetime.fromisoformat(recent[0]["ts"])
        if span >= dt.timedelta(hours=MIN_SPAN_H):
            bad = ", ".join(r.get("answer") or (r.get("error") or "error")[:40] for r in recent)
            nerfed, reason = True, f"no pass in {len(recent)} runs over {WINDOW_H}h: {bad}"
    if reason == "unchanged":
        reason = prev.get("reason", "no verdict yet")
    since = prev.get("since") if nerfed == prev.get("nerfed", False) and prev.get("since") else t.isoformat(timespec="seconds")
    return {"nerfed": nerfed, "since": since, "reason": reason, "updated": t.isoformat(timespec="seconds"),
            "last_run": rows[-1] if rows else None}


def derive_state(rows):
    """Replay the log in order: each judged run (pass or fail) applies the rules at its own time, as
    the live run did. Error runs are skipped; the last row of any kind is still reported as last_run."""
    state, judged = {}, []
    for r in rows:
        if judged_verdict(r) not in ("pass", "fail"):
            continue
        judged.append(r)
        state = compute_state(judged, state, dt.datetime.fromisoformat(r["ts"]))
    if not judged:
        state = {"nerfed": False, "since": now().isoformat(timespec="seconds"), "reason": "no judged run yet"}
    # Fail loud (2026-10-28): runs that ended in an error are not judged, so the nerfed flag above still
    # describes the last judged run. Say so: status "error" + the streak, never "last N runs passed" alone.
    streak = []
    for r in reversed(rows):
        if judged_verdict(r) in ("pass", "fail"):
            break
        streak.append(r)
    state["status"] = "error" if streak else "ok"
    if streak:
        state["reason"] = (f"UNKNOWN — last {len(streak)} run(s) errored since {streak[-1]['ts']}: "
                           f"{(streak[0].get('error') or 'no answer')[:100]} | last judged: {state['reason']}")
    state["updated"] = now().isoformat(timespec="seconds")
    state["last_run"] = rows[-1] if rows else None
    return state


def send_telegram(row, state):
    """A DM on change (see main; was one per run until 2026-10-28) via @vilavpn_grafana_bot (the chat the relay canary used, founder 2026-10-10).
    Config: ~/.config/review-lanes/nerf-canary-tg.env (TG_BOT_TOKEN, TG_CHAT_ID, mode 600). A send failure
    is logged to stderr (launchd .err) and never stops the run."""
    import urllib.parse, urllib.request
    try:
        env = dict(l.strip().split("=", 1) for l in open(os.path.join(CFG, "nerf-canary-tg.env")) if "=" in l)
        v = row.get("verdict")
        head = {"pass": "✅ PASS", "fail": "⛔ FAIL" + (" (model at capacity)" if row.get("answer") == "capacity" else ""), "error": "⚠️ ERROR (no answer, not judged)",
                "config_error": "⚠️ CONFIG ERROR (local setup, not counted as a nerf: fix the codex config)"}.get(v, v)
        good = sum(a == "21" for a in row.get("answers") or [])
        w = row.get("warmup") or {}
        lines = [f"[nerf canary] {ACCOUNT} · {row.get('model', '?')} {row.get('effort', '?')}",
                 f"{head} — {good}/{BURST} answered 21 (expect 21)" + (" · stops at first wrong" if STRICT else ""),
                 f"warm-up (not judged): {w.get('answer') or w.get('error') or '-'} ({w.get('reasoning_tokens')} tok)",
                 "burst: " + " · ".join(str(a) for a in row.get("answers") or []) + "  tok " +
                 "/".join(str(t) for t in row.get("reasoning_tokens") or [])]
        if row.get("error"):
            lines.append(f"error: {row['error'][:200]}")
        label = "UNKNOWN (run errored)" if state.get("status") == "error" else ("NERFED" if state["nerfed"] else "not nerfed")
        lines.append(f"state: {label} — {state['reason'][:240]}")
        data = urllib.parse.urlencode({"chat_id": env["TG_CHAT_ID"], "text": "\n".join(lines)}).encode()
        with urllib.request.urlopen("https://api.telegram.org/bot" + env["TG_BOT_TOKEN"] + "/sendMessage",
                                    data=data, timeout=30) as r:
            if json.load(r).get("ok") is not True:
                print("viraltech-nerf-canary: telegram send not ok", file=sys.stderr)
    except Exception as e:  # report, never echo the token-bearing URL
        print(f"viraltech-nerf-canary: telegram send failed: {type(e).__name__}", file=sys.stderr)


def main():
    os.makedirs(STATE_DIR, exist_ok=True)
    if "--state-only" not in sys.argv:
        row = run_canary()
        with open(LOG, "a") as f:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")
        print(json.dumps(row, ensure_ascii=False))
    try:
        prev = json.load(open(STATE))
    except FileNotFoundError:
        prev = {}
    state = derive_state(read_log())
    tmp = STATE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(state, f, ensure_ascii=False, indent=1)
    os.replace(tmp, STATE)
    if state["nerfed"] != prev.get("nerfed", False):
        print(f"viraltech-nerf-canary: state changed -> nerfed={state['nerfed']} ({state['reason']})", file=sys.stderr)
    print(json.dumps({k: state[k] for k in ("nerfed", "since", "reason")}, ensure_ascii=False))
    # DM only when something changed (2026-10-28): nerfed flips, status ok<->error flips, or a run
    # answered wrong. A routine pass and a repeat of an ongoing error streak stay silent.
    notify = (state["nerfed"] != prev.get("nerfed", False) or state["status"] != prev.get("status")
              or ("--state-only" not in sys.argv and row.get("verdict") == "fail"))
    if "--state-only" not in sys.argv and notify and not os.environ.get("VT_CANARY_STATE_DIR"):  # tests stay silent
        send_telegram(row, state)


if __name__ == "__main__":
    main()
