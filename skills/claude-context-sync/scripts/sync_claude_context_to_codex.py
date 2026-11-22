#!/usr/bin/env python3
"""One-way, redacted Claude context sync into Codex memory notes."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path


DEFAULT_MAX_FILE_BYTES = 200_000
SKIP_DIRS = {
    ".git",
    ".hg",
    ".svn",
    "node_modules",
    "vendor",
    ".dart_tool",
    "build",
    "dist",
    "target",
    ".next",
    ".turbo",
    "coverage",
    "Pods",
    ".build",
    ".venv",
    "venv",
    "__pycache__",
    "backups",
    "tmp",
    "cache",
    "sessions",
    "history",
    "file-history",
    ".claude",
    ".airpilot-worktrees",
    ".libcyberai-removed",
    ".pinescript-agents",
    "SourcePackages",
    "checkouts",
    "prod-mirror",
    "whmcsUpdate260424",
}
SKIP_PREFIXES = ("build-", "DerivedData")
KEY_TERMS = (
    "root cause",
    "implement",
    "plan",
    "agent",
    "parallel",
    "team",
    "git",
    "docker",
    "backup",
    "rollback",
    "remote config",
    "whmcs",
    "vilanet",
    "vpncheap",
    "grafana",
    "ssh",
    "prod",
    "test",
    "secret",
    "memory",
    "html",
    "brief",
    "sync",
    "held",
    "release",
)

SECRET_LINE_RE = re.compile(
    r"(?i)(password|passwd|token|secret|api[_-]?key|authorization|bearer|private[_ -]?key|client[_-]?secret|auth_pass|gh[_-]?token)"
)
SECRET_VALUE_RE = re.compile(
    r"(?i)(sk-[A-Za-z0-9_-]{8,}|gh[pousr]_[A-Za-z0-9_]{8,}|xox[baprs]-[A-Za-z0-9-]{8,}|bearer\s+[A-Za-z0-9._-]{8,})"
)
IPV4_RE = re.compile(
    r"\b(?:(?:25[0-5]|2[0-4][0-9]|1?[0-9]{1,2})\.){3}(?:25[0-5]|2[0-4][0-9]|1?[0-9]{1,2})\b"
)
IPV6_RE = re.compile(r"\b(?:[0-9A-Fa-f]{1,4}:){2,7}[0-9A-Fa-f]{0,4}\b")
EMAIL_RE = re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b")
URL_CREDS_RE = re.compile(r"(https?://)[^/\s:@]+:[^@\s]+@")
QUERY_SECRET_RE = re.compile(r"([?&](?:token|key|secret|password|auth|access_token|api_key)=)[^&\s)`'\"]+", re.IGNORECASE)
CREDS_PAIR_VALUE_RE = re.compile(
    r"\b([A-Za-z0-9._-]{3,32})\s*/\s*((?=[A-Za-z0-9._-]{12,})(?=[A-Za-z0-9._-]*[0-9])(?=[A-Za-z0-9._-]*[A-Za-z])[A-Za-z0-9._-]{12,})\b"
)
CREDS_PAIR_CONTEXT_RE = re.compile(r"(?i)(login|credential|creds|grafana|admin|user|prometheus)")
SSH_PATH_RE = re.compile(r"(?:~|/Users/[^/\s]+)/(?:\.ssh|\.env|\.config)/[^\s)`'\"]+")
SECRET_PATH_RE = re.compile(
    r"(?:~|/[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*)(?:/[A-Za-z0-9_.-]*(?:token|secret|credential|private[_-]?key|passwd|password|\.env)[A-Za-z0-9_.-]*)",
    re.IGNORECASE,
)
PRIVATE_BLOCK_RE = re.compile(
    r"-----BEGIN [A-Z ]*(?:PRIVATE KEY|OPENSSH KEY)[^-]*-----.*?-----END [A-Z ]*(?:PRIVATE KEY|OPENSSH KEY)[^-]*-----",
    re.DOTALL,
)
POST_REDACTION_RISK = (
    SECRET_VALUE_RE,
    URL_CREDS_RE,
    PRIVATE_BLOCK_RE,
    re.compile(r"(?i)\bAuthorization:\s*Bearer\s+[A-Za-z0-9._-]{6,}"),
    re.compile(r"(?i)\b(password|passwd|token|secret|client_secret|auth_pass)\s*=\s*[^ \n]+"),
)


@dataclass
class SourceSummary:
    path: Path
    digest: str
    lines: list[str]


class Redactor:
    def __init__(self) -> None:
        self.counts = {
            "secret_lines": 0,
            "secret_values": 0,
            "ip_addresses": 0,
            "email_addresses": 0,
            "url_credentials": 0,
            "credential_pairs": 0,
            "query_secrets": 0,
            "secret_paths": 0,
            "private_key_blocks": 0,
        }

    def sub(self, name: str, pattern: re.Pattern[str], repl: str, text: str) -> str:
        text, count = pattern.subn(repl, text)
        self.counts[name] += count
        return text

    def redact_text(self, text: str) -> str:
        text = self.sub("private_key_blocks", PRIVATE_BLOCK_RE, "[REDACTED_PRIVATE_KEY_BLOCK]", text)
        text = self.sub("url_credentials", URL_CREDS_RE, r"\1[REDACTED_CREDS]@", text)
        text = self.sub("query_secrets", QUERY_SECRET_RE, r"\1[REDACTED_TOKEN]", text)
        redacted: list[str] = []
        for raw in text.splitlines():
            line = raw.rstrip()
            lowered = line.lower()
            has_assignment = any(marker in line for marker in ("=", ": ", "Bearer ", "bearer "))
            if SECRET_LINE_RE.search(line) and has_assignment and not lowered.startswith(("- do not", "- never", "- avoid")):
                self.counts["secret_lines"] += 1
                redacted.append("- [REDACTED_SECRET_LINE]" if line.lstrip().startswith("-") else "[REDACTED_SECRET_LINE]")
                continue
            if CREDS_PAIR_CONTEXT_RE.search(line):
                line = self.sub("credential_pairs", CREDS_PAIR_VALUE_RE, "[REDACTED_CREDS_PAIR]", line)
            line = self.sub("secret_values", SECRET_VALUE_RE, "[REDACTED_TOKEN]", line)
            line = self.sub("ip_addresses", IPV4_RE, "[REDACTED_IP]", line)
            line = self.sub("ip_addresses", IPV6_RE, "[REDACTED_IP]", line)
            line = self.sub("email_addresses", EMAIL_RE, "[REDACTED_EMAIL]", line)
            line = self.sub("secret_paths", SSH_PATH_RE, "[REDACTED_SECRET_PATH]", line)
            line = self.sub("secret_paths", SECRET_PATH_RE, "[REDACTED_SECRET_PATH]", line)
            if len(line) > 260:
                line = line[:257] + "..."
            redacted.append(line)
        out = "\n".join(redacted)
        for pattern in POST_REDACTION_RISK:
            if pattern.search(out):
                raise ValueError(f"redaction failed closed; high-risk pattern remained: {pattern.pattern}")
        return out


def now_stamp() -> str:
    return dt.datetime.now().astimezone().strftime("%Y-%m-%dT%H-%M-%S%z")


def short_hash(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()[:12]


def read_limited(path: Path, max_bytes: int) -> tuple[str, str]:
    data = path.read_bytes()[:max_bytes]
    return data.decode("utf-8", errors="replace"), short_hash(data)


def skip_dir_name(name: str) -> bool:
    return name in SKIP_DIRS or name.startswith(SKIP_PREFIXES) or name.startswith(".git")


def find_project_claude_files(project: Path, max_depth: int) -> list[Path]:
    project = project.resolve()
    files: list[Path] = []
    for root, dirs, names in os.walk(project):
        root_path = Path(root)
        rel_parts = root_path.relative_to(project).parts if root_path != project else ()
        if len(rel_parts) > max_depth:
            dirs[:] = []
            continue
        dirs[:] = [d for d in dirs if not skip_dir_name(d)]
        if "CLAUDE.md" in names:
            files.append(root_path / "CLAUDE.md")
    return sorted(files)


def git_toplevel(path: Path) -> Path | None:
    try:
        result = subprocess.run(
            ["git", "-C", str(path), "rev-parse", "--show-toplevel"],
            check=True,
            capture_output=True,
            text=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None
    top = result.stdout.strip()
    return Path(top).resolve() if top else None


def discover_gitrepo_projects(root: Path, max_depth: int) -> list[Path]:
    root = root.expanduser().resolve()
    if not root.exists():
        return []
    discovered: set[Path] = set()
    for dirpath, dirs, names in os.walk(root):
        current = Path(dirpath)
        rel_parts = current.relative_to(root).parts if current != root else ()
        if len(rel_parts) > max_depth:
            dirs[:] = []
            continue
        dirs[:] = [d for d in dirs if not skip_dir_name(d)]
        if "CLAUDE.md" not in names:
            continue
        discovered.add(git_toplevel(current) or current)
    return sorted(discovered)


def extract_lines(path: Path, max_bytes: int, redactor: Redactor, max_lines: int = 18) -> SourceSummary:
    text, digest = read_limited(path, max_bytes)
    text = redactor.redact_text(text)
    selected: list[str] = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        lower = line.lower()
        if line.startswith("#") or line.startswith("- "):
            if line.startswith("#") or any(term in lower for term in KEY_TERMS):
                selected.append(line)
        if len(selected) >= max_lines:
            break
    if not selected:
        selected = [line.strip() for line in text.splitlines() if line.strip()][:max_lines]
    return SourceSummary(path=path, digest=digest, lines=selected)


def bullet_block(items: list[str], indent: str = "") -> str:
    if not items:
        return f"{indent}- None found."
    return "\n".join(f"{indent}- {item}" for item in items)


def rel_or_abs(path: Path, base: Path | None = None) -> str:
    try:
        if base:
            return str(path.resolve().relative_to(base.resolve()))
    except ValueError:
        pass
    return str(path)


def default_projects() -> list[Path]:
    cwd = Path.cwd()
    projects: list[Path] = []
    if (cwd / "CLAUDE.md").exists():
        projects.append(cwd)
    ssh = Path.home() / "ssh"
    if ssh.exists() and ssh not in projects:
        projects.append(ssh)
    return projects


def unique_paths(paths: list[Path]) -> list[Path]:
    seen: set[Path] = set()
    unique: list[Path] = []
    for path in paths:
        resolved = path.expanduser().resolve()
        if resolved in seen:
            continue
        seen.add(resolved)
        unique.append(resolved)
    return unique


def collect_context(
    claude_home: Path,
    codex_home: Path,
    projects: list[Path],
    max_file_bytes: int,
    max_depth: int,
) -> str:
    generated_at = dt.datetime.now().astimezone().isoformat(timespec="seconds")
    redactor = Redactor()
    global_sources: list[SourceSummary] = []
    for path in (claude_home / "CLAUDE.md", claude_home / "settings.json"):
        if path.exists():
            global_sources.append(extract_lines(path, max_file_bytes, redactor))

    project_sources: list[tuple[Path, list[SourceSummary]]] = []
    for project in projects:
        summaries = [extract_lines(p, max_file_bytes, redactor) for p in find_project_claude_files(project, max_depth)]
        project_sources.append((project, summaries))

    memory_sources: list[SourceSummary] = []
    agent_memory = claude_home / "agent-memory"
    if agent_memory.exists():
        for path in sorted(agent_memory.glob("*/MEMORY.md")):
            memory_sources.append(extract_lines(path, max_file_bytes, redactor, max_lines=14))

    skills_link = codex_home / "skills"
    if skills_link.is_symlink():
        skills_status = f"symlink -> {os.readlink(skills_link)}"
    elif skills_link.exists():
        skills_status = "exists but is not a symlink"
    else:
        skills_status = "missing"

    plans_dir = claude_home / "plans"
    plan_names = sorted(p.name for p in plans_dir.glob("*.md"))[:12] if plans_dir.exists() else []
    tasks_dir = claude_home / "tasks"
    task_count = len(list(tasks_dir.glob("*/*.json"))) if tasks_dir.exists() else 0

    lines: list[str] = [
        "# Claude Context Sync",
        "",
        f"Generated: {generated_at}",
        "",
        "This note was generated by `sync-claude-context-to-codex`. It is a redacted, Codex-native bridge from Claude global instructions, project `CLAUDE.md` files, and Claude memory indexes. It intentionally does not copy credentials, raw host inventories, private transcripts, or live access details.",
        "",
        "## Sync status",
        "",
        f"- Claude home: `{claude_home}`",
        f"- Codex home: `{codex_home}`",
        f"- Codex skills: `{skills_status}`",
        f"- Claude plan files sampled: {len(plan_names)}",
        f"- Claude task cards counted: {task_count}",
        "",
        "## Global Claude context",
        "",
    ]

    for summary in global_sources:
        lines.append(f"### `{summary.path}`")
        lines.append("")
        lines.append(f"- sha256: `{summary.digest}`")
        lines.append(bullet_block(summary.lines))
        lines.append("")

    lines.append("## Project context")
    lines.append("")
    for project, summaries in project_sources:
        lines.append(f"### `{project}`")
        lines.append("")
        if not summaries:
            lines.append("- No `CLAUDE.md` files found.")
            lines.append("")
            continue
        for summary in summaries:
            lines.append(f"#### `{rel_or_abs(summary.path, project)}`")
            lines.append("")
            lines.append(f"- sha256: `{summary.digest}`")
            lines.append(bullet_block(summary.lines))
            lines.append("")

    lines.append("## Claude memory indexes")
    lines.append("")
    if not memory_sources:
        lines.append("- No Claude agent-memory index files found.")
        lines.append("")
    for summary in memory_sources:
        lines.append(f"### `{summary.path.parent.name}`")
        lines.append("")
        lines.append(f"- source: `{summary.path}`")
        lines.append(f"- sha256: `{summary.digest}`")
        lines.append(bullet_block(summary.lines))
        lines.append("")

    lines.extend(
        [
            "## Resume-state hints",
            "",
            "Use Claude plans/tasks as a metadata source only when relevant. Check for held releases, pending verification, pending package rebuilds, exact staging/live targets, and explicit user holds before merging, publishing, or releasing.",
            "",
            "### Sample plan names",
            "",
            bullet_block(plan_names),
            "",
            "## Redaction boundary",
            "",
            "- Exact credentials, bearer tokens, passwords, key material, customer identifiers, raw transcript text, and live inventory tables are excluded.",
            "- IPv4/IPv6 addresses, email addresses, credential-bearing URLs, query secrets, SSH/config secret paths, private key blocks, and credential-like assignments are redacted by the generator.",
            "- Time-sensitive external facts from Claude memory must be refreshed before use.",
            "",
            "### Redaction placeholders",
            "",
            "- [REDACTED_IP]",
            "- [REDACTED_EMAIL]",
            "- [REDACTED_TOKEN]",
            "- [REDACTED_SECRET_LINE]",
            "- [REDACTED_SECRET_PATH]",
            "- [REDACTED_CREDS]",
            "- [REDACTED_CREDS_PAIR]",
            "- [REDACTED_PRIVATE_KEY_BLOCK]",
            "",
            "### Redaction counts",
            "",
        ]
    )
    lines.extend(f"- {name}: {count}" for name, count in redactor.counts.items())
    return "\n".join(lines).rstrip() + "\n"


def write_note(content: str, output_dir: Path, stamp: str | None = None) -> Path:
    output_dir.mkdir(parents=True, exist_ok=True)
    stamp = stamp or now_stamp()
    path = output_dir / f"{stamp}-claude-context-sync.md"
    path.write_text(content, encoding="utf-8")
    os.chmod(path, 0o600)
    return path


def run_sync(args: argparse.Namespace) -> Path | None:
    claude_home = Path(args.claude_home).expanduser().resolve()
    codex_home = Path(args.codex_home).expanduser().resolve()
    projects = [Path(p).expanduser().resolve() for p in args.project] if args.project else default_projects()
    for root in args.gitrepo_root or []:
        projects.extend(discover_gitrepo_projects(Path(root), args.gitrepo_max_depth))
    projects = unique_paths(projects)
    default_output_dir = codex_home / "memories" / "extensions" / "ad_hoc" / "notes"
    output_dir = Path(args.output_dir).expanduser().resolve() if args.output_dir else default_output_dir
    content = collect_context(
        claude_home=claude_home,
        codex_home=codex_home,
        projects=projects,
        max_file_bytes=args.max_file_bytes,
        max_depth=args.max_depth,
    )
    if args.dry_run or (not args.write and args.output_dir is None):
        if not args.dry_run:
            print("Preview only. Pass --write to write into Codex memory, or --output-dir DIR for a temp smoke write.", file=sys.stderr)
        sys.stdout.write(content)
        return None
    path = write_note(content, output_dir)
    print(path)
    return path


def assert_not_contains(text: str, needles: list[str]) -> None:
    for needle in needles:
        if needle in text:
            raise AssertionError(f"output leaked forbidden text: {needle}")


def run_self_test() -> None:
    root = Path(tempfile.mkdtemp(prefix="codex-claude-sync-test-"))
    try:
        claude = root / ".claude"
        codex = root / ".codex"
        project = root / "project"
        gitrepo = root / "gitrepo"
        gitrepo_project = gitrepo / "repo-a"
        notes = codex / "memories" / "extensions" / "ad_hoc" / "notes"
        (claude / "agent-memory" / "facts-verifier").mkdir(parents=True)
        (claude / "plans").mkdir(parents=True)
        (claude / "tasks" / "abc").mkdir(parents=True)
        (claude / "skills").mkdir(parents=True)
        notes.mkdir(parents=True)
        project.mkdir(parents=True)
        gitrepo_project.mkdir(parents=True)
        os.symlink(claude / "skills", codex / "skills")

        (claude / "CLAUDE.md").write_text(
            """# Global Instructions
