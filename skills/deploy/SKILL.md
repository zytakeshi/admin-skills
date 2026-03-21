---
name: deploy
description: Deploy files to remote servers via SSH/SCP with mandatory backup, permission fixing, and verification. Use this skill when the user says /deploy, "deploy", "push to production", "deploy to server", "update production", "ship it to prod", "deploy the changes", or any variation requesting deployment of local files to a remote server. Also trigger when deploying after a git merge or PR merge, or when the user asks to "sync production" with local changes. Works with any server, any project — resolves connection details from hosts.md or user input.
---

# Deploy to Production

A generic workflow for deploying files from a local directory to a remote server via SSH/SCP. Works with any project and any server — not tied to a specific codebase.

## Step 0: Resolve deployment target

Before anything else, determine the deployment parameters. You need all of these:

| Parameter | How to resolve |
|-----------|---------------|
| **Server** (user@host) | Ask user, or look up in `~/ssh/hosts.md`, or infer from conversation context |
| **SSH key** | Check `~/ssh/hosts.md` for the host, or try `~/.ssh/putty_key`, `~/.ssh/id_rsa`, `~/.ssh/sock` |
| **Local path** | The directory or files to deploy (from git diff, user input, or conversation context) |
| **Remote path** | Where files go on the server — ask if unknown |
| **File owner** | The user/group that should own the files. For web apps: `www-data`, `nginx`, `apache`. For services: the service user. If unsure, check existing files on the server: `ls -la <REMOTE_PATH>` |

If any parameter is unknown, ask the user. Don't guess server addresses or remote paths.

**Quick-resolve pattern:** If the user says "deploy X to Y", X is the local source and Y identifies the server. Look up Y in `~/ssh/hosts.md` for connection details.

**Multi-server:** If the user mentions multiple servers or a load-balanced setup, confirm the full server list upfront. Deploy to each server sequentially (not in parallel) so you can catch failures early without leaving servers in inconsistent states.

## Step 0.5: Pre-flight checks

Before starting, verify the basics:

```bash
# 1. SSH connectivity
ssh <SSH_OPTS> <USER>@<HOST> "echo 'SSH OK'"

# 2. Disk space on server (warn if <500MB free on the deploy partition)
ssh <SSH_OPTS> <USER>@<HOST> "df -h <REMOTE_PATH> | tail -1"

# 3. Local files exist and are committed
git status --short <files to deploy>
```

- If SSH fails, stop and help the user debug (wrong key, firewall, host down)
- If disk is low, warn the user — deployment may fail mid-transfer
- If local files have uncommitted changes, warn the user — they may be deploying work-in-progress

## Step 1: Identify changed files

Determine which files need deploying:

- **Git diff**: `git diff --name-only HEAD~1` or a specific commit range
- **PR merge**: `gh pr diff <number> --name-only` for all files in the PR
- **User-specified**: The user may list specific files or directories
- **Conversation context**: Files that were just edited in this session

Only deploy files that actually changed. Don't deploy entire directories unless explicitly asked.

## Step 2: Verify production files match last deploy

Before overwriting anything, check that the production files haven't been manually modified since the last deployment. If nobody hot-patched the server, the production file should be identical to what was last deployed (i.e., the previous git commit's version of that file).

For each file being deployed, compare the **production file size** against the **local file size from the previous commit**:

```bash
# Get production file size
ssh <SSH_OPTS> <USER>@<HOST> "wc -c <REMOTE_PATH>/<file>"

# Get local file size from the commit BEFORE the changes being deployed
git show HEAD~1:<file> | wc -c
```

- **Sizes match**: Production file is untouched since last deploy. Safe to proceed.
- **Sizes differ**: Someone modified the file on the server. Alert the user with the size difference and ask for explicit confirmation before overwriting. Show which files diverged so they can decide whether to proceed, skip that file, or investigate.
- **File doesn't exist on server**: New file, no conflict. Proceed.

If any files diverge, do NOT proceed without user confirmation. Hot-patches may contain critical fixes that aren't in git yet — overwriting them silently could cause an outage.

## Step 3: Backup production files

This step is mandatory — never skip it, even if the user doesn't mention backups.

```bash
# Create dated backup directory on server
ssh <SSH_OPTS> <USER>@<HOST> "mkdir -p <REMOTE_PATH>/backups/$(date +%Y-%m-%d)"

# Back up each file being replaced
ssh <SSH_OPTS> <USER>@<HOST> \
  "cp <REMOTE_PATH>/<file> <REMOTE_PATH>/backups/$(date +%Y-%m-%d)/<file>.bak"
```

- If a file doesn't exist on the server (new file), note it and skip its backup
- Log all backed-up files so the user knows what can be rolled back
- If the backup directory or copy fails, stop and alert the user

## Step 4: Deploy via SCP

Transfer each changed file to the server:

```bash
scp <SSH_OPTS> <LOCAL_PATH>/<file> <USER>@<HOST>:<REMOTE_PATH>/<file>
```

- Deploy independent files in parallel (multiple scp calls in the same message)
- Preserve directory structure — `scp` the file to its matching relative path
- Echo a confirmation for each file deployed

## Step 5: Fix ownership and permissions

Files uploaded via `scp` as root will be owned by `root:root`. Fix them:

```bash
ssh <SSH_OPTS> <USER>@<HOST> "chown <OWNER>:<GROUP> <REMOTE_PATH>/<each file>"
```

- Check the ownership of neighboring files on the server to determine the correct owner if not already known
- Only fix files that are wrong — don't blindly `chown -R` the entire directory

