---
name: codex-test
description: "Offload a headless / unattended / smoke / e2e TEST RUN to the OpenAI Codex CLI running autonomously: Codex drives a browser and is allowed to FIX code/tests/config and re-run until the flow passes; Claude assembles credentials + target URLs + success criteria first, streams progress, and reports the verdict plus any code changes. Codex prefers the Playwright MCP (isolated browser it logs into itself with the supplied creds — no native dialogs, never touches your real session) and only uses the chrome-devtools MCP when the test must reuse an already-logged-in Chrome session it can't reproduce headlessly. The write-enabled, browser-driving sibling of /codex (read-only review) and /codexloop (review-fix loop). Triggers on /codex-test, 'offload this test to codex', 'have codex run the e2e/smoke test', 'run the headless/browser test unattended', 'delegate the browser e2e/smoke test', 'unattended browser test', 'headless browser test'. DO NOT use — Claude KEEPS these itself — for tests needing live log monitoring/tailing during the run, interactive debugging (breakpoints, root-causing a flaky/unknown failure), or real-device / device-like iOS/Android testing (simulators, emulators, Xcode, Maestro, TestFlight); route those to webapp-testing / playwright / maestro-e2e."
---

You delegate a self-contained, unattended TEST RUN to the **OpenAI Codex CLI** (gpt-5.5, headless, write-enabled, browser-driving). Codex drives a browser and is allowed to FIX code to make the test pass. You assemble everything it needs up front, stream its progress, and report the verdict. This reuses the `/codex` machinery — same background-`--json`-Monitor pattern, same hang recovery — but **write-enabled and unsandboxed** (`--sandbox danger-full-access`, NOT read-only — a browser-driving run needs Chromium's normal multiprocess model, which the macOS seatbelt blocks; see Step 3) and **browser-driving**.

> **Browser driver, in one line: prefer Playwright, fall back to chrome-devtools only for a logged-in session.** Playwright launches its **own isolated browser** that Codex logs into with the creds you supply — it never touches the user's real Chrome, and it grants browser permissions (notifications, geolocation, clipboard…) **programmatically**, so there are no native "Allow" dialogs to click. Use chrome-devtools **only** when the test genuinely needs an **already-authenticated** Chrome session that can't be reproduced headlessly (live SSO/2FA cookies, a session the human already has open) — and know that `--autoConnect` drives the user's **real** Chrome. ⚠️ **Do not rely on computer-use to click native "Allow" dialogs in unattended `codex exec`:** computer-use app-control is gated by an MCP approval *elicitation* that is **denied** with no human present (observed: `Computer Use approval denied via MCP elicitation for app 'com.google.Chrome'`). Designing the Playwright path to avoid native dialogs entirely is what makes the run actually unattended.

## User Request

$ARGUMENTS

---

## Step 0 — DECISION GATE: delegate or keep? (do this FIRST)

Classify the test. **Delegate to Codex ONLY** if it is headless / unattended / smoke / e2e and can run fully autonomously in a browser. **KEEP it yourself** (run via `webapp-testing` / `playwright` / `maestro-e2e`) if it needs ANY of:

1. **Live log monitoring** — tailing/interpreting streaming server or device logs *as the test runs*.
2. **Interactive debugging** — stepping, breakpoints, root-cause spelunking, bisecting a *flaky / unknown* failure.
3. **Real-device / device-like testing** — physical iOS/Android, simulators/emulators, Xcode, Maestro on a device, TestFlight install flows — anything tied to real hardware/sim state.

| DELEGATE to Codex (✅) | KEEP — Claude runs it (⛔) |
|---|---|
| Headless web e2e flow (login → checkout → confirm) | Anything on a real iPhone/Android or simulator/emulator → `maestro-e2e` |
| Browser smoke test of a staging/local URL | Tailing server/device logs to diagnose a failure live |
| "Deploy to staging then smoke-test it" (non-prod) | Debugging a flaky/unknown failure (breakpoints, bisect) |
| API e2e flow / endpoint contract check | Xcode / devicectl / TestFlight install + launch verification |
| UI flow verification via chrome-devtools/Playwright | Native-app behavior needing device/sim state |
| A staging admin-panel flow smoke test (create a record → verify it persists) | Root-causing a heisenbug from streaming diagnostics |

**Ambiguous?** Make a quick judgment, then **state which path you took and why** in one line. If you genuinely can't tell, ask the user ONE short question before proceeding. Never silently delegate a device/log/debug task. Prod deploys stay gated — Codex tests against staging/local only (your gated deploy skill owns prod).

---

## Step 1 — Assemble credentials & context (the heart of this skill: "point Codex to everything it needs")

Codex should not hunt for anything. Read the sources, extract the **concrete** values, and inject them into the prompt:

- **Target environment** — explicit base URL(s); staging vs local vs prod-admin path (e.g. an admin panel that lives behind a non-obvious path, not `/admin`); which Chrome / profile to drive.
- **Credentials** — read the relevant `.env`, host/credential config, and any `CLAUDE.md` (which often documents where creds live), then pass the **concrete** test-account username/password/tokens/API-keys Codex needs. Never make Codex grep for secrets.
- **Flows + success criteria** — the exact steps to exercise AND explicit, checkable definitions of "pass" (e.g. "after login, dashboard shows the user's email and `/api/me` returns 200"), plus any fixtures / test data.
- **Scope / guardrails** — Codex MAY fix code/tests/config and re-run, but stays inside the project + staging/local. It must **NOT deploy to production or touch prod data**. Honor repo safety rules: **never `rm`** (use `mv` to back up), back up before destructive Docker ops, don't commit.
- **Secrets hygiene** — put the constructed prompt (with the concrete credentials) in a `0600` temp file under `/tmp` (the `PROMPT_FILE` of Step 3) that is **NOT** inside the repo and **NOT** committed, and feed it to codex via stdin — never as a quoted CLI argument (argv is visible in `ps`/telemetry). Instruct Codex not to echo secrets into logs/artifacts/the result file. Never write credentials into the working tree.

> If creds are missing, or you can't determine the target URL / success criteria, **ASK before launching** — a test with no pass/fail definition is worthless.

**Prerequisites** (mention only if relevant / if a run fails on them): the Playwright MCP installs its own Chromium on first use (`npx @playwright/mcp@latest`, ~once). `chrome-devtools-mcp` (only the logged-in-session path) needs Chrome available — `--autoConnect` attaches to the running Chrome. computer-use (rarely needed, see below) needs macOS **Screen Recording + Accessibility** granted to the "Codex Computer Use" app **and** is still subject to a per-app approval elicitation that headless runs can't satisfy. If `codex` isn't installed, fall back to Claude's own `webapp-testing` / `playwright` path and say so.

---

## Step 1.5 — Pick the browser driver (decide BEFORE building the prompt)

This choice drives Step 2 and Step 3. Pick exactly one primary driver:

| Driver | Use it when | Why |
|---|---|---|
| **Playwright MCP — DEFAULT** | The test needs **no login**, OR you can hand Codex the **credentials to log in itself** (the common case). | Launches its **own isolated Chromium** — never touches the user's real Chrome/session. Logs in deterministically with the supplied creds. Grants browser permissions **programmatically** (`new_context(permissions=[…])` / a native Playwright script) so **no native "Allow" dialog ever appears**. Fully unattended. |
| **chrome-devtools MCP — EXCEPTION** | The test **must reuse an already-authenticated Chrome session** you cannot reproduce headlessly — live SSO/2FA cookies, a session the human already has open, a logged-in profile. | `--autoConnect` attaches to the user's **real running Chrome**. Only choose this when re-doing the login in a clean browser is impossible. ⚠️ It drives the human's live session/tab — scope tightly, never mutate their state, and expect that any native permission/consent dialog may **block** (computer-use can't reliably clear it unattended). |

**Default to Playwright.** Reach for chrome-devtools only when "already logged in" is an actual requirement of the test. If you start on chrome-devtools and it can't connect quickly (see Step 5), fall back to Playwright. State which driver you picked and why in your kickoff line.

---

## Step 2 — Build the Codex prompt

Compose a single prompt containing the Step-1 context (target, concrete creds, flows, success criteria, guardrails), then append this standing directive block:

```
You are running an UNATTENDED end-to-end / smoke test. Run it to completion without asking me anything.

HOW TO DRIVE THE BROWSER (driver chosen in the section above — honor it):
- PREFERRED — Playwright: drive an ISOLATED Playwright browser (Playwright MCP, or write/run a native Playwright script). Log in yourself with the credentials provided above. Do NOT attach to the user's existing Chrome. This is the default for any test where you have (or don't need) credentials.
- Grant any browser permission (notifications, geolocation, camera, clipboard, etc.) PROGRAMMATICALLY — e.g. a native Playwright `browser.new_context(permissions=[...])` / `context.grant_permissions([...], {origin})`, or the Playwright MCP's permission handling. Do NOT rely on clicking a native OS "Allow" bubble; avoid producing one. (Gotcha: assert the grant via `navigator.permissions.query({name})` — in HEADLESS Chromium the legacy `Notification.permission` getter can read "denied" even when the permission is truly granted; if a test must assert that specific legacy getter, launch HEADED isolated Chromium.)
- EXCEPTION — chrome-devtools: use it ONLY if this test was explicitly assigned the "reuse an already-logged-in Chrome session" path. It attaches to the user's real Chrome via --autoConnect; do not mutate their session state.
- Take screenshots at each key step and on every failure.

PERMISSION / "ALLOW" DIALOGS:
- The right move is to NOT create native dialogs: on the Playwright path, pre-grant permissions in the browser context so no OS "Allow" bubble appears. This is what keeps the run unattended.
- If a native GUI dialog still appears (mainly on the chrome-devtools path): your own codex approvals are suppressed, but OS/browser dialogs are not. You MAY try the computer-use MCP to screenshot + click Allow — but expect it to be DENIED in this unattended run (app-control needs an approval elicitation no human can accept here). If computer-use is denied or the dialog won't clear, STOP and report the blocking dialog as the finding; do NOT silently auto-grant via a CDP/devtools API to fake a pass.

YOU MAY FIX THINGS:
- You MAY edit code, tests, and config and re-run the test until it passes — OR until you conclude the failure is a genuine product bug you should not paper over.
- Stay inside this project + the staging/local target. NEVER deploy to production or mutate production data. Never run `rm` (move files aside with `mv` to back up). Back up before any destructive Docker operation. Do not commit anything. Never write credentials into the repo or logs.

REPORT AT THE END:
- PASS/FAIL per flow, against the success criteria.
- Every fix you made, as file:line + a one-line reason.
- Any product bug you could NOT fix, with concrete evidence (console/network/log excerpt, screenshot path).
- Paths to all screenshots / artifacts you produced.

No confirmation or questions needed. Proceed autonomously to a verdict.
```

---

## Step 3 — Invoke Codex (WRITE-enabled, browser-driving, background, streaming)

The key divergence from `/codex`: **never `--sandbox read-only`** (Codex must fix code + drive a browser). Use **`--sandbox danger-full-access`** — *not* `workspace-write`. Browser automation launches Chromium, and Chromium's normal **multiprocess** model needs Mach service registration that the macOS Seatbelt sandbox (`workspace-write`) **denies** — a codex-launched Playwright/Chromium dies with a Mach-bootstrap error before the first page, and the only workaround under the sandbox (`--single-process`) is flaky (some web APIs like `Notification.permission` misbehave). Disabling the OS sandbox lets Chromium run normally. With `approval_policy="never"` already set, Codex runs fully unattended; the **prompt-level guardrails** (no prod, no `rm`, no commit, stay in project + staging/local) are the safety envelope in place of the OS sandbox. (MCP-driven browsers run as separate server processes *outside* the seatbelt, so they're less affected — but the native-Playwright path Codex falls back to is not, which is why `danger-full-access` is the right default for this browser-driving skill.)

Derive a per-invocation `TASK_ID = test_<slug>_$(date +%Y%m%d_%H%M%S)` and use it for ALL output paths — never hardcode `/tmp/codex_test_result.txt` (collisions across concurrent runs, and with `/codex`'s own files). Run **in the background** (`run_in_background: true`):

```bash
TASK_ID=test_<slug>_$(date +%Y%m%d_%H%M%S)
PROMPT_FILE=/tmp/codex_test_prompt_${TASK_ID}.md
umask 077          # PROMPT_FILE holds injected credentials → 0600
# Write the fully-constructed prompt (Step 1 context + Step 2 directive block) to
# "$PROMPT_FILE" WITHOUT printing it to the terminal (use the Write tool, or a heredoc).
codex exec --json --sandbox danger-full-access --skip-git-repo-check \
  -c model_reasoning_effort=high -c service_tier=priority \
  -c mcp_servers.playwright.enabled=true \
  -c mcp_servers.chrome-devtools.tools.new_page.approval_mode=auto \
  -c mcp_servers.chrome-devtools.tools.take_snapshot.approval_mode=auto \
  --cd <project_directory> \
  -o /tmp/codex_test_result_${TASK_ID}.txt \
  - < "$PROMPT_FILE" 2>&1 | tee /tmp/codex_test_events_${TASK_ID}.jsonl
```

> **Why the prompt goes through a file, not an argv string:** Step 1 injects concrete credentials into the prompt. Passing that as a CLI argument would expose secrets in `ps`/process listings and tool telemetry. Write the fully-constructed prompt (Step 1 context + Step 2 directive block) to `PROMPT_FILE` with `umask 077` first, then feed it via `codex exec … - < "$PROMPT_FILE"` (the `-` tells codex to read instructions from stdin; stdin EOFs when the file ends, so this preserves the stdin-hang prevention — no separate `</dev/null` needed). Never `echo`/`cat` the prompt to a terminal or log.

**Flag rationale (do not deviate):**

| Flag | Why |
|------|-----|
| `--sandbox danger-full-access` | Codex needs to fix code, run the server/test, **and launch a browser**. `read-only` blocks writes; `workspace-write` (the macOS Seatbelt) **blocks Chromium's multiprocess Mach registration** → a codex-launched browser dies with a Mach-bootstrap error before the first page (verified). `danger-full-access` disables the OS sandbox so Chromium runs normally. Safety comes from the prompt guardrails (no prod / no `rm` / no commit), not the sandbox. Valid `--sandbox` values: `read-only`, `workspace-write`, `danger-full-access`. |
| `-c mcp_servers.playwright.enabled=true` | **Enables the DEFAULT driver.** The Playwright MCP is registered-but-disabled in `~/.codex/config.toml`; this turns it on for the run (bare `true` parses as a TOML boolean — verified it enables Playwright). This is the isolated-browser path Codex should use whenever it has/needs no creds. Keep this on for nearly every run. |
| `-c mcp_servers.chrome-devtools.tools.new_page.approval_mode=auto` / `…take_snapshot.approval_mode=auto` | Only matters on the **chrome-devtools exception path** (already-logged-in session). `~/.codex/config.toml` sets these two chrome-devtools tools to `approval_mode="approve"`, which would stall an unattended drive on Codex's *own* tool-approval prompt. In codex-cli 0.142.3 the **valid per-tool values are `auto`, `prompt`, `approve`** — set `auto` for unattended runs. ⚠️ `never` is **not** a valid per-tool `approval_mode` and makes config loading **fail** (verified on 0.142.3). The hyphen in `chrome-devtools` needs no quoting in the dotted `-c` path. Harmless to leave in on Playwright-only runs. |
| `- < "$PROMPT_FILE"` (stdin) | Feeds the prompt from a `0600` temp file instead of an argv string, so **injected credentials never appear in `ps`/argv/telemetry**. `-` tells codex to read instructions from stdin; the file EOFs immediately, so it also **prevents the "Reading additional input from stdin…" hang** (the #1 codex wedge) — no separate `</dev/null` needed. Never pass the credential-bearing prompt as a quoted CLI argument. |
| (no `--full-auto`) | Deprecated; hangs with `--json`. Not needed — `approval_policy="never"` already gives unattended behavior. |
| `--json` + background + `tee` | Stream JSONL events for Monitor and capture for the post-mortem. |
| `-c model_reasoning_effort=high` / `-c service_tier=priority` | Lower latency, no quality loss; never drop reasoning below `high` to "go faster". |
| `--skip-git-repo-check` / `--cd` / `-o` | Run from any dir / target dir / capture the final verdict message. |

Use a **generous Bash timeout — up to `600000` ms**; e2e runs are long.

---

## Step 4 — Stream progress with Monitor

Reuse the shared, task-agnostic filter the `/codex` skill defines at `/tmp/codex_progress_filter.py` (reference it; only recreate it from the `/codex` skill if the file is missing). Launch the `Monitor` tool on:

```bash
tail -n +1 -f /tmp/codex_test_events_${TASK_ID}.jsonl | python3 -u /tmp/codex_progress_filter.py
```

Surface one-line updates (session started / running `<cmd>` / browser step / screenshot / fix applied / finished exit N) — **don't dump raw JSON**. Push-based; don't sleep-poll. When the completion notification fires, `TaskStop` the Monitor (`tail -f` never exits on its own) and the background Bash task.

---

## Step 5 — Hang detection & auto-recovery (do it yourself, don't wait)

Same failure mode and recovery as `/codex` — apply that skill's "Hang detection & auto-recovery" section. In brief:

- **Detect:** zero JSONL events after ~2 min, OR the codex process is `S` (sleeping) with `cputime` stuck near `0:00` while `etime` climbs, OR Monitor emits nothing for >2 min.
- **Recover:** kill *this run's* tree first, not every codex on the box — concurrent `/codex` / `/codexloop` / other `/codex-test` runs may be live. Prefer the background Bash task's PID (`TaskStop` it), or target by the unique TASK_ID — the result path is in codex's argv, so `pkill -9 -f "codex_test_result_${TASK_ID}" 2>/dev/null` kills this run's codex process, and `pkill -9 -f "codex_test_events_${TASK_ID}" 2>/dev/null` clears its `tee`. Only fall back to the blunt `pkill -9 -f "codex exec"` if no task-specific PID can be identified. Then `TaskStop` the Monitor. **Retry ONCE** (a stuck stdin is the usual cause — the `- < "$PROMPT_FILE"` feed should already prevent it; re-confirm the file exists and EOFs).
- **If it hangs a second time:** stop fighting Codex. Tell the user Codex was unavailable and either (a) run the test yourself via `webapp-testing` / `playwright`, or (b) suggest they run it interactively with `! codex …` (interactive Codex avoids the headless stdin hang).

**Browser-path wedges (seen in practice):**
- **chrome-devtools connect wedge:** the very first chrome-devtools call (`list_pages` / first navigate) can hang for the full ~300s tool timeout when `--autoConnect` can't cleanly attach to Chrome — Monitor goes silent after an `mcp_tool_call` *started* with no *completed*, and codex sits `S` with flat cputime. This is the #1 reason to **prefer Playwright**. If you're on chrome-devtools and see this, abort and **re-run on the Playwright isolated-browser path** (which doesn't depend on the user's Chrome). Note: a single `codex exec` run only spawns the MCP servers it needs and tears them down on exit — long-lived `chrome-devtools-mcp` processes on the box usually belong to the user's Codex.app, **not** your run; don't kill those.
- **Native dialog wedge:** if a real OS/browser "Allow" dialog appears and computer-use can't clear it (the expected unattended outcome — `Computer Use approval denied via MCP elicitation`), codex will stall. Don't wait it out: this means the chosen flow needs a native click that can't happen unattended — re-architect to the Playwright programmatic-permission path, or tell the user this specific flow needs a human/interactive `! codex …` run.
- **Chromium won't launch (macOS sandbox):** errors mentioning *Mach bootstrap / service registration*, or a Playwright/Chromium launch that dies before the first page, mean Codex was run under the Seatbelt — confirm the invocation used **`--sandbox danger-full-access`**, not `workspace-write`. (A `--single-process` Chromium launch can limp along under the sandbox but makes some web APIs like `Notification.permission` flaky — fix the sandbox flag instead.)

---

## Step 6 — Report the verdict

Read `/tmp/codex_test_result_${TASK_ID}.txt` (Codex's final message) and present:

```markdown
## Test Verdict (via Codex): PASS / FAIL / PARTIAL
**Target:** <url/env>   **Path taken:** delegated to codex (or: kept — reason)

### Flows
- <flow> — ✅ PASS / ❌ FAIL — <one-line evidence>

### Fixes Codex made (review these — uncommitted working-tree changes, NOT auto-committed)
- <file:line> — <what changed + why>

### Product bugs Codex could NOT fix
- <symptom> — <console/network/log evidence, screenshot path>

### Artifacts
- <screenshot / report paths>
```

Codex's edits are **real working-tree changes** — list them so the user can review. **Do NOT auto-commit.** To ship them, hand off to `/commit-push` or `/create-pr` (review with `/code-review` or `/codexloop`); any prod move goes through your gated deploy skill (e.g. `/deploy`) — this skill never touches prod.

---

## Sibling skills

- `/codex` — read-only code review/consultation (no writes, no browser).
- `/codexloop` — iterative review-then-fix loop until clean.
- `webapp-testing` / `playwright` — Claude's own browser testing (the KEEP path + the codex-unavailable fallback).
- `maestro-e2e` — real-device iOS/Android e2e (always KEEP — never delegate to codex-test).
- `deploy` — production deploys stay gated there, not in this skill.

---

## Examples

```
/codex-test run the staging login → checkout → confirm e2e flow on https://staging.example.com and fix anything that breaks
/codex-test offload the admin-panel smoke test to codex (admin URL + creds in .env), create a test record, verify it persists
/codex-test have codex run the headless signup → email-verify → dashboard flow on staging
/codex-test smoke-test the subscription/feed page in a real browser, fix it if it 500s
/codex-test run the API e2e flow against the staging base URL (creds in .env), pass = all 200s
```

**Counter-examples (this skill REFUSES → Claude keeps them):**
```
/codex-test run the iOS app login test on the simulator     → use maestro-e2e (real-device, not delegable)
/codex-test watch the server logs while reproducing the 502 → log-monitoring, keep it (webapp-testing + log tail)
/codex-test figure out why the e2e is flaky sometimes       → interactive debugging, keep it
```
