# Arming gates template

Referenced from `../SKILL.md` Steps 6–8. Defines the soak gates, the evidence that binds them to a
specific loop version, the audit log, the arm card, and the arm-transaction checklist. Nothing here
is armable until every gate below is met and the arm card is approved against a matching digest.

---

## Pre-registration (record BEFORE the soak starts)

Thresholds may never be chosen or relaxed after seeing the evidence.

- **`N`** = min organic proposals, each individually audited correct: ______
- **`M`** = min consecutive clean reconcile cycles against ground truth: ______
- **`D_min`** = min soak days before arming may be considered: ______
- **`D_deadline`** = day the soak escalates (`STALLED` → human) instead of waiting longer: ______
- **Audit window (start → end):** ______
- **Gate-policy hash (this document's policy version):** ______

> A material change to any gate value or policy resets the current-policy counters.

## Behavior-identity digest

The digest binds soak evidence to the exact behavior that produced it. Compute it over **everything
that changes behavior**, not just the loop's own source:

- loop code + config
- pinned runtime dependencies
- model / prompt / tool versions (for `hybrid` / `llm-agent` workers)
- supervisor policy (schedule, overlap, catch-up settings)

**Digest for this soak:** ______

> A material change to ANY component → new digest → counters reset → new soak. Soak evidence is
> **non-transferable across versions.** The arm card (below) may cite only evidence whose digest
> matches the digest being armed.

## Provenance tag scheme

Every ledger/run row carries exactly one tag. Gate counters count `ORGANIC` **only**.

| Tag | Meaning | Counts toward organic gate? |
|---|---|---|
| `ORGANIC` | real, in-the-wild proposal from a normal run | yes |
| `SMOKE_TEST` | any synthetic/test iteration — hand-run smoke runs and failure-injection alike | no (Gate 2 evidence) |
| `MANUAL_OPERATOR` | operator-triggered / bulk / batch action | no |

> Historical rows are judged against the **policy version in force when they were written** — a row
> from an older policy can neither certify nor fail the current policy. Re-trigger or re-scope the
> audit window instead of reusing stale rows.

## Gate 1 — organic evidence

- [ ] ≥ `N` organic proposals, each individually audited correct
- [ ] ≥ `M` consecutive clean reconcile cycles against ground truth
- [ ] ≥ `D_min` soak days elapsed
- [ ] Red-flag gate: zero unexplained executions · health green · config untouched · no unexplained/unresolved errors

## Gate 2 — synthetic resilience

The `../SKILL.md` Step 5 failure-injection matrix must pass, evidenced by `SMOKE_TEST` rows from the
isolated (non-production) target. Synthetic rows never satisfy Gate 1, but a failed resilience test
**blocks arming**. A case that genuinely does not apply (e.g. mutation/rollback tests for a
`read-only` loop) may be marked **N/A with a one-line reason** — an unexplained blank is a fail.

- [ ] timeout · [ ] overlap · [ ] malformed input · [ ] permission failure · [ ] dependency outage
- [ ] notification failure · [ ] disk pressure · [ ] restart mid-run · [ ] partial mutation + rollback
- [ ] clock: DST · missed run · catch-up

## STALLED deadline

- [ ] If gates are not met by `D_deadline` days, emit `STALLED` and hand the decision to a human.

> A gated loop that can wait forever silently is its own failure mode.

## Audit-log format

Append-only, one row per audited proposal:

```
timestamp | run_id | provenance_tag | behavior_digest | proposed_action | ground_truth |
audit_verdict(correct|incorrect|ambiguous) | auditor | policy_version | notes
```

- An `ambiguous` verdict is **not** a pass — it blocks arming until resolved (see arm card / Step 7).
- Rows with mismatched `behavior_digest` do not count toward the digest being armed.

## Arm card (bound to a digest)

Approving this card approves the digest named in it, and nothing else.

```
ARM CARD
  loop name:              ______
  behavior digest armed:  ______   (must match every cited evidence row)
  gate-policy hash:       ______   (the policy the evidence was judged under)
  risk class:             read-only | reversible-mutating | high-risk
  gates met:              N=__/__  M=__/__  D_min=__/__  red-flag: pass/fail
  resilience matrix:      pass/fail
  audits (organic):       __ correct / __ audited   ambiguous: __ (must be 0)
  reconcile cycles:       __ clean consecutive
  rollback tested:        yes/no + location
  blast radius:           ______
  approval:               human name + timestamp  (REQUIRED for every arm of a NEW behavior
                          digest of a high-risk loop; restart/recovery of the same approved
                          terminal digest is not a new arm)
                          OR auto-arm delegation ref (scope/limits/expiry/hash/revocation;
                          below high-risk only)
```

> On any ambiguous audit → **BLOCK, don't arm** (blocking is reversible; a wrong arm is not).
> Notify with the specific unblock action.

## Arm-transaction checklist (mirrors `../SKILL.md` Step 8)

Persist an `ARMING` marker with an **operation ID** before step 4 (any mutation). Mutation completes
before, and independently of, notification.

1. [ ] Freeze the behavior-identity digest AND the gate-policy hash
2. [ ] Verify both exactly match the approved arm card
3. [ ] Take the arm lock
4. [ ] Snapshot
5. [ ] Stage new config **disabled**
6. [ ] Validate + read back staged state
7. [ ] Constrained one-shot canary iteration
8. [ ] Reconcile canary against ground truth
9. [ ] Full enable + read back **effective** state
10. [ ] **Atomic persist:** terminalize/self-disable the armer AND record notification intent in a durable outbox
11. [ ] Deliver notifications from the outbox

**Failure paths (two distinct cases):**
- **Synchronous failure** — a step fails while the transaction is running: disarm/rollback,
  preserve evidence, report `BLOCKED`.
- **Restart recovery** — the process died and finds `ARMING` (or anything short of step 10's
  terminal persist): **reconcile the effective state** — read back what actually got enabled —
  then complete forward **only if digest, approval, gates, and effective enablement all match**;
  anything else → rollback and `BLOCKED`. Never a blind replay.

After the terminal persist, a crash or delivery failure only delays a notification (delivery
retries on its own); it never replays or rolls back the mutation.
