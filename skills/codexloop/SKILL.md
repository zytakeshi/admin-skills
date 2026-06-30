---
name: codexloop
description: "Run /codex in a loop: review the code, fix findings you agree with, re-review, and keep going until codex has nothing left to flag (or only disagreements remain). Use when the user types /codexloop or asks for an iterative codex review-and-fix cycle until clean. Triggers: '/codexloop', 'codex loop', 'iterative codex review', 'loop codex until clean', 'review and fix with codex until satisfied'."
---

You are running an iterative review-and-fix loop with Codex. Codex is the reviewer; you are the implementer. Keep looping until the code is clean or you and codex have reached an honest impasse on the remaining findings.

## User Request

$ARGUMENTS

## Why this exists

A single `/codex` pass finds issues but doesn't fix them. A single fix pass addresses today's findings but may introduce new ones, or may miss things that only become visible after the first round of edits. The loop closes that gap: review → fix → re-review → fix → … until codex stops finding things you consider real problems. Two agreeing models converging on "looks good" is a stronger signal than either one alone.

The loop is not "keep going until codex has zero complaints no matter how petty." It's "keep going until both of you are honestly satisfied." Those are different things — codex can always find something to nitpick, and endless iteration on style or micro-optimizations burns time and tokens without improving the code. Your job is to recognize when further iteration stops adding value.

## Core loop

Iterate **without a fixed cap**. The loop exits only on the conditions in Phase D below (clean review, stable impasse, no progress, or diminishing returns). Each iteration has four phases.

### Phase A — Review

Invoke the `codex` skill against the current working state. Use the `Skill` tool with `skill: "codex"` and pass the scope as `args`.

The `codex` skill delegates the actual run to a **Sonnet 5 watchdog sub-agent** (its Step 2.5) — it launches codex, babysits for hangs, recovers, and returns only the findings. That keeps the JSONL event stream out of this loop's context. **Phases B–C stay on you (the calling agent, Opus):** triaging which findings are real and applying fixes is judgment + code, not execution — never push it down to the runner. Each iteration uses a fresh runner for its one review run.

Scope rules:
- If the user passed a scope in `$ARGUMENTS`, forward it verbatim (e.g. `/codexloop staged changes` → `args: "review staged changes"`).
- If `$ARGUMENTS` is empty, default to reviewing all uncommitted changes. Pass `args: "review my uncommitted changes"`.
- If there are no uncommitted changes but the current branch is ahead of main, review the branch diff: `args: "review my branch vs main"`.

On iterations 2+, include a short note to codex about what changed since the last round, so it doesn't just repeat itself. Example:
> "This is iteration N of a review loop. Last round you flagged A, B, C. I fixed A and B. I disagreed with C because <one-sentence reason> — please re-examine that finding or drop it. Review the current state."

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

If something fast and already-configured can validate your fixes (type check, linter, single test file), run it. Skip long full test suites unless the user asked for them.

### Phase D — Decide

Exit the loop when **any** of these is true:

1. Codex's latest review is clean — no findings, or only "looks good" commentary.
2. Every remaining finding is one you already disagreed with on a prior iteration, and codex is repeating itself — you've reached a stable impasse.
3. You made no edits this round AND codex's findings are substantively the same as last round — you're stuck, not progressing.
4. The remaining findings are all low-value (style, micro-optimization, speculative refactors) and further iteration isn't justified. Say so explicitly in the final report rather than silently deciding.

There is **no fixed iteration cap.** As long as each round produces real fixes that aren't being re-flagged, keep going. Otherwise, go back to Phase A with the updated code.

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

**Exit reason**: clean review | stable impasse | max iterations | no progress | diminishing returns
```

The user wants to know what changed, what's still open, and why the loop stopped — not a replay of every codex message.

## Rules

- **Invoke codex via the `Skill` tool**, not by shelling out to `codex` yourself. The `codex` skill already handles backgrounding, event streaming, output capture, and per-task ID collision avoidance. Don't reimplement that.
- **One codex invocation per iteration.** Don't spawn parallel codex runs; they race on output files and muddle the loop's state.
- **Only act on what codex actually reported.** Don't invent findings. Don't fix unrelated issues you happen to notice — mention them in the final report and leave them alone. Scope discipline is how this loop stays useful.
- **Preserve the user's intent.** If codex wants to refactor something that works and the user didn't ask for a refactor, disagree. The loop is for correctness and honest improvements, not aesthetic churn.
- **Don't commit or push** unless the user explicitly asked. The loop edits files in place and reports; commits are the user's call.
- **Track disagreements across iterations.** Keep a running list of findings you've disagreed with, with reasons. This is what you feed back to codex in Phase A of later iterations, and what lets you detect the "stable impasse" exit condition.
- **Stop early when it makes sense.** A short clean loop is better than 5 iterations of diminishing returns. Calling it done at iteration 2 with a good reason beats grinding through to iteration 5.
- **Hang recovery is the runner's job, not yours.** Because you invoke codex via the `Skill` tool, the codex skill's Sonnet watchdog (its Step 2.5) owns launch, hang-detection, the `TASK_ID`-scoped kill, and the one retry — those tasks live inside the runner, so do **not** run `pkill`/`TaskStop` yourself in delegated mode. You only react to the returned `STATUS` line: `COMPLETED`/`RECOVERED` → triage the findings; `FALLBACK` → triage the native-review body the runner returned; `FAILED` → treat codex as unavailable (next bullet). (Only in explicit inline mode do you apply the codex skill's recovery directly.)
- **If codex is unavailable** (not installed, network down, persistent errors, or it hangs a second time after recovery), fall back to your own review pass (a fresh Opus reviewer over the same diff), say so explicitly in the report, and note the user can run codex interactively via `! codex …`.

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
