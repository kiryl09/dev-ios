"""Block ios-dev MCP, skills, and skill scripts when workspace is out of iOS scope."""

from __future__ import annotations

import json
import re
import sys

from ios_scope import plugin_applies

IOS_ONLY_SKILLS = frozenset(
    {
        "build-ios-apps",
        "ios-app-intents",
        "ios-debugger-agent",
        "ios-ettrace-performance",
        "ios-memgraph-leaks",
        "ios-simulator-browser",
    }
)

XCODEBUILDMCP_RE = re.compile(r"xcodebuildmcp", re.IGNORECASE)
SKILL_DIR_IN_PATH_RE = re.compile(
    r"(^|/)(plugins/)?(local/)?ios-dev/skills/([^/]+)",
    re.IGNORECASE,
)
IOS_ONLY_SKILL_SCRIPT_RE = re.compile(
    r"(^|[\s\"'])(plugins/)?(local/)?ios-dev/skills/("
    + "|".join(re.escape(name) for name in sorted(IOS_ONLY_SKILLS))
    + r")/scripts/",
    re.IGNORECASE,
)


def is_xcodebuildmcp_server(name: str) -> bool:
    return bool(XCODEBUILDMCP_RE.search(name or ""))


def skill_name_in_path(raw: str | None) -> str | None:
    if not raw:
        return None
    match = SKILL_DIR_IN_PATH_RE.search(raw.replace("\\", "/"))
    if not match:
        return None
    return match.group(4).lower()


def is_ios_only_skill_path(raw: str | None) -> bool:
    name = skill_name_in_path(raw)
    return name in IOS_ONLY_SKILLS if name else False


def path_fields(payload: dict) -> list[str]:
    values: list[str] = []
    for key in (
        "file_path",
        "path",
        "target_directory",
        "glob_pattern",
        "command",
    ):
        value = payload.get(key)
        if isinstance(value, str) and value.strip():
            values.append(value)
    return values


def gate_decision(payload: dict) -> tuple[str, str | None]:
    if plugin_applies(payload):
        return "allow", None

    event = (payload.get("hook_event_name") or "").strip()
    tool = (payload.get("tool_name") or "").strip()

    if event == "beforeMCPExecution":
        server = (payload.get("mcp_server_name") or "").strip()
        if is_xcodebuildmcp_server(server):
            return "deny", (
                "XcodeBuildMCP (iOS Simulator) applies only when ios-dev-scope is "
                "active. Use Shell xcodebuild or Xcode for macOS hosts."
            )

    if event in ("beforeReadFile", "preToolUse"):
        if tool in ("Read", "TabRead", "Grep", "Glob") or event == "beforeReadFile":
            for raw in path_fields(payload):
                if is_ios_only_skill_path(raw):
                    return "deny", (
                        "This ios-dev skill is iOS-only (Simulator/MCP). "
                        "SwiftUI skills without ios- prefix remain available on macOS."
                    )

    if event == "beforeShellExecution" or tool == "Shell":
        command = payload.get("command") or ""
        if IOS_ONLY_SKILL_SCRIPT_RE.search(command):
            return "deny", (
                "ios-dev iOS-only skill scripts cannot run outside ios-dev-scope."
            )

    return "allow", None


def main() -> int:
    raw = sys.stdin.read()
    try:
        payload = json.loads(raw) if raw.strip() else {}
    except json.JSONDecodeError:
        payload = {}

    decision, message = gate_decision(payload)
    if decision == "deny":
        body = {
            "permission": "deny",
            "agent_message": message,
            "user_message": "ios-dev iOS-only tooling blocked for this workspace.",
        }
        print(json.dumps(body))
        return 0

    print('{"permission":"allow"}')
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
