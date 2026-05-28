---
name: fleet-review
description: "Deploy a fleet of 10-15 parallel read-only agents to scan the codebase and produce a comprehensive, ranked audit report. Pure review and planning — no code changes. Use this skill when the user says /fleet-review, 'fleet review', 'deep audit', 'comprehensive review', 'scan everything', 'review the whole codebase', 'audit all files', 'what issues do we have', 'full code review', 'spawn agents to review', or any variation requesting a broad parallel codebase scan. Also trigger when the user wants a thorough analysis before deciding what to fix."
---

# Fleet Review

Deploy a fleet of parallel read-only agents to scan target directories and produce a comprehensive, ranked audit report. This skill is for **planning and assessment** — agents read and report only, zero file modifications.

Language-agnostic. Works for any codebase (Dart/Flutter, TypeScript/React, Python, Go, Rust, Ruby, Swift, Kotlin, etc.) — adapt the analyzer/linter commands and issue-type table to the project at hand.

## User Request

$ARGUMENTS

---

## 0. Parse Arguments

| Argument | Default | Description |
|----------|---------|-------------|
| `target` | project source root (`src/`, `lib/`, `app/`, etc.) | Directories to scan (space-separated) |
| `--type` / `-t` | `all` | Issue type(s) to scan for (comma-separated, or `all`) |
| `--depth` | `medium` | Scan depth: `quick` (grep-only), `medium` (grep + read key files), `deep` (read all files) |
| `--top` | `20` | Number of top issues to highlight in the summary |

### Issue Types (generic, language-agnostic)

| Type | What agents look for |
|------|---------------------|
| `analyzer-warnings` | Errors/warnings from the language's static analyzer (`flutter analyze`, `tsc --noEmit`, `mypy`, `cargo clippy`, `go vet`, `rubocop`, etc.) |
| `dead-code` | Unused imports, unreferenced symbols, unreachable code |
| `type-safety` | Loose typing (`dynamic`, `any`, `interface{}`, untyped catches), unsafe casts, missing type annotations |
| `error-handling` | Empty catch blocks, unhandled promises/futures/errors, swallowed exceptions, missing error boundaries |
| `deprecated-api` | Usage of APIs marked deprecated by the framework/runtime |
| `hardcoded-strings` | User-facing strings not going through i18n |
| `missing-translations` | Keys in the source-language file missing from other locale files |
| `ui-contrast` | Hardcoded colors instead of theme/token references, accessibility contrast issues |
| `architecture` | Service/dependency anti-patterns, circular dependencies, God objects, layering violations |
| `security` | Hardcoded secrets, unsafe deserialization, missing input validation, XSS/SQLi shapes |
| `all` | All of the above |

Add or remove types based on what matters for the project — this list is a starting menu, not a contract.

---

## 1. Pre-Scan Setup

### 1.1 Enumerate Files

Before spawning agents, map the target directory tree to plan agent assignments:

```bash
# Adjust the glob to the project's language
find <target> -type f \( -name "*.dart" -o -name "*.ts" -o -name "*.tsx" -o -name "*.py" -o -name "*.go" -o -name "*.rs" -o -name "*.swift" -o -name "*.kt" -o -name "*.rb" \) | wc -l
find <target> -type d | head -30
```

### 1.2 Run Static Analysis Upfront

If scanning for `analyzer-warnings` or `deprecated-api`, run the project's analyzer once and share the output with agents — saves them each re-running it:

```bash
# Pick the one for the project:
flutter analyze --no-pub 2>&1               # Flutter/Dart
tsc --noEmit 2>&1                           # TypeScript
mypy . 2>&1                                 # Python
go vet ./... 2>&1                           # Go
cargo clippy --all-targets 2>&1             # Rust
rubocop 2>&1                                # Ruby
swift build 2>&1 | grep -E 'warning|error'  # Swift
```

Save the output to a temp file and share its path with each relevant agent.

---

## 2. Fleet Deployment

### 2.1 Agent Count and Partitioning

Target **10-15 parallel sub-agents** depending on codebase size:

- **Small target (< 50 files):** 5-7 agents
- **Medium target (50-150 files):** 8-12 agents
- **Large target (150+ files):** 12-15 agents

Partition by assigning **specific directories or file lists** to each agent. Keep each agent's scope to **10-20 files max** — narrow scope produces more accurate findings. Don't give an agent the whole tree and tell it to figure out what to scan; give it a concrete file list or a leaf directory.

