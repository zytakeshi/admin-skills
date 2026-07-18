# Rationale — why each rule holds

The runtime workflow in `../SKILL.md` states *what* to do. This file states *why*, as neutral
invariants. Read a section only when a rule needs justification or a situation is ambiguous. Every
statement here is a property of unattended systems, not an anecdote.

---

## Worker/supervisor split

An unattended loop has two orthogonal concerns, and conflating them produces fragile automation:

- The **worker** decides *what one iteration computes*.
- The **supervisor** decides *when, whether, and under what limits an iteration runs*.

They fail independently and must be chosen independently. A perfect worker under a supervisor with no
overlap policy will stampede; a correct schedule around a worker with no idempotency will double-apply
on a retry. Two decisions, two designs.

**Why pure-rules work never goes to an LLM.** Polling, threshold checks, relaying, kill-on-hang, and
retry are fully specified by rules. An LLM adds latency, cost, and a nonzero rate of confidently wrong
output to a task with a deterministic correct answer — strictly worse on every axis. The corollary:
supervising a background job (waiting for completion, killing on hang, relaying output, retrying once)
is pure rules, so it is a **script's** job, never a spawned model of any tier. A model watchdog is the
canonical anti-pattern — it is more expensive and less reliable than the `while`/timeout it replaces.

**Why judgment work is still wrapped.** When an iteration genuinely needs fuzzy classification or
natural-language output, the model does that part — but inside a deterministic harness that owns the
timeout, the max-runtime cap, journaling, and locking. The harness supervises the model; a model that
supervises its own harness can neither be reliably bounded nor reliably killed.

## Dry-run first, arm last

The cost of a wrong unattended mutation is unbounded and paid while no one is watching. The cost of a
dry-run is a journal line. So the correct default is: born in shadow, mutate nothing, journal the
action it *would* take, and earn mutation authority through evidence. Arming is the **last** gate a
loop passes, never the first — and a "test" that mutates the production target is an arm that skipped
the gate, not a test.

## Reconciliation and idempotency

Unattended loops run across crashes, retries, overlapping cycles, and clock jumps. Under those
conditions, "did this action already happen?" cannot be answered by control flow — only by comparing
against ground truth. Hence: a stable idempotency key so a re-run repeats nothing, atomic checkpoints
so a crash resumes cleanly, and reconciliation against the source of record so the loop's belief and
reality stay identical. A loop that trusts its own memory over ground truth will eventually act on a
false belief.

## Compensation vs prevention

Reversible side effects can be corrected after the fact, so a compensating action suffices. A
genuinely non-compensable side effect (an irreversible external action, a spent resource) cannot —
correction is impossible, so the only defense is not making the mistake: bounded blast radius,
canarying, reconciliation before commit, and a stronger approval bar. Marking an action
"non-compensable" is therefore not paperwork; it changes which safeguards are mandatory.

## Fail-open vs fail-closed

For each failure mode, name the **protected invariant** and the **worst incorrect action**, then:

- **A guard that authorizes a mutation fails closed.** If uncertainty could let a harmful mutation
  through, the safe direction is to withhold authorization. Blocking is reversible; a wrong mutation
  may not be.
- **Only a non-blocking observer may fail open — and only loudly.** If a component's failure leaves
  the primary operation independently safe, it may degrade open rather than halt real work, but it
  must announce the degradation; a silent fail-open hides a broken invariant.
- **Then name what becomes load-bearing.** Any dependency whose failure stops production work must
  itself be monitored. An unmonitored load-bearing dependency is a silent single point of failure —
  the failure is discovered only when production has already stopped.

The general principle: broken invariants (corrupted state, missing required config, ambiguous
authorization) fail **loud**; expected external/runtime failures (a flaky endpoint, a transient
outage) get **bounded, observable, semantics-preserving** fallbacks. A fallback that swallows a broken
invariant converts a loud, fixable failure into a silent, compounding one.

