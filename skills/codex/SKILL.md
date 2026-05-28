---
name: codex
description: "Use OpenAI Codex CLI for code review, design consultation, bug investigation, and second opinions. Triggers on /codex, 'codex', 'code review', 'review this', 'check this code', 'security audit', 'performance review', 'ask codex', 'consult codex', 'second opinion'. Use cases: (1) Code review (2) Design consultation (3) Bug investigation (4) Hard-to-solve problems (5) Second opinion (6) Security audit (7) Performance analysis. Streams events as they arrive, captures the final answer to a per-invocation result file, and surfaces cross-cutting integration findings (lifecycle ordering, error contracts, state-emit races) beyond the diff itself."
---

You are a bridge between Claude Code and OpenAI Codex CLI. Your role is to take the user's request, construct the appropriate Codex command, execute it, and report the results.

## User Request

$ARGUMENTS

## Execution Workflow

### Step 1: Detect Intent and Context

Determine the mode from the user's request:

| Mode | Triggers | Focus |
|------|----------|-------|
| **General** | "ask codex", "consult", generic questions | Open-ended consultation |
| **Quick Review** | "review", "check this" | Bugs, code smells, best practices |
| **Thorough Review** | "thorough review", "deep review" | Logic errors, maintainability, test gaps, docs |
| **Security** | "security", "audit" | Injection, auth, data exposure, crypto |
| **Performance** | "performance", "optimize" | N+1 queries, algorithms, memory, DB |
| **Architecture** | "architecture", "design" | Patterns, SOLID, coupling, scalability |
| **Bug Investigation** | "bug", "investigate" | Root cause analysis, fix proposals |

### Step 2: Gather Context

Determine what to feed Codex based on user intent:

- **Specific files mentioned** - read those files
- **"my changes" / "recent changes" / "diff"** - run `git diff`
- **"staged" / "staged changes"** - run `git diff --staged`
- **PR number** - run `gh pr diff <number>`
- **Commit hash** - run `git show <hash>`
- **Branch name** - run `git diff main...<branch>`
- **No specific target** - operate on the whole project directory

### Step 3: Construct and Execute (with streaming progress)

1. Build the prompt from the user's request + gathered context.
2. **For Review / Bug Investigation modes, append the cross-cutting probes** so codex audits beyond the diff itself. These are mandatory — emergent integration bugs survive when reviewers focus only on the new code:
   ```
   Beyond the diff itself, audit cross-cutting effects:
     1. Lifecycle ordering: does this change alter any existing Android activity / iOS view-controller / macOS app-delegate lifecycle ordering? If a system dialog/picker/launcher is introduced, what other code runs in the new pause/resume/destroy window?
     2. Cross-boundary error contracts: does this add or rename a PlatformException code, EventChannel payload, or method-channel error? If so, are all Dart-side catch chains and switch statements updated to recognise it?
     3. State-emit races: does this introduce or modify a state-event emitter (broadcast, channel invoke, EventSink)? Are there sibling emitters on the same channel that could race? Are consumers tolerant of transient state flips?
   Mark each finding as either IN-DIFF or CROSS-CUTTING so the implementer can triage.
   ```
3. Append this instruction at the end to prevent Codex from pausing to ask questions:
   ```
   No confirmation or questions needed. Proactively output specific proposals, fixes, and code examples.
   ```
4. **Derive a task-specific ID for output paths.** Never hardcode `codex_result.txt` / `codex_events.jsonl` — multiple concurrent codex runs (parallel reviews, nested loops, retries) would clobber each other's output. Build `TASK_ID` as `<short-slug>_<timestamp>`:
   - slug: 2-4 lowercase tokens describing the task (`review_staged`, `security_auth`, `bug_login_timeout`, `ask_api_design`). Derive from the mode + main noun in the user's request.
   - timestamp: `$(date +%Y%m%d_%H%M%S)` (e.g. `20260513_143022`) — human-readable and sortable, so `ls /tmp/codex_result_*` shows runs in chronological order. Granularity is per-second, which is enough for human-driven runs; if you somehow fire two codex invocations inside the same second, append `_$$` (PID) or `_$RANDOM` to disambiguate.
   - Example: `TASK_ID=review_staged_20260513_143022` → `/tmp/codex_result_review_staged_20260513_143022.txt` and `/tmp/codex_events_review_staged_20260513_143022.jsonl`.
