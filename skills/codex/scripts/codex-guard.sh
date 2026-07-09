#!/usr/bin/env bash
# codex-guard.sh — deterministic supervisor for headless `codex exec` runs.
#
# Replaces the LLM watchdog sub-agent: launches codex with stdin closed,
# swallows the JSONL event stream into a file (NEVER onto the caller's
# context), applies a two-phase hang watchdog, retries once on startup
# hangs, and reports a single STATUS line.
#
# Usage:
#   codex-guard.sh <TASK_ID> <MAX_SECONDS> -- codex exec --json ... -o /tmp/codex_result_<TASK_ID>.txt "<prompt>"
#
# Convention (must match the -o flag in the wrapped command):
#   result: /tmp/codex_result_<TASK_ID>.txt
#   events: /tmp/codex_events_<TASK_ID>.jsonl
#   status: /tmp/codex_status_<TASK_ID>.txt
#
# Two-phase watchdog:
#   Phase 1 (startup gate): all known codex hangs (stdin left open,
#     --full-auto+--json, backgrounded-pipe stdin stall) wedge BEFORE the
#     session starts — zero events emitted. If no JSONL line appears within
#     STARTUP_TIMEOUT, kill and retry once. Near-zero false-positive risk:
#     a healthy run emits thread.started within seconds.
#   Phase 2 (running): once the first event arrives, silence is NORMAL
#     (long xhigh reasoning turns block on the model API with no output and
#     near-zero CPU — indistinguishable from a hang by silence alone). Only
#     a hard wall-clock cap applies; hitting it reports STATUS: TIMEOUT
#     (codex was alive but too slow) as distinct from FAILED (wedged/crashed)
#     so the caller can decide with evidence.
#     EXCEPTION — collab sub-agent wedge (observed 2026-07-09): codex at
#     xhigh can spawn "collab" verifier sub-agents; when one dies silently,
#     codex hangs forever on the close_agent collab call. Signature is
#     precise and unlike a reasoning turn: events file mtime frozen for
#     STALL_TIMEOUT seconds AND the last JSONL event is an item.started
#     collab_tool_call. On match: kill and report STATUS: STALLED — the
#     caller should re-run with a "no collab/verifier sub-agents,
#     single-threaded" instruction in the prompt.
#
# STATUS values:
#   COMPLETED  attempt 1 finished, result file non-empty
#   RECOVERED  attempt 2 finished after a startup-hang kill+retry
#   TIMEOUT    session started but exceeded MAX_SECONDS (diagnostics attached)
#   STALLED    wedged mid-run on a collab sub-agent tool call (diagnostics
#              attached) — re-run with a no-collab-sub-agents prompt
#   FAILED     never started (2x) or crashed without a result (diagnostics attached)
#
# Env overrides (mainly for tests):
#   CODEX_GUARD_STARTUP   startup gate seconds   (default 120)
#   CODEX_GUARD_POLL      poll interval seconds  (default 10)
#   CODEX_GUARD_HEARTBEAT heartbeat seconds      (default 600)
#   CODEX_GUARD_STALL     mid-run collab-wedge gate seconds (default 480)

set -u

TASK_ID="${1:?usage: codex-guard.sh TASK_ID MAX_SECONDS -- <codex command...>}"
MAX_SECONDS="${2:?missing MAX_SECONDS}"
[ "${3:-}" = "--" ] || { echo "codex-guard: expected '--' before command" >&2; exit 2; }
shift 3

RESULT="/tmp/codex_result_${TASK_ID}.txt"
EVENTS="/tmp/codex_events_${TASK_ID}.jsonl"
STATUS_FILE="/tmp/codex_status_${TASK_ID}.txt"

STARTUP_TIMEOUT="${CODEX_GUARD_STARTUP:-120}"
POLL="${CODEX_GUARD_POLL:-10}"
HEARTBEAT="${CODEX_GUARD_HEARTBEAT:-600}"
STALL_TIMEOUT="${CODEX_GUARD_STALL:-480}"

finish() { # $1=STATUS, rest=extra lines
  local st="$1"; shift
  { echo "STATUS: ${st}"; [ $# -gt 0 ] && printf '%s\n' "$@"; } > "$STATUS_FILE"
  [ $# -gt 0 ] && printf '%s\n' "$@"
  echo "STATUS: ${st}"
  case "$st" in COMPLETED|RECOVERED) exit 0;; TIMEOUT) exit 3;; STALLED) exit 4;; *) exit 1;; esac
}

diagnostics() { # $1=pid (may be gone)
  echo "--- diagnostics ---"
  ps -p "$1" -o stat,etime,cputime 2>/dev/null || echo "process ${1} already gone"
  echo "--- last events (tail -20) ---"
  tail -n 20 "$EVENTS" 2>/dev/null || echo "(no events file)"
  echo "-------------------"
}