## Dead-man / external monitoring

A loop's own logs can only describe runs that happened. The one failure a loop can never
self-report is the run that never launched — a disabled timer, a crashed supervisor, a host that
slept through the schedule all look identical from inside the loop: silence. Freshness must therefore
be judged from **outside**: a last-success timestamp with an alert threshold, owned by the layer that
can observe the *absence* of a run. This is the build-at-the-owning-layer rule applied to liveness —
the loop cannot own a signal it is structurally blind to.

## Prompt-injection model

When a worker reads external content — web pages, email, tickets, tool output — that content is
attacker-controllable input, not trusted instruction. The safe architecture assumes every such input
is trying to redirect the model, and confines the damage structurally rather than by hoping the model
resists:

- The model emits **proposals**, never direct side effects.
- A deterministic layer (allowlist, schema, policy) validates **every** side effect before it
  happens. This is the only component that must be trusted, and it contains no model.
- The model receives no unrestricted shell, no credential expansion, no kill-switch access, and no
  direct mutation authority — so even a fully hijacked model can only propose, and every proposal
  still faces the deterministic gate.

Security here is a property of the *architecture*, not of the prompt. A guardrail phrased as a prompt
instruction is bypassable by the same channel it is meant to defend.

## Quiet-by-default paging

Every page spends a human's attention and a fraction of the credibility of all future pages. A page
for non-actionable drift is a net loss twice over: it wastes attention now and desensitizes the
recipient to the next page, which may be real. So the intent hierarchy is strict — send nothing for
healthy-but-incomplete runs, `INFO` for state changes worth a glance, and `PAGE` only for a failure a
human must act on immediately. Run-on-demand beats page-on-schedule for anything that is not urgent,
and a page sent in error must be explicitly retracted, because an un-retracted false page is
indistinguishable from a real one that was ignored.

## Progress, not wall-clock or PID

Two different failures are easy to confuse. A **slow** run is making progress but taking long — it
needs a hard runtime budget so it cannot overrun into the next cycle. A **stalled** run has stopped
advancing — it needs a progress signal (output, journal advancement, heartbeat) to be detected. PID
existence proves only that a process exists, not that it is doing anything; a wedged process holds its
PID indefinitely. Detecting stall by wall-clock alone cannot tell slow from stuck, and detecting it by
PID cannot tell alive from working. Judge liveness by advancement of a real signal.

## Generic archetypes

Three shapes, to make the rules concrete. Details are illustrative defaults, not prescribed constants.

**Billing reconciliation loop** — touches money, so it **is `high-risk`** by definition. Worker:
deterministic (arithmetic and matching have exact answers). Mutations must be idempotent and
reconciled against the ledger of record before commit; each candidate correction is a proposal that
a deterministic policy validates. Born in dry-run, journaling the adjustment it *would* post; armed
only after ≥ `N` organic proposals audit correct and reconcile cycles come back clean. Because it is
high-risk, **every arm of a new behavior-identity digest requires explicit human approval** — money
blast radius never auto-arms.

**Fleet health watchdog** — `read-only` observer. Worker: deterministic (thresholds and reachability
are rule-checks — no model belongs here). Because it is a non-blocking observer, it may fail open, but
loudly: if it cannot evaluate health, it says so rather than reporting green. It never takes
destructive action on an indirect verdict — a watchdog advises and logs; killing or restarting on an
inferred signal is how a false positive becomes an outage. Paging is quiet-by-default: `PAGE` only a
real, actionable outage; `INFO` for state transitions; silence otherwise.

**Weekly report job** — `read-only`, low-risk. Worker: hybrid is defensible (deterministic collection,
optional model for narrative summary), but the numbers come from the deterministic half; the model
only phrases them. Supervisor choice centers on catch-up policy — a missed weekly run should coalesce
to one run, not silently vanish and not fire twice. Monitoring is a freshness check: the absence of a
report is the failure mode, and only an external dead-man check can see an absence.
