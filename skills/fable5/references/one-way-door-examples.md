# One-way-door examples

Worked examples of the Step 0 test from `SKILL.md`, across domains any project
might touch. Use these as a pattern to recognize your own one-way doors — not
as a literal checklist, since your actual candidates depend on what's in
flight in your own projects.

Ranked so the **top pattern has the highest amortization** (governs the most
downstream calls or unblocks the most work) — the same ranking logic you
should apply to your own shortlist.

| # | Pattern | Why it's a one-way door | Stays cheap-fleet |
|---|---------|--------------------------|--------------------|
| 1 | **Verification / ship-risk rubric + reviewer system prompt** | Governs your #1 recurring workflow (e.g. an adversarial multi-agent code review pipeline). One frontier session writes the grading rubric + verdict schema (confirmed / inflated / false-positive) + the system prompt the fleet runs on every review all week. Highest amortization — it governs *every future review*, not just one. | Every actual review run |
| 2 | **A service's public API / wire contract** | The shape a fleet of downstream consumers (other services, client apps, partner integrations) depends on. Changing it after consumers ship means a breaking-change migration, not a refactor. | Per-consumer wiring, mechanical adapter code |
| 3 | **A shared core library / config schema feeding multiple forks or clients** | THE abstraction other codebases build on (e.g. a config generator shared across CLI, web, and mobile clients). A schema change here fans out to the entire fork/consumer fleet — pure API-contract territory. | Per-fork adoption, parallel wiring |
| 4 | **A cross-language or cross-platform parity contract** | The exact byte/wire-format parity boundary (e.g. porting a core from one language to another, or keeping two independent implementations bit-compatible) defines everything downstream; get the shape wrong and you redo the whole port. | The translation itself, the parity test suite |
| 5 | **A new product/feature's data model** | A new tier, entitlement, or feature needs a new schema (DB tables, peer/user model). Data-model one-way door before the app-side build starts — changing it after data exists is expensive. | CRUD scaffolding, migration boilerplate |

## Do NOT spend the frontier tier on

These are cheap-to-reverse or mechanical — route to the cheap fleet instead:
- Release engineering: tag → bump downstream → deploy.
- i18n extraction / translation propagation.
- Per-fork ports of an already-decided change.
- Boilerplate scaffolding, searches, log/metric scans.
- **The code reviews themselves** — your review loop (e.g. `/codexloop`) runs
  on the cheap fleet against the frontier-written rubric (pattern #1), not on
  the frontier model.

## How to build your own ranked shortlist

1. List the in-flight decisions across your active projects — pull from
   whatever tracks that for you (a backlog, a roadmap doc, recent commits,
   open design docs).
2. For each candidate, apply the Step 0 one-way-door test in `SKILL.md`: is it
   expensive to reverse once data exists, clients ship, or the week ends?
3. Drop anything already shipped/decided; add new expensive-to-reverse
   decisions as they come up.
4. Re-rank by amortization — how many downstream calls, or how much blocked
   work, the artifact unlocks. Governing artifacts (rubrics, shared contracts)
   usually rank above one-off data models, since they shape *every* future
   run, not just the work directly downstream of them.
5. Treat the list as living — re-check it before every frontier session,
   since priorities and in-flight work shift.
