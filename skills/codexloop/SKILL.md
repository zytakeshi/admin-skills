---
name: codexloop
description: "Run /codex in a loop: review the code, fix findings you agree with, re-review, and keep going while P1 findings remain (correctness, security, money, data loss, swallowed errors); nits never extend the loop. Use when the user types /codexloop or asks for an iterative codex review-and-fix cycle until clean. Triggers: '/codexloop', 'codex loop', 'iterative codex review', 'loop codex until clean', 'review and fix with codex until satisfied'."
---

You are running an iterative review-and-fix loop with Codex. Codex is the reviewer; you are the implementer. Loop until no P1 finding remains, or until the round budget is spent (see The stopping rule below).

## User Request

$ARGUMENTS

## Why this exists

A single `/codex` pass finds issues but doesn't fix them. A single fix pass addresses today's findings but may introduce new ones, or may miss things that only become visible after the first round of edits. The loop closes that gap: review → fix → re-review → fix → … until codex stops finding things you consider real problems. Two agreeing models converging on "looks good" is a stronger *static* signal than either one alone — it is not a substitute for exercising the changed behavior (DB semantics, transactions, auth, payments only fail for real when executed).

The loop is not "keep going until codex has zero complaints no matter how petty." It's "keep going until both of you are honestly satisfied." Those are different things — codex can always find something to nitpick, and endless iteration on style or micro-optimizations burns time and tokens without improving the code. Your job is to recognize when further iteration stops adding value.

## The stopping rule

> **After the first review, only a P1 finding buys another round. Stop at 3 rounds, or 6 if the change touches prod, money, or auth.**

**P1** = correctness, security, money, data loss, or a swallowed error. Everything else — style, naming, micro-optimization, speculative refactors, missing-but-optional tests — is a **nit**.

Nits do not extend the loop. Collect them, apply the ones you agree with in a single batch at the end, and **never re-review that batch**. A nit batch does not earn another 500k-token round.

Why the floor exists: measured over 114 real loops, the codex report shrinks to ~2,800 characters by round 3 and then plateaus there permanently, while input tokens grow 3.4x by round 11. Codex always finds something to say. The severity floor is the exit; the round count is only a backstop. A change still producing P1 findings at round 6 has a design problem, not a review problem — stop and escalate to the user.

The round budget is set **before** round 1, from the change's blast radius:

| Blast radius | Budget |
|---|---|
| Touches prod, money, billing, certs, DNS, fleet state, or auth | 6 rounds |
| Everything else | 3 rounds |

## Core loop

Each iteration has four phases.

### Phase A — Review

Invoke the `codex` skill against the current working state. Use the `Skill` tool with `skill: "codex"` and pass the scope as `args`.

The `codex` skill runs codex under its deterministic **`codex-guard.sh` supervisor** (its Step 2.5) — no watchdog agent at all: the script launches codex, swallows the JSONL event stream into a file, handles startup-hang kill+retry, and reports one `STATUS:` line. The event stream never enters this loop's context, and each iteration is just one background Bash call. **Phases B–C stay on you (the calling agent, Opus):** triaging which findings are real and applying fixes is judgment + code, not execution.

Scope rules:
- If the user passed a scope in `$ARGUMENTS`, forward it verbatim (e.g. `/codexloop staged changes` → `args: "review staged changes"`).
- If `$ARGUMENTS` is empty, default to reviewing all uncommitted changes. Pass `args: "review my uncommitted changes"`.
- If there are no uncommitted changes but the current branch is ahead of main, review the branch diff: `args: "review my branch vs main"`.

On iterations 2+, include a short note to codex about what changed since the last round, so it doesn't just repeat itself. Example:
> "This is iteration N of a review loop. Last round you flagged A, B, C. I fixed A and B. I disagreed with C because <one-sentence reason>. Re-examine C independently against the current code; if you still believe it's real, keep flagging it and say why that reason is wrong — do not drop it just because I disagreed. Review the current state."

### Phase B — Triage

Read codex's findings and categorize each one. For each finding, do a short LLM-classification step:

```
{
  "summary": "<one-line description>",
  "category": "AGREE | DISAGREE | UNSURE",
  "reason": "<one-sentence justification>",
  "non_controversial": true | false,
  "confidence": 0-100
}
```

**`non_controversial: true`** (auto-apply if also AGREE and `confidence > 90`):
- Formatting, whitespace, import ordering
- Typo fixes in strings, comments, docs
- Null-checks where the codepath demonstrably allows null
- Missing error handling on already-defined error paths
- Removing dead code (unused imports, unreachable branches)
- Obvious bug fixes (off-by-one, wrong variable name, swapped args)
- Missing tests for existing behavior

