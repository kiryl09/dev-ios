#!/bin/sh
set -eu

meta=$(dd bs=65536 count=1 2>/dev/null)

python3 - "$meta" <<'PY'
import hashlib
import json
import os
import re
import signal
import subprocess
import sys
import time
import uuid
from pathlib import Path

meta = sys.argv[1] if len(sys.argv) > 1 else ""
try:
    payload = json.loads(meta) if meta.strip() else {}
except json.JSONDecodeError:
    payload = {}

event = payload.get("hook_event_name") or ""
conversation_id = (
    payload.get("conversation_id")
    or payload.get("session_id")
    or "unknown"
)
command = payload.get("command") or ""
duration = payload.get("duration")
output = payload.get("output") or ""

REGISTRY_ROOT = Path.home() / ".cursor" / "dev-ios" / "shell-registry"
REGISTRY_ROOT.mkdir(parents=True, exist_ok=True)
registry_path = REGISTRY_ROOT / f"{conversation_id}.jsonl"

SKILL_SCRIPT_RE = re.compile(
    r"(?:^|[\s\"'])(?:plugins/)?dev-ios/skills/[^/\s\"']+/scripts/",
    re.IGNORECASE,
)
LONG_RUNNING_RE = re.compile(
    r"serve-sim|swiftui-preview-browser\.py|npx\s+--yes\s+serve-sim",
    re.IGNORECASE,
)
DIAGNOSTIC_RE = re.compile(
    r"dump_zsh_state.*ps\s+-axo|ps\s+-axo.*RuntimeRoot|ps\s+-axo.*SpringBoard",
    re.IGNORECASE,
)

MCP_XCODEBUILD_SERVER = "XcodeBuildMCP"
MCP_XCODEBUILD_TOOLS = frozenset(
    {"build_sim", "test_sim", "build_run_sim", "clean"}
)


def should_track(cmd: str) -> bool:
    if not cmd.strip():
        return False
    if SKILL_SCRIPT_RE.search(cmd):
        return True
    if LONG_RUNNING_RE.search(cmd):
        return True
    if DIAGNOSTIC_RE.search(cmd):
        return True
    return False


def classify(cmd: str) -> str:
    if LONG_RUNNING_RE.search(cmd):
        return "long_running"
    if DIAGNOSTIC_RE.search(cmd):
        return "diagnostic"
    return "script"


def append_registry(record: dict) -> None:
    with registry_path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, separators=(",", ":")) + "\n")


def load_registry() -> list[dict]:
    if not registry_path.is_file():
        return []
    rows = []
    for line in registry_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return rows


def command_key(cmd: str) -> str:
    normalized = re.sub(r"\s+", " ", cmd.strip())[:500]
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest()[:16]


def normalize_command(cmd: str) -> str:
    return re.sub(r"\s+", " ", cmd.strip())


def list_process_rows() -> list[tuple[int, str]]:
    result = subprocess.run(
        ["ps", "-axo", "pid=,command="],
        capture_output=True,
        text=True,
        check=False,
    )
    rows: list[tuple[int, str]] = []
    for line in result.stdout.splitlines():
        match = re.match(r"\s*(\d+)\s+(.*)$", line)
        if not match:
            continue
        rows.append((int(match.group(1)), match.group(2)))
    return rows


def command_matches_process(registered: str, process_cmd: str) -> bool:
    reg = normalize_command(registered)
    proc = normalize_command(process_cmd)
    if not reg or not proc:
        return False
    if reg == proc:
        return True
    if len(proc) >= 48 and proc in reg:
        return True
    if len(reg) >= 48 and reg in proc:
        return True
    return False


def capture_run_pids(registered: str) -> list[int]:
    exact: list[int] = []
    fuzzy: list[int] = []
    reg_norm = normalize_command(registered)
    for pid, process_cmd in list_process_rows():
        proc_norm = normalize_command(process_cmd)
        if reg_norm == proc_norm:
            exact.append(pid)
        elif command_matches_process(registered, process_cmd):
            fuzzy.append(pid)
    if exact:
        return sorted(set(exact))
    if len(fuzzy) == 1:
        return fuzzy
    script_match = re.search(
        r"dev-ios/skills/[^/\s\"']+/scripts/[^\s\"']+",
        registered,
        re.IGNORECASE,
    )
    if script_match:
        tail = script_match.group(0)
        tail_pids = [
            pid for pid, process_cmd in list_process_rows() if tail in process_cmd
        ]
        if len(tail_pids) == 1:
            return tail_pids
    return sorted(set(fuzzy))


def child_pids(root: int) -> list[int]:
    result = subprocess.run(
        ["pgrep", "-P", str(root)],
        capture_output=True,
        text=True,
        check=False,
    )
    children: list[int] = []
    for line in result.stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            child = int(line)
        except ValueError:
            continue
        children.append(child)
        children.extend(child_pids(child))
    return children


