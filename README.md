# admin-skills

A collection of sysadmin and DevOps skills for Claude Code.

## Install

```bash
npx skills add zytakeshi/admin-skills
```

Or install a specific skill:

```bash
npx skills add zytakeshi/admin-skills@deploy
```

## Available Skills

| Skill | Description |
|-------|-------------|
| [deploy](skills/deploy/) | Deploy files to remote servers via SSH/SCP with mandatory backup, drift detection, cache clearing, and smoke testing |

## Usage

After installing, use `/deploy` in Claude Code to trigger the deployment workflow.
