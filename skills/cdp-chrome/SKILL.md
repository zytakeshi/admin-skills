---
name: cdp-chrome
description: >-
  Run Chrome DevTools (CDP) browser automation UNATTENDED on Chrome 136+ by
  attaching to a dedicated, already-logged-in Chrome instance instead of your
  default profile — so the native "Allow remote debugging?" consent dialog never
  appears. Use this skill whenever you set up, debug, or run chrome-devtools-mcp /
  Puppeteer / Playwright against a real logged-in Chrome and hit any of: the
  "Allow remote debugging?" dialog, a hang on connect/list_pages, "DevTools remote
  debugging requires a non-default data directory", --remote-debugging-port being
  silently ignored, or "I need browser automation to run without a human clicking
  a permission prompt". Triggers: "chrome-devtools won't connect", "allow remote
  debugging dialog", "unattended browser automation", "headless CDP login",
  "cdp-chrome", "browserUrl vs autoConnect", "chrome 136 remote debugging broken",
  "switch to autoConnect mode", "attach to my real Chrome", "auto-click the allow
  remote debugging dialog", "chrome 144 allow dialog every session".
---

# cdp-chrome — unattended Chrome DevTools automation on Chrome 136+

Connect a CDP client (chrome-devtools-mcp, Puppeteer, Playwright) to a **real,
logged-in Chrome** with **zero permission dialogs**, on Chrome 136 and later.

> **Platform: macOS.** The core trick relies on macOS Keychain behavior. Linux/Windows
> need a different cookie-key approach — see *Other platforms* at the end.

## The problem (why automation stalls)

Two Chrome security changes collide:

1. **Chrome 136+** silently **ignores `--remote-debugging-port` on the default profile**
   (anti-cookie-theft hardening). The port is never opened; tools see
   *"DevTools remote debugging requires a non-default data directory"*.
2. **chrome-devtools-mcp `--autoConnect`** (Chrome 144+) attaches to your running
   Chrome via a native channel that pops **"Allow remote debugging?" (Cancel / Allow)**
   **every session**. It's a Chrome-owned window, so no automation can click it —
   and tools like Claude's computer-use grant browsers read-only (screenshot, no click)
   by design. The first call (`list_pages`) hangs until a human answers.

So out of the box you must choose: **real logged-in profile** (autoConnect, but a manual
click each session) *or* **unattended** (a fresh, logged-OUT profile). You can't get both
the naive way.

## The fix (have both: logged-in AND unattended)

Run a **dedicated Chrome instance** from a **copy** of your real profile, on a
**non-default `--user-data-dir`**, with the debug port opened **by you**:

- A non-default dir satisfies the Chrome 136+ rule → the port opens.
- On **macOS**, the Keychain `"Chrome Safe Storage"` key is **per-user, not bound to the
  profile path**, so the **copied cookies still decrypt** → the dedicated instance is
  **logged in** to your accounts (as of the copy).
- You open the port yourself (no `--autoConnect`) → **no consent dialog, ever**.
- Your main Chrome is untouched (separate instance, separate dir).

Tradeoff: it's a **point-in-time snapshot** (re-seed to refresh logins) and a **separate
window**, not your main one. That's the unavoidable cost of the Chrome 136+ design.

```
 cdp-chrome start  ──launches/keeps alive──▶  Dedicated Chrome  :9222
                                              (copied profile, logged in,
                                               debug port open, no dialog)
                                                        ▲
 chrome-devtools-mcp ──── --browserUrl http://127.0.0.1:9222 ────┘
   (drives the browser exactly as before)
```

## Two attach modes (and how to switch)

chrome-devtools-mcp can attach two ways. This skill supports **both** and lets you flip
between them by rewriting `mcpServers.chrome-devtools.args` in `~/.claude.json`:

| Mode | Flag it sets | What it drives | Dialog? | Use it when |
|------|--------------|----------------|---------|-------------|
| **copied** *(default)* | `--browserUrl http://127.0.0.1:<PORT>` | the dedicated copied-profile Chrome this skill runs | **never** | almost always — unattended automation, CI-like runs, anything scripted |
| **autoconnect** | `--autoConnect` | your **real** running Chrome (live tabs, real session, direct LAN) | **every session** (Chrome 144+, un-suppressible) | you specifically need the live session / a tab that's already open, and can tolerate (or auto-click) the prompt |

```bash
cdp-chrome mode              # show which mode is currently configured
cdp-chrome mode copied       # ← default: point the MCP at the dedicated :PORT instance
cdp-chrome mode autoconnect  # point the MCP at your real Chrome (expect the dialog)
```

