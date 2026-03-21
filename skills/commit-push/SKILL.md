---
name: commit-push
description: "Analyze all uncommitted changes, generate a comprehensive yet succinct commit message, stage, commit, and push in one step. Use this skill when the user says /commit-push, 'commit and push', 'push my changes', 'commit everything and push', 'ship it', 'save and push', or any variation requesting to commit and push changes together. Also trigger when user wants a smart commit message generated automatically."
---

# Commit & Push

Analyze all uncommitted changes in the repository, generate a high-quality commit message, stage relevant files, commit, and push — all in one fluid workflow.

## Step 1: Gather Context

Run these commands in parallel to understand the current state:

1. `git status` — see staged, unstaged, and untracked files (never use `-uall`)
2. `git diff` — unstaged changes
3. `git diff --cached` — staged changes
4. `git log --oneline -10` — recent commits for style matching
5. `git branch --show-current` — current branch name
6. `git rev-parse --abbrev-ref @{upstream} 2>/dev/null` — check if remote tracking exists

## Step 2: Validate

Before proceeding, check for these edge cases:

- **No changes at all**: If working tree is clean with nothing to commit, tell the user and stop.
- **No remote tracking branch**: If the branch has no upstream, you'll need to use `git push -u origin <branch>` later.
- **Sensitive files**: Never stage files matching these patterns — warn the user if they exist:
  - `.env`, `.env.*`
  - `credentials*`, `secrets*`, `*_secret*`
  - `*.pem`, `*.key`, `*.p12`, `*.keystore`
  - `serviceAccount*.json`
  - Any file already in `.gitignore`

## Step 3: Analyze Changes and Generate Commit Message

Study the diffs carefully. Identify:

- **What changed**: files added/modified/deleted, functions changed, configs updated
- **Why it changed**: the intent behind the changes — bug fix, new feature, refactor, build config, CI, docs, etc.
- **Scope**: which area of the codebase is affected (e.g., `api`, `auth`, `db`, `config`, `ci`, `ui`)

### Commit Message Format

Use conventional commits, matching the repository's existing style when possible:

```
<type>(<optional-scope>): <summary>
```

**Types**: `feat`, `fix`, `refactor`, `chore`, `docs`, `style`, `test`, `build`, `ci`, `perf`

**Rules for the summary line:**
- Imperative mood ("add", "fix", "update" — not "added", "fixes", "updated")
- Lowercase first letter after the colon
- No period at the end
- Under 72 characters
- Capture the "why" or high-level "what", not low-level details

**For multi-area changes**, use a summary line + bullet body:

```
fix: resolve race condition in cache invalidation and improve error logging
```

Or with a body for complex changes:

```
feat: add retry logic for failed webhook deliveries

- implement exponential backoff with configurable max attempts
- add dead letter queue for permanently failed deliveries
- log delivery failures with request context for debugging
```

## Step 4: Present and Confirm

Show the user:
1. A summary of files to be staged (grouped by status: new, modified, deleted)
2. The generated commit message
3. The target branch and remote

Ask for confirmation before proceeding. The user may want to:
- Edit the commit message
- Exclude certain files
- Abort entirely

## Step 5: Stage and Commit

Stage files explicitly by name — never use `git add -A` or `git add .` to avoid accidentally including sensitive files or large binaries. Group the add command sensibly.

Commit using a HEREDOC for proper formatting:

```bash
git commit -m "$(cat <<'EOF'
<commit message here>
EOF
)"
```

If a pre-commit hook fails:
- Read the error output
- Fix the issue (formatting, lint, etc.)
- Re-stage the fixed files
- Create a NEW commit (never amend)

## Step 6: Push

**Safety check for protected branches**: If the current branch is `main` or `master`, warn the user explicitly and ask for confirmation before pushing. Phrase it clearly: "You're about to push directly to main. Are you sure?"

Push the commit:
- If upstream exists: `git push`
- If no upstream: `git push -u origin <branch-name>`

After pushing, run `git status` to confirm everything is clean, and show the user the result.

## Behavior Notes

- If changes span many unrelated areas, suggest splitting into multiple commits instead of one giant commit. Ask the user.
- If there are both staged and unstaged changes, include everything unless the user previously staged specific files intentionally (check if there were already staged changes before this skill ran — if so, ask whether to include only staged or everything).
- Keep the entire flow interactive — the user should feel in control at every step, but the skill does the heavy lifting of analysis and message writing.
