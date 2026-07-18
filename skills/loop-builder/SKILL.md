---
name: loop-builder
description: "Design, build, test, soak, harden, or safely arm an unattended recurring automation. Use for cron, launchd, systemd timers, scheduled agents, daemons, recurring jobs, broken/misbehaving cron jobs, script-vs-agent decisions, and 'can I let this run unattended / arm it' questions. Triggers: '/loop-builder', 'build a loop', 'make an automation loop', 'set up a recurring job', 'turn this into a daily/weekly automation', 'harden this automation', 'my cron job misbehaved'."
---

You are designing, building, testing, or arming an **unattended automation loop** — a recurring job (cron, launchd, systemd timer, scheduled agent, or service-managed daemon) that runs with no human watching. The bar is high: an unwatched mutator that is wrong is worse than no automation at all. Work the numbered steps top to bottom. Do not skip to "enable" — arming is the last gate, not the first move.

## User Request

$ARGUMENTS

## Pipeline

```
0 classify ─► 1 spec+risk ─► 2 worker+supervisor ─► 3 security contract
     │                                                      │
     ▼                                                      ▼
4 implement dry-run, register DISABLED ─► 5 rollback + failure-injection (isolated)
     │
     ▼
6 soak (2 gates, pre-registered) ─► 7 arm authority ─► 8 arm transaction ─► 9 handoff
```

Nothing mutates production until Step 8. Every step below closes with the concrete **Output** it must produce before the next step begins.

## Step 0 — Classify the request

Decide which path you are on:

- **New loop** → run Steps 1–9 in order.
- **Existing-loop repair or hardening** → run the Steps 1–3 baseline audit first (spec + risk class, worker/supervisor fit, security contract) *before* any targeted fix. **No gate bypass:** an existing loop does not skip the baseline just because it already runs. Step 5's test matrix doubles as the audit checklist.
- **Arm-readiness question** ("can I let this run unattended / arm it?") → first **validate or produce the Steps 1–4 outputs** (spec + risk class, worker/supervisor, security contract, dry-run implementation) — Step 5 depends on them — then traverse Steps 5–8 in full. There is no fast path to armed. The one thing that never waits: **emergency disarm/containment of a misbehaving loop happens immediately**, before any baseline review.

**Reference-loading contract:** read `references/loop-spec-template.md` at Step 1, `references/arming-gates-template.md` at Steps 6–8, and `references/rationale.md` only when a rule needs justification or the situation is ambiguous. Do not preload all references.

**Output:** the chosen path (new / repair / arm-readiness) and which steps this request must traverse.

## Step 1 — Loop spec + risk class

Interview the owner and fill `references/loop-spec-template.md`. Capture: what one iteration does; what it mutates; the blast radius of a *wrong* iteration; the ground truth it reads; who is told what, when; the kill switch; the owner; the review/decommission date.

Assign a **risk class** — it sets every downstream bar:

| Class | Meaning |
|---|---|
| `read-only` | observes and reports; mutates nothing |
| `reversible-mutating` | mutates, every action cleanly reversible |
| `high-risk` | money, security, destructive, customer-facing, or broad production |

**Output:** a filled loop spec (identity, owner, mutation surface, blast radius, ground truth, kill switch, review date) + assigned risk class.

## Step 2 — Choose worker and supervisor (two independent decisions)

**Worker** — how one iteration computes:
- `script` — deterministic. Pure-rules iterations (poll, threshold check, relay, kill-on-hang, retry, formatting) are a script's job, **never an LLM at any tier**.
- `hybrid` — deterministic collector + LLM analyst.
- `llm-agent` — judgment iterations (triage, fuzzy classification, natural-language output). An LLM worker is always **wrapped in a deterministic harness** (timeout, max-runtime cap, journaling, locking). The harness supervises the agent; the agent never supervises the harness.

**Supervisor** — what launches iterations: `cron` | `launchd`/`systemd timer` | platform `scheduled-agent` | service-managed `daemon`. Choose on: cadence; catch-up/coalescing policy on missed runs; overlap behavior; restart supervision; host sleep/reboot behavior; user/session requirements; resource limits. **Never a naked `while true`** — a continuous worker belongs under a service manager that owns restart and resource policy.

**Environment-semantics checklist** (a loop that ignores these fails intermittently and blames luck): explicit timezone + DST double/skip behavior · clock skew · jitter · absolute paths · working directory · `PATH` · locale · `umask` · service identity · CPU/memory/disk limits.

