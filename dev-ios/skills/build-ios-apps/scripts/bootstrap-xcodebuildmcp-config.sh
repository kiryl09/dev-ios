#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# shellcheck source=xcodebuildmcp-host-dir.sh
source "$SCRIPT_DIR/xcodebuildmcp-host-dir.sh"

usage() {
  cat <<'EOF'
Usage: bootstrap-xcodebuildmcp-config.sh [--repo-root PATH] [--xcodeproj PATH]
       [--scheme NAME] [--test-scheme NAME] [--force]

Create <xcodeproj-dir>/.xcodebuildmcp/config.yaml next to a host iOS .xcodeproj.

  --repo-root     Deprecated alias; must match the folder that contains the .xcodeproj
  --xcodeproj     Host .xcodeproj (default: shallowest under project root; see repo README)
  --scheme        App scheme (default: xcodeproj basename)
  --test-scheme   Test scheme (default: <scheme>Tests)
  --force         Overwrite an existing yaml

Do not copy yaml from another checkout. After writing, ask for Developer: Reload Window.
EOF
}

repo_root=""
explicit_repo_root=""
xcodeproj=""
app_scheme=""
test_scheme=""
force=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root)
      explicit_repo_root="${2:-}"
      shift 2
      ;;
    --repo-root=*) explicit_repo_root="${1#--repo-root=}"; shift ;;
    --xcodeproj)
      xcodeproj="${2:-}"
      shift 2
      ;;
    --xcodeproj=*) xcodeproj="${1#--xcodeproj=}"; shift ;;
    --scheme)
      app_scheme="${2:-}"
      shift 2
      ;;
    --scheme=*) app_scheme="${1#--scheme=}"; shift ;;
    --test-scheme)
      test_scheme="${2:-}"
      shift 2
      ;;
    --test-scheme=*) test_scheme="${1#--test-scheme=}"; shift ;;
    --force) force=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

PLUGIN_SELF="$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)"

if [[ -z "$xcodeproj" ]]; then
  search_root=""
  if [[ -n "$explicit_repo_root" ]]; then
    search_root="$(cd "$explicit_repo_root" && pwd)"
  else
    search_root="$(xcodebuildmcp_project_root)"
  fi
  if ! xcodeproj="$(xcodebuildmcp_pick_host_xcodeproj "$search_root")"; then
    exit 1
  fi
fi

if [[ ! -d "$xcodeproj" ]]; then
  echo "error: .xcodeproj not found: $xcodeproj" >&2
  exit 1
fi
xcodeproj="$(cd "$(dirname "$xcodeproj")" && pwd)/$(basename "$xcodeproj")"
host_dir="$(dirname "$xcodeproj")"
repo_root="$host_dir"

if [[ -n "$explicit_repo_root" ]]; then
  explicit_abs="$(cd "$explicit_repo_root" && pwd)"
  if [[ "$explicit_abs" != "$host_dir" && "$explicit_abs" != "$(xcodebuildmcp_project_root)" ]]; then
    echo "error: --repo-root must be project root or the directory that contains the .xcodeproj ($host_dir)" >&2
    exit 1
  fi
fi

if [[ "$repo_root" == "$PLUGIN_SELF" || "$repo_root" == "$PLUGIN_SELF"/* ]]; then
  echo "error: host directory is inside the dev-ios plugin checkout, not a user iOS app" >&2
  exit 1
fi

config_path="$repo_root/.xcodebuildmcp/config.yaml"
if [[ -f "$config_path" && "$force" -eq 0 ]]; then
  echo "error: $config_path already exists (pass --force to overwrite)" >&2
  exit 1
fi

if [[ -z "$app_scheme" ]]; then
  app_scheme="$(basename "$xcodeproj" .xcodeproj)"
fi
if [[ -z "$test_scheme" ]]; then
  test_scheme="${app_scheme}Tests"
fi

pick_simulator() {
  python3 <<'PY'
import json
import subprocess

result = subprocess.run(
    ["xcrun", "simctl", "list", "devices", "available", "-j"],
    capture_output=True,
    text=True,
    check=True,
)
data = json.loads(result.stdout)
runtimes = sorted(
    [k for k in data.get("devices", {}) if "iOS" in k and "SimRuntime" in k],
    reverse=True,
)
for runtime in runtimes:
    for dev in data["devices"][runtime]:
        if not dev.get("isAvailable"):
            continue
        if dev.get("state") == "unavailable":
            continue
        print(dev["udid"])
        print(dev.get("name", "iPhone"))
        print(runtime.replace("com.apple.CoreSimulator.SimRuntime.", ""))
        raise SystemExit(0)
raise SystemExit("no simulator")
PY
}

sim_lines="$(pick_simulator)"
udid="$(printf '%s\n' "$sim_lines" | sed -n '1p')"
name="$(printf '%s\n' "$sim_lines" | sed -n '2p')"

mkdir -p "$repo_root/.xcodebuildmcp"
cat >"$config_path" <<YAML
schemaVersion: 1
activeSessionDefaultsProfile: app
sessionDefaultsProfiles:
  app:
    projectPath: $xcodeproj
    scheme: $app_scheme
    configuration: Debug
    simulatorName: $name
    simulatorId: $udid
    simulatorPlatform: iOS Simulator
    useLatestOS: false
    platform: iOS Simulator
  tests:
    projectPath: $xcodeproj
    scheme: $test_scheme
    configuration: Debug
    simulatorName: $name
    simulatorId: $udid
    simulatorPlatform: iOS Simulator
    useLatestOS: false
    platform: iOS Simulator
sessionDefaults:
  projectPath: $xcodeproj
  scheme: $app_scheme
  configuration: Debug
  simulatorName: $name
  simulatorId: $udid
  simulatorPlatform: iOS Simulator
  useLatestOS: false
  platform: iOS Simulator
YAML

printf '%s\n' "$config_path"
