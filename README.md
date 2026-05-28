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
- **`/fleet-review`** — Deploy 10–15 parallel read-only sub-agents to scan a codebase and produce a ranked audit report. Language-agnostic. Pure planning — no file modifications.
- **`/team`** — Orchestrate parallel agent teams to implement plans, specs, or multi-file tasks. Decomposes the work, spawns scoped teammates in tmux panes, coordinates outputs.
- **`/finish-translation`** — Auto-detect your project's i18n framework (ARB, JSON/i18next, .strings, .xcstrings, gettext, YAML/Rails, Android XML, .resx) and propagate, audit, or scan for hardcoded strings.

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
npx skills add zytakeshi/admin-skills@fleet-review
npx skills add zytakeshi/admin-skills@team
npx skills add zytakeshi/admin-skills@finish-translation
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
| [fleet-review](skills/fleet-review/) | Deploy 10–15 parallel read-only sub-agents to audit a codebase. Pure planning, no file modifications. Language-agnostic |
| [team](skills/team/) | Orchestrate parallel agent teams: decompose work, spawn scoped teammates in tmux panes, coordinate outputs |
| [finish-translation](skills/finish-translation/) | Auto-detect your i18n framework and propagate / audit / scan for hardcoded strings across all locales |

## Usage

After installing, use the skills in Claude Code:

- `/deploy` — trigger the deployment workflow
- `/commit-push` — analyze, commit, and push changes
- `/create-pr` — create a PR with automated Codex code review
- `/html-specialist` — build a single-file animated HTML explainer
- `/codex` — call OpenAI Codex CLI for review / consultation
- `/codexloop` — iterative codex review-and-fix loop until clean
- `/fleet-review` — parallel codebase audit with 10–15 read-only sub-agents
- `/team` — spawn an agent team to implement a multi-file task
- `/finish-translation` — sync / audit translations across all locales

## See Also

- [sing-box-skills](https://github.com/zytakeshi/sing-box-skills) — Building sing-box from source + converting v2ray/clash subscriptions to Sing-box configs
- [statusline4claudecode](https://github.com/zytakeshi/statusline4claudecode) — A custom status line for Claude Code that displays real-time token usage, cost, and model info
