#!/usr/bin/env bash
set -euo pipefail

MONOREPO_ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
PLUGIN_REPO="$MONOREPO_ROOT/plugin"
# shellcheck source=find-harness-checkout.sh
source "$(dirname "$0")/find-harness-checkout.sh"
HARNESS="$(find_harness_checkout "$MONOREPO_ROOT")"
WRAPPER="$PLUGIN_REPO/skills/build-ios-apps/scripts/xcodebuildmcp-with-xcode-derived-data.sh"
BOOTSTRAP="$PLUGIN_REPO/skills/build-ios-apps/scripts/bootstrap-xcodebuildmcp-config.sh"
RESOLVE="$PLUGIN_REPO/skills/build-ios-apps/scripts/resolve-derived-data-path.sh"

chmod +x "$WRAPPER" "$BOOTSTRAP" "$RESOLVE"

gate_temp_xcodeproj() {
  local parent="$1"
  local base
  base="$(basename "$parent")"
  local proj="$parent/${base}.xcodeproj"
  mkdir -p "$proj"
  touch "$proj/project.pbxproj"
  printf '%s\n' "$proj"
}

tmpdir="$(mktemp -d)"
out="$(cd "$tmpdir" && "$WRAPPER" --dry-run)"
echo "$out" | grep -Fq "xcodebuildmcp launcher ready"
rm -rf "$tmpdir"

[[ -n "$HARNESS" ]]
expected="$(cd "$HARNESS" && WORKSPACE_FOLDER_PATHS="$HARNESS" "$RESOLVE")"
test -n "$expected"

created="$(mktemp -d)"
created="$(cd "$created" && pwd -P)"
proj="$(gate_temp_xcodeproj "$created")"
(cd "$created" && WORKSPACE_FOLDER_PATHS="$created" "$BOOTSTRAP" --xcodeproj "$proj" >/dev/null)
test -f "$created/.xcodebuildmcp/config.yaml"
grep -q 'projectPath:' "$created/.xcodebuildmcp/config.yaml"
grep -q '-parallel-testing-enabled' "$created/.xcodebuildmcp/config.yaml"
rm -rf "$created"

nested="$(mktemp -d)"
nested="$(cd "$nested" && pwd -P)"
nested_proj="$(gate_temp_xcodeproj "$nested/nested")"
"$BOOTSTRAP" --xcodeproj "$nested_proj" >/dev/null
test -f "$nested/nested/.xcodebuildmcp/config.yaml"
grep -q 'projectPath:' "$nested/nested/.xcodebuildmcp/config.yaml"
if "$BOOTSTRAP" --xcodeproj "$nested_proj" >/dev/null 2>&1; then
  echo "FAIL: bootstrap must refuse existing yaml without --force" >&2
  exit 1
fi
rm -rf "$nested"

probe="$(mktemp -d "$PLUGIN_REPO/.gate-probe.XXXXXX")"
probe_proj="$(gate_temp_xcodeproj "$probe")"
if "$BOOTSTRAP" --xcodeproj "$probe_proj" >/dev/null 2>&1; then
  echo "FAIL: bootstrap must refuse plugin checkout" >&2
  rm -rf "$probe"
  exit 1
fi
rm -rf "$probe"

ready="$(mktemp -d)"
ready="$(cd "$ready" && pwd -P)"
ready_proj="$(gate_temp_xcodeproj "$ready")"
"$BOOTSTRAP" --xcodeproj "$ready_proj" >/dev/null
expected="$(cd "$ready" && WORKSPACE_FOLDER_PATHS="$ready" "$RESOLVE")"
test -n "$expected"
rm -rf "$ready"

echo "gate-wrapper PASS"
