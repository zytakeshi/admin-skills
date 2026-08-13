---
name: codex
description: "Use OpenAI Codex CLI for code review, design consultation, bug investigation, and second opinions. Triggers on /codex, 'codex', 'code review', 'review this', 'check this code', 'security audit', 'performance review', 'ask codex', 'consult codex', 'second opinion'. Use cases: (1) Code review (2) Design consultation (3) Bug investigation (4) Hard-to-solve problems (5) Second opinion (6) Security audit (7) Performance analysis (8) Delegated implementation — when asked to have codex implement/fix/apply a change, run it in implementer mode (--sandbox workspace-write), not read-only. Streams events as they arrive, captures the final answer to a per-invocation result file, and surfaces cross-cutting integration findings (lifecycle ordering, error contracts, state-emit races) beyond the diff itself."
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
| **Implementer** | "implement", "fix it", "make the change", "apply the fix", "write the code", or the calling session explicitly delegates implementation to codex | Codex writes/edits code in the project |

**Sandbox follows the mode.** Review/consult/investigation modes run `--sandbox read-only` (codex must not touch the codebase). **Implementer mode runs `--sandbox workspace-write`** — when the user or calling session has asked codex to implement, do NOT run it read-only and do NOT let it "report what it would change" instead of changing it. Everything else in this skill (guard script, TASK_ID, `--json`, stdin closing, hang recovery) is identical in both modes; only the `--sandbox` value changes. Implementer-mode extras:
- Add to the prompt: scope (which files/dirs it may touch), "make the changes directly — do not just describe them", and guardrails: no `git commit`/`push`, no `rm`, no touching files outside the stated scope, no prod credentials/deploys.
- `workspace-write` confines writes to the `--cd` project directory — that is the safety envelope replacing read-only. Never use `danger-full-access` here (that's `/codex-test`'s browser-driving exception).
- After completion, run `git status`/`git diff` and review the diff yourself before reporting it done. Codex's edits are unverified output until you've read them.
- ⛔ Mission-critical work (prod deploys, billing, certs, DNS, fleet state) never goes to codex implementer mode — per global model routing, that stays with Opus/you.

### Step 2: Gather Context

Determine what to feed Codex based on user intent:

- **Specific files mentioned** - read those files
- **"my changes" / "recent changes" / "diff"** - run `git diff`
- **"staged" / "staged changes"** - run `git diff --staged`
- **PR number** - run `gh pr diff <number>`
- **Commit hash** - run `git show <hash>`
- **Branch name** - run `git diff main...<branch>`
- **No specific target** - operate on the whole project directory

### Step 2.5: Run via `codex-guard.sh` — deterministic supervisor, no watchdog agent (default)

Babysitting a codex run is pure rules (launch, watch, kill-on-startup-hang, retry once, report), so it is done by a **script**, not an LLM. `scripts/codex-guard.sh` (next to this skill) supervises the whole run and guarantees the caller's context stays clean: codex's JSONL event stream is swallowed into `/tmp/codex_events_<TASK_ID>.jsonl` and **never** printed; the guard's own stdout is only a handful of milestone lines plus one final `STATUS:` line.

After constructing the codex command in Step 3 (points 1–4: prompt, probes, `TASK_ID`), launch it wrapped in the guard, with `run_in_background: true`:

```bash
bash ~/.claude/skills/codex/scripts/codex-guard.sh <TASK_ID> 1800 -- \
  codex exec --json --sandbox <read-only|workspace-write> --skip-git-repo-check \
  -c service_tier=priority \
  --cd <project_directory> -o /tmp/codex_result_<TASK_ID>.txt "<constructed_prompt>"
```

