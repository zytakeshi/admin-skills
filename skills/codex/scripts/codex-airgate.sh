#!/usr/bin/env bash
# Run `codex` against our own relay (profile `airgate` in ~/.codex/config.toml),
# with the API key read from the macOS Keychain at run time — never from a file or argv.
# Usage: codex-airgate.sh exec [codex args...]   (same args as `codex`; `--profile airgate` is added)
#
# Nerf gate (founder 2026-09-30): before codex starts, one canary request asks the relay the
# candy question (expected 21) with the lane's own model + effort. Only a correct answer lets
# the review run on the relay; anything else exits non-zero so the caller falls back to the
# ChatGPT-login lane. The canary goes through the same relay route (Excel for BPS models).
#
# Excel gate (founder 2026-09-30 evening): the relay lane runs only on the Excel route. Before the
# canary, a read-only admin-API call checks the relay account: Excel switched on (the relay turns it
# off by itself after a BPS 403) and the lane's model on its Excel list. Otherwise the request would
# go native (nerfed), so the lane exits 96. The Excel quota cooldown lives only in the relay's process
# memory; during it the relay answers 429 rate_limit_error, which the canary also maps to 96.
#
# Exit codes (the caller treats every non-zero as a lane failure and falls back):
#   96 Excel route not usable now (switched off, model not on the Excel list, cooldown 429,
#      a model/effort override, its state could not be read), or the route check found a
#      review request that went native (the result file is then moved aside)
#   97 key missing from the Keychain
#   98 canary answered, but not 21 (nerf suspected)
#   99 canary request failed (HTTP error, timeout, unreadable reply, config unreadable)
# The canary prints one JSONL event before and one after, so codex-guard counts the run as
# started: a canary failure is reported as FAILED once, never retried (no double charge).
set -u
# RETIRED (founder 2026-10-13): the AirGate relay causes account nerf. Exit before any request;
# 96 is the existing "lane not usable" code, so a stale caller falls through to lane 5.
echo "codex-airgate: lane RETIRED 2026-10-13 (the AirGate relay causes account nerf) — not run, go to lane 5" >&2
exit 96
KEYCHAIN_SERVICE="${AIRGATE_KEYCHAIN_SERVICE:-airgate-review-lanes}"
AIRGATE_API_KEY="$(security find-generic-password -s "$KEYCHAIN_SERVICE" -w 2>/dev/null)"
if [ -z "$AIRGATE_API_KEY" ]; then
  echo "codex-airgate: no key in Keychain service '$KEYCHAIN_SERVICE'" >&2
  exit 97
fi
case "$AIRGATE_API_KEY" in
  *[![:graph:]]*) echo "codex-airgate: key in Keychain service '$KEYCHAIN_SERVICE' is malformed (non-printable characters)" >&2; exit 97 ;;
esac
export AIRGATE_API_KEY
[ "${1:-}" = "exec" ] || { echo "codex-airgate: first argument must be 'exec'" >&2; exit 2; }
shift

# The gate and the canary check the profile's model and effort, so an override would run the
# review on a model they never checked (possibly a native-only one). A user-named model goes to lane 2.
prev=""
for a in "$@"; do
  case "$a" in -m*|--model|--model=*|-p*|--profile|--profile=*|--oss|--local-provider*|--ignore-user-config) override="$a" ;; esac
  case "$prev" in -c|--config) case "$a" in *model*|*profile*|*provider*) override="-c $a" ;; esac ;; esac
  case "$a" in --config=*model*|--config=*profile*|--config=*provider*) override="$a" ;; esac
  prev="$a"
done
if [ -n "${override:-}" ]; then
  echo "codex-airgate: model/effort override '$override' is not allowed on the Excel lane — falling back" >&2
  exit 96
fi

# Read the admin key before the first event: a Keychain hang then still trips codex-guard's startup gate.
AIRGATE_ADMIN_KEY="$(security find-generic-password -s sub2api-admin-api-key -w 2>/dev/null)"
echo '{"type":"airgate.excel_gate.started"}'
AIRGATE_ADMIN_KEY="$AIRGATE_ADMIN_KEY" python3 - <<'PY'
import json, os, re, sys, tomllib, urllib.request, urllib.error