## Step 6: Verify

Compare file sizes between local and production:

```bash
# Local
wc -c <local files>

# Remote
ssh <SSH_OPTS> <USER>@<HOST> "wc -c <remote files>"
```

Sizes must match exactly. If any mismatch, alert the user immediately and do not proceed.

## Step 7: Check if cache clearing is needed

After deploying, probe the server to determine what caches exist and whether they need clearing. Don't assume the stack — detect it.

### Detect running services

```bash
ssh <SSH_OPTS> <USER>@<HOST> "
  # Application caches
  systemctl is-active php*-fpm 2>/dev/null && echo 'DETECTED: php-fpm';
  systemctl is-active redis* 2>/dev/null && echo 'DETECTED: redis';
  systemctl is-active memcached 2>/dev/null && echo 'DETECTED: memcached';
  # Web servers
  systemctl is-active nginx 2>/dev/null && echo 'DETECTED: nginx';
  systemctl is-active apache2 2>/dev/null && echo 'DETECTED: apache2';
  systemctl is-active httpd 2>/dev/null && echo 'DETECTED: httpd';
  # Node/Python/other app servers
  systemctl is-active pm2* 2>/dev/null && echo 'DETECTED: pm2';
  systemctl is-active gunicorn* 2>/dev/null && echo 'DETECTED: gunicorn';
  systemctl is-active uvicorn* 2>/dev/null && echo 'DETECTED: uvicorn';
  # Check for OPcache specifically
  php -m 2>/dev/null | grep -qi opcache && echo 'DETECTED: opcache';
"
```

### Clear based on what's detected

| Detected | When to clear | How |
|----------|--------------|-----|
| **PHP OPcache** | Any `.php` file deployed | `systemctl reload php*-fpm` |
| **Redis** | App uses Redis for page/object/session cache AND deployed files affect cached data (templates, routes, config) | `redis-cli FLUSHDB` (app DB only) or ask user — don't flush blindly |
| **Memcached** | Same logic as Redis | `echo 'flush_all' \| nc localhost 11211` or restart service |
| **Nginx** (fastcgi_cache/proxy_cache) | Deployed files are served through a cache zone | Check for cache dirs: `ls /var/cache/nginx/` — if populated, ask user before purging |
| **Varnish** | Detected on server | `varnishadm 'ban req.url ~ .'` — ask user first |
| **CDN** (Cloudflare, CloudFront, etc.) | Static assets (JS/CSS/images) deployed | Alert user — CDN purge requires external API calls, don't do automatically |
| **Node.js (PM2)** | Any JS/TS file deployed | `pm2 reload all` or specific app name |
| **Python (gunicorn/uvicorn)** | Any `.py` file deployed | `systemctl reload gunicorn` or `kill -HUP <pid>` |
| **Web server config** | nginx/apache/httpd config files deployed | Reload the corresponding service |

### When no cache action is needed
- Only data files (`.json`, `.csv`, `.yaml`, `.env`) were deployed that the app reads fresh each request
- No bytecode/object/page caching is running
- The app is a simple file-serving setup with no caching layer

### Important
- **Never blindly `FLUSHALL` Redis** — it may contain sessions, queues, or data for other apps
- **Always tell the user** what caches were detected, which were cleared, and which were skipped (and why)
- **Ask before clearing** if the cache serves multiple applications or if you're unsure of the impact

Always tell the user whether cache was cleared or wasn't needed, and why.

## Step 8: Smoke test

After cache clearing, verify the application still works:

```bash
# For web apps — check HTTP status
ssh <SSH_OPTS> <USER>@<HOST> "curl -s -o /dev/null -w '%{http_code}' http://localhost/<health-endpoint>"

# For PHP — check for syntax errors in deployed files
ssh <SSH_OPTS> <USER>@<HOST> "php -l <REMOTE_PATH>/<each .php file>"

# For Node.js — check process is running
ssh <SSH_OPTS> <USER>@<HOST> "pm2 status"

# Check error logs for new errors since deploy
ssh <SSH_OPTS> <USER>@<HOST> "tail -5 /var/log/<app-error-log>"
```

- If the app has a known health endpoint or URL, hit it and confirm 200
- If no health endpoint exists, check the error log for PHP fatals, Python tracebacks, or Node crashes since the deploy timestamp
- If the smoke test fails, alert the user immediately and offer to rollback

## Step 9: Report

Summarize the deployment:
- Files deployed (with byte sizes)
- Backup location on server
- Permission fixes applied
- Caches cleared (or why none were needed)
- Smoke test result
- Rollback command

## Rollback

If the user asks to rollback:

```bash
# 1. Restore files from backup
ssh <SSH_OPTS> <USER>@<HOST> \
  "cp <REMOTE_PATH>/backups/<date>/<file>.bak <REMOTE_PATH>/<file> && \
   chown <OWNER>:<GROUP> <REMOTE_PATH>/<file>"

# 2. Re-clear caches (same as Step 7 — rolled-back files need fresh cache too)

# 3. Smoke test again to confirm rollback worked
```

## Safety rules

- Backup before deploying is non-negotiable — the user explicitly requires this
- Always verify file sizes match after transfer
- Always fix file ownership — scp as root creates root-owned files which break web servers
- Never deploy `.env`, credentials, private keys, or secret files
- Never use `rsync --delete` unless explicitly asked (it can wipe server-only files like logs and backups)
- Never use `rm` or `rm -rf` on the server — use `mv` to move files instead
- Ask for confirmation if deploying more than 10 files at once
