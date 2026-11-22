# CLAUDE.md

**admin-skills** is a public Claude Code skills package (`zytakeshi/admin-skills`) of sysadmin and DevOps workflows, installed via `npx skills add zytakeshi/admin-skills`.

## Architecture

Each skill is `skills/<skill-name>/SKILL.md`: YAML frontmatter, then the steps Claude runs. Skill list: `skills/*/SKILL.md` frontmatter is authoritative. Some skills bundle a `scripts/` helper (e.g. `skills/ask-grok/scripts/ask_grok.sh`); reference it relative to the skill's own directory, never by absolute path, so it resolves wherever the package installs.

## Skill Authoring Conventions

- **Frontmatter**: `name` (kebab-case), `description` (what the skill does + the intent categories that should route to it; add a literal trigger phrase only when a real miss shows the categories did not catch it — descriptions ride in every session's skill listing)
- **Safety-first**: Every skill that touches production must include backup/rollback steps. Never use `rm -rf`. Never stage `.env` or credential files.
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

`skills/create-pr/SKILL.md` in **this repo** is the single source of truth. The standalone public repo `create-pr-codex-review` (`zytakeshi/create-pr-codex-review`) ships a **real-file copy** of it — not a symlink, because a symlink to a local `admin-skills` path cannot resolve for external `npx skills add` installs and hides content drift.

Edits here do **not** auto-propagate. After updating `skills/create-pr/SKILL.md`, commit + push here, then manually sync the downstream repo:

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
