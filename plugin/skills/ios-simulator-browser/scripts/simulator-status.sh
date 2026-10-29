#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: simulator-status.sh status [options]

Authoritative simulator inventory. Does not shut down devices, quit Simulator.app, or send signals.

Commands:
  status              Print booted/booting devices, Simulator.app, and background load

Options:
  --json              Machine-readable output for status
  --check             With status: exit 1 when background_load=true
  --stale-seconds N   Mark xcodebuild older than N seconds as stale in status only (default: 7200; not a kill signal)

Reads projectPath from .xcodebuildmcp/config.yaml.
Run from the host project checkout.
EOF
}

STATUS_SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
STATUS_HOST_DIR_LIB="$STATUS_SCRIPT_DIR/../../build-ios-apps/scripts/xcodebuildmcp-host-dir.sh"
# shellcheck source=../../build-ios-apps/scripts/xcodebuildmcp-host-dir.sh
source "$STATUS_HOST_DIR_LIB"

find_repo_root() {
  xcodebuildmcp_find_host_dir 0
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

if mode == "human":
    print(f"xcodebuild_count={workload['xcodebuild_count']}")
    print(f"stale_xcodebuild_count={workload['stale_xcodebuild_count']}")
    print(f"all_xcodebuild_count={workload['all_xcodebuild_count']}")
    print(f"project_xcodebuild_cpu_percent={workload['project_xcodebuild_cpu_percent']}")
    print(f"project_xcodebuild_mem_percent={workload['project_xcodebuild_mem_percent']}")
    print(f"simulator_process_count={workload['simulator_process_count']}")
    print(f"simulator_cpu_percent={workload['simulator_cpu_percent']}")
    print(f"simulator_mem_percent={workload['simulator_mem_percent']}")
    print(f"background_load={str(workload['background_load']).lower()}")
    if workload["background_load_reasons"]:
        print(f"background_load_reasons={','.join(workload['background_load_reasons'])}")
    for proc in workload["xcodebuild_processes"]:
        stale = "yes" if proc["stale"] else "no"
        print(
            "xcodebuild\t{pid}\t{elapsed}\tcpu={cpu}\tmem={mem}\tstale={stale}\t{command}".format(
                pid=proc["pid"],
                elapsed=proc["elapsed"],
                cpu=proc["cpu_percent"],
                mem=proc["mem_percent"],
                stale=stale,
                command=proc["command"],
            )
        )
    if workload["background_load"]:
        print(
            "warning: background Xcode/simulator load detected; wait or ask the user — do not kill xcodebuild or wipe SourcePackages"
        )
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

print_status_human() {
  local json_output="$1"
  local project_path="$2"
  local stale_seconds="$3"
  local simulator_json
  simulator_json="$(simulator_status_json "$json_output")"
  python3 - "$simulator_json" <<'PY'
import json
import sys

simulator = json.loads(sys.argv[1])
print(f"simulator_app_running={simulator['simulator_app_running']}")
print(f"active_device_count={simulator['active_device_count']}")
for device in simulator["devices"]:
    clone = "yes" if device["is_clone"] else "no"
    print(f"{device['state']}\t{device['udid']}\t{device['name']}\tclone={clone}")
if simulator["simulator_app_running"] and simulator["active_device_count"] == 0:
    print("warning: Simulator.app is running but simctl reports no Booted/Booting devices (stale windows)")
PY
  workload_python human "$project_path" "$stale_seconds" "$simulator_json"
}

json_field() {
  local json_payload="$1"
  local expression="$2"
  printf '%s' "$json_payload" | python3 -c "import json,sys; data=json.load(sys.stdin); print(${expression})"
}

command="${1:-}"
shift || true

json_flag=0
check_flag=0
stale_seconds=7200

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) json_flag=1 ;;
    --check) check_flag=1 ;;
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

devices_json="$(list_active_devices_json)"
status_exit=0

case "$command" in
  status)
    simulator_json="$(simulator_status_json "$devices_json")"
    workload_json="$(workload_python json "$project_path" "$stale_seconds" "$simulator_json")"
    if [[ "$json_flag" -eq 1 ]]; then
      python3 - "$simulator_json" "$workload_json" <<'PY'
import json
import sys

simulator = json.loads(sys.argv[1])
workload = json.loads(sys.argv[2])
print(json.dumps({**simulator, **workload}, indent=2))
PY
    else
      print_status_human "$devices_json" "$project_path" "$stale_seconds"
    fi
    if [[ "$check_flag" -eq 1 ]]; then
      background_load="$(json_field "$workload_json" '"true" if data["background_load"] else "false"')"
      [[ "$background_load" != "true" ]] || status_exit=1
    fi
    exit "$status_exit"
    ;;
  *)
    echo "error: unknown command: $command" >&2
    usage >&2
    exit 1
    ;;
esac
