#!/usr/bin/env bash
# cursor-review-guard.sh — lane 1 of the /codex review chain: run a READ-ONLY review through the
# Cursor CLI (`cursor agent`) and report one STATUS line, using the same file convention as
# codex-guard.sh so the caller treats both lanes alike.
#
# Usage:
#   cursor-review-guard.sh <TASK_ID> <MAX_SECONDS> <PROJECT_DIR> "<prompt>"
#
# Files (same names codex-guard.sh uses, so Step 4 of the skill reads the result unchanged):
#   result: /tmp/codex_result_<TASK_ID>.txt
#   events: /tmp/cursor_events_<TASK_ID>.jsonl
#   status: /tmp/codex_status_<TASK_ID>.txt
#
# Model: read from ~/.config/review-lanes/cursor-model (never hardcoded here); CURSOR_REVIEW_MODEL
# overrides it for one run. A '*' there means "newest version" (see the resolver below). `--model` is STICKY in Cursor — it rewrites the default in
# ~/.cursor/cli-config.json — so the config is snapshotted before launch and restored after the
# init event (so parallel runs see the user's default) and again after exit.
#
# STATUS values:
#   COMPLETED  a successful `result` event with non-empty text — result file written
#   TIMEOUT    exceeded MAX_SECONDS (killed)
#   FAILED     no event within the startup gate, an error result (quota, auth, model), or a crash
# Anything but COMPLETED means: fall through to lane 2 (codex-guard.sh).
#
# Env overrides (mainly for tests): CURSOR_GUARD_STARTUP (default 120), CURSOR_GUARD_POLL (default 5)

set -u

TASK_ID="${1:?usage: cursor-review-guard.sh TASK_ID MAX_SECONDS PROJECT_DIR PROMPT}"
MAX_SECONDS="${2:?missing MAX_SECONDS}"
PROJECT_DIR="${3:?missing PROJECT_DIR}"
PROMPT="${4:?missing PROMPT}"

RESULT="/tmp/codex_result_${TASK_ID}.txt"
EVENTS="/tmp/cursor_events_${TASK_ID}.jsonl"
STATUS_FILE="/tmp/codex_status_${TASK_ID}.txt"
CFG="$HOME/.cursor/cli-config.json"
SNAP="/tmp/cursor_cfg_${TASK_ID}.json"
LOCK="/tmp/cursor-review-lane.lock"   # released/stale locks are moved aside in /tmp, which macOS cleans
STARTUP_TIMEOUT="${CURSOR_GUARD_STARTUP:-120}"
POLL="${CURSOR_GUARD_POLL:-5}"
# CURSOR_GUARD_MODE=write = implementer mode (founder 2026-10-01: easy implementation goes to Cursor
# first): the agent may edit files in PROJECT_DIR; shell commands run in Cursor's sandbox. Default = read-only review.
case "${CURSOR_GUARD_MODE:-review}" in
  review) MODE_ARGS=(--mode ask) ;;
  write)  MODE_ARGS=(--force --sandbox enabled) ;;
  *) echo "cursor-guard: unknown CURSOR_GUARD_MODE '${CURSOR_GUARD_MODE}' (review|write)" >&2; exit 2 ;;
esac

finish() { # $1=STATUS, rest=extra lines
  local st="$1"; shift
  { echo "STATUS: ${st}"; [ $# -gt 0 ] && printf '%s\n' "$@"; } > "$STATUS_FILE"
  [ $# -gt 0 ] && printf '%s\n' "$@"
  echo "STATUS: ${st}"
  case "$st" in COMPLETED) exit 0;; TIMEOUT) exit 3;; *) exit 1;; esac
}

MODEL="${CURSOR_REVIEW_MODEL:-$(head -1 "$HOME/.config/review-lanes/cursor-model" 2>/dev/null)}"
[ -n "$MODEL" ] || finish FAILED "no Cursor model configured (~/.config/review-lanes/cursor-model is missing or empty)"
# The CLI ships as `cursor agent` (app shim) or as the standalone `cursor-agent`; accept either.
if command -v cursor >/dev/null; then CURSOR_CLI=(cursor agent)
elif command -v cursor-agent >/dev/null; then CURSOR_CLI=(cursor-agent)
else finish FAILED "Cursor CLI not found on PATH (neither cursor nor cursor-agent)"; fi
# A '*' in the configured id is a version wildcard (founder 2026-09-28: "use whatever is newer"):
# `grok-*-xhigh-fast` → the highest-versioned id in Cursor's live list that matches, with or
# without the older `cursor-` prefix. Resolved per run, so a new release is picked up at once.
if [ "${MODEL#*\*}" != "$MODEL" ]; then
  spec="$MODEL"
  re="^(cursor-)?$(printf '%s' "$spec" | sed -e 's/[.]/\\./g' -e 's/\*/([0-9]+([.][0-9]+)*)/')\$"
  MODEL="$(cd /tmp && "${CURSOR_CLI[@]}" --list-models 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | awk '{print $1}' \
    | grep -E "$re" | awk '{v=$0; sub(/^(cursor-)?[a-z]+-/, "", v); sub(/-.*/, "", v); print v "\t" $0}' \
    | sort -t "$(printf '\t')" -k1,1V | tail -1 | cut -f2)"
  [ -n "$MODEL" ] || finish FAILED "no Cursor model matches '${spec}' (${CURSOR_CLI[*]} --list-models)"
  echo "cursor-guard: '${spec}' resolved to ${MODEL}"
