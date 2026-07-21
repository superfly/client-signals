from __future__ import annotations

from dataclasses import dataclass
import os
import re
import stat
from pathlib import Path
from typing import Any, MutableMapping

DEFAULT_HEADER_PREFIX = "Fly"
MAX_INVOKED_BY_LEN = 64
INVOKED_BY_PATTERN = re.compile(r"^[a-z0-9][a-z0-9-]{0,63}$")

KNOWN_MARKERS = [
    {"agent": "claude-code", "env": "CLAUDECODE", "kind": "exactValue", "values": ["1"]},
    {"agent": "claude-code", "env": "CLAUDE_CODE_ENTRYPOINT", "kind": "presence"},
    {"agent": "pi", "env": "PI_CODING_AGENT", "kind": "exactValue", "values": ["true"]},
    {"agent": "openclaw", "env": "OPENCLAW_SHELL", "kind": "exactValue", "values": ["exec"]},
    {"agent": "openclaw", "env": "OPENCLAW_CLI", "kind": "exactValue", "values": ["1"]},
    {"agent": "goose", "env": "GOOSE_TERMINAL", "kind": "exactValue", "values": ["1"]},
    {"agent": "hermes", "env": "HERMES_SESSION_ID", "kind": "presence"},
    {"agent": "codex", "env": "CODEX_SANDBOX", "kind": "presence"},
    {"agent": "codex", "env": "CODEX_THREAD_ID", "kind": "presence"},
    {"agent": "cursor", "env": "CURSOR_TRACE_ID", "kind": "presence"},
    {"agent": "cursor", "env": "CURSOR_AGENT", "kind": "presence"},
    {"agent": "gemini-cli", "env": "GEMINI_CLI", "kind": "presence"},
    {"agent": "kiro", "env": "TERM_PROGRAM", "kind": "exactValue", "values": ["kiro"]},
    {"agent": "antigravity", "env": "ANTIGRAVITY_AGENT", "kind": "presence"},
    {"agent": "augment", "env": "AUGMENT_AGENT", "kind": "presence"},
    {"agent": "replit", "env": "REPL_ID", "kind": "presence"},
    {"agent": "opencode", "env": "OPENCODE", "kind": "presence"},
    {"agent": "opencode", "env": "OPENCODE_CALLER", "kind": "presence"},
    {"agent": "opencode", "env": "OPENCODE_CLIENT", "kind": "presence"},
    {"agent": "copilot", "env": "COPILOT_MODEL", "kind": "presence"},
    {"agent": "copilot", "env": "COPILOT_ALLOW_ALL", "kind": "presence"},
    {"agent": "kilo-code", "env": "KILO_PLATFORM", "kind": "exactValue", "values": ["vscode"]},
]


@dataclass(frozen=True)
class Signals:
    interactive: bool
    parent: str
    agent: str = ""
    agent_source: str = ""
    ci: bool = False


_cached_signals: Signals | None = None


def detect() -> Signals:
    agent, source = _detect_agent()
    return Signals(
        interactive=_is_interactive(),
        parent=_parent_bucket(),
        agent=agent,
        agent_source=source,
        ci=_is_ci(),
    )


def detect_once() -> Signals:
    global _cached_signals
    if _cached_signals is None:
        _cached_signals = detect()
    return _cached_signals


def reset_cached_for_test() -> None:
    global _cached_signals
    _cached_signals = None


def headers_for(signals: Signals | dict[str, Any], prefix: str = DEFAULT_HEADER_PREFIX) -> dict[str, str]:
    headers = {
        f"{prefix}-Client-Interactive": str(_field(signals, "interactive")).lower(),
        f"{prefix}-Client-Parent": _field(signals, "parent"),
    }
    agent = _field(signals, "agent")
    if agent:
        headers[f"{prefix}-Client-Agent"] = agent
        headers[f"{prefix}-Client-Agent-Source"] = _field(signals, "agent_source", "agentSource")
    if _field(signals, "ci"):
        headers[f"{prefix}-Client-CI"] = "true"
    return headers


def apply_headers(
    target: MutableMapping[str, str],
    signals: Signals | dict[str, Any],
    prefix: str = DEFAULT_HEADER_PREFIX,
) -> MutableMapping[str, str]:
    target.update(headers_for(signals, prefix))
    return target


def user_agent_suffix(signals: Signals | dict[str, Any]) -> str:
    suffix = f"interactive={str(_field(signals, 'interactive')).lower()}; parent={_field(signals, 'parent')}"
    agent = _field(signals, "agent")
    if agent:
        suffix += f"; agent={agent}"
    return f"({suffix})"


def operator(signals: Signals | dict[str, Any]) -> str:
    """Return one process-operator classification: ci > agent > interactive > unknown."""
    if _field(signals, "ci"):
        return "ci"
    if _field(signals, "agent"):
        return "agent"
    if _field(signals, "interactive"):
        return "interactive"
    return "unknown"


def sanitize_invoked_by(value: str) -> tuple[str, bool]:
    sanitized = value.strip().lower()
    if not sanitized or len(sanitized) > MAX_INVOKED_BY_LEN:
        return "", False
    if not INVOKED_BY_PATTERN.match(sanitized):
        return "", False
    return sanitized, True


def classify_parent_name(raw: str) -> str:
    name = os.path.basename(raw).lower()
    if name.endswith(".exe"):
        name = name[:-4]
    if name == "node":
        return "node"
    if name in {"python", "python3", "python2"}:
        return "python"
    if name in {"bash", "zsh", "fish", "sh", "dash", "ksh", "tcsh", "csh", "cmd", "powershell", "pwsh"}:
        return "shell"
    return "other"


def _detect_agent() -> tuple[str, str]:
    if "FLY_INVOKED_BY" in os.environ:
        agent, ok = sanitize_invoked_by(os.environ["FLY_INVOKED_BY"])
        if ok:
            return agent, "env:FLY_INVOKED_BY"

    for marker in KNOWN_MARKERS:
        env = marker["env"]
        if env not in os.environ:
            continue
        if marker["kind"] == "presence":
            return marker["agent"], f"env:{env}"
        if os.environ[env] in marker["values"]:
            return marker["agent"], f"env:{env}"

    if "AGENT" in os.environ:
        agent, ok = sanitize_invoked_by(os.environ["AGENT"])
        if ok:
            return agent, "env:AGENT"

    return "", ""


def _is_interactive() -> bool:
    try:
        return os.isatty(1)
    except OSError:
        return False


def _is_ci() -> bool:
    return "CI" in os.environ or "GITHUB_ACTIONS" in os.environ


def _parent_bucket() -> str:
    return classify_parent_name(_lookup_parent_name(os.getppid()))


def _lookup_parent_name(ppid: int) -> str:
    proc_comm = Path(f"/proc/{ppid}/comm")
    try:
        return proc_comm.read_text(encoding="utf-8").strip()
    except OSError:
        return ""


def _field(signals: Signals | dict[str, Any], snake: str, camel: str | None = None) -> Any:
    if isinstance(signals, dict):
        if snake in signals:
            return signals[snake]
        if camel is not None:
            return signals[camel]
        return signals[snake]
    return getattr(signals, snake)


def is_interactive_file_for_test(path: str) -> bool:
    try:
        return stat.S_ISCHR(os.stat(path).st_mode)
    except OSError:
        return False