def expand_run_pids(registered: str, pids: list[int]) -> list[int]:
    expanded = set(pids)
    for pid in pids:
        expanded.update(child_pids(pid))
    if expanded:
        return sorted(expanded)
    return capture_run_pids(registered)


def terminate_pids(pids: list[int]) -> list[int]:
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(2)
    survivors = []
    for pid in pids:
        try:
            os.kill(pid, 0)
            survivors.append(pid)
        except ProcessLookupError:
            pass
    return survivors


def latest_started(rows: list[dict], key: str) -> dict | None:
    matches = [row for row in rows if row.get("phase") == "started" and row.get("key") == key]
    return matches[-1] if matches else None


def collect_tracked_pids(rows: list[dict]) -> list[int]:
    pids: set[int] = set()
    for row in rows:
        if row.get("phase") != "tracked":
            continue
        for pid in row.get("pids") or []:
            try:
                pids.add(int(pid))
            except (TypeError, ValueError):
                continue
    return sorted(pids)


def in_flight_pids(rows: list[dict]) -> list[int]:
    pids: set[int] = set(collect_tracked_pids(rows))
    tracked_run_ids = {
        row.get("run_id") for row in rows if row.get("phase") == "tracked" and row.get("run_id")
    }
    for row in rows:
        if row.get("phase") != "started":
            continue
        run_id = row.get("run_id")
        if run_id and run_id in tracked_run_ids:
            continue
        command = row.get("command") or ""
        if not command:
            continue
        pids.update(expand_run_pids(command, capture_run_pids(command)))
    return sorted(pids)


def kill_pids(pids: list[int]) -> tuple[list[dict], list[dict]]:
    killed: list[dict] = []
    skipped: list[dict] = []
    for pid in pids:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            continue
        survivors = terminate_pids([pid])
        if survivors:
            skipped.append({"pid": pid, "reason": "survived"})
        else:
            killed.append({"pid": pid})
    return killed, skipped


def mcp_build_tracked(payload: dict) -> tuple[bool, str]:
    server = (payload.get("mcp_server_name") or "").strip()
    tool = (payload.get("tool_name") or "").strip()
    if server != MCP_XCODEBUILD_SERVER:
        return False, tool
    if tool not in MCP_XCODEBUILD_TOOLS:
        return False, tool
    return True, tool


def read_project_path_from_config(config_path: Path, repo_root: Path) -> str | None:
    text = config_path.read_text(encoding="utf-8")
    match = re.search(r"^\s+projectPath:\s+(\S+)\s*$", text, re.MULTILINE)
    if not match:
        return None
    project_path = Path(match.group(1))
    if not project_path.is_absolute():
        project_path = repo_root / project_path
    return str(project_path.resolve())


def resolve_mcp_project_path(payload: dict) -> str | None:
    candidates: list[str] = []
    tool_input = payload.get("tool_input")
    args: dict = {}
    if isinstance(tool_input, str) and tool_input.strip():
        try:
            parsed = json.loads(tool_input)
            if isinstance(parsed, dict):
                args = parsed
        except json.JSONDecodeError:
            args = {}
    elif isinstance(tool_input, dict):
        args = tool_input

    for key in ("projectPath", "project_path", "workspacePath", "workspace_path"):
        value = args.get(key) or payload.get(key)
        if value:
            candidates.append(str(value))

    session_defaults = payload.get("session_defaults") or payload.get("defaults")
    if isinstance(session_defaults, dict):
        for key in ("projectPath", "workspacePath"):
            value = session_defaults.get(key)
            if value:
                candidates.append(str(value))

    workspace_roots = payload.get("workspace_roots") or []
    if isinstance(workspace_roots, str):
        workspace_roots = [workspace_roots]

    for raw in candidates:
        path = Path(raw).expanduser()
        if not path.is_absolute():
            for root in workspace_roots:
                candidate = (Path(root) / path).resolve()
                if candidate.exists():
                    path = candidate
                    break
        else:
            path = path.resolve()
        return str(path)

    for root in workspace_roots:
        config = Path(root) / ".xcodebuildmcp" / "config.yaml"
        if config.is_file():
            resolved = read_project_path_from_config(config, Path(root))
            if resolved:
                return resolved
    return None


def open_mcp_builds(rows: list[dict]) -> list[dict]:
    finished = {
        row.get("run_id")
        for row in rows
        if row.get("phase") == "mcp_finished" and row.get("run_id")
    }
    open_rows: list[dict] = []
    for row in rows:
        if row.get("phase") != "mcp_started":
            continue
        run_id = row.get("run_id")
        if run_id and run_id in finished:
            continue
        open_rows.append(row)
    return open_rows


def close_open_mcp_builds(rows: list[dict], reason: str) -> list[dict]:
    closed: list[dict] = []
    for row in open_mcp_builds(rows):
        record = {
            "phase": "mcp_finished",
            "run_id": row.get("run_id"),
            "tool": row.get("tool"),
            "project_path": row.get("project_path"),
            "reason": reason,
            "ts": time.time(),
        }
        append_registry(record)
        closed.append(record)
    return closed


