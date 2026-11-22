---
name: claude-context-sync
description: Sync Claude Code global/project context and selected Claude memory indexes into Codex-safe memory notes. Use when the user asks to keep Codex in sync with Claude, bridge CLAUDE.md to AGENTS.md, import Claude memory into Codex, create or run a redacted context sync, or verify that Claude/Codex context sync works end to end.
---

# Claude Context Sync

Use this skill to run a one-way, redacted sync from Claude context into Codex memory notes. Keep `~/.codex/AGENTS.md` Codex-native; do not symlink it to `~/.claude/CLAUDE.md`.

## Workflow

1. Preview the generated note:

   ```sh
   scripts/sync_claude_context_to_codex.py --project /path/to/project
   ```

   This prints to stdout by default. Persistent Codex memory writes require `--write`.

   For the user's usual project tree, discover project-level `CLAUDE.md` files under `~/gitrepo`:

   ```sh
   scripts/sync_claude_context_to_codex.py --gitrepo-root ~/gitrepo
   ```

2. Run the fixture-based end-to-end test after any edit:

   ```sh
   scripts/sync_claude_context_to_codex.py --self-test
   ```

3. For a real-data smoke test that does not touch memory, write to a temporary output directory:

   ```sh
   TMPDIR="$(mktemp -d)" &&
   scripts/sync_claude_context_to_codex.py --gitrepo-root ~/gitrepo --output-dir "$TMPDIR"
   ```

4. Review the generated note before relying on it. The script redacts credential-like material, but exact live values should still be fetched from source docs only at execution time.

5. After reviewing, write a persistent note explicitly:

   ```sh
   scripts/sync_claude_context_to_codex.py --gitrepo-root ~/gitrepo --write
   ```

## Rules

- Keep sync one-way: Claude sources are inputs, Codex memory notes are outputs.
- Do not auto-run this silently on shell startup. Manual or explicitly scheduled runs are safer because the output is persistent memory.
- Keep `~/.codex/skills -> ~/.claude/skills` as the shared-skill bridge when present.
- Store reusable code under this skill's `scripts/` directory, not as loose home-dir glue.
- Default runs are preview-only. Use `--write` for persistent memory, `--self-test` for fixture validation, and a temporary `--output-dir` for real-source smoke testing.
- Use `--gitrepo-root ~/gitrepo` for project-level `CLAUDE.md` discovery. It deduplicates by Git top-level when possible, searches to depth 5 by default, skips dependency/build/archive/worktree mirrors, and still includes nested scoped `CLAUDE.md` files in each discovered project.
- Do not import credentials, raw host inventories, customer identifiers, payment identifiers, raw transcript text, private key material, or live access details.
