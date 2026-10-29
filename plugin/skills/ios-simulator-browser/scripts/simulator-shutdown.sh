#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: simulator-shutdown.sh <command> [options]

Shuts down booted simulators with simctl shutdown. Refuses while this project's xcodebuild is running. Does not quit Simulator.app or send signals.

Commands:
  shutdown            Shut down simulators (default: all except configured UDID)
  shutdown-all        Shut down every booted simulator

Options:
  --keep-udid UUID    Keep this UDID booted during shutdown (overrides config)
  --all               With shutdown: shut down configured device too (same as shutdown-all)
  --stale-seconds N   Stale xcodebuild threshold for refusal (default: 7200)

Reads simulatorId and projectPath from .xcodebuildmcp/config.yaml.
Run from the host project checkout.
EOF
}

SHUTDOWN_SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SHUTDOWN_HOST_DIR_LIB="$SHUTDOWN_SCRIPT_DIR/../../build-ios-apps/scripts/xcodebuildmcp-host-dir.sh"
# shellcheck source=../../build-ios-apps/scripts/xcodebuildmcp-host-dir.sh
source "$SHUTDOWN_HOST_DIR_LIB"

find_repo_root() {
  xcodebuildmcp_find_host_dir 0
}

read_configured_udid() {
  python3 - "$1" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text()
block = re.search(
    r"tests:\s*\n(?:[ \t].*\n)*?[ \t]+simulatorId:\s*(\S+)",
    text,
)
if not block:
    raise SystemExit("error: tests.simulatorId not found in config")
print(block.group(1))
PY
}

read_project_path() {
  python3 - "$1" "$2" <<'PY'
import re
import sys
from pathlib import Path

config_path = Path(sys.argv[1])
repo_root = Path(sys.argv[2])
text = config_path.read_text()
match = re.search(r"^\s+projectPath:\s+(\S+)\s*$", text, re.MULTILINE)
if not match:
    raise SystemExit("error: projectPath not found in config")
project_path = Path(match.group(1))
if not project_path.is_absolute():
    project_path = repo_root / project_path
print(project_path.resolve())
PY
}

list_active_devices_json() {
  xcrun simctl list devices --json
}

workload_python() {
  local plugin_lib
  plugin_lib="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/hooks/lib"
  python3 - "$plugin_lib" "$@" <<'PY'
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(sys.argv[1])))
import project_xcodebuild as px

SIMULATOR_MARKERS = (
    "Simulator.app",
    "com.apple.CoreSimulator",
    "SimLaunchHost",
    "SimStreamProcessor",
    "SimulatorTrampoline",
)

def is_simulator_process(command: str, comm: str) -> bool:
    haystack = f"{comm} {command}"
    return any(marker in haystack for marker in SIMULATOR_MARKERS)

def build_workload(project_path: str, stale_seconds: int, simulator_json: str | None) -> dict:
    project_name = os.path.basename(project_path)
    rows = px.list_process_rows()

    all_xcodebuild = [row for row in rows if "xcodebuild" in row["command"]]
    project_xcodebuild = [
        row
        for row in all_xcodebuild
        if px.project_matches(row["command"], project_path, project_name)
    ]
    simulator_rows = [row for row in rows if is_simulator_process(row["command"], row["comm"])]

    for row in project_xcodebuild:
        row["stale"] = row["elapsed_seconds"] >= stale_seconds
        row["kind"] = "xcodebuild"

    project_cpu = round(sum(row["cpu_percent"] for row in project_xcodebuild), 1)
    project_mem = round(sum(row["mem_percent"] for row in project_xcodebuild), 1)
    simulator_cpu = round(sum(row["cpu_percent"] for row in simulator_rows), 1)
    simulator_mem = round(sum(row["mem_percent"] for row in simulator_rows), 1)
    simulator_process_count = len(simulator_rows)

    simulator = json.loads(simulator_json) if simulator_json else {}
    active_device_count = int(simulator.get("active_device_count", 0))
    simulator_app_running = bool(simulator.get("simulator_app_running", False))
    stale_simulator_app = simulator_app_running and active_device_count == 0

    reasons = []
    if project_xcodebuild:
        reasons.append("project_xcodebuild_running")
    if any(row.get("stale") for row in project_xcodebuild):
        reasons.append("stale_project_xcodebuild")
    if active_device_count > 1:
        reasons.append("multiple_booted_simulators")
    if stale_simulator_app:
        reasons.append("stale_simulator_app")
    if simulator_cpu >= 50.0:
        reasons.append("high_simulator_cpu")
    if project_cpu >= 20.0:
        reasons.append("high_project_xcodebuild_cpu")
    if active_device_count == 0 and simulator_process_count > 0 and simulator_cpu >= 5.0:
        reasons.append("orphan_coresimulator_load")

    return {
        "xcodebuild_count": len(project_xcodebuild),
        "stale_xcodebuild_count": sum(1 for row in project_xcodebuild if row["stale"]),
        "all_xcodebuild_count": len(all_xcodebuild),
        "xcodebuild_processes": project_xcodebuild,
        "simulator_process_count": simulator_process_count,
        "simulator_cpu_percent": simulator_cpu,
        "simulator_mem_percent": simulator_mem,
        "project_xcodebuild_cpu_percent": project_cpu,
        "project_xcodebuild_mem_percent": project_mem,
        "background_load": bool(reasons),
        "background_load_reasons": reasons,
    }