- `-c service_tier=priority` is **Fast mode** (codex's model catalog advertises this tier as `{id: "priority", name: "Fast"}` — ~1.5× speed at increased usage). Always pass it; headless runs are latency-bound and the caller is blocked on the result. It does **not** change reasoning effort — never pass `-c model_reasoning_effort` to "go faster".
- `1800` is the hard wall-clock cap in seconds (30 min). Raise it per-run for very large audits. The guard closes stdin itself — you don't need `</dev/null` here.
- **Do NOT start a Monitor, poll, or sleep-loop.** The background task notifies you exactly once, when the guard exits — no per-event notifications spam the session. (Only if the user explicitly asks for live progress, run the Step 6 Monitor tail on the events file — the filter emits one short line per event.)
- The `-o` path **must** use the same `<TASK_ID>` as the guard's first argument — that convention is how the guard finds the result/events files and how its scoped kill works.

**Two-phase hang logic (inside the script — you don't implement this):** all known codex hangs (stdin, `--full-auto`+`--json`) wedge *before* the session starts, emitting zero events — so the guard kills and retries once only if **no** JSONL appears within 120s of launch. Once the first event arrives, silence is treated as normal (long xhigh reasoning turns are quiet for minutes); only the hard cap applies after that.

When the completion notification arrives, read the guard's output / `/tmp/codex_status_<TASK_ID>.txt` and act on the STATUS line:

| STATUS | Meaning | Your move |
|--------|---------|-----------|
| `COMPLETED` / `RECOVERED` | Result is in `/tmp/codex_result_<TASK_ID>.txt` | Read it, run Step 4 / triage |
| `TIMEOUT` | codex was **alive but slow** — exceeded the cap (diagnostics attached) | Judgment call: re-run with a higher cap, narrow the scope, or fall back to native review |
| `STALLED` | Wedged **mid-run** on a collab sub-agent tool call — events frozen with a pending `collab_tool_call` (diagnostics attached) | Re-run once with the same prompt — the mandatory no-collab preamble (Step 3 point 3) normally prevents this; make sure it's present. If it stalls again, fall back per `FAILED`. |
| `FAILED` | Hung at startup twice, or crashed without a result (diagnostics attached) | **The fallback review is YOURS:** do it yourself or spawn a fresh **Opus** reviewer over the same diff (never Haiku/Sonnet — review is judgment work). Tell the user codex was unavailable and they can run `! codex …` interactively. |

**If the guard script is missing** (skill checked out without `scripts/`, or a remote context), fall back to running Steps 3–7 inline yourself, applying the Hang-recovery section manually.

> Steps 3–7 below are the manual/inline path. With the guard, you still do Step 3 points 1–4 (construct the command) and Step 4 (report); the guard replaces points 5–7's launch-and-babysit.

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
3. Append this block at the end — it prevents Codex from pausing to ask questions, prevents the collab sub-agent wedge (headless codex at xhigh spawns "collab" verifier sub-agents that can die silently and wedge the whole run on `close_agent` — observed 2026-07-09; the verifier lane has never returned useful output headlessly), and carries the three failure-semantics invariants. **The invariants ride here on purpose:** a codex worktree may not discover the repo's instruction file at all, so any rule that only lives in `AGENTS.md`/`CLAUDE.md` can be undeliverable (observed 2026-07-31: a repo had a `CLAUDE.md` but no `AGENTS.md`, and a local policy rejection shipped as an authoritative server-verdict error code that reached end users). The preamble is the one path that always reaches the implementer:
   ```
   Work single-threaded: do NOT spawn any collaborator/verifier sub-agents or use collab tools — do the entire task yourself directly. No confirmation or questions needed. Proactively output specific proposals, fixes, and code examples.

   Invariants — apply to any code you write, and flag violations in any code you review:
     1. A new producer inherits the value's existing meaning. Before routing a failure into an existing error code / enum value / reason, read what its current consumers already do with it.
     2. A local check never speaks for a remote authority. Local validation / policy / config / parse failures get their own distinct code; only the server, OS, or device may render a verdict about its own state.
     3. An unnamed failure meaning is an unassigned decision. If the spec adds a check but does not say what its failure means to the user, do not pick silently — give it a distinct code and say so in your report.
   ```
4. **Derive a task-specific ID for output paths.** Never hardcode `codex_result.txt` / `codex_events.jsonl` — multiple concurrent codex runs (parallel reviews, nested loops, retries) would clobber each other's output. Build `TASK_ID` as `<short-slug>_<timestamp>`:
   - slug: 2-4 lowercase tokens describing the task (`review_staged`, `security_auth`, `bug_login_timeout`, `ask_api_design`). Derive from the mode + main noun in the user's request.
   - timestamp: `$(date +%Y%m%d_%H%M%S)` (e.g. `20260513_143022`) — human-readable and sortable, so `ls /tmp/codex_result_*` shows runs in chronological order. Granularity is per-second, which is enough for human-driven runs; if you somehow fire two codex invocations inside the same second, append `_$$` (PID) or `_$RANDOM` to disambiguate.
   - Example: `TASK_ID=review_staged_20260513_143022` → `/tmp/codex_result_review_staged_20260513_143022.txt` and `/tmp/codex_events_review_staged_20260513_143022.jsonl`.
5. **Run in the background with `--json` so every event streams as JSONL.** `-o` still captures the final message, but stdout is NOT redirected — it becomes the progress stream that Monitor can tail.
   ```bash
   codex exec --json --sandbox <read-only|workspace-write> --skip-git-repo-check -c service_tier=priority --cd <project_directory> -o /tmp/codex_result_<TASK_ID>.txt "<constructed_prompt>" </dev/null
   ```
   - **Always pass `-c service_tier=priority`** (Fast mode) — same as the guarded path above.
   - **NEVER pass `--full-auto`** — it's deprecated in codex >=0.130 and the combination `--json + --full-auto` reliably hangs codex at "Reading additional input from stdin..." with zero JSONL events emitted (observed 35+ minute hangs). The `--sandbox` flag already constrains codex, so `--full-auto` adds nothing here.
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

**Always end the report with the session handle**, so a follow-up can reach this exact Codex session:

```
Codex session: <TASK_ID>  (thread <first 8 chars of thread_id>)
```

Get the thread id from the events file: `grep -o '"thread_id":"[^"]*"' /tmp/codex_events_<TASK_ID>.jsonl | head -1 | cut -d'"' -f4`.

**Hand off to `/codex-reply` — do this automatically, without being asked** — when the user's next message *discusses this answer* rather than requesting new work:

| User's next message | Route to |
|---|---|
| "why did codex flag X?", "codex is wrong about Y", "that's intentional", "ask it what it meant" | **`/codex-reply`** — resumes THIS session, so codex answers with its own finding in context |
| "review again", "re-review after my fix", "check the new code" | **`/codex` (fresh)** — a resumed session defends its old findings and still holds the OLD file contents |

⛔ The moment the code changes, the session is stale: route to fresh `/codex`, never `/codex-reply`.

## Hang detection & auto-recovery (inline mode only — `codex-guard.sh` does all of this for you)

`codex exec` can wedge with **zero output** and near-zero CPU, indefinitely. In the default path this whole section is implemented deterministically by `scripts/codex-guard.sh`; apply it manually only when running inline without the guard. Treat a hung codex as an expected failure mode and recover the moment you detect it — never sit waiting for a completion notification that will never arrive.

**Root causes, in order of likelihood:**
1. **stdin left open** — codex stalls at "Reading additional input from stdin..." forever. The fix is `</dev/null`. This is the #1 cause, and it happens almost every time someone shells out to `codex exec` manually instead of using this skill (which closes stdin for you). If you pipe stdout through `| tee` without `</dev/null`, codex stalls on its stdin reader.
2. **`--full-auto` + `--json`** — deprecated combo that reliably hangs. Never pass `--full-auto`.
3. **Bash-tool auto-backgrounding** a long foreground run (e.g. `timeout: 600000`) whose stdin is a pipe — same stdin stall, now invisible because it's backgrounded.
4. **Collab sub-agent wedge (MID-RUN — the only known post-startup wedge).** Headless codex at xhigh spawns "collab" verifier sub-agents; when one dies silently, codex hangs forever on the `close_agent` collab tool call (observed 2026-07-09: events file frozen 19+ min right after `item.started` of a `collab_tool_call`, zero CPU). Prevented by the mandatory no-collab prompt preamble (Step 3 point 3); detected by the guard's STALL gate (`STATUS: STALLED`).

**Detection signal — two-phase (silence alone is NOT a hang signal mid-run):**
- **Startup gate:** root causes 1–3 wedge codex *before* the session starts — a hung run emits **zero** JSONL events, not even `thread.started` (a healthy run emits it within seconds). No events within **~2 minutes of launch** → it's hung; kill and retry.
- **After the first event:** silence is normal — a long xhigh reasoning turn blocks on the model API with no output and near-zero CPU, the *same* signature as a hang, so do NOT kill on silence or `cputime`-stuck alone. The one exception is the precise collab-wedge signature (root cause 4): events file mtime frozen for ~8+ min AND the last JSONL event is an `item.started` `collab_tool_call` — that IS a wedge; kill and re-run with the no-collab preamble. Anything else frozen is just slow: only the generous hard wall-clock cap (default 30 min) applies; hitting it means "alive but slow" (TIMEOUT), a judgment call — not a wedge.

**Auto-recovery procedure (run it yourself, immediately, without asking):**
1. **Kill only THIS run's tree** — never a blunt fleet-wide kill, because parallel codex runs and other watchdogs may be live (this skill's own delegation spawns one runner per review, so concurrency is the norm). The `TASK_ID` is in codex's argv and the `tee` target, so scope by it:
   ```bash
   pkill -9 -f "codex_result_${TASK_ID}" 2>/dev/null; pkill -9 -f "codex_events_${TASK_ID}" 2>/dev/null
   ```
   Prefer `TaskStop` on the background Bash task by its task id, and `TaskStop` any Monitor task so it stops firing. Only fall back to the blunt `pkill -9 -f "codex exec"` if no `TASK_ID`-scoped process can be identified **and** you've confirmed no other codex run is in flight.
2. **Retry once, correctly** — via this skill's canonical invocation: background, `--json`, the mode's `--sandbox` value, `--skip-git-repo-check`, `-c service_tier=priority`, `-o /tmp/codex_result_<TASK_ID>.txt`, and **`</dev/null`**. In practice just adding `</dev/null` fixes it. Do NOT shell out with a bare `codex exec … | tee` and no stdin redirect — that is what hung.
3. **If it hangs a second time, stop fighting codex** (the guard reports this as `STATUS: FAILED`). Fall back to a Claude-native review — yourself or a fresh **Opus** reviewer over the same diff (review is judgment work; never Haiku/Sonnet) — so the user still gets a thorough review, and tell them codex was unavailable and that they can run it themselves interactively via `! codex …` (interactive codex doesn't hit the headless stdin hang).

The cardinal rule: a hung codex must never silently block the task. Detect → kill → retry-with-`</dev/null` → fall back. Prefer invoking codex through **this skill** (or the `Skill` tool) rather than hand-rolling `codex exec`, precisely so stdin is closed and the recovery path is consistent.

## Command Parameters

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `--json` | (flag) | Stream events as JSONL on stdout so Monitor can surface progress |
| `--sandbox` | `read-only` (review/consult/investigate) or `workspace-write` (implementer mode) | Read-only for reviews — Codex cannot modify files. `workspace-write` when codex is invoked as implementer — writes confined to the `--cd` project dir. Never `danger-full-access` here. |
| `--skip-git-repo-check` | (flag) | Skip the git-repo guard so codex runs from any working directory |
| `</dev/null` (stdin) | shell redirect | Close stdin — required to prevent "Reading additional input from stdin..." hang |
| ~~`--full-auto`~~ | DO NOT USE | Deprecated in codex 0.130+; combined with `--json` it hangs the process. The `--sandbox` flag already gives the non-interactive behavior we want. |
| `-c service_tier` | `priority` (always) | **Fast mode** — the catalog tier `{id: "priority", name: "Fast"}`, ~1.5× speed at increased usage. Pass it on every run; it overrides the `service_tier` in `~/.codex/config.toml` for this invocation only, leaving interactive codex untouched. `-c service_tier=fast` is a legacy alias — use `priority`. |
| ~~`-c model_reasoning_effort`~~ | DO NOT PASS | Don't override reasoning effort — let codex use the `model_reasoning_effort` from `~/.codex/config.toml`. Speed comes from `service_tier=priority`, never from dropping reasoning effort. Change the config file if you want a different default. |
| `--cd` | project directory | Target directory for analysis |
| `-o` | file path | Capture the final agent message so we can read it after completion |

## Important Rules

- **Sandbox follows the mode:** `--sandbox read-only` for review/consult/investigation (Codex must not modify the codebase); `--sandbox workspace-write` for Implementer mode (Codex was asked to make the change — don't run it read-only and don't let it merely describe the edit). See Step 1 for implementer guardrails; verify the resulting diff yourself before reporting done.
- **Always pass `-c service_tier=priority` (Fast mode); never pass `-c model_reasoning_effort=...`.** Headless runs block the caller, so the speed tier is worth the extra usage — `priority` is the tier codex's own model catalog labels "Fast" (~1.5× speed). It is per-invocation, so `~/.codex/config.toml` (and the user's interactive codex) stays on its configured tier. Reasoning effort still comes from that config file — dropping it to go faster is not allowed.
- If `$ARGUMENTS` is empty or only contains "review" with no further description, **default to reviewing all uncommitted changes** (run `git diff` + `git diff --staged` to gather context).
- **Always run in background via `codex-guard.sh`** (Step 2.5). Do not add a `Monitor` by default — the guard's single completion notification is the signal, and per-event Monitor notifications spam the calling session. Use the Step 6 Monitor tail only when the user explicitly wants live progress. Never redirect codex stdout to `/dev/null` (the guard captures it to the events file for post-mortems).
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
