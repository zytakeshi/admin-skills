# One-way-door examples

Worked examples of the Step 0 test from `SKILL.md`, across domains any project
might touch — deliberately **not** all code. Use these as a pattern to
recognize your own one-way doors — not as a literal checklist, since your
actual candidates depend on what's in flight in your own projects.

The point of spanning domains: a one-way door is defined by **leverage ×
irreversibility**, not by whether the output is a schema. A taxonomy, a grading
rubric, or a research direction can be just as much a one-way door as an API
contract — and often has *higher* amortization.

Ranked so the **top pattern has the highest amortization** (governs the most
downstream calls or unblocks the most work) — the same ranking logic you should
apply to your own shortlist.

| # | Pattern | Domain | Why it's a one-way door | Stays cheap-fleet |
|---|---------|--------|--------------------------|--------------------|
| 1 | **Verification / grading rubric + reviewer system prompt** | Process | Governs your #1 recurring workflow (e.g. an adversarial multi-agent review pipeline, an eval harness, a triage flow). One frontier session writes the grading rubric + verdict schema (confirmed / inflated / false-positive) + the system prompt the fleet runs on every run all week. Highest amortization — it governs *every future run*, not just one. | Every actual run against the rubric |
| 2 | **A core interface / abstraction / contract others build on** | Code | The public surface a fleet of downstream consumers depends on — an API or wire contract, a shared library's boundary, a plugin interface, a cross-language/cross-platform parity contract. Changing it after consumers ship is a breaking-change migration, not a refactor. | Per-consumer wiring, adapters, the parity test suite |
| 3 | **A data / domain model or schema** | Code | The schema a new feature, tier, or entitlement needs (DB tables, domain/user model, event shape). A data-model one-way door before the build starts — changing it after data exists is expensive. | CRUD scaffolding, migration boilerplate |
| 4 | **A taxonomy, information architecture, or content model** | Content | The category system or navigation a large body of docs, a knowledge base, a help center, or a UI commits to. Re-slicing it later means re-tagging or re-writing everything already filed under the old shape. | Writing/filing each individual entry |
| 5 | **A research plan or product / positioning spec** | Strategy | The direction a multi-week effort or a fleet of experiments follows. Get the framing or the success metric wrong and every downstream experiment, doc, and build measures the wrong thing — you redo the body of work, not one task. | Running each experiment, drafting each doc |
| 6 | **A policy / set of principles / decision record** | Governance | The rule set that governs many future judgment calls — pricing/discount logic, a moderation or safety policy, a style guide, an "how we decide X" record. Cheap to write once; expensive to unwind after a week of decisions have assumed it. | Applying the policy to each case |

## Do NOT spend the frontier tier on

These are cheap-to-reverse or mechanical — route to the cheap fleet instead:
- Release engineering: tag → bump downstream → deploy.
- i18n extraction / translation propagation.
- Per-fork ports of an already-decided change.
- Boilerplate scaffolding, searches, log/metric scans, formatting.
- Applying an existing rubric/policy to individual cases (that's execution).
- **The reviews themselves** — your review loop (e.g. `/codexloop`) runs on the
  cheap fleet against the frontier-written rubric (pattern #1), not on the
  frontier model.

## How to build your own ranked shortlist

1. List the in-flight decisions across your active projects — pull from
   whatever tracks that for you (a backlog, a roadmap doc, recent commits, open
   design docs, an experiment plan). Include non-code decisions: content
   structure, policy, research direction.
2. For each candidate, apply the Step 0 one-way-door test in `SKILL.md`: is it
   expensive to reverse once data exists, consumers ship, a body of work
   commits to it, or the week ends?
3. Drop anything already shipped/decided; add new expensive-to-reverse
   decisions as they come up.
4. Re-rank by amortization — how many downstream calls, or how much blocked
   work, the artifact unlocks. Governing artifacts (rubrics, shared contracts,
   taxonomies) usually rank above one-off models, since they shape *every*
   future run, not just the work directly downstream of them.
5. Treat the list as living — re-check it before every frontier session, since
   priorities and in-flight work shift.