fi
[ -d "$PROJECT_DIR" ] || finish FAILED "project dir not found: $PROJECT_DIR"
: > "$EVENTS"

restored=0
restore_cfg() { [ -s "$SNAP" ] && cp "$SNAP" "$CFG"; }
release_lock() { [ "$(cat "$LOCK/pid" 2>/dev/null)" = "$$" ] && mv "$LOCK" "$LOCK.released.$$" 2>/dev/null; }

# ---- snapshot + launch under a lock, so a parallel run never snapshots our sticky model ----
waited=0
until mkdir "$LOCK" 2>/dev/null; do
  owner="$(cat "$LOCK/pid" 2>/dev/null)"
  if [ -n "$owner" ] && ! kill -0 "$owner" 2>/dev/null; then   # stale lock from a dead run
    mv "$LOCK" "$LOCK.stale.$$" 2>/dev/null; continue
  fi
  [ "$waited" -ge 180 ] && finish FAILED "Cursor lane lock held for 180s by pid ${owner:-?}"
  sleep 2; waited=$((waited + 2))
done
echo $$ > "$LOCK/pid"
cp "$CFG" "$SNAP" 2>/dev/null
trap 'restore_cfg; release_lock' EXIT

set -m   # own process group for the cursor tree, so a kill reaches every child
( cd "$PROJECT_DIR" && exec "${CURSOR_CLI[@]}" -p "$PROMPT" --output-format stream-json \
    "${MODE_ARGS[@]}" --trust --model "$MODEL" --workspace "$PROJECT_DIR" ) </dev/null >>"$EVENTS" 2>&1 &
pid=$!
set +m
kill_run() { kill -TERM -- "-$pid" 2>/dev/null; sleep 2; kill -KILL -- "-$pid" 2>/dev/null; true; }

has_event() { grep -q -m1 "$1" "$EVENTS" 2>/dev/null; }
diagnostics() { echo "--- last events (tail -15) ---"; tail -n 15 "$EVENTS" 2>/dev/null | cut -c1-400; echo "------------------------------"; }

echo "cursor-guard: launched (task ${TASK_ID}, model ${MODEL}, cap ${MAX_SECONDS}s)"

# ---- startup gate: the init event, then hand the config back ----
elapsed=0
while [ "$elapsed" -lt "$STARTUP_TIMEOUT" ]; do
  has_event '"subtype":"init"' && break
  kill -0 "$pid" 2>/dev/null || break
  sleep 1; elapsed=$((elapsed + 1))
done
restore_cfg; release_lock
if ! has_event '"subtype":"init"'; then
  if kill -0 "$pid" 2>/dev/null; then
    kill_run; finish FAILED "cursor never started (no init event within ${STARTUP_TIMEOUT}s)." "$(diagnostics)"
  fi
  finish FAILED "cursor exited before its init event (bad model id, auth, or quota — see events)." "$(diagnostics)"
fi
echo "cursor-guard: session started ($(grep -m1 '"subtype":"init"' "$EVENTS" | python3 -c 'import sys,json;print(json.loads(sys.stdin.read()).get("model","?"))' 2>/dev/null))"

# ---- running: the `result` event is the finish line, not process exit ----
while ! has_event '"type":"result"'; do
  kill -0 "$pid" 2>/dev/null || break
  if [ "$elapsed" -ge "$MAX_SECONDS" ]; then
    kill_run; restore_cfg
    finish TIMEOUT "cursor was alive but exceeded the ${MAX_SECONDS}s cap." "$(diagnostics)"
  fi
  sleep "$POLL"; elapsed=$((elapsed + POLL))
done
sleep 1; kill -0 "$pid" 2>/dev/null && kill_run   # the CLI can linger after its result event
restore_cfg

# ---- evaluate the result event ----
verdict="$(python3 - "$EVENTS" "$RESULT" <<'PY'
import json, sys
events, out = sys.argv[1], sys.argv[2]
model, res = "?", None
for line in open(events, encoding="utf-8", errors="replace"):
    line = line.strip()
    if not line.startswith("{"):
        continue
    try:
        d = json.loads(line)
    except ValueError:
        continue
    if d.get("type") == "system" and d.get("subtype") == "init":
        model = d.get("model", "?")
    if d.get("type") == "result":
        res = d
if res is None:
    print("FAILED|no result event (model %s)" % model)
elif res.get("is_error") or res.get("subtype") != "success" or not (res.get("result") or "").strip():
    print("FAILED|error result subtype=%s is_error=%s text=%s (model %s)"
          % (res.get("subtype"), res.get("is_error"), str(res.get("result"))[:300], model))
else:
    open(out, "w", encoding="utf-8").write(res["result"])
    print("COMPLETED|model: %s" % model)
PY
)"
case "$verdict" in
  COMPLETED\|*) finish COMPLETED "result: ${RESULT}" "${verdict#COMPLETED|}";;
  *) finish FAILED "${verdict#FAILED|}" "$(diagnostics)";;
esac
