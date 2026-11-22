#!/usr/bin/env bash
# Codex on the the viraltech account ChatGPT account (founder 2026-10-08).
# Usage: codex-viraltech.sh exec [codex exec args...]   (drop-in for `codex exec ...`)
# - CODEX_HOME = the Orca-managed account home named in ~/.config/review-lanes/codex-viraltech-home.
#   Never copy or edit that auth.json: a token refresh rotates it, and a copy can log Orca out.
# - Fails loud unless the home's login is the email in ~/.config/review-lanes/codex-viraltech-email.
# - That home has no config.toml/profiles, so model and effort are read from a profile file:
#   CODEX_VT_PROFILE_FILE (default ~/.codex/review.config.toml; implementer mode passes
#   ~/.codex/config.toml). A -m or -c model_reasoning_effort=... passed by the caller wins.
# - NEVER daybreak on this account (founder 2026-10-15): a daybreak profile model is swapped for
#   review.config.toml's model; a caller -m daybreak exits 93.
# - Fast mode OFF (founder 2026-10-25, reverted the same day: "fast mode is too much"): no
#   service_tier flag; runs inherit service_tier from the profile (austerity, 2026-09-11).
# Exit codes: 97 = home/auth missing or unreadable, 95 = login is not the expected account,
#   94 = the hourly canary marked the account nerfed (viraltech-nerf-canary.py),
#   93 = a daybreak model was requested (not available on viraltech),
#   98 = the account already holds its cap of concurrent codex sessions (codex-slot.py).
set -euo pipefail
CFG="$HOME/.config/review-lanes"
HOME_FILE="$CFG/codex-viraltech-home"; EMAIL_FILE="$CFG/codex-viraltech-email"
[[ -r "$HOME_FILE" && -r "$EMAIL_FILE" ]] || { echo "codex-viraltech: missing $HOME_FILE or $EMAIL_FILE" >&2; exit 97; }
VT_HOME="$(head -1 "$HOME_FILE")"; WANT="$(head -1 "$EMAIL_FILE")"
[[ -r "$VT_HOME/auth.json" ]] || { echo "codex-viraltech: no auth.json in the account home" >&2; exit 97; }
GOT="$(python3 - "$VT_HOME/auth.json" <<'PY'
import base64, json, sys
d = json.load(open(sys.argv[1])); t = (d.get("tokens") or {}).get("id_token") or ""
t = t.get("raw_jwt", "") if isinstance(t, dict) else t
try:
    p = t.split(".")[1]; p += "=" * (-len(p) % 4)
    print(json.loads(base64.urlsafe_b64decode(p)).get("email", ""))
except Exception:
    print("")
PY
)"
[[ "$GOT" == "$WANT" ]] || { echo "codex-viraltech: account home is logged in as '${GOT:-unknown}', expected '$WANT'" >&2; exit 95; }
# Nerf state (founder 2026-10-09: not normal for several hours = nerfed → skip to lane 2). Written
# hourly by viraltech-nerf-canary.py; the canary itself sets CODEX_VT_CANARY=1 to bypass this.
# A state older than 3h means the canary stopped: warn and run (an outage of the monitor is not a nerf).
# Founder hold (2026-10-10: keep the account quiet, /codex uses the main account): while this file
# exists, every non-canary run exits 94 at once. Remove the hold with `mv` when the founder says so.
HOLD="$CFG/viraltech-hold"
if [[ "${CODEX_VT_CANARY:-0}" != "1" && -e "$HOLD" ]]; then
  echo "codex-viraltech: account ON HOLD ($(head -1 "$HOLD")) — skipping to lane 2" >&2; exit 94
fi
NERF_STATE="${VT_CANARY_STATE_DIR:-$HOME/.local/state/review-lanes}/viraltech-nerf-state.json"
if [[ "${CODEX_VT_CANARY:-0}" != "1" && -r "$NERF_STATE" ]]; then
  NERF="$(python3 - "$NERF_STATE" <<'PY'
import datetime as dt, json, sys
s = json.load(open(sys.argv[1]))
age = dt.datetime.now(dt.timezone.utc) - dt.datetime.fromisoformat(s["updated"])
if age > dt.timedelta(hours=3):
    print(f"stale\tcanary state not updated for {int(age.total_seconds() // 3600)}h — running anyway")