**Example partitioning (abstract — substitute your project's actual structure):**

| Agent | Assigned Scope |
|-------|---------------|
| 1 | `src/services/auth_service.*` + `src/services/session_service.*` |
| 2 | `src/services/api_*` + `src/services/network_*` |
| 3 | `src/services/storage_*` + `src/services/cache_*` |
| 4 | `src/services/` (remaining files not covered above) |
| 5 | `src/controllers/` + `src/state/` |
| 6 | `src/components/` |
| 7 | `src/widgets/` (or `src/views/`) |
| 8 | `src/settings/` + `src/config/` |
| 9 | `src/models/` + `src/types/` |
| 10 | `src/utils/` + `src/helpers/` |
| 11 | `src/i18n/` + `src/theme/` + `src/constants/` |
| 12 | Entry points: `src/main.*` + `src/app.*` + `src/router*.*` |

Adjust dynamically based on the actual `--target` and what files exist. The goal is **even coverage with no gaps and no overlap**.

### 2.2 Spawn All Agents in One Turn

**Spawn all agents simultaneously in a single message.** Use the `Agent` tool (or your harness's equivalent) with a code-reading agent type for each. These are read-only sub-agents — inline is correct here.

Each agent gets a prompt like:

> You are a code reviewer. Your assigned scope: `<file list or directory>`.
>
> Scan for: `<issue types>`
>
> For each issue found, output a finding in this exact format:
> ```
> FILE: src/path/to/file.ext
> LINE: 42
> SEVERITY: high
> TYPE: <issue-type>
> DESCRIPTION: <what the issue is>
> SUGGESTION: <how to fix it>
> EFFORT: trivial|small|medium|large
> ---
> ```
>
> Rules:
> - Read each file thoroughly. Only report issues you can verify by reading the code.
> - Do NOT modify any files.
> - For `analyzer-warnings`: use the pre-run analyzer output shared with you, don't re-run it.
> - Focus on issues that actually matter — skip trivial style preferences.
> - If a file is clean, say "SCOPE CLEAN: <file>" so I know you checked it.
> - End your report with a one-line summary: "Found N issues across M files."

### 2.3 While Agents Run — Prepare Report Template

While waiting for agents to complete, prepare the consolidation structure. Don't sit idle.

---

## 3. Consolidate Findings

### 3.1 Parse All Agent Reports

As agents return, parse their findings into a unified list. Each finding has:
- File, line, severity, type, description, suggestion, effort

### 3.2 Deduplicate

Remove duplicates where two agents reported the same `(file, line)` pair. Keep the finding with more detail.

### 3.3 Rank

Sort by:
1. Severity: `critical` → `high` → `medium` → `low`
2. Effort: `trivial` and `small` ranked higher than `large` at the same severity (easier wins first)
3. File path alphabetically as tiebreaker

### 3.4 Group by Theme

After ranking, group findings into themes for the report:
- Quick wins (high severity + trivial/small effort)
- Systemic issues (same problem appearing in 5+ files)
- Per-type breakdown

---

## 4. Report

Present a structured report:

```
# Fleet Review Report
Scanned: <target> | Agents: <N> | Files checked: <N> | Issues found: <total>

## Quick Wins (fix these first)
High/critical severity + trivial/small effort
1. [HIGH] src/services/foo.* :42 — <description> | Fix: <suggestion>
2. [HIGH] src/utils/bar.* :17 — <description> | Fix: <suggestion>
...

## By Severity
### Critical (N)
...
### High (N)
...
### Medium (N)
...
### Low (N)
...

## Systemic Issues
Patterns appearing across 3+ files:
- <pattern>: found in N files — <list top 5 examples>

## By Type
| Type | Count | Top File |
|------|-------|----------|
| analyzer-warnings | N | ... |
| dead-code | N | ... |
...

## Scope Coverage
| Agent | Files Checked | Issues Found | Status |
|-------|--------------|-------------|--------|
| Agent 1 | N | N | complete |
...

## Suggested Next Steps
Based on findings, recommended order of attack:
1. <highest-impact action>
2. <second action>
3. ...
```

**No files were modified.** Use a follow-up implementation pass (e.g., `/team`) to act on the findings.

---

## 5. Notes on Agent Behavior

- Sub-agents run inline (no team-orchestration needed) — just spawn them all with the agent tool in one message
- If an agent times out or returns no findings for its scope, note it in the coverage table and move on
- For `--depth quick`: agents grep only, no file reading → faster but may miss context-dependent issues
- For `--depth deep`: agents read every file in scope → thorough but slower; use for critical pre-release audits
