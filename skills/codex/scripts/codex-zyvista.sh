#!/usr/bin/env bash
# codex-zyvista.sh — lane 1 of the codex review lanes (since 2026-10-28, viraltech expired): codex on the default ~/.codex login (zyvista).
# Founder 2026-10-13: pause a nerfed account from the review lanes. This wrapper skips a nerfed
# account and then runs codex unchanged.
# Usage: codex-zyvista.sh exec --profile review …   (all arguments go to codex as they are)
# Exit codes besides codex's own:
#   98 = the account already holds its cap of concurrent codex sessions (codex-slot.py).
#   94 = the zyvista canary (viraltech-nerf-canary.py --account zyvista) marked the account nerfed.
# The canary runs twice a day, so a state older than 25 h (one missed slot plus a late wake) means
# it stopped: warn and run (an outage of the monitor is not a nerf).
set -u
NERF_STATE="${VT_CANARY_STATE_DIR:-$HOME/.local/state/review-lanes}/zyvista-nerf-state.json"
if [[ -r "$NERF_STATE" ]]; then
  NERF="$(python3 - "$NERF_STATE" <<'PY'
import datetime as dt, json, sys
s = json.load(open(sys.argv[1]))
age = dt.datetime.now(dt.timezone.utc) - dt.datetime.fromisoformat(s["updated"])
if age > dt.timedelta(hours=25):
    print(f"stale\tcanary state not updated for {int(age.total_seconds() // 3600)}h — running anyway")
elif s.get("nerfed"):
    print(f"nerfed\tsince {s.get('since')}: {s.get('reason')}")
PY
)" || NERF="stale	nerf state unreadable — running anyway"
  case "$NERF" in
    nerfed*) echo "codex-zyvista: account marked NERFED ${NERF#*	} — skipping to lane 3" >&2; exit 94 ;;
    stale*)  echo "codex-zyvista: WARNING ${NERF#*	}" >&2 ;;
  esac
else
  echo "codex-zyvista: WARNING no canary state at $NERF_STATE — running anyway" >&2
fi
# Concurrency cap (founder 2026-10-25): take one of 5 slots for this account, then exec codex in the
# same process; a full account exits 98 and the caller goes to lane 3.
exec python3 "$(dirname "${BASH_SOURCE[0]}")/codex-slot.py" run zyvista --next "lane 3 (Cursor)" -- env -u CODEX_HOME codex "$@"
