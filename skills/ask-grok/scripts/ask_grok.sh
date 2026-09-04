#!/usr/bin/env bash
# ask_grok.sh — query Grok via the official Grok CLI (subscription OAuth), robustly.
#
# Why this wrapper exists: the bare `grok -p` call has two sharp edges that bite
# every caller. (1) Web/X search is a *tool*, and headless mode cancels tool
# calls unless --always-approve is passed — without it you get empty output and
# stopReason "Cancelled". (2) The CLI occasionally emits a transient
# `Auth(AuthorizationRequired)` worker error (and a stray missing-MCP 'dart'
# line) on stderr and returns nothing; a single retry clears it. This script
# bakes in both fixes so callers don't have to remember them.
#
# Usage:   ask_grok.sh "your prompt"  [model]
#   model  optional; defaults to the CLI's default (grok-4.3 family).
#          Override via arg 2 or the GROK_MODEL env var.
#
# Output format: defaults to structured JSON (the CLI's `--output-format json`),
#   so callers get the answer plus metadata (`.text`, `.stopReason`,
#   `.sessionId`, `.thought`) in one parseable object. Override with the
#   GROK_FORMAT env var — `plain` for the bare answer text, or `streaming-json`
#   for the incremental event stream.
#
# Defaults: a standing instruction is appended to the prompt telling Grok to
#   search the web/X for anything time-sensitive and cite sources with URLs —
#   this is what you almost always want from a live-knowledge query, so it's the
#   default rather than something every caller must remember. Disable it (send
#   the prompt exactly as given) with GROK_RAW=1.
#
# Timeout: each attempt is capped at GROK_TIMEOUT seconds (default 600). A killed
#   attempt is NEVER emitted — Grok writes its narration first and the answer last,
#   so a truncated run yields prose that parses as "no result" instead of failing.
#   That silent-wrong-answer mode is why the cap is enforced loudly, not softly.
#
# Output:  Grok's answer on stdout, exit 0 — a JSON object by default, or the
#          format set via GROK_FORMAT. On failure: exit 1 and a diagnostic
#          (stdout+stderr of a final attempt) on stderr so the caller can see why.
set -u

PROMPT="${1:?usage: ask_grok.sh \"prompt\" [model]}"
MODEL="${2:-${GROK_MODEL:-}}"
OUTPUT_FORMAT="${GROK_FORMAT:-json}"
# Seconds before an attempt is killed. A live web/X query on a high-effort model
# routinely runs 5+ minutes (a 16-site harvest measured ~300s on 2026-08-19), so
# the old 180s ceiling truncated real answers. Raise for heavier sweeps.
GROK_TIMEOUT="${GROK_TIMEOUT:-600}"

# Append the standing search+cite default unless the caller opted out.
if [ -z "${GROK_RAW:-}" ]; then
  PROMPT="${PROMPT}

(If answering this accurately depends on current or recent information, search the web and X first, and cite your sources with URLs. Be concise and don't pad.)"
fi

GROK_BIN="${GROK_BIN:-$HOME/.grok/bin/grok}"
[ -x "$GROK_BIN" ] || GROK_BIN="$(command -v grok 2>/dev/null || true)"
[ -x "$GROK_BIN" ] || { echo "ERROR: grok CLI not found (expected ~/.grok/bin/grok or on PATH)." >&2; exit 127; }

JQ_BIN="$(command -v jq 2>/dev/null || true)"

# --always-approve is REQUIRED so web/X search executes instead of being cancelled.
# --output-format selects plain text vs. structured JSON (default).
args=(--always-approve --output-format "$OUTPUT_FORMAT" -p "$PROMPT")
[ -n "$MODEL" ] && args=(-m "$MODEL" "${args[@]}")

# has_answer: did this attempt produce a usable answer (vs. an empty/Cancelled run)?
# For json we inspect `.text` so a valid-but-empty Cancelled object still retries;
# for other formats we fall back to "is there any non-whitespace output".
has_answer() {
  if [ "$OUTPUT_FORMAT" = json ] && [ -n "$JQ_BIN" ]; then
    local text
    text="$(printf '%s' "$1" | "$JQ_BIN" -re '.text // empty' 2>/dev/null)" || return 1
    [ -n "${text//[[:space:]]/}" ]
  else
    [ -n "${1//[[:space:]]/}" ]
  fi
}

killed=0
for attempt in 1 2; do
  out="$(timeout "$GROK_TIMEOUT" "$GROK_BIN" "${args[@]}" 2>/dev/null)"
  rc=$?
  # rc 124 = the timeout killed it mid-run. Whatever landed in $out is a
  # TRUNCATED PREFIX: Grok narrates ("I'll search X and the web...") and emits the
  # real answer LAST, so a killed run leaves narration that looks like output but
  # contains none of it. has_answer() cannot tell the two apart, and a caller that
  # parses the prefix silently gets a plausible, wrong, empty result. Discard it
  # and say so rather than passing truncation off as an answer.
  if [ "$rc" -eq 124 ]; then
    killed=1
    echo "ask_grok: attempt $attempt exceeded ${GROK_TIMEOUT}s and was killed; truncated output discarded." >&2
    continue
  fi
  killed=0
  if has_answer "$out"; then
    printf '%s\n' "$out"
    exit 0
  fi
done

# Timed out: the cause is already known, so don't burn another full window on a
# diagnostic re-run — just say what to raise.
if [ "$killed" -eq 1 ]; then
  echo "ERROR: Grok exceeded ${GROK_TIMEOUT}s on every attempt and produced no complete answer." >&2
  echo "       Raise the ceiling (e.g. GROK_TIMEOUT=1200 ask_grok.sh ...) and retry." >&2
  exit 1
fi

# Empty (not truncated): re-run once surfacing everything so the caller can diagnose
# (expired token → run `grok login`; network; tier gate, etc.).
echo "ERROR: Grok returned no output after 2 attempts. Diagnostic run follows:" >&2
timeout "$GROK_TIMEOUT" "$GROK_BIN" "${args[@]}" 1>&2
exit 1
