---
name: fable5
description: >-
  Step-by-step guide for spending a frontier-tier model session (e.g. Claude's
  Fable 5) well: decide whether a piece of work is a "one-way door" worth the
  frontier tier, compress the context into a distilled pack before the session,
  have the frontier model write the one governing artifact — the durable
  decision, spec, contract, or framework the most downstream work depends on —
  as a mid-flight sub-agent spawn, then return control to your main-loop model,
  which hands off execution and verification to your cheap fleet (an
  implementation/execution pass plus a review-and-fix loop — this collection's
  own /codex + /codexloop skills, or whatever equivalent tooling you use),
  escalating back to the main loop only on real ambiguity. The work is
  domain-agnostic: the artifact might be a data model or API contract, but
  equally a PRD, a research plan, a taxonomy, a grading rubric, an information
  architecture, a policy, or the system prompt your fleet runs on. Use this
  WHENEVER the user mentions Fable 5 or a frontier model tier, asks "should I
  use the frontier model or my main model (or a cheap model) for this," wants
  to plan/architect a one-way-door decision, asks what to spend an expensive
  frontier session on, is prepping a frontier-model session, wants to reduce
  main-loop-model usage, or asks how to route a task across model tiers — even
  if they don't name a specific model but describe an expensive-to-reverse
  decision (a data model, an API contract, a core abstraction, a spec, a
  rubric, a policy) they want done right.
---

# Spending a frontier-tier model session

## The one idea

