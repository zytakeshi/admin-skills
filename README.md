# admin-skills

**[English](README.md)** | [日本語](README.ja.md) | [中文](README.zh.md)

---

A collection of sysadmin and DevOps skills for Claude Code. Automate deployments, git workflows, and code review — all from a single `/command`.

## Why Use These Skills?

- **`/deploy`** — Zero-downtime deployments with mandatory backups, drift detection, and automatic cache clearing. Never forget a rollback plan again.
- **`/commit-push`** — Analyzes your diffs, generates conventional commit messages, and safely pushes. No more "fix stuff" commits.
- **`/create-pr`** — Creates a PR and automatically gets it reviewed by [OpenAI Codex](https://chatgpt.com/codex). When the review completes, Claude reads the feedback, fixes the issues it agrees with, pushes the fixes, and asks you to merge — fully automated end-to-end.
- **`/html-specialist`** — Produces a single self-contained animated `.html` page (dark scrollytelling, CJK-safe, zero dependencies) that explains a concept, system, dataset, or product.
- **`/codex`** — Bridge to the OpenAI Codex CLI for code review, design consultation, bug investigation, security audits, and second opinions. Streams events as they arrive, captures the final answer to a per-invocation result file, and surfaces cross-cutting integration findings beyond the diff.
- **`/codexloop`** — Iterative review-and-fix loop with Codex. Codex reviews, Claude fixes the findings it agrees with, repeat until clean (or both sides reach an honest impasse). No fixed iteration cap.
- **`/codex-test`** — Offload a headless/unattended browser smoke or e2e test to the Codex CLI. It drives an isolated Playwright browser (or attaches to a logged-in Chrome session when one's required), may fix code and re-run until the flow passes, streams progress, and reports a PASS/FAIL verdict plus any changes it made.
- **`/fleet-review`** — Deploy 10–15 parallel read-only sub-agents to scan a codebase and produce a ranked audit report. Language-agnostic. Pure planning — no file modifications.
- **`/team`** — Orchestrate parallel agent teams to implement plans, specs, or multi-file tasks. Decomposes the work, spawns scoped teammates in tmux panes, coordinates outputs.
- **`/finish-translation`** — Auto-detect your project's i18n framework (ARB, JSON/i18next, .strings, .xcstrings, gettext, YAML/Rails, Android XML, .resx) and propagate, audit, or scan for hardcoded strings.
- **`/ask-grok`** — Consult Grok (xAI) for real-time web and X/Twitter knowledge using your existing X Premium / SuperGrok subscription (no API key). Routes "what's the latest on…", breaking news, newest tool versions, and "what are people saying on X about…" to Grok via the official Grok CLI, then shows the answer verbatim with its source links.
- **`/cdp-chrome`** — Run Chrome DevTools (CDP) browser automation **unattended** on Chrome 136+ by attaching to a dedicated, already-logged-in Chrome instance via `--browserUrl` — so the native "Allow remote debugging?" consent dialog never appears and `chrome-devtools-mcp` / Puppeteer / Playwright stop hanging on connect. Bundles a `cdp-chrome` helper (start / reseed / status / config). macOS.
- **`/fable5`** — Guide for spending a frontier-tier model session (e.g. Claude's Fable 5) well: decide if work is a "one-way door" worth the frontier tier, compress context first, have the frontier model write the governing artifact (PRD / contract / data model / rubric), then hand off implementation to `/codex` and verification to `/codexloop`.

> **Note (March 31, 2026):** Codex Code Review now counts toward your regular Codex usage limit instead of having a separate allowance. Heavy Code Review usage may cause you to reach your overall Codex limit sooner. See [OpenAI's announcement](https://chatgpt.com/codex) for details.

## Install

```bash
npx skills add zytakeshi/admin-skills
```

Or install a specific skill:

```bash
npx skills add zytakeshi/admin-skills@deploy
npx skills add zytakeshi/admin-skills@commit-push
npx skills add zytakeshi/admin-skills@create-pr
npx skills add zytakeshi/admin-skills@html-specialist
npx skills add zytakeshi/admin-skills@codex
npx skills add zytakeshi/admin-skills@codexloop
npx skills add zytakeshi/admin-skills@codex-test
npx skills add zytakeshi/admin-skills@ask-chatgpt-pro
npx skills add zytakeshi/admin-skills@fleet-review
npx skills add zytakeshi/admin-skills@team
npx skills add zytakeshi/admin-skills@finish-translation
npx skills add zytakeshi/admin-skills@ask-grok
npx skills add zytakeshi/admin-skills@cdp-chrome
npx skills add zytakeshi/admin-skills@fable5
```

## Available Skills

| Skill | Description |
|-------|-------------|
| [deploy](skills/deploy/) | Deploy files to remote servers via SSH/SCP with mandatory backup, drift detection, cache clearing, and smoke testing |
| [commit-push](skills/commit-push/) | Analyze changes, generate a commit message, stage, commit, and push in one step |
| [create-pr](skills/create-pr/) | Full PR lifecycle: commit, push, create PR, wait for Codex review, fix issues, and merge |
| [html-specialist](skills/html-specialist/) | Build a single self-contained animated HTML explainer — scrollytelling, CJK-safe, zero dependencies |
| [codex](skills/codex/) | Bridge to OpenAI Codex CLI for code review, design consultation, security audits, and second opinions — with streaming progress |
| [codexloop](skills/codexloop/) | Iterative review-and-fix loop with Codex: review → fix → re-review until clean or honest impasse |
| [codex-test](skills/codex-test/) | Offload a headless/unattended browser smoke or e2e test to the Codex CLI — Playwright-first (isolated browser), may fix code and re-run, reports PASS/FAIL |
| [ask-chatgpt-pro](skills/ask-chatgpt-pro/) | Consult the GPT Pro model in the ChatGPT browser UI for important specs, architecture/migration decisions, comparisons, source-backed research, or critique — then verify and adapt locally |
| [fleet-review](skills/fleet-review/) | Deploy 10–15 parallel read-only sub-agents to audit a codebase. Pure planning, no file modifications. Language-agnostic |
| [team](skills/team/) | Orchestrate parallel agent teams: decompose work, spawn scoped teammates in tmux panes, coordinate outputs |
| [finish-translation](skills/finish-translation/) | Auto-detect your i18n framework and propagate / audit / scan for hardcoded strings across all locales |
| [ask-grok](skills/ask-grok/) | Consult Grok (xAI) for real-time web + X/Twitter knowledge via the official Grok CLI (subscription OAuth, no API key) — latest releases, breaking news, social pulse, answers shown verbatim with source links |
| [cdp-chrome](skills/cdp-chrome/) | Run Chrome DevTools (CDP) automation unattended on Chrome 136+ — attach to a dedicated, logged-in Chrome via `--browserUrl` so the "Allow remote debugging?" dialog never appears; bundles a `cdp-chrome` helper (start / reseed / status / config). macOS |
| [fable5](skills/fable5/) | Guide for spending a frontier-tier model session well — one-way-door test, context-pack compression, spawn-as-sub-agent-then-return pattern, handoff to `/codex` + `/codexloop` |

## Usage

After installing, use the skills in Claude Code:

- `/deploy` — trigger the deployment workflow
- `/commit-push` — analyze, commit, and push changes
- `/create-pr` — create a PR with automated Codex code review
- `/html-specialist` — build a single-file animated HTML explainer
- `/codex` — call OpenAI Codex CLI for review / consultation
- `/codexloop` — iterative codex review-and-fix loop until clean
- `/codex-test` — offload a headless browser smoke / e2e test to Codex
- `/ask-chatgpt-pro` — consult the GPT Pro model in the ChatGPT browser UI for high-stakes decisions and research
- `/fleet-review` — parallel codebase audit with 10–15 read-only sub-agents
- `/team` — spawn an agent team to implement a multi-file task
- `/finish-translation` — sync / audit translations across all locales
- `/ask-grok` — get live web / X answers from Grok, shown verbatim with sources
- `/cdp-chrome` — set up unattended Chrome DevTools automation (dedicated logged-in Chrome, no permission dialog)
- `/fable5` — decide whether work is worth a frontier-tier model session, and how to spend it well

## See Also

- [sing-box-skills](https://github.com/zytakeshi/sing-box-skills) — Building sing-box from source + converting v2ray/clash subscriptions to Sing-box configs
- [statusline4claudecode](https://github.com/zytakeshi/statusline4claudecode) — A custom status line for Claude Code that displays real-time token usage, cost, and model info
