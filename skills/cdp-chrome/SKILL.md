---
name: cdp-chrome
description: Run Chrome DevTools (CDP) browser automation UNATTENDED on Chrome 136+ by attaching to a dedicated, already-logged-in Chrome instance instead of your default profile — so the native "Allow remote debugging?" consent dialog never appears. Use this skill whenever you set up, debug, or run chrome-devtools-mcp / Puppeteer / Playwright against a real logged-in Chrome and hit any of: the "Allow remote debugging?" dialog, a hang on connect/list_pages, "DevTools remote debugging requires a non-default data directory", --remote-debugging-port being silently ignored, or "I need browser automation to run without a human clicking a permission prompt". Triggers: "chrome-devtools won't connect", "allow remote debugging dialog", "unattended browser automation", "headless CDP login", "cdp-chrome", "browserUrl vs autoConnect", "chrome 136 remote debugging broken".
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

## Setup

The skill bundles `scripts/cdp-chrome`. Reference it from the skill directory (do not
hardcode an absolute path). For everyday use, install it on your PATH:

```bash
install -m 0755 "$(dirname "$0")/scripts/cdp-chrome" "$HOME/.local/bin/cdp-chrome"
# (or run it in place: ./scripts/cdp-chrome <command>)
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
| `cdp-chrome reseed` | Re-copy your real profile into the dedicated dir to refresh logins (quit main Chrome first) |
| `cdp-chrome status` | Report up / down |
| `cdp-chrome config` | Print the `--browserUrl` args for your CDP client |

Override defaults via env: `CDP_PORT`, `CDP_PROFILE`, `CDP_SOURCE_PROFILE`, `CDP_CHROME`.

## Troubleshooting

- **CDP client can't connect / `list_pages` hangs** → the dedicated Chrome isn't running:
  `cdp-chrome start`. Confirm with `cdp-chrome status`.
- **A site shows you logged out in automation** → the snapshot went stale:
  `cdp-chrome reseed` (quit your main Chrome first for a consistent copy).
- **Still seeing "Allow remote debugging?"** → your client is still on `--autoConnect`,
  or the MCP host wasn't restarted after the config change. Re-check step 3.
- **`--remote-debugging-port` ignored / "non-default data directory"** → you're pointing
  at the default profile. The dir in `CDP_PROFILE` must be non-default (the bundled
  default `~/.cache/cdp-mcp-profile` already is).
- **Websocket 403 / origin error** → keep `--remote-allow-origins=*` (the script sets it;
  it must be quoted so the shell doesn't glob it).

## Other platforms

The "copy the profile and cookies still decrypt" step is macOS-specific (Keychain key is
per-user). On **Linux**, the cookie key lives in the copied `Local State` (+ optionally a
keyring) so a same-user copy usually decrypts too; on **Windows**, App-Bound Encryption
binds the key more tightly and a plain copy often won't decrypt cookies — prefer logging
into the dedicated profile once and reusing it. The `--browserUrl` + non-default
`--user-data-dir` mechanism itself works on all three.

## Safety

- Never `rm -rf` the profile dir; if you must reset it, move it aside (`mv`).
- The dedicated profile contains real session cookies — treat `CDP_PROFILE` as sensitive
  and don't commit or share it.
- An open `--remote-debugging-port` is local attack surface; bind to `127.0.0.1` only
  (default) and don't expose it.
