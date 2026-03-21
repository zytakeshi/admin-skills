# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**admin-skills** is a Claude Code skills package (`zytakeshi/admin-skills`) providing sysadmin and DevOps automation workflows. Skills are installed via `npx skills add zytakeshi/admin-skills`.

## Architecture

Each skill is a single `SKILL.md` file inside `skills/<skill-name>/`. There is no executable code — skills are declarative markdown with YAML frontmatter (name, description, trigger phrases) followed by step-by-step instructions Claude executes at runtime.

### Current Skills

| Directory | Purpose |
|-----------|---------|
| `skills/deploy/` | SSH/SCP deployment with backup, drift detection, cache clearing, smoke testing |
| `skills/commit-push/` | Smart commit message generation, stage, commit, push in one step |
| `skills/create-pr/` | Full PR lifecycle: commit → push → create PR → wait for Codex review → fix → merge |

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

## Downstream Repos

`skills/create-pr/SKILL.md` is the single source of truth shared with the standalone `create-pr-codex-review` repo via symlink. When this file is updated, also commit and push in the downstream repo.

## Internationalization

README is maintained in three languages: `README.md` (English), `README.ja.md` (Japanese), `README.zh.md` (Chinese). Keep all three in sync when updating documentation.