ACCOUNT_ID = 1  # the relay's only upstream account (founder 2026-09-30: no second account)

def event(verdict, **kw):
    print(json.dumps({"type": "airgate.excel_gate.result", "verdict": verdict, **kw}, ensure_ascii=False), flush=True)

def unavailable(reason, **kw):
    event("unavailable", reason=reason, **kw)
    print(f"codex-airgate: Excel route not usable ({reason}) — falling back", file=sys.stderr)
    sys.exit(96)

try:
    home = os.environ.get("CODEX_HOME") or os.path.expanduser("~/.codex")
    with open(os.path.join(home, "airgate.config.toml"), "rb") as f:
        prof = tomllib.load(f)
    with open(os.path.join(home, "config.toml"), "rb") as f:
        base = tomllib.load(f)["model_providers"][prof["model_provider"]]["base_url"].rstrip("/")
    model = prof["model"]
except Exception as e:
    unavailable(f"config unreadable: {type(e).__name__}: {e}")
key = os.environ.get("AIRGATE_ADMIN_KEY")
if not key:
    unavailable("relay admin key missing from the Keychain")
if not re.fullmatch(r"[\x21-\x7e]+", key):  # a CR/LF would make urllib's header error echo the key
    unavailable("relay admin key in the Keychain is malformed (non-printable characters)")
admin_base = base[:-3] if base.endswith("/v1") else base
req = urllib.request.Request(f"{admin_base}/api/v1/admin/accounts/{ACCOUNT_ID}", headers={"x-api-key": key})
try:
    with urllib.request.urlopen(req, timeout=20) as r:
        acct = json.load(r)["data"]
except urllib.error.HTTPError as e:
    unavailable(f"account read HTTP {e.code}")
except Exception as e:
    unavailable(f"account read failed: {type(e).__name__}: {e}")
extra = acct.get("extra") or {}
if acct.get("status") != "active" or not acct.get("schedulable"):
    unavailable("relay account not schedulable", status=acct.get("status"))
if extra.get("openai_excel_bps") is not True:
    unavailable("Excel switched off on the relay account", disabled_at=extra.get("openai_excel_bps_403_disabled_at"))
if model not in (extra.get("openai_excel_bps_models") or []):
    unavailable("model not on the Excel list", model=model)
event("pass", model=model)
PY
rc=$?
[ "$rc" -eq 0 ] || exit "$rc"

if [ "${AIRGATE_SKIP_CANARY:-0}" != "1" ]; then
  echo '{"type":"airgate.canary.started"}'
  python3 - <<'PY'
import json, os, re, sys, time, tomllib, urllib.request, urllib.error

def event(verdict, **kw):
    print(json.dumps({"type": "airgate.canary.result", "verdict": verdict, **kw}, ensure_ascii=False), flush=True)

try:
    home = os.environ.get("CODEX_HOME") or os.path.expanduser("~/.codex")  # same lookup as codex itself
    with open(os.path.join(home, "airgate.config.toml"), "rb") as f:
        prof = tomllib.load(f)
    with open(os.path.join(home, "config.toml"), "rb") as f:
        prov = tomllib.load(f)["model_providers"][prof["model_provider"]]
    base, model = prov["base_url"].rstrip("/"), prof["model"]
    effort = prof.get("model_reasoning_effort")
except Exception as e:
    event("error", reason=f"config unreadable: {type(e).__name__}: {e}")
    print(f"codex-airgate: canary config unreadable: {e}", file=sys.stderr); sys.exit(99)

PROMPT = ("在一个黑色的袋子里放有三种口味的糖果，每种糖果有两种不同的形状（圆形和五角星形，不同的形状靠手感可以分辨）。"
          "现已知不同口味的糖和不同形状的数量统计如下表。参赛者需要在活动前决定摸出的糖果数目，那么，最少取出多少个糖果"
          "才能保证手中同时拥有不同形状的苹果味和桃子味的糖？（同时手中有圆形苹果味匹配五角星桃子味糖果，或者有圆形桃子味"
          "匹配五角星苹果味糖果都满足要求）\n苹果味 桃子味 西瓜味\n圆形 7 9 8\n五角星形 7 6 4"
          "\n\n只输出最终整数，不要解释。")
