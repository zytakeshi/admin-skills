# One-way-door shortlist (Fable-worthy work)

This is a **living** list of the highest-amortization one-way doors across the
active portfolio. It goes stale — projects ship, priorities move. Before
recommending a target, refresh it: check `MEMORY.md` + recent memory files, run
`/recall` on the candidate, and confirm the item is still in-flight and still
un-decided.

Ranked so the **top item has the highest amortization** (governs the most
downstream calls or unblocks the most work). Re-rank on refresh.

| # | Fable target | Why it's a one-way door | Stays cheap-fleet |
|---|--------------|-------------------------|-------------------|
| 1 | **Verification / ship-risk rubric + codexloop system prompt** | Governs the user's #1 workflow (adversarial multi-agent audit). One Fable session writes the grading rubric + verdict schema (confirmed / inflated / false-positive) + the system prompt the fleet runs on every audit all week. Highest amortization. | Every actual review run |
| 2 | **V2bX-rust data-plane + live admin API contract** | From-scratch Rust reimpl forking cfal/shoes; the admin API shape + outbound abstraction are expensive to reverse post-fleet-deploy (the VMess-multi-user removal was already flagged a one-way door). | Per-protocol wiring, mechanical Rust translation |
| 3 | **vilanet-core config / generator contract** | THE shared abstraction feeding cli/openwrt/merlin. A schema change here fans out to the entire fork fleet — pure API-contract territory. | Per-fork adoption + parallel wiring |
| 4 | **VilaNet HarmonyOS core byte-parity contract** | The Dart-golden byte-parity boundary + crypto/adapter/apipath port *shape* define everything downstream; wrong here = redo the whole core. | The TS translation + the 259 tests |
| 5 | **WireGuard tier data model** | New product tier = new panel/peer schema. Data-model one-way door before the app-side build starts. | Panel CRUD, migration boilerplate |

## Do NOT spend Fable on

These are cheap-to-reverse or mechanical — route to the cheap fleet:
- Release engineering: tag core → bump downstream → deploy.
- i18n extraction / translation propagation.
- Per-fork ports of an already-decided change.
- Boilerplate scaffolding, searches, log/metric scans.
- **The code reviews themselves** — codexloop runs on the cheap fleet against
  Fable's rubric (item #1), not on Fable.

## How to refresh this list

1. Re-read `MEMORY.md` and the `project_*` memory files for in-flight work.
2. For each candidate, apply the Step 0 one-way-door test in `SKILL.md`.
3. Drop anything shipped/decided; add new expensive-to-reverse decisions.
4. Re-rank by amortization (how many downstream calls / how much blocked work the
   artifact unlocks), governing artifacts first.