mode = sys.argv[2]
project_path = sys.argv[3]
stale_seconds = int(sys.argv[4])
simulator_json = sys.argv[5] if len(sys.argv) > 5 and sys.argv[5] != "-" else None
workload = build_workload(project_path, stale_seconds, simulator_json)

if mode == "json":
    print(json.dumps(workload, indent=2))
    raise SystemExit(0)

raise SystemExit(f"error: unknown workload mode: {mode}")
PY
}

simulator_status_json() {
  local json_output="$1"
  python3 - "$json_output" <<'PY'
import json
import subprocess
import sys

payload = json.loads(sys.argv[1])
active_states = {"Booted", "Booting", "Shutting Down"}
devices = []
for runtime, entries in payload.get("devices", {}).items():
    for entry in entries:
        state = entry.get("state", "")
        if state not in active_states:
            continue
        name = entry.get("name", "")
        devices.append(
            {
                "udid": entry.get("udid", ""),
                "name": name,
                "state": state,
                "is_available": entry.get("isAvailable", False),
                "runtime": runtime,
                "is_clone": "clone" in name.casefold(),
            }
        )

sim_running = subprocess.run(
    ["pgrep", "-qx", "Simulator"], check=False
).returncode == 0

booted = [d for d in devices if d["state"] == "Booted"]
booting = [d for d in devices if d["state"] == "Booting"]
shutting = [d for d in devices if d["state"] == "Shutting Down"]

print(json.dumps(
    {
        "simulator_app_running": sim_running,
        "booted_count": len(booted),
        "booting_count": len(booting),
        "shutting_down_count": len(shutting),
        "active_device_count": len(devices),
        "active_count": len(devices),
        "devices": devices,
    }
))
PY
}

shutdown_devices() {
  local keep_udid="$1"
  local shutdown_all="$2"
  local json_output="$3"

  python3 - "$json_output" "$keep_udid" "$shutdown_all" <<'PY'
import json
import subprocess
import sys

payload = json.loads(sys.argv[1])
keep_udid = sys.argv[2]
shutdown_all = sys.argv[3] == "1"
active_states = {"Booted", "Booting"}

targets = []
for entries in payload.get("devices", {}).values():
    for entry in entries:
        state = entry.get("state", "")
        if state not in active_states:
            continue
        udid = entry.get("udid", "")
        if not shutdown_all and keep_udid and udid == keep_udid:
            continue
        targets.append((udid, entry.get("name", ""), state))

for udid, name, state in targets:
    result = subprocess.run(
        ["xcrun", "simctl", "shutdown", udid],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        err = (result.stderr or result.stdout or "unknown error").strip()
        print(f"failed\t{udid}\t{name}\t{err}", file=sys.stderr)
        raise SystemExit(1)
    print(f"shutdown\t{udid}\t{name}")

if not targets:
    print("nothing_to_shutdown")
PY
}

json_field() {
  local json_payload="$1"
  local expression="$2"
  printf '%s' "$json_payload" | python3 -c "import json,sys; data=json.load(sys.stdin); print(${expression})"
}

refuse_if_project_xcodebuild() {
  local project_path="$1"
  local stale_seconds="$2"
  local devices_json="$3"
  local simulator_json workload_json count
  simulator_json="$(simulator_status_json "$devices_json")"
  workload_json="$(workload_python json "$project_path" "$stale_seconds" "$simulator_json")"
  count="$(json_field "$workload_json" 'data["xcodebuild_count"]')"
  if [[ "${count:-0}" -gt 0 ]]; then
    echo "error: project xcodebuild still running (count=${count}); not shutting down simulators" >&2
    echo "wait_for_xcodebuild=yes"
    return 1
  fi
  return 0
}

command="${1:-}"
shift || true

keep_udid=""
shutdown_all=0
stale_seconds=7200

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep-udid)
      shift
      keep_udid="${1:-}"
      [[ -n "$keep_udid" ]] || {
        echo "error: --keep-udid requires a value" >&2
        exit 1
      }
      ;;
    --all) shutdown_all=1 ;;
    --stale-seconds)
      shift
      stale_seconds="${1:-}"
      [[ "$stale_seconds" =~ ^[0-9]+$ ]] || {
        echo "error: --stale-seconds requires a positive integer" >&2
        exit 1
      }
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

if [[ -z "$command" ]]; then
  usage >&2
  exit 1
fi

if ! repo_root="$(find_repo_root)"; then
  echo "error: .xcodebuildmcp/config.yaml not found (run from host project checkout)" >&2
  exit 1
fi

config_path="$repo_root/.xcodebuildmcp/config.yaml"
project_path="$(read_project_path "$config_path" "$repo_root")"
if [[ -z "$keep_udid" && "$shutdown_all" -eq 0 ]]; then
  keep_udid="$(read_configured_udid "$config_path")"
fi

devices_json="$(list_active_devices_json)"

case "$command" in
  shutdown)
    refuse_if_project_xcodebuild "$project_path" "$stale_seconds" "$devices_json"
    shutdown_devices "$keep_udid" "$shutdown_all" "$devices_json"
    ;;
  shutdown-all)
    refuse_if_project_xcodebuild "$project_path" "$stale_seconds" "$devices_json"
    shutdown_devices "" 1 "$devices_json"
    ;;
  *)
    echo "error: unknown command: $command" >&2
    usage >&2
    exit 1
    ;;
esac