**`non_controversial: false`** (always surface for human judgment):
- Refactoring approach, extract function, abstraction-boundary changes
- Library / dependency choice changes
- API shape changes (function signatures, public interfaces)
- Architecture changes (split file, merge files, restructure modules)
- Performance trade-offs (caching, memoization decisions)
- Anything touching critical paths: signing configs, payment flows, cert renewal scripts, auth, security headers
- **Cross-cutting / integration concerns** that codex marks as CROSS-CUTTING (lifecycle ordering interactions, native↔Dart error-contract races, state-emit sibling races) — these often require nuanced judgment about whether the interaction is actually risky in this codebase, and the fix may need broader changes than the diff itself; surface them rather than auto-applying.

Be honest in both directions. Don't rubber-stamp codex; it can be wrong, overzealous, or suggest churn that makes the code worse. Don't reflexively dismiss either; if you can't articulate a concrete reason to disagree, the finding is probably real. Stylistic or subjective findings generally favor the existing code's conventions — don't let codex drive a rewrite the user didn't ask for.

### Phase C — Fix

Apply fixes based on the Phase B classification:

- **Auto-apply** when `category == AGREE` AND `non_controversial == true` AND `confidence > 90`. Use `Edit` for targeted changes; don't rewrite files wholesale.
- **Surface for human judgment** when `category == AGREE` but `non_controversial == false` OR `confidence <= 90` — list these in the final report rather than applying silently.
- **Don't apply** anything categorized DISAGREE.

If a fix turns out to be harder than expected (e.g. it requires a refactor codex didn't anticipate, or would touch code outside the original scope), either:
- Scope the fix down to the safe, local part, note the rest as unresolved, and move on; or
- Escalate to the user with the tradeoff.

If something fast and already-configured can validate your fixes (type check, linter, single test file), run it. Skip long full test suites unless the user asked for them — except the mission-critical independent check required by Phase D exit condition 1, which overrides this skip.

### Phase D — Decide

Exit the loop when **any** of these is true:

0. **The severity floor is hit** — the latest review produced no P1 finding. Batch the remaining nits, apply the ones you agree with, and exit. Do not re-review the batch. This is the normal exit.

1. Codex's latest review is clean — no findings, or only "looks good" commentary.
   **Mission-critical carve-out** (the Phase B critical-path scope: payments/billing, auth, certs, security headers, prod deploys): a clean review alone does not exit. Also require one independent check that exercises the changed invariant/boundary — prefer the relevant tests or a behavioral verification (the smallest meaningful integration check is enough); a fresh reviewer pass with no loop history is a fallback only when nothing executable exists, and is weaker evidence. If the check fails, fix and keep looping. If nothing independent is runnable, exit anyway but name the residual risk explicitly in the report — never present a clean review as verified.
2. Every remaining finding is one you already disagreed with on a prior iteration, and codex is repeating itself — you've reached a stable impasse. (The same finding returning with a new rationale still counts as repetition after one honest re-triage — don't re-litigate forever.) **Consult, then decide — do not ask the user.** Put the disputed findings and your reasons to one fresh reviewer that has no loop history (the `review-fallback-opus` agent at high, or Cursor for a simple change). It sides with you → exit, and record each dispute with its reason in the report. It sides with codex → fix and loop once more. Ask the user only when the dispute touches money, auth, prod state or a public release.
3. You made no edits this round AND codex's findings are substantively the same as last round — you're stuck, not progressing.
4. **The round budget is spent** (3, or 6 for prod/money/auth changes). Stop and report what is still open. If P1 findings are still appearing at the budget ceiling, say so plainly and escalate — that pattern means the change needs a design review, not another round.

Otherwise, go back to Phase A with the updated code.

## Final report

When the loop exits, give the user a tight summary:

```
## Codexloop complete — N iteration(s)

**Fixed** (M items):
- <file:line> — <what changed, one line>

**Disagreed with** (K items, if any):
- <file:line> — <finding summary> — Why: <reason>

**Unresolved** (L items, if any):
- <file:line> — <finding> — <why deferred: needs user call / scope creep / etc.>

**Verification**: none | <test/behavioral check that ran> | residual risk: <named, if nothing runnable>

**Exit reason**: no P1 remaining | clean review | clean review + verified | stable impasse | no progress | round budget spent (N of M)
```