elif s.get("nerfed"):
    print(f"nerfed\tsince {s.get('since')}: {s.get('reason')}")
PY
)" || NERF="stale	nerf state unreadable — running anyway"
  case "$NERF" in
    nerfed*) echo "codex-viraltech: account marked NERFED ${NERF#*	} — skipping to lane 2" >&2; exit 94 ;;
    stale*)  echo "codex-viraltech: WARNING ${NERF#*	}" >&2 ;;
  esac
fi
PROFILE="${CODEX_VT_PROFILE_FILE:-$HOME/.codex/review.config.toml}"
read_key() { awk -F'=' -v k="$1" '$1 ~ "^[[:space:]]*"k"[[:space:]]*$" {gsub(/^[[:space:]]*"|"[[:space:]]*$/, "", $2); print $2; exit}' "$PROFILE"; }
MODEL="$(read_key model || true)"; EFFORT="$(read_key model_reasoning_effort || true)"
# The viraltech account has NO daybreak models (founder 2026-10-15: "never use daybreak on
# viraltech"; measured: HTTP 400 "not supported when using Codex with a ChatGPT account").
# A profile that names daybreak (implementer mode's ~/.codex/config.toml) gets the review
# profile's model instead, said out loud; a caller -m daybreak is a caller error and fails.
REVIEW_PROFILE="$HOME/.codex/review.config.toml"
if [[ "$MODEL" == *daybreak* ]]; then
  OLD="$MODEL"; MODEL="$(PROFILE="$REVIEW_PROFILE" read_key model || true)"
  [[ -n "$MODEL" && "$MODEL" != *daybreak* ]] || { echo "codex-viraltech: profile model '$OLD' is daybreak (not on this account) and $REVIEW_PROFILE has no usable model" >&2; exit 93; }
  echo "codex-viraltech: '$OLD' is not available on viraltech — using '$MODEL' from $(basename "$REVIEW_PROFILE")" >&2
fi
HAS_M=0; HAS_E=0; PREV=""
for a in "$@"; do
  [[ "$a" == "-m" || "$a" == "--model" || "$a" == --model=* ]] && HAS_M=1
  [[ "$a" == model_reasoning_effort=* ]] && HAS_E=1
  if [[ ( ( "$PREV" == "-m" || "$PREV" == "--model" ) && "$a" == *daybreak* ) || "$a" == --model=*daybreak* ]]; then
    echo "codex-viraltech: caller asked for '${a#--model=}', but daybreak models are not on the viraltech account — use lane 2 (zyvista) for daybreak" >&2; exit 93
  fi
  PREV="$a"
done
EXTRA=()
[[ $HAS_M -eq 0 && -n "$MODEL" ]] && EXTRA+=(-m "$MODEL")
[[ $HAS_E -eq 0 && -n "$EFFORT" ]] && EXTRA+=(-c "model_reasoning_effort=$EFFORT")
[[ $HAS_M -eq 1 ]] && MODEL="caller-override"; [[ $HAS_E -eq 1 ]] && EFFORT="caller-override"
echo "codex-viraltech: account=$GOT model=${MODEL:-default} effort=${EFFORT:-default} profile=$(basename "$PROFILE")" >&2
# Concurrency cap (founder 2026-10-25): codex-slot.py takes one of 5 slots for this account, then
# execs codex in the same process; a full account exits 98 and the caller goes to lane 2. The canary
# is exempt from the refusal (a refused canary run would read as a nerf) but still holds a slot.
SLOT=(python3 "$(dirname "${BASH_SOURCE[0]}")/codex-slot.py" run viraltech --next "lane 2 (zyvista)")
[[ "${CODEX_VT_CANARY:-0}" == "1" ]] && SLOT+=(--force)
if [[ "${1:-}" == "exec" ]]; then
  shift
  exec "${SLOT[@]}" -- env CODEX_HOME="$VT_HOME" codex exec ${EXTRA[@]+"${EXTRA[@]}"} "$@"
fi
exec "${SLOT[@]}" -- env CODEX_HOME="$VT_HOME" codex "$@"
