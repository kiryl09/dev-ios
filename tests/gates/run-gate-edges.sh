#!/usr/bin/env bash
set -euo pipefail

MONOREPO_ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
ROOT="$MONOREPO_ROOT/plugin"
PLUGIN_REPO="$(CDPATH= cd -- "$ROOT/.." && pwd)"
MONOREPO_ROOT="$PLUGIN_REPO"
# shellcheck source=find-harness-checkout.sh
source "$(dirname "$0")/find-harness-checkout.sh"
HARNESS="$(find_harness_checkout "$MONOREPO_ROOT")"
WRAPPER="$ROOT/skills/build-ios-apps/scripts/xcodebuildmcp-with-xcode-derived-data.sh"
BOOTSTRAP="$ROOT/skills/build-ios-apps/scripts/bootstrap-xcodebuildmcp-config.sh"

STATUS="$ROOT/skills/ios-simulator-browser/scripts/simulator-status.sh"
SHUTDOWN="$ROOT/skills/ios-simulator-browser/scripts/simulator-shutdown.sh"
LIFECYCLE="$ROOT/hooks/agent-session-lifecycle.sh"
SIM_SKILL="$ROOT/skills/ios-simulator-browser/SKILL.md"

[[ ! -f "$ROOT/skills/ios-simulator-browser/scripts/simulator-hygiene.sh" ]]
! grep -q 'kill-xcodebuild' "$STATUS"
! grep -q 'simctl shutdown' "$STATUS"
! grep -q 'osascript' "$STATUS"
grep -q 'simctl shutdown' "$SHUTDOWN"
! grep -q 'osascript' "$SHUTDOWN"
! grep -q 'SIGTERM' "$SHUTDOWN"
! grep -q 'SIGTERM' "$LIFECYCLE"
! grep -q 'os.kill' "$LIFECYCLE"
! grep -q 'simulator-hygiene' "$SIM_SKILL"
[[ ! -f "$ROOT/skills/ios-simulator-browser/scripts/swiftui-preview-browser.py" ]]
[[ ! -f "$ROOT/skills/ios-memgraph-leaks/scripts/capture_sim_memgraph.sh" ]]
! grep -q 'kill_project_xcodebuild' "$ROOT/hooks/lib/project_xcodebuild.py"
! grep -q 'probe_project_root' "$ROOT/skills/build-ios-apps/scripts/xcodebuildmcp-with-xcode-derived-data.sh"
grep -q 'Do not call MCP `clean`' "$ROOT/skills/build-ios-apps/references/checkout-environment.md"
grep -q '## One at a time' "$ROOT/skills/ios-debugger-agent/SKILL.md"
! grep -q 'failClosed' "$ROOT/hooks/hooks.json"
! grep -q 'deny-' "$ROOT/hooks/hooks.json"
[[ ! -f "$ROOT/hooks/deny-xcode-bypass.sh" ]]
[[ ! -f "$ROOT/hooks/deny-mcp-derived-data-copy.sh" ]]
[[ ! -f "$ROOT/hooks/deny-dev-ios-out-of-scope.sh" ]]
[[ ! -f "$ROOT/hooks/witness-mcp-derived-data-copy.sh" ]]
grep -q 'xcodebuild' "$ROOT/rules/xcode-mcp-only.mdc"

[[ -n "$HARNESS" ]]

dd1="$(cd "$HARNESS" && "$ROOT/skills/build-ios-apps/scripts/resolve-derived-data-path.sh")"
dd2="$(cd "$HARNESS" && "$ROOT/skills/build-ios-apps/scripts/resolve-derived-data-path.sh" --sync-config)"
[[ "$dd1" == "$dd2" ]]

other="$(mktemp -d)"
mkdir -p "$other/.xcodebuildmcp"
printf 'schemaVersion: 1\nmarker: keep\n' >"$other/.xcodebuildmcp/config.yaml"
before="$(cat "$other/.xcodebuildmcp/config.yaml")"
(cd "$PLUGIN_REPO" && "$WRAPPER" --dry-run >/dev/null) || true
after="$(cat "$other/.xcodebuildmcp/config.yaml")"
[[ "$before" == "$after" ]]
rm -rf "$other"

grep -q 'bootstrap-xcodebuildmcp-config.sh' "$ROOT/skills/build-ios-apps/SKILL.md"
grep -q 'XCODEBUILDMCP_DISABLE_SESSION_DEFAULTS' "$ROOT/mcp.json"
grep -q 'Do \*\*not\*\* call `session_clear_defaults`' "$ROOT/skills/build-ios-apps/references/session-defaults.md"
grep -q 'buildForTesting: true' "$ROOT/skills/build-ios-apps/references/session-defaults.md"
grep -q 'yyyy-MM-dd_HH-mm-ss.xctestproducts' "$ROOT/skills/build-ios-apps/references/session-defaults.md"
grep -q 'Do not pass a timestamped child to `build_sim`' "$ROOT/skills/build-ios-apps/references/session-defaults.md"
grep -q 'SWIFT_ENABLE_INCREMENTAL_COMPILATION=NO' "$ROOT/skills/build-ios-apps/references/session-defaults.md"
grep -q 'timestamped child' "$MONOREPO_ROOT/docs/plugin-functional-requirements.md"
grep -q 'XCODEBUILDMCP_DISABLE_XCODE_AUTO_SYNC' "$ROOT/mcp.json"
! grep -q 'patch-xcodebuildmcp-prepared-test-derived-data.sh' "$ROOT/skills/build-ios-apps/scripts/xcodebuildmcp-with-xcode-derived-data.sh"
grep -q 'xcodebuildmcp-pinned-version' "$ROOT/skills/build-ios-apps/scripts/xcodebuildmcp-with-xcode-derived-data.sh"
grep -q 'resolve-derived-data-path.sh.*--sync-config' "$ROOT/skills/build-ios-apps/scripts/xcodebuildmcp-with-xcode-derived-data.sh"
PIN_VERSION="$(tr -d '[:space:]' <"$ROOT/skills/build-ios-apps/scripts/xcodebuildmcp-pinned-version")"
grep -q "xcodebuildmcp@\${XBMCP_PIN_VERSION}" "$ROOT/skills/build-ios-apps/scripts/xcodebuildmcp-with-xcode-derived-data.sh"
grep -q 'xcodebuildmcp-with-xcode-derived-data' "$ROOT/mcp.json"
! grep -q 'XCODEBUILDMCP_SEARCH_ROOT' "$ROOT/mcp.json"
! grep -q '\${workspaceFolder}' "$ROOT/mcp.json"
! grep -q '"cwd": "\${CURSOR_PLUGIN_ROOT}"' "$ROOT/mcp.json"
! grep -q '@latest' "$ROOT/mcp.json"

echo "gate-edges PASS"