- Root cause first with file:line evidence.
- Use agents in parallel for independent work.
- E2E_CANARY_PASSWORD=P@ssw0rd-SYNC-DoNotLeak!
- Authorization: Bearer e2e_canary_bearer_9f1e4c8b7a6d5c4b
- X-API-Secret: e2e_canary_x_api_secret_123456
- client_secret=e2e_canary_client_secret_abcdef
- auth_pass=e2e_canary_auth_pass_abcdef
- ghp_E2E_CANARY_0123456789abcdef0123456789abcdef
- sk-live-E2E_CANARY_0123456789abcdef
- xoxb-E2E-CANARY-1234567890
- Grafana login: admin / E2E_CANARY_DASH_PASS123
- Server: 203.0.113.24
- Node: NODE__203.0.113.24
- IPv6: fd00:dead:beef::42
- URL: mysql://sync_user:E2E_CANARY_DB_PASS@203.0.113.44:3306/app
- HTTPS: https://sync_user:E2E_CANARY_BASIC_PASS@example.invalid/api?token=e2e_canary_query_token
-----BEGIN OPENSSH PRIVATE KEY-----
E2E_CANARY_PRIVATE_KEY_BODY
-----END OPENSSH PRIVATE KEY-----
""",
            encoding="utf-8",
        )
        (claude / "settings.json").write_text('{"env":{"SECRET_TOKEN":"ghp_shouldnotleak123456"}}\n', encoding="utf-8")
        (project / "CLAUDE.md").write_text(
            """# Project Rules
