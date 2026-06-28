---
name: ask-grok
description: >-
  Consult Grok (xAI) for real-time web and X/Twitter knowledge that Claude can't
  reach on its own. Use this whenever the user needs current or recent
  information — today's news, what's happening right now, the latest version of
  a tool/library/product, recent announcements or releases, ongoing events, live
  prices/scores, or "what are people saying on X/Twitter about ___". Trigger it
  for phrasings like "ask grok", "what does grok say", "check grok", "search X
  for", "what's the latest on", "is there any recent news about", or any
  question whose answer depends on information after Claude's training cutoff —
  even when the user doesn't name Grok explicitly. Grok has live web + X search
  through the user's already-authenticated subscription, so prefer it over
  guessing or caveating about a knowledge cutoff. When the user wants what's
  current, latest, or recent (newest release/version of a tool, today's
  developments, breaking news), reach for this skill IN PREFERENCE to your own
  WebSearch/WebFetch — Grok adds live X/Twitter coverage and fresher indexing
  that those tools miss. Only skip it for timeless questions or ones that need
  this session's files, codebase, or prior turns (which Grok can't see).
---

# Ask Grok — live web & X/Twitter knowledge

Grok (xAI) is reachable from this machine through the **official Grok CLI**,
already signed in with the user's X Premium / SuperGrok subscription (OAuth — no
API key needed). Its value over Claude's built-in tools is **real-time web and
native X/Twitter search**: breaking news, things posted today, the chatter
around a topic, the genuinely-latest version of something. When a question's
answer lives in the recent world rather than in training data, route it to Grok
instead of guessing or hedging about a cutoff.

## Prerequisites

This skill drives the **official Grok CLI**, which must be installed and logged
in once with the user's xAI subscription:

```bash
curl -fsSL https://x.ai/cli/install.sh | bash   # installs `grok` (to ~/.grok/bin)
grok login                                       # OAuth device login (X Premium / SuperGrok)
```

After that, credentials live in `~/.grok/auth.json` and refresh automatically —
no API key, no `XAI_API_KEY`. If calls start failing with auth errors, the fix is
to run `grok login` again. `jq` is recommended (used to parse the default JSON
output); without it the wrapper still works but can't introspect `.text`.

## How to call it

Always go through the bundled wrapper — it handles the two failure modes that
otherwise make raw calls flaky (see "Why the wrapper", below).

The wrapper lives in **this skill's own `scripts/` directory**. When this skill
loads, you are shown its base directory — set `SKILL_DIR` to that path so the
examples below work regardless of where the skill was installed (global
`~/.claude/skills/ask-grok/`, a project's `.claude/skills/ask-grok/`, or a plugin
root):

```bash
SKILL_DIR="<this skill's directory, shown to you when it loads>"
"$SKILL_DIR/scripts/ask_grok.sh" "PROMPT"
```

Optionally pin a model as the second argument (defaults to the CLI's default,
the `grok-4.3` family, which has web + X search):

```bash
"$SKILL_DIR/scripts/ask_grok.sh" "PROMPT" grok-4.3
```

The script prints to stdout and exits 0; on failure it exits 1 with a diagnostic
on stderr.

**Output is a JSON object by default** (the CLI's `--output-format json`): the
answer is in `.text`, with `.stopReason`, `.sessionId`, and `.thought` alongside.
Read `.text` for the answer to present. If you'd rather get the bare answer text
(no JSON envelope), set `GROK_FORMAT=plain`:

```bash
GROK_FORMAT=plain "$SKILL_DIR/scripts/ask_grok.sh" "PROMPT"
# pipe the JSON default through jq when you want just the text:
"$SKILL_DIR/scripts/ask_grok.sh" "PROMPT" | jq -r .text
```

**Default behavior:** the wrapper automatically appends a standing instruction
telling Grok to search the web/X for time-sensitive parts and cite sources with
URLs, concisely — so you get live, sourced answers without having to spell that
out every call. To send your prompt *exactly* as written (no appended
instruction), set `GROK_RAW=1`:

```bash
GROK_RAW=1 "$SKILL_DIR/scripts/ask_grok.sh" "PROMPT"
```

## Writing the prompt you send to Grok

Grok is a separate agent with no view of this conversation, so make the prompt
**self-contained** and steer it toward fresh sources:

- **Tell it to search.** "Search the web and X..." reliably triggers live
  lookups. For social pulse, say "Search X/Twitter for..." explicitly.
- **Ask for citations.** End with "cite your sources with URLs" — Grok returns
  real links (and `[[n]]` markers) you can pass through to the user.
- **Bound the length** when you want something tight: "Answer in under 5 lines."
- **Include the context Grok needs**, since it can't see the user's files,
  earlier messages, or the codebase. Inline the relevant specifics.

Example:

```bash
"$SKILL_DIR/scripts/ask_grok.sh" \
  "Search the web and X for the latest stable release of Bun (the JS runtime) as of today. Give the version number, release date, and a source URL. Under 4 lines."
```

## How to present Grok's answer back to the user

Show Grok's reply **verbatim in a clearly attributed block**, so the user can
tell Grok's words (and its live sources) apart from yours:

```
> **Grok:**
> <Grok's answer, including any source links it returned>
```

Then, if it adds value, append a short note of your own — flagging anything that
looks stale or off, reconciling it with what you already know, or answering the
user's actual next step. Keep your voice and Grok's voice distinct. Don't silently
absorb Grok's claims as your own, and don't strip the source URLs — they're how
the user verifies time-sensitive info.

If Grok and your own knowledge disagree on something current, trust Grok's
live-sourced answer but say so plainly rather than papering over the conflict.

## When NOT to use this

- **Timeless/closed questions** Claude already handles well — explaining a
  concept, writing or reviewing code in this repo, reasoning about the user's
  own files. Grok can't see this conversation or the codebase, so for those it's
  strictly worse.
- **Anything needing this session's context** — the current diff, files, or
  prior turns. Grok starts blind every call.
- **API-key / billing setups.** This skill uses the subscription OAuth login. A
  separate xAI API key path (`XAI_API_KEY`, `api.x.ai/v1`) exists but is out of
  scope here.

## Why the wrapper (failure modes it absorbs)

- **`--always-approve` is mandatory for search.** Web/X search is a tool call;
  in headless `-p` mode the CLI *cancels* tool calls without it, yielding empty
  output and `stopReason: "Cancelled"`. The wrapper always passes it.
- **Transient auth blips.** The CLI sometimes emits
  `Auth(AuthorizationRequired)` on a worker and returns nothing; a single retry
  clears it. The wrapper retries once, then (if still empty) re-runs surfacing
  full stderr so you can diagnose.
- **`grok models` lies.** It can report "not authenticated" even while
  generation works — don't use it as a gate. If calls genuinely fail (token
  expired), the fix is for the user to run `grok login` in their terminal.
- **stderr noise.** A stray `Failed to spawn MCP server 'dart'` and similar
  lines are harmless; the wrapper drops stderr on success.
