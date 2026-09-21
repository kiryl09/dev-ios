#!/usr/bin/env bash
set -euo pipefail

MONOREPO_ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
ROOT="$MONOREPO_ROOT/dev-ios"
PLUGIN_REPO="$(CDPATH= cd -- "$ROOT/.." && pwd)"
MONOREPO_ROOT="$PLUGIN_REPO"
# shellcheck source=find-harness-checkout.sh
source "$(dirname "$0")/find-harness-checkout.sh"
HARNESS="$(find_harness_checkout "$MONOREPO_ROOT")"
WRAPPER="$ROOT/skills/build-ios-apps/scripts/xcodebuildmcp-with-xcode-derived-data.sh"
BOOTSTRAP="$ROOT/skills/build-ios-apps/scripts/bootstrap-xcodebuildmcp-config.sh"

! grep -q 'kill-xcodebuild' "$ROOT/skills/ios-simulator-browser/scripts/simulator-hygiene.sh"
! grep -q 'kill_project_xcodebuild' "$ROOT/hooks/lib/project_xcodebuild.py"
! grep -q 'probe_project_root' "$ROOT/skills/build-ios-apps/scripts/xcodebuildmcp-with-xcode-derived-data.sh"
grep -q 'Do not call MCP clean' "$ROOT/hooks/lib/mcp_dd_policy.py"
! grep -q 'deny_parallel_run' "$ROOT/hooks/lib/mcp_dd_policy.py"
grep -q '## One at a time' "$ROOT/skills/ios-debugger-agent/SKILL.md"

[[ -n "$HARNESS" ]]

bypass_perm() {
  python3 -c 'import json,sys; print(json.load(sys.stdin)["permission"])'
}
hook_payload() {
  python3 -c "import json,sys; print(json.dumps({'hook_event_name':'beforeShellExecution','tool_name':'Shell','command':sys.argv[1],'workspace_roots':[sys.argv[2]]}))" "$1" "$HARNESS"
}
[[ "$(hook_payload 'kill 12345' | "$ROOT/hooks/deny-xcode-bypass.sh" | bypass_perm)" == "deny" ]]
[[ "$(hook_payload 'simulator-hygiene.sh kill-xcodebuild' | "$ROOT/hooks/deny-xcode-bypass.sh" | bypass_perm)" == "deny" ]]
[[ "$(hook_payload "rm -rf $HOME/Library/Developer/Xcode/DerivedData/SomeProduct-x/SourcePackages" | "$ROOT/hooks/deny-xcode-bypass.sh" | bypass_perm)" == "deny" ]]
[[ "$(hook_payload 'npx --yes serve-sim@latest --kill ABC' | "$ROOT/hooks/deny-xcode-bypass.sh" | bypass_perm)" == "allow" ]]

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

grep -q 'bootstrap-xcodebuildmcp-config.sh' "$ROOT/skills/build-ios-apps/scripts/xcodebuildmcp-with-xcode-derived-data.sh"
grep -q 'bootstrap-xcodebuildmcp-config.sh' "$ROOT/skills/build-ios-apps/SKILL.md"
grep -q 'If MCP still exits' "$ROOT/skills/build-ios-apps/SKILL.md"
grep -q 'patch-xcodebuildmcp-prepared-test-derived-data.sh' "$ROOT/skills/build-ios-apps/scripts/xcodebuildmcp-with-xcode-derived-data.sh"
grep -q 'xcodebuildmcp-pinned-version' "$ROOT/skills/build-ios-apps/scripts/xcodebuildmcp-with-xcode-derived-data.sh"
PIN_VERSION="$(tr -d '[:space:]' <"$ROOT/skills/build-ios-apps/scripts/xcodebuildmcp-pinned-version")"
grep -q "xcodebuildmcp@\${XBMCP_PIN_VERSION}" "$ROOT/skills/build-ios-apps/scripts/xcodebuildmcp-with-xcode-derived-data.sh"
grep -q 'xcodebuildmcp-with-xcode-derived-data' "$ROOT/mcp.json"
! grep -q 'XCODEBUILDMCP_SEARCH_ROOT' "$ROOT/mcp.json"
! grep -q '\${workspaceFolder}' "$ROOT/mcp.json"
! grep -q '"cwd": "\${CURSOR_PLUGIN_ROOT}"' "$ROOT/mcp.json"
! grep -q '@latest' "$ROOT/mcp.json"

echo "gate-edges PASS"