body = {"model": model, "input": PROMPT, "stream": False}
if effort:
    body["reasoning"] = {"effort": effort}
req = urllib.request.Request(base + "/responses", data=json.dumps(body).encode(), method="POST",
                             headers={"Authorization": "Bearer " + os.environ["AIRGATE_API_KEY"],
                                      "Content-Type": "application/json"})
t0 = time.time()
try:
    with urllib.request.urlopen(req, timeout=300) as r:
        d = json.load(r)
except urllib.error.HTTPError as e:
    detail = e.read()[:300].decode("utf-8", "replace")
    if e.code == 429:  # the relay's Excel quota cooldown (or an account-wide rate limit)
        event("unavailable", reason="relay 429 rate-limited (Excel cooldown)", detail=detail, model=model)
        print(f"codex-airgate: relay rate-limited (Excel cooldown) — falling back: {detail}", file=sys.stderr)
        sys.exit(96)
    event("error", reason=f"HTTP {e.code}", detail=detail, model=model)
    print(f"codex-airgate: canary HTTP {e.code}: {detail}", file=sys.stderr); sys.exit(99)
except Exception as e:
    event("error", reason=f"{type(e).__name__}: {e}", model=model)
    print(f"codex-airgate: canary request failed: {e}", file=sys.stderr); sys.exit(99)

text = "".join(c.get("text", "") for o in d.get("output", []) if o.get("type") == "message"
               for c in o.get("content", []) if c.get("type") in ("output_text", "text")).strip()
nums = re.findall(r"\d+", text)
secs = round(time.time() - t0, 1)
if not nums:
    event("error", reason="no integer in reply", reply=text[:200], model=model, seconds=secs)
    print(f"codex-airgate: canary reply had no integer: {text[:200]!r}", file=sys.stderr); sys.exit(99)
if nums[-1] != "21":
    event("fail", answer=nums[-1], reply=text[:200], model=model, effort=effort, seconds=secs)
    print(f"codex-airgate: nerf canary FAILED (answered {nums[-1]}, expected 21) — falling back", file=sys.stderr)
    sys.exit(98)
event("pass", answer="21", model=model, effort=effort, seconds=secs)
PY
  rc=$?
  [ "$rc" -eq 0 ] || exit "$rc"
fi

# Route check (founder 2026-09-30 evening: never a review on the native route). The relay can still
# route a request natively after the gate passed (Excel switched off mid-run, or a native fallback for
# something Excel cannot do), and only its usage log records the route of each request. So codex runs
# under a supervisor that reads the review key's usage log every 30 s and once more after codex ends.
# Any request not on the Excel endpoint, or no logged request at all, moves the result file aside
# (so codex-guard cannot read it as COMPLETED) and exits 96.
AIRGATE_ADMIN_KEY="$AIRGATE_ADMIN_KEY" python3 - "$@" <<'PY'
import json, os, signal, subprocess, sys, time, tomllib, urllib.request
from datetime import datetime, timedelta, timezone

REVIEW_KEY_ID = 11  # relay API key `airgate-review-lanes` (the Keychain key above)
EXCEL_ENDPOINT = "/basispoints/api/responses"
POLL_SECONDS = 30

args = sys.argv[1:]
result = None
for i, a in enumerate(args):
    if a in ("-o", "--output-last-message") and i + 1 < len(args):
        result = args[i + 1]
    elif a.startswith("--output-last-message="):
        result = a.split("=", 1)[1]

def event(verdict, **kw):
    print(json.dumps({"type": "airgate.route_check.result", "verdict": verdict, **kw}, ensure_ascii=False), flush=True)

def fail(reason, **kw):
    moved = None
    if result and os.path.exists(result):
        moved = f"{result}.not-excel-{time.strftime('%Y%m%d-%H%M%S')}"
        os.replace(result, moved)
    event("unavailable", reason=reason, result_moved_to=moved, **kw)
    print(f"codex-airgate: {reason} — falling back", file=sys.stderr)
    sys.exit(96)

