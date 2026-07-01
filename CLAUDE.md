# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**admin-skills** is a Claude Code skills package (`zytakeshi/admin-skills`) providing sysadmin and DevOps automation workflows. Skills are installed via `npx skills add zytakeshi/admin-skills`.

## Architecture

Each skill is a `SKILL.md` file inside `skills/<skill-name>/`, with YAML frontmatter (name, description, trigger phrases) followed by step-by-step instructions Claude executes at runtime. Most skills are pure declarative markdown; a few also bundle a `scripts/` directory with an executable helper (e.g. `skills/ask-grok/scripts/ask_grok.sh`). Skills that bundle scripts must reference them relative to the skill's own directory (not a hardcoded absolute path) so they resolve regardless of install location.

### Current Skills

| Directory | Purpose |
|-----------|---------|
| `skills/deploy/` | SSH/SCP deployment with backup, drift detection, cache clearing, smoke testing |
| `skills/commit-push/` | Smart commit message generation, stage, commit, push in one step |
| `skills/create-pr/` | Full PR lifecycle: commit → push → create PR → wait for Codex review → fix → merge |
| `skills/html-specialist/` | Build a single self-contained animated HTML explainer (scrollytelling, CJK-safe, zero deps) |
| `skills/codex/` | Bridge to OpenAI Codex CLI for code review / consultation, with streaming progress and per-task ID result files |
| `skills/codexloop/` | Iterative Codex review-and-fix loop — review, fix agreed findings, re-review, until clean or stable impasse |
| `skills/codex-test/` | Headless/unattended browser smoke or e2e test delegation to Codex CLI, with Playwright-first browser driving and pass/fail reporting |
| `skills/fleet-review/` | Parallel codebase audit with 10–15 read-only sub-agents, language-agnostic, planning-only |
| `skills/team/` | Orchestrate parallel agent teams via `TeamCreate` + tmux-pane teammates, with integration validation |
| `skills/finish-translation/` | Multi-framework i18n: detect → audit → propagate / find hardcoded strings (ARB, JSON, .strings, .xcstrings, gettext, YAML, Android XML, .resx) |
| `skills/ask-grok/` | Consult Grok (xAI) for real-time web + X/Twitter knowledge via the official Grok CLI (subscription OAuth, no API key); bundles `scripts/ask_grok.sh` (handles `--always-approve`, retry, JSON output, search+cite default) |
| `skills/cdp-chrome/` | Run Chrome DevTools (CDP) browser automation unattended on Chrome 136+ — attach a CDP client (chrome-devtools-mcp/Puppeteer/Playwright) to a dedicated, logged-in Chrome via `--browserUrl` so the "Allow remote debugging?" dialog never appears; bundles `scripts/cdp-chrome` (start/reseed/status/config). macOS |
| `skills/fable5/` | Guide for spending a frontier-tier model session (e.g. Claude's Fable 5) well: one-way-door test, context-pack compression, spawn-as-sub-agent-then-return pattern, handoff to your cheap fleet for implementation and verification (pairs with `/codex` + `/codexloop`, or any equivalent) |

## Skill Authoring Conventions

- **Frontmatter**: `name` (kebab-case), `description` (include all trigger phrases — this is how Claude matches user intent to skill)
- **Safety-first**: Every skill that touches production must include backup/rollback steps. Never use `rm -rf`. Never stage `.env` or credential files.
- **Parallel where possible**: Group independent shell commands to run in parallel (e.g., `git status` + `git diff` + `git log`)
- **Explicit staging**: Always `git add <specific-files>`, never `git add -A` or `git add .`
- **Conventional commits**: Skills that create commits use the format `type: description` (feat, fix, refactor, chore, docs, style, test, perf, ci, build)

## External Tool Dependencies

- `git` — all skills
- `gh` (GitHub CLI) — create-pr skill
- `ssh`, `scp` — deploy skill
- `~/ssh/hosts.md` — deploy skill looks here for server connection details
- `curl`, `rsync`, Google Chrome (macOS) — cdp-chrome skill

## Downstream Repos

`skills/create-pr/SKILL.md` in **this repo** is the single source of truth. The standalone public repo `create-pr-codex-review` (`zytakeshi/create-pr-codex-review`) ships a **real-file copy** of it — not a symlink. (It used to be a committed symlink pointing at a local `admin-skills` path; that could not resolve for external `npx skills add` installs and silently masked content drift, so it was dereferenced.)

Because there is no longer a symlink, edits here do **not** auto-propagate. After updating `skills/create-pr/SKILL.md`, commit + push here, then manually sync the downstream repo:

```bash
SRC=/path/to/admin-skills/skills/create-pr/SKILL.md
DST=/path/to/create-pr-codex-review/skills/create-pr/SKILL.md
cp "$SRC" "$DST"
cmp "$SRC" "$DST" && echo "byte-identical"   # sanity check
cd "$(dirname "$DST")/../.." && git add skills/create-pr/SKILL.md && \
  git commit -m "chore(create-pr): sync SKILL.md with admin-skills" && git push
```

Keep the two files byte-identical (verify with `cmp` or matching `shasum -a 256`). Never re-introduce the symlink — it breaks external installs.

## Internationalization

README is maintained in three languages: `README.md` (English), `README.ja.md` (Japanese), `README.zh.md` (Chinese). Keep all three in sync when updating documentation.