Every model lineup has a frontier tier: most capable, most expensive, run
rarely (for Claude Code today, that's Fable 5). A single frontier session that
produces the right **durable artifact** governs **thousands** of downstream
cheap-fleet calls for the rest of the week. The cost amortizes to near-zero per
use.

The artifact is whatever, *for your work*, the most downstream effort is built
on — the decision that's expensive to change once things depend on it. In code
that's often a data model, an API or wire contract, or a core abstraction. But
it's just as often not code at all: a PRD or product spec, a research plan, a
verification rubric or grading schema, a taxonomy or content structure, a
policy or set of principles, or the system prompt your fleet runs on. The skill
is domain-agnostic — what matters is **leverage × reversibility**, not whether
the output is a schema.

So the whole game is: **point the frontier model at the one-way doors and the
artifacts that govern the fleet — and nothing else.** Everything cheap-to-
reverse or mechanical goes to the cheap fleet. This is also how you cut your
main (mid-tier) model's usage: the reusable judgment your main model currently
re-derives every session gets frozen into a frontier-written artifact once, so
the main model is left only with orchestration and genuinely-novel calls.

**The frontier model is orchestrator/planner only — never code-touching.** It
never runs as the main loop for a coding session. The pattern is: **your main
model (the main loop) spawns the frontier model as a sub-agent for exactly one
planning/artifact call, then control returns to the main model** as soon as the
artifact comes back — via a one-off sub-agent spawn pinned to the frontier
model for a single call, or a scripted pipeline step pinned to the frontier
model for just that one stage. The frontier model does delegation, planning,
coordination, and synthesis inside that one call: it writes the governing
artifact — the spec, contract, rubric, plan, or model. It does **not** write
implementation, edit files, or do code review, and it never holds the session
past that call. Every implementation/review step goes to your main model
(judgment) or the cheap fleet (execution) — concretely, this collection's own
`/codex` skill for implementation and `/codexloop` for verification (see Steps
4-5), if you have them installed, or whatever equivalent implementation/
review-loop tooling you already use.

## The three tiers

```
TIER-0  FRONTIER   one-way doors + governing artifacts        run rarely · amortizes
                    the durable decision/spec/contract/         over 1000s of calls
                    framework the most downstream work depends
                    on — schema · API contract · core
                    abstraction · PRD · rubric · taxonomy ·
                    policy · the system-prompt the fleet runs on
─────────────────────────────────────────────────────────────────────────────────
TIER-1  MAIN MODEL  orchestration + genuinely-novel judgment    SHRINKS as judgment
                    (the call not yet codified in an artifact)  moves up into Tier-0
─────────────────────────────────────────────────────────────────────────────────
TIER-2  CHEAP       compressor (context→distilled pack) · exec  runs all week
        FLEET       + review-loop (yours, e.g. /codex + /codexloop) ·
                     i18n · search · mechanical transforms
```

Artifacts flow **down** from the frontier tier and govern the fleet. Your main
model only catches escalations the fleet can't resolve.

## Step 0 — The one-way-door test (decide if this even needs the frontier tier)

Before spending a frontier session, ask: **is this expensive to reverse once
the week ends?**

Route to the **frontier tier** when the work is a *decision that locks in
structure others build on* — and is expensive to change once they have:
- **Structural / technical contracts** — a data model or schema, an API or wire
  format, a core abstraction/interface. Changing these after data exists or
  consumers ship is a migration, not a refactor.
- **Governing artifacts the fleet runs against all week** — a PRD, a
  verification rubric, a grading schema, a taxonomy, or a system prompt. These
  have the highest amortization of all: one frontier session shapes thousands
  of runs.
- **Direction-setting decisions** — a research plan, a product / positioning
  spec, an information architecture, a policy or set of principles. Cheap to
  write, expensive to unwind once a body of work commits to them.

The common thread is **leverage × irreversibility, not the medium.** If lots of
later work will assume this decision and re-doing it means redoing that work,
it's a one-way door — whether the output is a schema, a rubric, or a plan.

Route to the **cheap fleet** when the work is *cheap to reverse or mechanical*:
release engineering (tag → bump → deploy), i18n propagation, per-fork ports,
boilerplate, searches, log/metric scans, and — importantly — **the reviews
themselves** (your review loop, e.g. `/codexloop`, runs on the cheap fleet
against the frontier model's rubric).

If you're unsure, apply the metaphor: **a revolving door (walk back out freely)
→ cheap fleet. A door that locks behind you → frontier tier.**

See `references/one-way-door-examples.md` for worked examples across several
domains (not just code), and for how to build your own ranked shortlist from
your active projects.

## Step 1 — Pick the target

Pick the single highest-amortization one-way door available right now. Prefer,
in order: (1) a governing artifact that unblocks the fleet for the week (a
rubric, a shared contract, a spec), (2) a core abstraction or framing other
work is currently blocked on, (3) a structural decision — schema, contract,
information architecture — needed before downstream build starts. One frontier
session should have **one** clear artifact as its output — don't try to make it
do three unrelated things.

## Step 2 — Compress before you spend (protect the frontier model's input tokens)

The frontier model's input tokens are precious. **Never feed it raw repo reads
(or raw doc dumps).** Instead, have the cheap fleet build a **distilled context
pack** first:

1. If you have a call-graph / static-analysis tool available (e.g. an MCP that
   can trace symbol references, call graphs, or architecture summaries), use it
   to pull the exact symbols/contracts in play with file:line precision — this
   is far cheaper and more precise than dumping files. For non-code work, the
   equivalent is pointing a cheap-fleet agent at the authoritative sources (the
   current spec, the existing taxonomy, the prior decision record) and having
   it extract the shape. Either way, distill rather than dump.
2. Have that agent distill: the current contract/shape, the constraints, the
   invariants that must hold, and the specific decision(s) the frontier model
   must make. Output a compact pack, not a file dump.
3. Use `assets/context-pack-template.md` as the shape of that pack.

The goal: the frontier session opens already knowing the terrain, spending its
capacity on the *decision*, not on reading.

## Step 3 — Spawn the frontier model mid-flight, then return to your main model

Stay on your main model as the main loop. **Spawn the frontier model as a
single sub-agent call** for this one planning step, hand it the distilled pack,
and ask for the **durable artifact**, not the downstream work — whichever form
fits:
- a **spec / PRD / architecture or design doc** (what to build or do and why,
  with the hard trade-offs resolved),
- a **frozen shape** — an API or wire contract, a data model or schema, a
  taxonomy, or an information architecture,
- a **verification rubric + verdict schema** (e.g. confirmed / inflated /
  false-positive) and/or the **system prompt** the cheap fleet runs on all
  week,
- a **direction** — a research plan, a policy, or a decision record that
  settles a contested call once.

Use `assets/fable-session-brief-template.md` to frame the session.

- **One-off, interactive session:** spawn a fresh sub-agent pinned to the
  frontier model for this one call — not a fork or continuation of your main
  session (the frontier model should not inherit main-loop session state).
- **Scripted pipeline:** a single pipeline stage pinned to the frontier model
  for that one planning step, e.g. an `agent()` call with `phase: 'Plan'` and
  the frontier model set — every other stage (implement, verify) stays on your
  main model or the cheap fleet per your normal tiering rule.

The moment the artifact comes back, **control returns to your main model** —
the frontier model does not stay in the loop, does not see the implementation,
and is not spawned again unless a *new* one-way-door decision comes up. The
artifact should be self-contained enough that your main model or the cheap
fleet can implement/run against it without re-consulting the frontier model.

## Step 4 — Execute via the cheap fleet

Back on your main model: hand the frontier model's artifact to a cheap-fleet
execution agent — this collection's own `/codex` skill if you have it
installed, or any equivalent implementation/execution tooling — to do the work
**against the artifact** (write the code, produce the content, run the
analysis). The design decisions are already made; this is execution. Keep the
output minimal and traceable back to the artifact.

## Step 5 — Verify via a cheap-fleet review loop (against the frontier model's rubric)

Run a cheap-fleet review-and-fix loop — this collection's own `/codexloop` if
installed, or your own equivalent — to review-and-iterate. Because the frontier
model already wrote the grading rubric and verdict schema in Step 3, the loop
grades against a frozen, high-quality standard instead of re-inventing criteria
each run. This is exactly the "one frontier session shapes thousands of
downstream calls" payoff.

## Step 6 — Escalate to your main model only on a real ambiguity

The cheap fleet (execution + review loop) runs the loop autonomously. Your main
model (the orchestrator, already the main loop throughout Steps 4-6) steps in
**only** when the loop surfaces a genuine ambiguity or gap the artifact didn't
cover — not for routine execution. If that ambiguity is itself a reusable
judgment call your main model would otherwise re-derive every time, that's the
signal to go back to Step 3 and spawn the frontier model again to codify it
into the artifact — don't just answer it inline and let it stay tribal
knowledge.

## How this reduces main-model usage

This reduction is not "use your main model less carefully." It's **stop making
it re-derive what a frozen artifact could encode.** Today your main model
re-invents verdict criteria, root-cause heuristics, and design calls every
session. Move the reusable ~80% of that judgment into frontier-authored
rubrics, decision records, and schemas once, and your main model is left with
orchestration plus the genuinely-novel call. The tier shrinks because its
recurring work moved up into durable Tier-0 artifacts.

## Mission-critical override (do not skip)

The frontier model *writes the contract*; it does not get to *ship the prod
change*. Any production deploy, irreversible/hard-to-reverse action, or
customer-facing / money / billing / cert / DNS / fleet-state change still runs
on your **main model** with the user gating — regardless of how mechanical the
steps look, and even when a frontier-written runbook exists. A frozen artifact
lowers the reasoning cost of the decision; it does not remove the human gate on
the action. Never route mission-critical or irreversible actions to a cheap
model, no matter how mechanical the steps look.

## Anti-patterns

- **Feeding the frontier model raw repo reads (or raw doc dumps).** Compress
  first (Step 2). Burning frontier input tokens on file dumps is the most
  common waste.
- **Asking the frontier model for the finished work instead of the artifact.**
  Its leverage is the design/contract/rubric/plan; the cheap fleet produces the
  code, content, or analysis against it.
- **Spending the frontier tier on cheap-to-reverse work** (releases, i18n,
  ports, the reviews themselves). That's fleet work.
- **One frontier session, three unrelated goals.** One artifact per session.
- **Letting your main model re-derive a judgment it makes every week.** Codify
  it into a frontier-written artifact so the fleet can run it.

## Reference & template files

- `references/one-way-door-examples.md` — worked examples of one-way-door vs.
  cheap-fleet work across several domains (code, process, content, research,
  policy), plus how to build your own ranked shortlist for your active
  projects.
- `assets/fable-session-brief-template.md` — how to frame a frontier session so
  it outputs a durable artifact.
- `assets/context-pack-template.md` — the shape of the distilled context pack
  the cheap fleet builds in Step 2.