kill_run() { # $1=pid — kill only THIS run's tree, scoped by TASK_ID in argv
  kill "$1" 2>/dev/null
  sleep 2
  kill -9 "$1" 2>/dev/null
  pkill -9 -f "codex_result_${TASK_ID}" 2>/dev/null
  pkill -9 -f "codex_events_${TASK_ID}" 2>/dev/null
  true
}

session_started() { grep -q -m1 '^{' "$EVENTS" 2>/dev/null; }

events_mtime() { stat -f %m "$EVENTS" 2>/dev/null || stat -c %Y "$EVENTS" 2>/dev/null || echo 0; }

# True iff the last JSONL event is a still-open collab tool call — the exact
# wedge signature. A normal long reasoning turn never leaves this as the tail.
last_event_pending_collab() {
  local last_ev
  last_ev="$(grep '^{' "$EVENTS" 2>/dev/null | tail -n 1)"
  case "$last_ev" in
    *'"item.started"'*'"collab_tool_call"'*|*'"collab_tool_call"'*'"item.started"'*) return 0 ;;
    *) return 1 ;;
  esac
}

for attempt in 1 2; do
  echo "codex-guard: attempt ${attempt} launching (task ${TASK_ID}, cap ${MAX_SECONDS}s)"
  echo "# guard attempt ${attempt} $(date '+%Y-%m-%dT%H:%M:%S')" >> "$EVENTS"
  "$@" </dev/null >>"$EVENTS" 2>&1 &
  pid=$!

  # ---- Phase 1: startup gate ----
  started=0 elapsed=0
  while [ "$elapsed" -lt "$STARTUP_TIMEOUT" ]; do
    if session_started; then started=1; break; fi
    kill -0 "$pid" 2>/dev/null || break   # exited before/without events
    sleep "$POLL"; elapsed=$((elapsed + POLL))
  done

  if [ "$started" -eq 0 ] && kill -0 "$pid" 2>/dev/null; then
    echo "codex-guard: no events after ${STARTUP_TIMEOUT}s — startup hang, killing attempt ${attempt}"
    diag="$(diagnostics "$pid")"
    kill_run "$pid"
    if [ "$attempt" -eq 2 ]; then
      finish FAILED "codex hung at startup twice (no JSONL events within ${STARTUP_TIMEOUT}s each try)." "$diag"
    fi
    continue  # retry once
  fi

  [ "$started" -eq 1 ] && echo "codex-guard: session started"

  # ---- Phase 2: running — silence allowed, hard cap + collab-wedge gate ----
  hb=0 stall_s=0 last_mt="$(events_mtime)"
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$elapsed" -ge "$MAX_SECONDS" ]; then
      echo "codex-guard: wall-clock cap ${MAX_SECONDS}s reached"
      diag="$(diagnostics "$pid")"
      kill_run "$pid"
      finish TIMEOUT "codex was alive but exceeded the ${MAX_SECONDS}s cap — not a wedge; consider re-running with a higher cap." "$diag"
    fi
    sleep "$POLL"; elapsed=$((elapsed + POLL)); hb=$((hb + POLL))
    mt="$(events_mtime)"
    if [ "$mt" = "$last_mt" ]; then
      stall_s=$((stall_s + POLL))
    else
      last_mt="$mt"; stall_s=0
    fi
    if [ "$stall_s" -ge "$STALL_TIMEOUT" ]; then
      if last_event_pending_collab; then
        echo "codex-guard: events frozen ${stall_s}s on a pending collab_tool_call — collab sub-agent wedge, killing"
        diag="$(diagnostics "$pid")"
        kill_run "$pid"
        finish STALLED "codex wedged mid-run on a collab sub-agent tool call (events frozen ${stall_s}s). Re-run with an explicit 'work single-threaded; do NOT spawn collaborator/verifier sub-agents or use collab tools' instruction in the prompt." "$diag"
      fi
      stall_s=0  # frozen but not the collab signature: treat as a long reasoning turn
    fi
    if [ "$hb" -ge "$HEARTBEAT" ]; then
      hb=0
      evcount=$(grep -c '^{' "$EVENTS" 2>/dev/null)
      echo "codex-guard: still running (${elapsed}s elapsed, ${evcount:-0} events)"
    fi
  done
  wait "$pid" 2>/dev/null; rc=$?

  # ---- Post-exit evaluation ----
  if [ -s "$RESULT" ]; then
    [ "$attempt" -eq 1 ] && finish COMPLETED "result: ${RESULT}"
    finish RECOVERED "result: ${RESULT} (after 1 startup-hang retry)"
  fi
  echo "codex-guard: attempt ${attempt} exited rc=${rc} with empty/missing result"
  if [ "$attempt" -eq 2 ] || [ "$started" -eq 1 ]; then
    # started-then-crashed: retrying rarely helps and burns the cap — report.
    finish FAILED "codex exited rc=${rc} without writing ${RESULT}." "$(diagnostics "$pid")"
  fi
  # not started + quick crash → one retry
done

finish FAILED "unreachable"