home = os.environ.get("CODEX_HOME") or os.path.expanduser("~/.codex")
with open(os.path.join(home, "airgate.config.toml"), "rb") as f:
    prof = tomllib.load(f)
with open(os.path.join(home, "config.toml"), "rb") as f:
    base = tomllib.load(f)["model_providers"][prof["model_provider"]]["base_url"].rstrip("/")
admin_base = base[:-3] if base.endswith("/v1") else base
admin_key = os.environ["AIRGATE_ADMIN_KEY"]

def usage_page(page, size):
    req = urllib.request.Request(
        f"{admin_base}/api/v1/admin/usage?api_key_id={REVIEW_KEY_ID}&page={page}&page_size={size}",
        headers={"x-api-key": admin_key})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.load(r)["data"]

def requests_since(baseline, baseline_at):
    # The list is newest first by created_at, not by id, so read pages until a row is clearly
    # older than the baseline row (5 min margin), then keep the rows with a higher id.
    found, page = [], 1
    while True:
        d = usage_page(page, 500)
        batch = d.get("items") or []
        found += [x for x in batch if x["id"] > baseline]
        older = any(datetime.fromisoformat(x["created_at"]) < baseline_at for x in batch)
        if older or not batch or page >= (d.get("pages") or 1):
            return found
        page += 1

def codex_rows(items):
    # Key 11 has other users (the canary, scripts); only codex's own requests are this review.
    return [x for x in items if str(x.get("user_agent", "")).startswith("codex_exec/")]

def native(items):
    return [x for x in items if x.get("upstream_endpoint") != EXCEL_ENDPOINT]

try:
    newest = usage_page(1, 1).get("items") or []
    baseline = newest[0]["id"] if newest else 0
    baseline_at = (datetime.fromisoformat(newest[0]["created_at"]) - timedelta(minutes=5)
                   if newest else datetime.min.replace(tzinfo=timezone.utc))
except Exception as e:
    fail(f"route check unavailable before the run: {type(e).__name__}")

env = {k: v for k, v in os.environ.items() if k != "AIRGATE_ADMIN_KEY"}
# stdin=DEVNULL: this python reads its own script from stdin, and codex must never inherit an open stdin.
# Own process group, so a stop also reaches codex's children (they would otherwise keep running).
proc = subprocess.Popen(["codex", "exec", "--profile", "airgate", *args], env=env, stdin=subprocess.DEVNULL,
                        start_new_session=True)
while True:
    try:
        rc = proc.wait(timeout=POLL_SECONDS)
        break
    except subprocess.TimeoutExpired:
        pass
    try:
        bad = native(codex_rows(requests_since(baseline, baseline_at)))
    except Exception as e:  # the check after the run is authoritative; say so, keep running
        print(f"codex-airgate: mid-run route check failed ({type(e).__name__}); retrying in {POLL_SECONDS}s", file=sys.stderr)
        continue
    if bad:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:  # codex ended during the poll; the move below still runs
            pass
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            pass
        try:
            os.killpg(proc.pid, signal.SIGKILL)  # children that ignored SIGTERM
        except ProcessLookupError:
            pass
        proc.wait()
        fail("a review request went native mid-run", native=len(bad), endpoint=bad[0].get("upstream_endpoint"))

# The relay writes usage rows asynchronously: re-read until two reads 5 s apart agree (max ~45 s).
items, last = None, None
for _ in range(9):
    time.sleep(5)
    try:
        items = codex_rows(requests_since(baseline, baseline_at))
    except Exception as e:
        fail(f"route check failed after the run: {type(e).__name__}")
    ids = sorted(x["id"] for x in items)
    if ids == last:
        break
    last = ids
else:
    fail("relay usage rows still changing after 45 s — the Excel route is unproven")
if not items:
    fail("no codex request logged for the review key — the Excel route is unproven")
bad = native(items)
if bad:
    fail("a review request went native", native=len(bad), total=len(items), endpoint=bad[0].get("upstream_endpoint"))
event("pass", requests=len(items), codex_rc=rc)
sys.exit(rc)
PY