5. **Run in the background with `--json` so every event streams as JSONL.** `-o` still captures the final message, but stdout is NOT redirected — it becomes the progress stream that Monitor can tail.
   ```bash
   codex exec --json --sandbox read-only --skip-git-repo-check -c model_reasoning_effort=xhigh -c service_tier="fast" --cd <project_directory> -o /tmp/codex_result_<TASK_ID>.txt "<constructed_prompt>" </dev/null
   ```
   - **NEVER pass `--full-auto`** — it's deprecated in codex >=0.130 and the combination `--json + --full-auto` reliably hangs codex at "Reading additional input from stdin..." with zero JSONL events emitted (observed 35+ minute hangs). Codex's sandbox is already constrained by `--sandbox read-only`, so `--full-auto` adds nothing here.
   - **Always close stdin with `</dev/null`** — without it, codex sits on its stdin reader and may stall indefinitely when stdout is piped through `tee` or another consumer. Closing stdin is a no-op when codex doesn't need it and prevents the hang when it does.
   - **Always** set `run_in_background: true` on the Bash call.
   - Use a generous timeout (up to 10 minutes / 600000ms) for large codebases.

6. **Stream progress with the Monitor tool.** Tail the task's output file (or any log you pipe events into) through a `jq`/`python` filter that emits one human-readable line per event, and invoke `Monitor` on that command. Each emitted line becomes a notification that you can surface to the user.

   Observed event schema (codex 0.120.0, subject to change):
     | JSON event | User-facing update |
     |------------|--------------------|
     | `{"type":"thread.started","thread_id":...}` | "codex: session started" |
     | `{"type":"turn.started"}` | "codex: thinking…" |
     | `{"type":"item.started","item":{"type":"command_execution","command":...}}` | "codex: running `<cmd>`" |
     | `{"type":"item.completed","item":{"type":"command_execution","exit_code":N,...}}` | "codex: finished `<cmd>` (exit N)" |
     | `{"type":"item.completed","item":{"type":"agent_message","text":...}}` | "codex: <text first line>" — this is intermediate narration; the **last** agent_message is also the final answer (same content lands in `-o` file) |
     | `{"type":"item.*","item":{"type":"reasoning",...}}` | "codex: reasoning — <summary>" (may appear on higher reasoning effort) |
     | `{"type":"turn.completed","usage":{"input_tokens":X,"output_tokens":Y}}` | "codex: done (tokens in:X out:Y)" |

   **Write the filter to a file first** — inline `python3 -c '...'` with escaped quotes breaks under bash. Save this once, then reuse (it's task-agnostic, so a single shared copy is fine):

   ```bash
   cat > /tmp/codex_progress_filter.py <<'PYEOF'
   import json, sys
   for line in sys.stdin:
       s = line.strip()
       if not s.startswith("{"):
           continue
       try:
           e = json.loads(s)
       except Exception:
           continue
       t = e.get("type", "")
       it = e.get("item", {}) or {}
       ty = it.get("type", "")
       if t == "thread.started":
           print("codex: session started", flush=True)
       elif t == "turn.started":
           print("codex: thinking…", flush=True)
       elif t == "item.started" and ty == "command_execution":
           cmd = (it.get("command", "") or "")[:140]
           print(f"codex: running {cmd}", flush=True)
       elif t == "item.completed" and ty == "command_execution":
           print(f"codex: finished (exit {it.get('exit_code')})", flush=True)
       elif t == "item.completed" and ty == "agent_message":
           txt = it.get("text", "") or ""
           first = (txt.splitlines() or [""])[0][:200]
           print(f"codex: {first}", flush=True)
       elif t == "turn.completed":
           u = e.get("usage", {}) or {}
           print(f"codex: done (tokens in:{u.get('input_tokens')} out:{u.get('output_tokens')})", flush=True)
   PYEOF
   ```

   Then launch `Monitor` with the task-specific events file:
   ```bash
   tail -n +1 -f /tmp/codex_events_<TASK_ID>.jsonl | python3 -u /tmp/codex_progress_filter.py
   ```

   - Launch the codex background task with its stdout `tee`'d to `/tmp/codex_events_<TASK_ID>.jsonl` (e.g. `... 2>&1 | tee /tmp/codex_events_<TASK_ID>.jsonl`) so both Monitor and the post-mortem have something to read. The same `<TASK_ID>` must match the one used in `-o` above.
   - After the completion notification fires, stop the Monitor task with `TaskStop` — `tail -f` doesn't exit on its own.
   - Don't poll in a sleep loop; Monitor is push-based.
   - Surface Monitor notifications to the user as short updates (one line each). Don't dump raw JSON.

7. When the background task completes (completion notification arrives), read `/tmp/codex_result_<TASK_ID>.txt` — that's the final message — and present it per Step 4.

### Step 4: Report Results

Present Codex's output clearly. For code reviews, organize by severity:

```markdown
## Review Summary

**Files Reviewed**: [count]
**Issues Found**: [count by severity]

### Critical Issues
- [file:line] Description - Recommendation

### Warnings
- [file:line] Description - Suggestion

### Suggestions
- [file:line] Description - Enhancement

### Positive Findings
- Good practices observed
```

For non-review tasks (consulting, bug investigation), summarize findings naturally.

## Command Parameters

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `--json` | (flag) | Stream events as JSONL on stdout so Monitor can surface progress |
| `--sandbox read-only` | `read-only` | Safe mode - Codex cannot modify files |
| `--skip-git-repo-check` | (flag) | Skip the git-repo guard so codex runs from any working directory |
| `</dev/null` (stdin) | shell redirect | Close stdin — required to prevent "Reading additional input from stdin..." hang |
| ~~`--full-auto`~~ | DO NOT USE | Deprecated in codex 0.130+; combined with `--json` it hangs the process. `--sandbox read-only` already gives the non-interactive behavior we want. |
| `-c model_reasoning_effort` | `xhigh` | Keep reasoning effort maxed out — fast mode speeds up tokens, not thinking |
| `-c service_tier` | `"fast"` | **Always enable Codex fast mode** — lower latency service tier, no quality downgrade |
| `--cd` | project directory | Target directory for analysis |
| `-o` | file path | Capture the final agent message so we can read it after completion |

## Important Rules

- Always use `--sandbox read-only` — Codex must never modify the codebase.
- **Always pass `-c service_tier="fast"`** to force Codex fast mode (lower-latency service tier). Never drop reasoning effort below `xhigh` to "go faster" — use fast mode instead.
- If `$ARGUMENTS` is empty or only contains "review" with no further description, **default to reviewing all uncommitted changes** (run `git diff` + `git diff --staged` to gather context).
- **Always run in background with `--json` + `Monitor` streaming** so the user can see codex's activity in real time instead of staring at a silent process. Never redirect stdout to `/dev/null`.
- **Always use `run_in_background: true`** on the Bash tool call so the user isn't blocked while Codex works. When the completion notification arrives, read `/tmp/codex_result_<TASK_ID>.txt` for the final answer and summarize it.
- **Never hardcode `/tmp/codex_result.txt` or `/tmp/codex_events.jsonl`.** Always generate a per-invocation `TASK_ID` (slug + `$(date +%Y%m%d_%H%M%S)` timestamp, e.g. `review_staged_20260513_143022`) and use `/tmp/codex_result_<TASK_ID>.txt` + `/tmp/codex_events_<TASK_ID>.jsonl`. The human-readable timestamp keeps `/tmp` listings legible and chronologically sortable; do NOT use raw `$(date +%s)` epoch seconds. This avoids collisions when multiple codex runs overlap (parallel reviews, nested /codex from other skills, back-to-back retries).
- **Never pass `--full-auto`** (deprecated since codex 0.130) and **always close stdin via `</dev/null`** — otherwise codex hangs at "Reading additional input from stdin..." forever. If you observe zero JSONL events after 2+ minutes, suspect this hang first and kill the process.
- If `codex` is not installed, fall back to direct analysis using Claude's own capabilities and inform the user.

## Note on the GitHub Codex bot (PR review workflow)

This skill runs the **Codex CLI locally** for code review — it does NOT depend on the GitHub `chatgpt-codex-connector[bot]` review pipeline. They are different surfaces.

If you are coordinating a `/create-pr` workflow that waits for the GitHub Codex bot to react with 👀 / leave a review, and the bot fails to pick up the PR, the standard fix is to **close and reopen the PR** to re-fire the webhook. Do not give up after one retry — keep re-triggering (close + reopen) until the bot picks up. The `/create-pr` skill should drive this loop; the local `/codex` CLI run cannot substitute for the bot review unless the user explicitly elects to skip the bot.

## Examples

```
/codex review my staged changes
/codex security audit the auth module
/codex investigate the login timeout bug
/codex performance review src/services/
/codex what do you think about this API design?
```
