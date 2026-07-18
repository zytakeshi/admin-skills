# Loop spec template

Fill one of these per automation loop before building it. Referenced from `../SKILL.md` Step 1;
the security and iteration sections are completed at Steps 3–4. Keep it beside the loop's code
and update it on every material change (a change resets the soak — see `../SKILL.md` Step 6).

---

## 1. Identity & owner

- **Name:**
- **Owner (human accountable for it):**
- **Runner / supervisor:** cron | launchd | systemd timer | scheduled-agent | daemon
- **Schedule / cadence:**
- **Purpose (one sentence — what one iteration achieves):**
- **Review / decommission date:**

## 2. Risk class

- **Class:** `read-only` | `reversible-mutating` | `high-risk`
- **What one iteration mutates:**
- **Blast radius of a *wrong* iteration:**
- **Ground truth it reads (source of record):**

## 3. Worker & supervisor (two independent choices)

- **Worker:** `script` | `hybrid` (deterministic collector + LLM analyst) | `llm-agent`
  - If `hybrid`/`llm-agent`: name the deterministic harness (timeout, max-runtime, journaling, locking) that wraps it.
- **Supervisor:** chosen on cadence · catch-up/coalescing on missed runs · overlap behavior · restart supervision · host sleep/reboot behavior · user/session requirements · resource limits.
- **Why this worker/supervisor pair** (one line):

## 4. Environment semantics

- **Timezone + DST behavior (double/skipped hour):**
- **Clock-skew tolerance / jitter:**
- **Absolute paths · working directory:**
- **`PATH` · locale · `umask`:**
- **Service identity (user it runs as):**
- **CPU / memory / disk limits:**

## 5. Security contract

- **Dedicated least-privilege identity/token:**
- **Secret source (protected storage — NOT argv/prompt/ledger/notification/committed config):**
- **Rotation / revocation procedure:**
- **Log/journal redaction rules · retention:**
- **LLM trust boundary (if `hybrid`/`llm-agent`):** external content treated as untrusted; model produces **proposals only**; deterministic allowlist/schema/policy validates every side effect; model has no shell, no credential expansion, no kill-switch access, no direct mutation.

## 6. Iteration mechanics

- **Overlap policy:** `skip` | `coalesce` | `queue` | `safe-parallel`
- **Lock/lease + stale-lock recovery (fencing if distributed):**
- **Timeout behavior:** kills whole process tree, releases lock
- **Idempotency key + atomic checkpointing:**
- **Retry classes:** retryable vs permanent · backoff + jitter · rate-limit/cost ceiling · circuit breaker
- **Compensation:** compensating action, OR marked **explicitly non-compensable** → prevention (bounded blast radius, canary, reconciliation, stronger approval)
- **Max-runtime cap → `ABORTED`:**
- **Cooldowns on external-facing actions (e.g. multi-day per-target notify cooldown):**
- **Config read via the owning app's loader (never regex):** yes/how
- **Untrusted input passed via argv/stdin/file, never interpolated into a shell string:** yes

## 7. Observability

- **Run record fields:** `run_id` · `scheduled_for` · policy/runbook version · provenance tag (`ORGANIC` | `SMOKE_TEST` | `MANUAL_OPERATOR`) · start/end · duration · outcome · exit code · action/idempotency key
- **Log rotation · retention · permissions · disk cap:**
- **External missed-run / dead-man / freshness monitor** (last-success timestamp + alert threshold — a loop cannot detect its own missed launch):
- **SLO:** low-risk → missed-run/failure-streak threshold; critical → explicit success/freshness objective

### Fail-open vs fail-closed (per failure mode)

For each failure mode, name the **protected invariant** and the **worst incorrect action**:

| Failure mode | Protected invariant | Worst wrong action | Verdict |
|---|---|---|---|
|  |  |  | fail-closed / fail-open-loud |

Rule: a guard that **authorizes** a mutation **fails closed**. Only a non-blocking observer whose
failure leaves the primary operation independently safe may **fail open — loudly**. Then record what
becomes **load-bearing**: any dependency whose failure stops production work must itself be monitored.

## 8. Notification matrix (four state fields — never conflated)

- **`run_outcome`** (per iteration): `SUCCEEDED` · `SKIPPED` · `RETRYABLE_FAILED` · `PERMANENT_FAILED` · `ABORTED`
- **`control_state`** (lifecycle): `DRY_RUN` · `SOAKING` · `ARMED` · `BLOCKED` · `STALLED` · `DISABLED`
- **`notification_intent`:** `NONE` (healthy-but-gates-unmet) · `INFO` (control-state change) · `PAGE` (actionable failure now)
- **`notification_delivery`:** tracked + retried separately from outcome/control state

| Event | intent | Channel |
|---|---|---|
| first-run-OK / ARMED / BLOCKED / STALLED | INFO |  |
| actionable failure a human must act on now | PAGE |  |
| healthy, gates unmet | NONE | — |

## 9. Kill switch

- **One-liner to stop the loop immediately:**
- **Who can invoke it · where documented:**

## 10. Rollback

- **Snapshot location:**
- **Disable/rollback procedure (written AND tested before first enable):**
- **Runbook path:**

## 11. Registry entry

- **Registered disabled in:** control plane | portable manifest (name · runner · schedule · status · owner)
- **On-disk-but-unregistered = drift:** confirmed registered

## 12. Auto-arm delegation record (only if auto-arm is intended, below high-risk)

- **Exact scope:**
- **Limits:**
- **Expiry:**
- **Approved policy hash:**
- **Revocation path:**

> High-risk loops (money, security, destructive, customer-facing, broad-production) cannot be
> auto-armed — **every arm of a new behavior-identity digest** requires explicit human approval
> at arm time (a changed digest is a new arm; restart/recovery of the same approved terminal
> digest is not).
