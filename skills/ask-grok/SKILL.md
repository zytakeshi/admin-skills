---
name: ask-grok
description: "Consult Grok (xAI) for LIVE WEB and X/Twitter knowledge \u2014 today's news, latest releases/versions, ongoing events, prices, or 'what are people saying on X about ___'. Prefer over WebSearch for anything current/recent (fresher indexing + live X coverage). LIVE WEB/X ONLY: code review, design, implementation or any non-web second opinion naming Grok routes to /grok. Triggers: '/ask-grok', 'search X for', 'what is the latest on', 'any recent news about', or any question past the training cutoff. Skip for timeless questions or ones needing this session's files/context."

---

# Ask Grok — live web & X/Twitter knowledge

Grok (xAI) is reachable from this machine through the **official Grok CLI**,
already signed in with the user's X Premium / SuperGrok subscription (OAuth — no
API key needed). Its value over Claude's built-in tools is **real-time web and
native X/Twitter search**: breaking news, things posted today, the chatter
around a topic, the genuinely-latest version of something. When a question's
answer lives in the recent world rather than in training data, route it to Grok
instead of guessing or hedging about a cutoff.

## How to call it

Always go through the bundled wrapper — it handles the two failure modes that
otherwise make raw calls flaky (see "Why the wrapper", below):

```bash
~/.claude/skills/ask-grok/scripts/ask_grok.sh "PROMPT"
```

Leave the model unset. The script falls through to the Grok CLI's own default,
which is the current web + X search family. Only pass a second argument when the
user names an exact model in that message — never pin a slug here, it goes stale:

```bash
~/.claude/skills/ask-grok/scripts/ask_grok.sh "PROMPT"            # normal
~/.claude/skills/ask-grok/scripts/ask_grok.sh "PROMPT" <model>    # only if asked
```

The script prints to stdout and exits 0; on failure it exits 1 with a diagnostic
on stderr.

**Output is a JSON object by default** (the CLI's `--output-format json`): the
answer is in `.text`, with `.stopReason`, `.sessionId`, and `.thought` alongside.
Read `.text` for the answer to present. If you'd rather get the bare answer text
(no JSON envelope), set `GROK_FORMAT=plain`:

```bash
GROK_FORMAT=plain ~/.claude/skills/ask-grok/scripts/ask_grok.sh "PROMPT"
# pipe the JSON default through jq when you want just the text:
~/.claude/skills/ask-grok/scripts/ask_grok.sh "PROMPT" | jq -r .text
```

**Default behavior:** the wrapper automatically appends a standing instruction
telling Grok to search the web/X for time-sensitive parts and cite sources with
URLs, concisely — so you get live, sourced answers without having to spell that
out every call. To send your prompt *exactly* as written (no appended
instruction), set `GROK_RAW=1`:

```bash
GROK_RAW=1 ~/.claude/skills/ask-grok/scripts/ask_grok.sh "PROMPT"
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
~/.claude/skills/ask-grok/scripts/ask_grok.sh \
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