`mode` backs up `~/.claude.json` first (timestamped `*.cdp-chrome-bak-*`), rewrites **only**
the connection flag (keeping the package spec and any other args you've set), and re-parses
the result to confirm it's valid JSON — restoring the backup if it somehow isn't. After a
switch, **reconnect the MCP** (`/mcp` in Claude Code, or restart the MCP host) for it to take
effect. `copied` mode also needs the dedicated Chrome up (`cdp-chrome start`).

> **autoconnect's dialog is unavoidable.** On Chrome 144+ `--autoConnect` pops a native
> "Allow remote debugging?" bubble **every** session and Google made this un-suppressible —
> enterprise policy `RemoteDebuggingAllowed` is all-or-nothing, and the persistence request
> ([chrome-devtools-mcp#825](https://github.com/ChromeDevTools/chrome-devtools-mcp/issues/825))
> was closed *"not planned."* The only way to keep it from blocking is to **click it for
> you** → `cdp-chrome allow-watch` (EXPERIMENTAL; see below). Prefer `copied` mode whenever
> you can — it sidesteps the dialog entirely.

## Setup

The skill bundles `scripts/cdp-chrome`. For everyday use, install it on your PATH.
Run these **from this skill's own directory** (the one containing `SKILL.md`; Claude is
given its absolute path at invocation, so `cd` there first — don't rely on `$0`):

```bash
cd /path/to/skills/cdp-chrome   # this skill's directory
mkdir -p "$HOME/.local/bin"
install -m 0755 ./scripts/cdp-chrome "$HOME/.local/bin/cdp-chrome"
# (or skip installing and run it in place: ./scripts/cdp-chrome <command>)
```

1. **Seed the dedicated profile** (copies your real profile, caches excluded). For the
   cleanest copy, quit your main Chrome first:
   ```bash
   cdp-chrome reseed
   ```
2. **Start the dedicated Chrome** (idempotent — does nothing if already up):
   ```bash
   cdp-chrome start
   ```
3. **Point your CDP client at it.** For chrome-devtools-mcp, set its args (e.g. in
   `~/.claude.json` → `mcpServers.chrome-devtools.args`), replacing any `--autoConnect`:
   ```json
   ["chrome-devtools-mcp@latest", "--browserUrl", "http://127.0.0.1:9222"]
   ```
   `cdp-chrome config` prints this snippet. **Restart the MCP host** (e.g. Claude Code)
   for the arg change to take effect.
4. **Verify** — this should return JSON with no dialog:
   ```bash
   curl -s http://127.0.0.1:9222/json/version
   ```

## Keeping it running automatically

The dedicated Chrome must be up for `--browserUrl` to attach. Make `cdp-chrome start`
run on its own (it's idempotent and async-safe):

- **Claude Code SessionStart hook** (comes up only when you use Claude Code) — in
  `~/.claude/settings.json`:
  ```json
  { "hooks": { "SessionStart": [ { "hooks": [
    { "type": "command", "command": "$HOME/.local/bin/cdp-chrome start", "async": true }
  ] } ] } }
  ```
- **macOS LaunchAgent** (comes up at login, always on) — alternative if you want the
  port available outside Claude Code. Note an always-open CDP port is extra attack surface.

## Commands

| Command | What it does |
|---------|--------------|
| `cdp-chrome start`  | Launch the dedicated Chrome on `:PORT` if it's down (idempotent) |
| `cdp-chrome reseed` | Mirror your real profile into the dedicated dir to refresh logins. Quit the dedicated Chrome first — `reseed` refuses to run while it's up (copying over a live profile corrupts it). Uses `rsync --delete`, so revoked sessions / removed extensions don't linger |
| `cdp-chrome status` | Report up / down |
| `cdp-chrome config` | Print the `--browserUrl` args for your CDP client |
| `cdp-chrome mode [copied\|autoconnect]` | Flip the chrome-devtools-mcp attach mode in `~/.claude.json` (no arg = show current). Backs up + validates JSON. `/mcp` reconnect needed after |
| `cdp-chrome allow-watch` | **EXPERIMENTAL** — for `autoconnect` mode, run a bounded loop that auto-clicks Chrome's "Allow remote debugging?" dialog. See caveats below |

Override defaults via env:

| Var | Default | Purpose |
|-----|---------|---------|
| `CDP_PORT` | `9222` | CDP / remote-debugging port (bound to 127.0.0.1) |
| `CDP_PROFILE` | `~/.cache/cdp-mcp-profile` | The dedicated (copied) user-data-dir — must be non-default |
| `CDP_SOURCE_PROFILE` | `~/Library/Application Support/Google/Chrome` | Your real Chrome user-data-dir to copy from |
| `CDP_PROFILE_DIR` | `Default` | Which profile inside it — set to `"Profile 1"` etc. if your logged-in profile isn't Default |
| `CDP_CHROME` | `/Applications/Google Chrome.app` | Chrome `.app` **bundle** (passed to `open -a`, not the inner binary) |
| `CDP_ALLOW_ORIGINS` | *(unset)* | CDP websocket Origin allowlist. Unset = `--remote-allow-origins` is omitted (secure default — only no-Origin clients connect). See **Security** |
| `CDP_CLAUDE_CONFIG` | `~/.claude.json` | MCP host config that `cdp-chrome mode` edits (point at another host's config if not Claude Code) |
| `CDP_ALLOW_WATCH_SECONDS` | `60` | How long `cdp-chrome allow-watch` scans for the dialog before giving up |

## Auto-clicking the autoConnect dialog (EXPERIMENTAL — last resort)

`autoconnect` mode blocks on Chrome's un-suppressible "Allow remote debugging?" bubble every
session (see *Two attach modes*). `cdp-chrome allow-watch` is a **workaround of last resort**,
**not a supported mechanism**: it runs a **bounded** macOS-accessibility loop (`osascript` /
System Events) that watches Google Chrome for an **"Allow"** button and clicks it.

```bash
cdp-chrome mode autoconnect   # (once) put the MCP on --autoConnect, then /mcp reconnect
cdp-chrome allow-watch        # start the watcher, THEN trigger your first CDP call
```

How it behaves:

- Polls ~once/sec for up to `CDP_ALLOW_WATCH_SECONDS` (default **60**), then stops — it
  **never runs forever**. Stops early once it has clicked and then sees 3 clean passes.
- Clicks **every** matching "Allow" each pass, because a known bug can **stack multiple**
  dialogs ([chrome-devtools-mcp#1794](https://github.com/ChromeDevTools/chrome-devtools-mcp/issues/1794)).
- The button is exposed via macOS accessibility (`AXButton` named "Allow") on the Google
  Chrome process — the same UI family as the mic/camera permission bubbles.
- **First run needs a one-time permission grant** for whatever process launches `osascript`
  (Terminal / iTerm / Ghostty / the Claude app): **System Settings → Privacy & Security →
  Accessibility** (enable it) *and* **→ Automation** (allow it to control "System Events").
  Without both, `allow-watch` fails **immediately with a clear message** instead of hanging.

**Caveats — treat as fragile:**

- It's a UI-scraping hack against a Chrome-owned dialog: a Chrome UI change, a non-English
  button label, or a differently-anchored bubble can silently make it miss. It is **best-effort**.
- Do **not** rely on it for anything important — prefer **`copied` mode**, which never shows
  the dialog at all.
- **Security:** autoConnect opens a CDP port on your **real** profile (all your live logins).
  cdp-chrome's existing secure default still applies — with `CDP_ALLOW_ORIGINS` unset, the
  `--remote-allow-origins` flag is omitted, so Chrome rejects origin-bearing web-page hijack
  attempts and accepts only no-Origin native CDP clients (see **Security**). Keep it unset.

## Troubleshooting

- **Which Chrome change am I hitting? (the two get conflated)** — they're different:
  - **Chrome 136+ default-profile port block** happens in **`copied`/`--browserUrl` setups**:
    `--remote-debugging-port` is **silently ignored on the default profile**, so the port
    never opens and tools report *"non-default data directory"*. Fix = a non-default
    `--user-data-dir` (what this skill's dedicated profile does). See
    [remote-debugging-port changes](https://developer.chrome.com/blog/remote-debugging-port).
  - **Chrome 144+ autoConnect dialog** happens in **`autoconnect`/`--autoConnect` setups**:
    the port opens fine but Chrome pops a native **"Allow remote debugging?"** consent bubble
    every session. Fix = answer it, use `allow-watch`, or switch to `copied` mode. See
    [chrome-devtools-mcp session debugging](https://developer.chrome.com/blog/chrome-devtools-mcp-debug-your-browser-session).

    One is a **silently-ignored flag** (copied mode); the other is a **blocking dialog**
    (autoconnect mode). Different symptom, different mode, different fix.
- **CDP client can't connect / `list_pages` hangs** → the dedicated Chrome isn't running:
  `cdp-chrome start`. Confirm with `cdp-chrome status`.
- **A site shows you logged out in automation** → the snapshot went stale:
  `cdp-chrome reseed`. Quit the dedicated Chrome first (reseed refuses while it's up); also
  quit your main Chrome for the most consistent source copy.
- **My logged-in profile isn't "Default"** (you use `Profile 1`, a work profile, etc.) →
  set `CDP_PROFILE_DIR="Profile 1"` for both `reseed` and `start`.
- **Still seeing "Allow remote debugging?"** → you're in `autoconnect` mode (or the MCP host
  wasn't reconnected after a config change). Switch back with `cdp-chrome mode copied` then
  `/mcp` reconnect — or, if you deliberately want autoconnect, run `cdp-chrome allow-watch`.
- **`allow-watch` says permission not granted / does nothing** → grant Accessibility **and**
  Automation to whatever runs `osascript` (System Settings → Privacy & Security), then re-run.
  If it still never clicks, the prompt may not have fired, the button label/locale differs, or
  the bubble is anchored oddly — it's best-effort; fall back to `copied` mode.
- **`mode` reports "no chrome-devtools MCP server found"** → your `~/.claude.json` has no
  `mcpServers.chrome-devtools` entry yet. Add one (`cdp-chrome config` prints a starting
  point), or point `CDP_CLAUDE_CONFIG` at the host config that actually has it.
- **`--remote-debugging-port` ignored / "non-default data directory"** → you're pointing
  at the default profile. The dir in `CDP_PROFILE` must be non-default (the bundled
  default `~/.cache/cdp-mcp-profile` already is).
- **Websocket 403 / origin error** → your CDP client sends an `Origin` header (most don't).
  By default the script omits `--remote-allow-origins`, which rejects origin-bearing
  connections. Set `CDP_ALLOW_ORIGINS` to that client's exact origin (e.g.
  `CDP_ALLOW_ORIGINS="http://127.0.0.1:9222" cdp-chrome start` — match your `CDP_PORT`),
  or `*` to allow all (insecure — see **Security**).
- **`start` says "already up" but the wrong browser answers** → something else already
  holds `CDP_PORT`. The port must be exclusive to this tool — pick a free `CDP_PORT`, or
  stop the other listener (`lsof -ti tcp:9222`).

## Other platforms

The "copy the profile and cookies still decrypt" step is macOS-specific (Keychain key is
per-user). On **Linux**, the cookie key lives in the copied `Local State` (+ optionally a
keyring) so a same-user copy usually decrypts too; on **Windows**, App-Bound Encryption
binds the key more tightly and a plain copy often won't decrypt cookies — prefer logging
into the dedicated profile once and reusing it. The `--browserUrl` + non-default
`--user-data-dir` mechanism itself works on all three.

## Security

This skill runs a **logged-in** browser with an open CDP endpoint, so treat it carefully.

- **CDP origin allowlist (`CDP_ALLOW_ORIGINS`, default: unset → flag omitted).** A logged-in
  browser with an open CDP port is a sensitive target: loopback binding does **not** stop a
  malicious *web page* (open in any browser on the machine) from connecting to
  `ws://127.0.0.1:<port>` and driving your authenticated session. Chrome gates this with the
  websocket `Origin` check. By default this skill **omits `--remote-allow-origins`**, so
  Chrome accepts only connections with **no `Origin` header** — exactly what native CDP
  clients (chrome-devtools-mcp / Puppeteer / Playwright) send — and rejects origin-bearing
  web-page connections. (Verified: chrome-devtools-mcp attaches fine with the flag omitted.)
  Only set `CDP_ALLOW_ORIGINS` if a client genuinely needs an allowed origin — prefer a
  specific value (`http://127.0.0.1:9222`) over `*`. `CDP_ALLOW_ORIGINS="*"` disables the
  check entirely and is **insecure** for a logged-in profile — avoid it.
- The port binds to `127.0.0.1` only (Chrome default) — don't forward or expose it.
- **Need the copied-profile instance from another machine (LAN)?** Tunnel it, don't bind it.
  Prefer `ssh -L 9222:127.0.0.1:9222 <host>` (keeps the endpoint loopback-only, authenticated
  by SSH) over launching Chrome with `--remote-debugging-address` on a LAN interface — the
  latter exposes a **logged-in, unauthenticated CDP endpoint** to anyone who can reach that IP.
- The dedicated profile holds real session cookies — treat `CDP_PROFILE` as sensitive;
  never commit or share it.
- Never `rm -rf` the profile dir; if you must reset it, move it aside (`mv`). `reseed`
  refuses to overwrite a running dedicated profile and mirrors with `rsync --delete` so
  revoked sessions don't linger.
