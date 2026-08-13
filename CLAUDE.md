# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**admin-skills** is a Claude Code skills package (`zytakeshi/admin-skills`) providing sysadmin and DevOps automation workflows. Skills are installed via `npx skills add zytakeshi/admin-skills`.

## Architecture

Each skill is a `SKILL.md` file inside `skills/<skill-name>/`, with YAML frontmatter (name, description, trigger phrases) followed by step-by-step instructions Claude executes at runtime. Most skills are pure declarative markdown; a few also bundle a `scripts/` directory with an executable helper (e.g. `skills/ask-grok/scripts/ask_grok.sh`). Skills that bundle scripts must reference them relative to the skill's own directory (not a hardcoded absolute path) so they resolve regardless of install location.

### Current Skills

Skill list: see `skills/*/SKILL.md` frontmatter (this table went stale; frontmatter is authoritative).

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
- ChatGPT browser UI / Google Chrome — ask-chatgpt-pro skill
- `grok`, `timeout`, optional `jq` — ask-grok skill
- `curl`, `rsync`, `lsof`, `pgrep`, Google Chrome (macOS) — cdp-chrome skill

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
