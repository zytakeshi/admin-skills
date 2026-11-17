---
name: verify
description: "Prove a code change works by running the real thing before a commit, then record how it was proved. Picks checks from the diff, runs the fast path first, takes the pass signal from outside the code under test, and ends with a `Verified: <surface>|unit|none` line for the commit trailer. When the repo has no verify skill of its own, it writes one from the steps that worked. Use before a commit, for 'verify this', 'smoke-test the change', 'does it actually work', 'check it in the real app', before claiming green, or to set up verification for a new repo. A project `.claude/skills/verify` skill takes precedence over this one."
---

# verify: run it, then say what you saw

Verify means run it. `Verified: <surface>` means the changed behavior ran in a real process on a real surface and a signal from outside the code confirmed it. Tests alone, mutants included, are `Verified: unit`.

## 0. Find the project skill first
If the repo has `.claude/skills/verify/SKILL.md`, follow that file and stop reading this one. It holds the repo's real commands and traps. Otherwise do steps 1–7 (fallback), then step 8 (scaffold).

## 1. Preflight
Check the toolchain and logins the change needs (compiler, package manager, simulator, `gh`, cloud CLI). If one is missing, stop that part and report it. Do not edit code against a toolchain you could not run. If only the target runtime is missing (an old interpreter, a device), run what you can and name the gap in the report.

## 2. Map the diff to checks
`git diff --name-only <base>...HEAD` plus `git status --short` give the changed paths. Pick one row per area:

| Changed area | Verify with | Pass signal (from outside the code) |
|---|---|---|
| UI / screens | launch the app, open the changed screen | screenshot shows the change; the process is alive after 20 s |
| Server / API | run it locally, send a real request | HTTP status + body from the request, or the DB row it wrote |
| CLI | run the binary on a real input | exit code + output file or stdout |
| Library | call it from a caller-level test or example | the caller's result, not the unit's own assertion only |
| Network / OS integration | run on the real OS surface | the OS answers (`scutil --nc list`, `ss -tlnp`, route table), never the app's status text |
| Config / infra | validate or dry-run in non-prod | the tool's own validate/plan exit code |
| Docs only | none | `Verified: none` |

If the only real surface is production, use the nearest non-prod one (staging, loopback, local replica). If none exists, stop at `Verified: unit` and name the surface you could not reach.

To start the app, read the repo's README, `docs/`, Makefile, package scripts, CI file, or recent PR descriptions. The built-in `run` skill has launch patterns per project type.

## 3. Fast path first
Run the cheapest check that exercises the changed behavior. Widen only when it passes. Move slow builds to a build machine if the repo or your setup has one.

## 4. Prove the check can fail
For each new check, break the change once (revert the fix or stub it out). Do it in a scratch copy (`git worktree add` or `git archive`), never by editing tracked files in place. If the repo has its own mutation harness, use it. A check aimed at the change must fail; restore the change and it must pass. A check aimed at the change that stays green with the fix removed is a fake gate: rewrite it. A test that guards behavior the change did not touch may stay green.

## 5. Safety
- Never touch production. Staging is read-only unless the user says otherwise.
- Use test accounts, never a real user's account or synced settings.
- If the run can change shared state (app preferences with the same bundle id, a local DB, a config file), back it up first and restore it after. Avoid side effects you cannot undo (system log writes, sent messages); if one happens, list it in the report.
- On a live website: one load at most, with analytics blocked. Test locally first.
- Shut down every process, simulator, emulator or container you started.

## 6. Stop and flaky rules
- Still failing after 3 fix rounds: stop. Hand the human the failing command, its exit code, the last output, and what you tried.
- A flaky test gets no `sleep`, retry loop or skip. Find the cause. If you cannot, delete the test and write down why.

## 7. Report
List each check you ran with its observed result, each check you could not run with the reason, and any shared state you restored. The last line is the commit trailer:
```
Verified: <surface>     # e2e-macos, e2e-android, staging, loopback, ...
Verified: unit          # only unit tests ran
Verified: none          # nothing ran (valid; never leave the line out)
```

## 8. Scaffold the project skill
After a fallback run passed, write `.claude/skills/verify/SKILL.md` in the repo so the next run starts from facts:
- Frontmatter: `name: verify`, and a description that names the repo and its surfaces.
- The step-2 table rewritten with this repo's real paths, commands and pass signals.
- Exact commands, fast path first. Include only commands that ran in this session; mark the others `untested`.
- The traps you hit (missing LFS files, signing, shared preferences, ports), each with its fix.
- One line each for the stop rule, the flaky rule and the `Verified:` line.
- Keep it under ~120 lines. If a step needs a long script, put it in a file next to the skill and call that file. Test that script like a gate: it must exit non-zero on bad input (no arguments, a misspelled name).

Do not commit the new skill unless the user asks. Report its path.