- Remote Config gate before publish.
- WHMCS deploy requires backup and rollback.
- contact admin@example.com
- key path ~/.ssh/e2e_canary_private_key
- node token /etc/e2e-sync/node-token.txt
- docs host 198.51.100.17 and 2001:db8:abcd::1234
""",
            encoding="utf-8",
        )
        (gitrepo_project / "CLAUDE.md").write_text(
            """# Gitrepo Project Rules
- Use project-level CLAUDE discovery.
- Release is held until user unholds.
""",
            encoding="utf-8",
        )
        (claude / "agent-memory" / "facts-verifier" / "MEMORY.md").write_text(
            "- [sing-box facts](facts_singbox.md) - refresh before use\n"
            "- [OpenWrt apk facts](facts_openwrt.md) - verified format\n",
            encoding="utf-8",
        )
        (claude / "plans" / "held-release.md").write_text("Do not release until user unholds\n", encoding="utf-8")
        (claude / "tasks" / "abc" / "1.json").write_text('{"title":"held"}\n', encoding="utf-8")

        content = collect_context(
            claude_home=claude,
            codex_home=codex,
            projects=[project, *discover_gitrepo_projects(gitrepo, max_depth=3)],
            max_file_bytes=DEFAULT_MAX_FILE_BYTES,
            max_depth=3,
        )
        out = write_note(content, notes, stamp="2000-01-01T00-00-00+0000")
        text = out.read_text(encoding="utf-8")

        required = [
            "Root cause first",
            "Use agents in parallel",
            "Remote Config gate",
            "WHMCS deploy",
            "Gitrepo Project Rules",
            "Release is held",
            "facts-verifier",
            "held-release.md",
            "symlink ->",
            "[REDACTED_IP]",
            "[REDACTED_SECRET_LINE]",
            "[REDACTED_SECRET_PATH]",
            "[REDACTED_CREDS_PAIR]",
            "[REDACTED_PRIVATE_KEY_BLOCK]",
            "Redaction counts",
        ]
        for item in required:
            if item not in text:
                raise AssertionError(f"missing required text: {item}")
        assert_not_contains(
            text,
            [
                "P@ssw0rd-SYNC-DoNotLeak!",
                "e2e_canary_bearer",
                "e2e_canary_x_api_secret",
                "e2e_canary_client_secret",
                "e2e_canary_auth_pass",
                "ghp_E2E_CANARY",
                "sk-live-E2E_CANARY",
                "xoxb-E2E-CANARY",
                "E2E_CANARY_DASH_PASS123",
                "203.0.113.24",
                "198.51.100.17",
                "fd00:dead:beef::42",
                "2001:db8:abcd::1234",
                "admin@example.com",
                "~/.ssh/e2e_canary_private_key",
                "/etc/e2e-sync/node-token.txt",
                "E2E_CANARY_PRIVATE_KEY_BODY",
                "E2E_CANARY_BASIC_PASS",
                "e2e_canary_query_token",
            ],
        )
        mode = out.stat().st_mode & 0o777
        if mode != 0o600:
            raise AssertionError(f"expected 0600 output mode, got {oct(mode)}")
        print(f"SELF-TEST PASS {out}")
    finally:
        shutil.rmtree(root, ignore_errors=True)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--claude-home", default=str(Path.home() / ".claude"))
    parser.add_argument("--codex-home", default=str(Path.home() / ".codex"))
    parser.add_argument("--project", action="append", help="Project root to scan for CLAUDE.md files. Repeatable.")
    parser.add_argument("--gitrepo-root", action="append", help="Discover Git/project roots containing CLAUDE.md under this directory. Repeatable.")
    parser.add_argument("--gitrepo-max-depth", type=int, default=5, help="Max depth under --gitrepo-root while discovering CLAUDE.md files.")
    parser.add_argument("--output-dir", help="Write note to this directory. Useful for temp smoke tests.")
    parser.add_argument("--write", action="store_true", help="Persist the generated note to the default Codex memory notes directory.")
    parser.add_argument("--max-depth", type=int, default=4)
    parser.add_argument("--max-file-bytes", type=int, default=DEFAULT_MAX_FILE_BYTES)
    parser.add_argument("--dry-run", action="store_true", help="Print the generated note instead of writing it.")
    parser.add_argument("--self-test", action="store_true", help="Run fixture-based end-to-end tests.")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.self_test:
        run_self_test()
        return 0
    run_sync(args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