The user wants to know what changed, what's still open, and why the loop stopped — not a replay of every codex message.

## Rules

- **Invoke codex via the `Skill` tool**, not by shelling out to `codex` yourself. The `codex` skill already handles backgrounding, event streaming, output capture, and per-task ID collision avoidance. Don't reimplement that.
- **One codex invocation per iteration.** Don't spawn parallel codex runs; they race on output files and muddle the loop's state.
- ⛔ **Every iteration starts a FRESH codex session. Never `/codex-reply` or `codex exec resume` inside this loop** — not to "save context", not to "let codex see its own last round". Two reasons, both fatal to the loop: (1) a resumed session defends the findings it already made instead of re-deriving them, so a clean exit would prove agreement with itself, not that the code is clean; (2) the session still holds the PRE-fix file contents, so it reviews code you already changed. Feed prior-round context the supported way — the disagreement list in the Phase A prompt.
- **Only act on what codex actually reported.** Don't invent findings. Don't fix unrelated issues you happen to notice — mention them in the final report and leave them alone. Scope discipline is how this loop stays useful.
- **Preserve the user's intent.** If codex wants to refactor something that works and the user didn't ask for a refactor, disagree. The loop is for correctness and honest improvements, not aesthetic churn.
- **Don't commit or push** unless the user explicitly asked. The loop edits files in place and reports; commits are the user's call.
- **Track disagreements across iterations.** Keep a running list of findings you've disagreed with, with reasons. This is what you feed back to codex in Phase A of later iterations, and what lets you detect the "stable impasse" exit condition.
- **No numeric grades as ship evidence.** Never ask codex for a score, and never quote one ("94/100 PASS") as justification to ship or to exit clean — in the report, in memory, or to the user. Loop outputs are findings + exit conditions; ship evidence is tests or behavioral verification. If codex volunteers a score unprompted, ignore it. (Phase B's internal `confidence` field is fine — it gates auto-apply, it is not a ship grade.)
- **Stop early when it makes sense.** The budget is a ceiling, not a target. A round that finds only nits ends the loop, even if it is round 1.
- **Hang recovery is `codex-guard.sh`'s job, not yours.** The codex skill's guard script (its Step 2.5) owns launch, the startup-gate hang detection, the `TASK_ID`-scoped kill, and the one retry — do **not** run `pkill`/`TaskStop` yourself. You only react to the reported `STATUS` line: `COMPLETED`/`RECOVERED` → triage the findings; `TIMEOUT` → codex was alive but over the cap — re-run with a higher cap or narrow scope; `STALLED` → mid-run collab sub-agent wedge — re-run once making sure the no-collab preamble (codex skill Step 3 point 3) is in the prompt, then treat as `FAILED` if it recurs; `FAILED` → treat codex as unavailable and do the fallback review yourself on Opus (next bullet). (Only in explicit inline mode do you apply the codex skill's recovery directly.)
- **Each iteration's review follows the codex skill's review lane order** (Codex lane on the viraltechofficial@gmail.com account via `codex-viraltech.sh` → Codex lane on the default ChatGPT login (zyvista) directly when viraltech is nerfed or errors → Cursor lane → `review-fallback-opus` agent, its Step 2.5; the AirGate lane is retired (founder 2026-10-13: the AirGate relay causes account nerf)). A lane that failed in one iteration is tried again in the next — quota can return. Name the lane and model per iteration in the final report. Only when all four lanes fail does the loop stop and report codex/Cursor unavailable; the user can still run codex interactively via `! codex …`.

## Note on the GitHub Codex bot (PR review workflow)

This loop runs the **Codex CLI locally**. It is independent of the GitHub `chatgpt-codex-connector[bot]` PR-review pipeline.

If a downstream `/create-pr` step is waiting on the GitHub bot and the bot doesn't pick up the PR (no 👀 reaction within ~90 s), the standard fix is to **close and reopen the PR** to re-fire the webhook. Don't give up after one retry — keep re-triggering until the bot picks up or the user explicitly chooses to merge without bot review. This loop's local Codex pass does not replace the bot's review on the merged PR.

## Examples

```
/codexloop
  → review uncommitted changes, fix agreed findings, re-review, loop until clean

/codexloop staged changes
  → review git diff --staged, fix, loop

/codexloop security audit src/auth
  → review src/auth with security focus, fix agreed findings, loop

/codexloop PR 123
  → review PR 123 diff, fix, loop

/codexloop performance review src/services
  → review with performance focus, fix agreed findings, loop
```