def rewrite_registry(rows: list[dict]) -> None:
    kept = [
        row
        for row in rows
        if row.get("phase") not in ("tracked", "started", "mcp_started")
    ]
    if kept:
        registry_path.write_text(
            "".join(json.dumps(row, separators=(",", ":")) + "\n" for row in kept),
            encoding="utf-8",
        )
    elif registry_path.is_file():
        registry_path.unlink(missing_ok=True)


def force_stop_session_processes(clear_registry: bool) -> dict:
    rows = load_registry()
    pids = in_flight_pids(rows)
    killed, skipped = kill_pids(pids)
    mcp_closed = close_open_mcp_builds(rows, "stop_registry_only")

    if clear_registry:
        if registry_path.is_file():
            registry_path.unlink(missing_ok=True)
    else:
        rewrite_registry(rows)

    mode = "session_end" if clear_registry else "stop_aborted"
    return {
        "mode": mode,
        "killed": killed,
        "skipped": skipped,
        "mcp_closed": mcp_closed,
    }


def cleanup_session_end() -> dict:
    return force_stop_session_processes(clear_registry=True)


def cleanup_stale_diagnostics() -> dict:
    rows = load_registry()
    now = time.time()
    killed = []
    skipped = []

    for row in rows:
        if row.get("phase") != "tracked":
            continue
        if row.get("kind") != "diagnostic":
            continue
        started_at = float(row.get("started_ts") or row.get("ts") or 0)
        if now - started_at < 30:
            continue
        for pid in row.get("pids") or []:
            try:
                pid_int = int(pid)
            except (TypeError, ValueError):
                continue
            try:
                os.kill(pid_int, 0)
            except ProcessLookupError:
                continue
            survivors = terminate_pids([pid_int])
            if survivors:
                skipped.append({"pid": pid_int, "reason": "survived"})
            else:
                killed.append({"pid": pid_int})

    return {"mode": "stale", "killed": killed, "skipped": skipped}


if event == "beforeShellExecution":
    if should_track(command):
        key = command_key(command)
        append_registry(
            {
                "phase": "started",
                "run_id": str(uuid.uuid4()),
                "key": key,
                "command": command,
                "kind": classify(command),
                "ts": time.time(),
            }
        )
elif event == "afterShellExecution":
    if should_track(command):
        rows = load_registry()
        key = command_key(command)
        started = latest_started(rows, key)
        run_id = started.get("run_id") if started else str(uuid.uuid4())
        started_ts = float(started.get("ts") or time.time()) if started else time.time()
        kind = classify(command)
        pids = expand_run_pids(command, capture_run_pids(command))
        append_registry(
            {
                "phase": "tracked",
                "run_id": run_id,
                "key": key,
                "command": command,
                "kind": kind,
                "pids": pids,
                "started_ts": started_ts,
                "ts": time.time(),
                "duration_ms": duration,
                "output_bytes": len(output),
            }
        )
elif event == "beforeMCPExecution":
    tracked, tool = mcp_build_tracked(payload)
    if tracked:
        append_registry(
            {
                "phase": "mcp_started",
                "run_id": str(uuid.uuid4()),
                "tool": tool,
                "project_path": resolve_mcp_project_path(payload),
                "ts": time.time(),
            }
        )
elif event == "afterMCPExecution":
    tracked, tool = mcp_build_tracked(payload)
    if tracked:
        rows = load_registry()
        open_for_tool = [
            row for row in open_mcp_builds(rows) if row.get("tool") == tool
        ]
        match = open_for_tool[-1] if open_for_tool else None
        run_id = match.get("run_id") if match else str(uuid.uuid4())
        project_path = (match or {}).get("project_path") or resolve_mcp_project_path(
            payload
        )
        append_registry(
            {
                "phase": "mcp_finished",
                "run_id": run_id,
                "tool": tool,
                "project_path": project_path,
                "duration_ms": payload.get("duration"),
                "ts": time.time(),
            }
        )
elif event == "stop":
    status = payload.get("status") or ""
    if status in ("completed", "aborted", "error"):
        result = force_stop_session_processes(clear_registry=False)
        messages = []
        if result["killed"]:
            messages.append(
                f"shell processes stopped: {result['killed']}"
            )
        if messages:
            print(
                json.dumps(
                    {
                        "agent_message": f"dev-ios: agent stop ({status}) — {'; '.join(messages)}"
                    }
                )
            )
elif event == "sessionEnd":
    result = cleanup_session_end()
    messages = []
    if result["killed"]:
        messages.append(f"shell processes stopped: {result['killed']}")
    if messages:
        print(
            json.dumps(
                {
                    "agent_message": f"dev-ios: session end — {'; '.join(messages)}"
                }
            )
        )

PY

exit 0