**Output:** worker type, supervisor type, and the environment-semantics checklist answered — each with a one-line justification.

## Step 3 — Security contract (mandatory for every loop)

Fill the security section of the loop spec:

- **Identity & secrets.** Dedicated least-privilege identity/token. Secrets injected from protected storage — **never** in argv, prompt text, ledger rows, notifications, or committed config. Name the rotation/revocation procedure.
- **Redaction & retention.** Structured redaction and data-retention rules for logs and journals.
- **LLM trust boundary (for `hybrid`/`llm-agent`).** External content (web, email, tickets, tool output) is **untrusted data — prompt injection is assumed**. The model produces **proposals only**; a deterministic allowlist/schema/policy layer validates *every* side effect (model-proposes, deterministic-validates). The model gets no unrestricted shell, no credential expansion, no kill-switch access, and no direct mutation authority.

**Output:** completed security contract (identity, secret source, rotation path, redaction/retention, LLM trust boundary if applicable).

## Step 4 — Implement dry-run first; register disabled

**Mutating loops are born in dry-run/shadow:** observe real events, journal the action they *would* take, touch nothing live. Journal from the first run.

**Iteration mechanics** (design them, don't just name them):
- **Overlap policy:** `skip` | `coalesce` | `queue` | `safe-parallel`. Atomic lock/lease with stale-lock recovery (fencing token if distributed). A timeout kills the **whole process tree** and releases the lock.
- **Idempotency:** stable idempotency key per action; atomic checkpointing so a re-run repeats nothing.
- **Retry classes:** distinguish retryable from permanent errors; bounded backoff + jitter; rate-limit / cost ceiling; circuit breaker. Define a **compensating action** where one exists. Where a side effect is genuinely non-compensable, **mark it explicitly non-compensable** and require *prevention* instead: bounded blast radius, canarying, reconciliation, and a stronger approval bar — and a non-compensable mutation **forces the loop's risk class to `high-risk`**.
- **Runtime cap:** a max-runtime cap exits with an explicit `ABORTED` outcome rather than overrunning into the next cycle.
- **Cooldowns:** external-facing actions carry a cooldown (e.g. a multi-day per-target notify cooldown); skipped actions are journaled, not silently dropped.
- **Provenance markers:** every ledger row carries an explicit provenance tag — `ORGANIC` | `SMOKE_TEST` | `MANUAL_OPERATOR` — so later analysis separates real signal from operator and test rows.
- **Config via the owning loader.** Read config through the owning application's own loader/parser — **never ad-hoc regex over config files.** Regex cannot tell an active setting from a commented-out or overridden one, so it returns confidently wrong values.
- **Never interpolate untrusted input into a shell string.** Pass metacharacter-bearing input via argv arrays, stdin, or a file. A launch corrupted by shell parsing fails silently, *before* any in-loop guard can engage.

**Observability (structured, bounded).** Every run record carries: `run_id`, `scheduled_for`, policy/runbook version, provenance tag, start/end, duration, outcome, exit code, action/idempotency key. Define rotation, retention, permissions, redaction, and a disk cap. **Missed-run detection is external** — a loop cannot report that its scheduler never launched it. Important loops get scheduler-native or external **dead-man / freshness** monitoring (a last-success timestamp with an alert threshold). Proportional SLOs: low-risk jobs → missed-run/failure-streak thresholds; critical jobs → explicit success/freshness objectives.

**Register disabled.** Register the loop in your loop inventory/control plane **disabled** — registration is part of "created," not an afterthought. If you have no control plane, create a minimal portable manifest: one file listing every loop (name, runner, schedule, status, owner). **Unregistered-on-disk = drift.**

**Output:** a dry-run/shadow implementation with the iteration mechanics above wired, structured run records emitting, external freshness monitor defined, and a registry entry in state `DISABLED`.

## Step 5 — Rollback before enable, then test in isolation

Before the first armed run: snapshot current state; **write and test** the disable/rollback procedure; write the runbook. Rollback authored *after* arming is not rollback.

**Failure-injection test matrix** (beyond the happy path): timeout · overlap · malformed input · permission failure · dependency outage · notification failure · disk pressure · restart mid-run · partial mutation + rollback. Plus clock cases: DST · missed run · catch-up. Plus one hand-run smoke iteration tagged `SMOKE_TEST` in the ledger.

**Isolation boundary.** All mutation and rollback testing runs against an isolated fixture or a staging target — **non-production only**. The first production canary is Step 8.7, inside the arm transaction, *after* authority. **The production target stays dry-run until Step 8.** A "test" that mutates production is an arm without authority.

**Output:** a tested rollback procedure + runbook, and a passing failure-injection matrix run against an isolated target — production still untouched.

## Step 6 — Soak: two independent gates, thresholds fixed up front

**Soak activation (`DISABLED` → `SOAKING`):** enable the *scheduler* in dry-run/shadow mode through a read-back-verified transition — confirm the supervisor actually launches iterations and run records flow — and set `control_state = SOAKING`. The mutation path stays disabled; only observation is live. Without this explicit transition there is no organic evidence to soak on.

**Pre-register before the soak starts:** concrete `N`, `M`, `D_min`, `D_deadline` values (`D_min` = minimum soak days before arming is even considered; `D_deadline` = the day the soak escalates instead of waiting longer), the audit window, and a **hash of the gate policy**. Thresholds may never be chosen — or relaxed — after seeing the evidence. Any material gate-policy change resets the current-policy counters.

**Evidence binds to the artifact.** Every soak-evidence record carries the **behavior-identity digest** of the loop version that produced it — covering not just the loop's code and config but everything that changes behavior: pinned runtime dependencies, model/prompt/tool versions (for LLM workers), and the supervisor policy (schedule, overlap, catch-up). A material change to **any** component resets the organic counters — a new soak for the new digest. Soak evidence is **non-transferable across versions**; the Step 7 arm card may only cite evidence whose digest matches the digest being armed.

**Gate 1 — organic evidence:**
- ≥ `N` **organic** proposals, each individually audited correct.
- ≥ `M` consecutive clean reconcile cycles against ground truth.
- ≥ `D_min` soak days.
- Red-flag gate: zero unexplained executions, health green, config untouched, no unexplained or unresolved errors.

Gate counters count **only** `ORGANIC` rows — `SMOKE_TEST` (any synthetic/test iteration: hand-run smoke and failure-injection alike) and `MANUAL_OPERATOR` rows are excluded, or the gates lie. Historical rows are judged against the **policy version in force when written** — a row from an older policy can neither certify nor fail the current one; re-trigger or re-scope the audit window instead.

**Gate 2 — synthetic resilience:** the Step 5 failure-injection matrix passes, evidenced by `SMOKE_TEST` rows from the isolated target. Synthetic rows never satisfy the organic counters, but a **failed resilience test blocks arming**.

**Deadline the soak.** After `D_deadline` days without meeting the gates, emit `STALLED` and hand the decision to a human. A gated loop that can wait forever silently is its own failure mode.

**Output:** pre-registered thresholds + gate-policy hash + behavior-identity digest; Gate 1 evaluated against digest-matched `ORGANIC` evidence, Gate 2 against isolated `SMOKE_TEST` evidence.

## Step 7 — Arm authority

Soak/build authorization is **not** arm authorization. Produce an **arm card** (evidence summary: gates met, audits, reconciles, resilience results, rollback tested, blast radius) recording **both** the behavior-identity digest being armed **and** the gate-policy hash the evidence was judged under — approving the card approves *that digest under that policy*, nothing else.

- **Every arm of a new behavior-identity digest of a high-risk loop** (financial, security, destructive, customer-facing, broad-production) **requires explicit human approval at arm time** — a changed digest is a new arm, not a continuation. Restart/recovery of the *same* already-approved terminal digest is not a new arm.
- Auto-arm below that bar is allowed **only** if the owner recorded the delegation in the loop spec: exact scope, limits, expiry, approved policy hash, and revocation path. Absent that record, human approval is required regardless of class.
- **On any ambiguous audit → BLOCK, don't arm.** Blocking is reversible; a wrong arm is not. Notify with the specific unblock action.

**Output:** an approved arm card bound to the digest being armed — either a human approval (required for high-risk) or a valid recorded auto-arm delegation — or a `BLOCKED` verdict with its unblock action.

## Step 8 — Arm transaction

Run this **exact ordered sequence**; mutation completes before, and independently of, notification:

1. Freeze the behavior-identity digest **and** the gate-policy hash.
2. Verify both exactly match the approved arm card.
3. Take the arm lock.
4. Snapshot.
5. Stage the new config **disabled**.
6. Validate + read back the staged state.
7. Constrained **one-shot canary** iteration.
8. Reconcile the canary against ground truth.
9. Full enable + read back the **effective** state.
10. In **one atomic persist**: terminalize/self-disable the armer **and** record the notification intent in a durable outbox.
11. Deliver notifications from the outbox afterwards.

**Crash-safety brackets the whole transaction.** Before any mutation, durably persist an `ARMING` marker with an **operation ID**. Two distinct failure paths — don't conflate them:
- **Synchronous failure** (a step fails while the transaction is running): disarm/rollback, preserve evidence, report `BLOCKED`.
- **Restart recovery** (the process died and finds `ARMING`, or anything short of the terminal persist at step 10): **reconcile the effective state** — read back what actually got enabled — then **complete forward only if digest, approval, gates, and effective enablement all match**; anything else → rollback and `BLOCKED`. Never a blind replay of the mutation.

A crash or delivery failure *after* the terminal persist can delay a notification but never lose it, and never replays or rolls back the mutation — **delivery retries on its own.**

**Output:** the loop `ARMED` on the verified digest with the armer self-disabled, or rolled back to `DISABLED`/`BLOCKED` with evidence preserved.

## Step 9 — Handoff

Report: status, evidence locations, owner, runbook path, kill-switch one-liner, review/decommission date.

**Four-field state model — never conflate these:**

| Field | Values |
|---|---|
| `run_outcome` (per iteration) | `SUCCEEDED` · `SKIPPED` · `RETRYABLE_FAILED` · `PERMANENT_FAILED` · `ABORTED` |
| `control_state` (loop lifecycle) | `DRY_RUN` · `SOAKING` · `ARMED` · `BLOCKED` · `STALLED` · `DISABLED` |
| `notification_intent` | `NONE` · `INFO` · `PAGE` |
| `notification_delivery` | whether the intent actually reached its channel — tracked and retried separately |

**Quiet by default (`notification_intent` rules):**
- Healthy-but-gates-unmet runs send **nothing** (`NONE`).
- Control-state changes (`ARMED` / `BLOCKED` / `STALLED` / first-run-OK) send `INFO`.
- `PAGE` only for an actionable failure a human must act on **now**.
- **Never page non-actionable drift** — run-on-demand beats page-on-schedule. A false page erodes every future page and must be explicitly retracted.

**Stall detection:** a **progress signal** (output/journal advancement, heartbeat) determines *stalled* — **PID existence is NOT progress.** A separate **hard runtime budget** still terminates a merely *slow* run. Judge by progress, never wall-clock alone.

**Output:** a handoff record — control state, evidence locations, owner, runbook path, kill-switch one-liner, review/decommission date — and the four state fields wired into the loop's reporting.

## Anti-pattern table

| Anti-pattern | Do instead |
|---|---|
| LLM watchdog/monitor babysitting a job | deterministic script under the chosen supervisor |
| Born-armed mutator | dry-run first (Step 4), arm last (Step 8) |
| Page-per-run | quiet by default; page only actionable failures |
| Gate counters polluted by test rows | count `ORGANIC` only; tag every row |
| Regex config parsing | read via the owning app's loader |
| Wall-clock-only stall detection | progress signal + separate runtime budget |
| PID-as-progress | require output/journal/heartbeat advancement |
| Unregistered loop | register disabled in inventory/manifest |
| Armer that never self-disables | atomic terminalize at Step 8.10 |
| Soak with no deadline | `STALLED` after `D_deadline` days → human |
| Silent overrun into next cycle | max-runtime cap → `ABORTED` |
| Rollback written after arming | write + test rollback before enable (Step 5) |
| Secrets in argv/prompt/ledger | inject from protected storage |
| Naked `while true` | run under a service manager |
| Fallback that hides a broken invariant | fail loud on broken invariants (see `references/rationale.md`) |

## Scoring guidance (advisory, with non-compensable blockers)

Score the design 1–100 to communicate overall maturity — but scoring is **not** the arm gate. Any of these missing is a **non-compensable blocker: DO NOT ARM regardless of score** — missing owner · kill switch · secrets boundary · overlap policy · reconciliation · rollback/compensation (or documented non-compensable prevention controls) · arm authority. Fix the blocker, then re-score.
