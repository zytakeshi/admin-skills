---
name: team
description: Orchestrate agent teams to implement plans, specs, or large tasks. Automatically analyzes the work, determines optimal team composition (roles, number of agents), and spawns parallel agents with scoped responsibilities. Use this skill when the user types /team, asks to "use a team", "spin up agents", "implement this with agents", or has a multi-file task that would benefit from parallel execution. Also use proactively when a task clearly spans multiple independent domains (backend + frontend, multiple modules, code + tests).
---

# Agent Team Orchestrator

You are a team lead. Your job is to analyze a task, decompose it into parallel workstreams, spawn focused agents for each workstream, and coordinate their outputs into a coherent result.

## When to Use

- User types `/team` with a plan, spec, or task description
- User asks to "use agents", "spin up a team", or "implement in parallel"
- A task clearly spans 2+ independent workstreams that would benefit from parallel execution

## CRITICAL: Teammates ARE sub-agents — spawn them, then reap them

⚠️ **Harness note (verified 2026-08-10).** There is no longer a separate "agent team" mechanism. `TeamCreate`/`TeamDelete` do not exist in this build; `Agent`'s `team_name` is *"Deprecated; ignored. The session has a single implicit team"*; `ListAgents` describes what it returns as *"in-process subagents you spawned"*. **A `/team` teammate is a named sub-agent — nothing more.** Earlier versions of this file claimed teammates were separate tmux-pane processes and told you to shut them down with tools that no longer exist; those steps silently no-op'd, which is why teammates dangled forever.

What the `name` parameter still buys you is real and is the whole point: a named sub-agent is addressable via `SendMessage` and, critically, **stoppable via `TaskStop`**. An unnamed one is not. That is why naming is mandatory below.

The required workflow is:

1. `TaskCreate` — one task per workstream (no team creation step; the session has one implicit team)
2. `Agent` with a **`name`** parameter — spawns the teammate. Do NOT pass `team_name`; it is ignored.
3. Record every spawned agent's name/ID. You cannot dismiss what you did not record.
4. Wait for teammate messages (they arrive automatically)
5. **`TaskStop` on each recorded agent the moment it reaches ANY terminal state** (finished, crashed, rejected, stalled, or reclaimed) — this is the dismissal. Per agent, not only at the end.
6. `ListAgents` as the final gate — confirm none of your teammates are still listed. Any survivor gets `TaskStop` again before you report to the user.

⛔ Do NOT originate `SendMessage {"type": "shutdown_request"}` — the tool documents it as a legacy protocol and says not to originate it. ⛔ Do NOT call `TeamDelete`; it does not exist.

## Process

### Step 1: Analyze the Work

Read and deeply understand the task, plan, or spec provided. Identify:

1. **Workstreams** — Independent units of work that can run in parallel. Look for natural boundaries:
   - Backend vs. frontend vs. tests
   - Different modules or services
   - Different file types or layers (models, routes, UI components)
   - Infrastructure vs. application code
   - Different platforms (iOS, Android, web)

2. **Dependencies** — Work that MUST complete before other work can start. Only flag true blocking dependencies, not soft ones. Most things can run in parallel if agents are given clear interface contracts.

3. **Integration points** — Where the agents' outputs will need to connect (shared types, API contracts, import paths, database schemas).

### Step 2: Design the Team

Based on your analysis, define the team:

- **Team size**: Use the minimum number of agents needed. Typical range is 2-5. Don't create an agent for trivial work — fold it into a related agent's scope.
- **Agent roles**: Give each agent a clear, descriptive name based on what they own (e.g., "api-routes", "react-components", "test-suite"). Use kebab-case names — these become the teammate `name` parameter.
- **Scope boundaries**: Each agent gets a precise list of files/directories they own. No overlap — if two agents need to touch the same file, one agent owns it and the other gets explicit instructions about the interface.

Present the team plan to the user in a compact table:

```
Team Plan: [task summary]
| Agent (name) | Scope | Key Deliverables |
|--------------|-------|-----------------|
| [kebab-name] | [files/dirs owned] | [what they produce] |
```

Then immediately proceed to execution — do NOT wait for confirmation unless the task is ambiguous.

### Step 3: Spawn Teammates

**Step 3a: Create tasks** using `TaskCreate` for each workstream (all in parallel). There is no team-creation step — the session has one implicit team.

**Step 3b: Spawn ALL teammates simultaneously** in a single message using the `Agent` tool. Every Agent call MUST include:
- `name` — the teammate's kebab-case name, made **run-unique** (e.g. append a short run suffix). It is both the message address and the `TaskStop` handle.
- ⛔ Do NOT pass `team_name` — the parameter is documented as "Deprecated; ignored".

**Step 3c: Record every spawned agent's returned ID immediately**, as each call returns — not in a batch afterwards. If one spawn in the parallel batch fails, the ones that already succeeded are live and must still be recorded, or they can never be dismissed. This record is the cleanup list.

Each agent's prompt should contain:

1. **Their role, team name, and scope** — What they own and what they're building
2. **The relevant portion of the plan/spec** — Only what they need, not the entire plan
3. **Interface contracts** — Types, function signatures, API shapes they must conform to so their work integrates with other agents
4. **Task assignment** — Which task number(s) they own
5. **Validation instructions** — After implementing, they must:
   - Run the project's linter/formatter if one exists
   - Run type checking if applicable (tsc, pyright, mypy, dart analyze)
   - Fix any errors they introduced
   - Mark their task(s) as completed via `TaskUpdate`
   - Send a completion message to the team lead via `SendMessage`

**Agent prompt template:**

```
You are the [ROLE] teammate on the [WORKSTREAM] workstream implementing [TASK SUMMARY].

## Your Scope
You own these files/areas: [LIST]
Do NOT modify files outside your scope.

## Your Task
[SPECIFIC INSTRUCTIONS FROM THE PLAN]
You are assigned task #[N]: [TASK SUBJECT]

## Interface Contracts
[SHARED TYPES, API SHAPES, FUNCTION SIGNATURES that other agents depend on]

## When Done
1. Run linting/formatting: [COMMAND]
2. Run type checking: [COMMAND]
3. Fix any errors you introduced
4. Mark task #[N] as completed using TaskUpdate
5. Send a completion message to the team lead via SendMessage with a summary of files created/modified and any issues
```

### Step 4: Coordinate Results

Teammate messages arrive automatically — do NOT poll or check manually. Proceed once every teammate has either reported OR been judged terminal per the stall rule (a crashed agent never reports; waiting for it hangs cleanup forever):

1. **Review each teammate's report** — Check what they built, any issues flagged
2. **Validate integration points** — Verify that:
   - Import paths between teammates' files are correct
   - Shared types/interfaces match across boundaries
   - API contracts are consistent (request/response shapes)
   - No duplicate or conflicting code
3. **Fix integration issues** — If teammates produced inconsistent outputs, fix them directly. Common issues:
   - Mismatched import paths
   - Type mismatches at boundaries
   - Missing exports
4. **Run project-wide checks** — Execute linting, type checking, and tests across the full project (not just individual scopes)
5. **Dismiss teammates** — `TaskStop` on each recorded agent, per agent, as soon as it reaches ANY terminal state. Terminal means **finished, crashed, output rejected, stalled, or you reclaimed its work** — not only "accepted". An agent whose output you decided to fix yourself is still running until you stop it.
6. **Confirm none survive** — `ListAgents`, filtered against your recorded IDs. Any survivor gets `TaskStop` again, then re-list. If a recorded ID is still live after the retry, report shutdown **FAILED** and say so; do not claim completion.
7. **Reconcile tasks** — any `TaskCreate` record whose agent died without reporting gets marked accordingly. Never leave it falsely pending or falsely completed.
8. **Report to user** — Summarize what was built, organized by teammate, and flag any issues that need human attention

## Guidelines

### Team Decomposition Heuristics

Choose the decomposition strategy that best fits the work:

- **By layer**: Backend / Frontend / Tests — when the task spans the full stack
- **By module**: Auth / Users / Billing — when the task touches multiple independent modules
- **By concern**: Data models / Business logic / API routes / UI — when building a feature end-to-end
- **By platform**: iOS / Android / Web — for cross-platform work
- **Hybrid**: Mix strategies when it makes sense (e.g., "Backend API Agent" + "React Dashboard Agent" + "E2E Test Agent")

### What Makes a Good Agent Boundary

- Each agent can work without needing real-time input from other agents
- The interface between agents is small and well-defined (a type, an API shape, a file path convention)
- Each agent has enough work to justify the overhead (at least 2-3 files or meaningful logic)

### Anti-patterns to Avoid

- **Too many agents**: 6+ agents for a simple feature creates more coordination overhead than it saves. 2-4 is the sweet spot for most tasks.
- **Overlapping scopes**: Two agents editing the same file causes conflicts. Assign clear file ownership.
- **Sequential disguised as parallel**: If Agent B truly can't start until Agent A finishes, don't pretend they're parallel. Run A first, then spawn B.
- **Agent for trivial work**: A one-file, 10-line change doesn't need its own agent. Fold it into a related agent's scope or do it yourself after the team completes.

### Error Handling

- **Cleanup runs on EVERY exit path, not just the happy one.** Success, partial failure, abandoned run, user interruption, or you deciding to finish the work yourself — the Step 5-6 dismissal still runs before you write your final message. A run that ends without it leaks teammates.
- **Never block cleanup on a report that may never arrive.** A crashed or stalled agent never sends a completion message; waiting for "all teammates report" hangs the cleanup forever. Treat no-progress as terminal per the global stall rule and `TaskStop` it.
- ⚠️ **Known residual leak:** a hard session kill bypasses these instructions entirely. Prompt-level cleanup cannot close that — it needs harness-level parent-death cancellation. Do not claim teammates are always reaped.
- If an agent fails or produces broken output, `TaskStop` it first, then fix it directly rather than re-spawning the agent
- If the task turns out to be smaller than expected (only 1 workstream), skip the team pattern and just implement it directly — don't force parallelism where none exists
- If agents produce conflicting approaches to the same problem, pick the better one and align the other agent's output to match
