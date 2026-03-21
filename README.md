# admin-skills

**[English](README.md)** | [日本語](README.ja.md) | [中文](README.zh.md)

---

A collection of sysadmin and DevOps skills for Claude Code. Automate deployments, git workflows, and code review — all from a single `/command`.

## Why Use These Skills?

- **`/deploy`** — Zero-downtime deployments with mandatory backups, drift detection, and automatic cache clearing. Never forget a rollback plan again.
- **`/commit-push`** — Analyzes your diffs, generates conventional commit messages, and safely pushes. No more "fix stuff" commits.
- **`/create-pr`** — Creates a PR and automatically gets it reviewed by [OpenAI Codex](https://chatgpt.com/codex). Codex review uses a **separate quota** from your ChatGPT subscription — it does NOT consume your normal Codex task limits. Free, high-quality AI code review on every PR. When the review completes, Claude reads the feedback, fixes the issues it agrees with, pushes the fixes, and asks you to merge — fully automated end-to-end.

## Install

```bash
npx skills add zytakeshi/admin-skills
```

Or install a specific skill:

```bash
npx skills add zytakeshi/admin-skills@deploy
npx skills add zytakeshi/admin-skills@commit-push
npx skills add zytakeshi/admin-skills@create-pr
```

## Available Skills

| Skill | Description |
|-------|-------------|
| [deploy](skills/deploy/) | Deploy files to remote servers via SSH/SCP with mandatory backup, drift detection, cache clearing, and smoke testing |
| [commit-push](skills/commit-push/) | Analyze changes, generate a commit message, stage, commit, and push in one step |
| [create-pr](skills/create-pr/) | Full PR lifecycle: commit, push, create PR, wait for Codex review, fix issues, and merge |

## Usage

After installing, use the skills in Claude Code:

- `/deploy` — trigger the deployment workflow
- `/commit-push` — analyze, commit, and push changes
- `/create-pr` — create a PR with automated Codex code review

## See Also

- [statusline4claudecode](https://github.com/zytakeshi/statusline4claudecode) — A custom status line for Claude Code that displays real-time token usage, cost, and model info
