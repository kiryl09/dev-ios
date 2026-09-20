#!/usr/bin/env bash
set -euo pipefail

MONOREPO_ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
ROOT="$MONOREPO_ROOT/ios-dev"
MONOREPO_ROOT="$(CDPATH= cd -- "$ROOT/.." && pwd)"
# shellcheck source=find-harness-checkout.sh
source "$(dirname "$0")/find-harness-checkout.sh"
HOOK="$ROOT/hooks/deny-mcp-derived-data-copy.sh"
POLICY="$ROOT/hooks/lib/mcp_dd_policy.py"
DD="$HOME/Library/Developer/Xcode/DerivedData/Example-abcdefghijklmnopqrstuvwxyzabcd"

chmod +x "$HOOK"

deny() {
  python3 "$POLICY" deny <<<"$1" | python3 -c 'import json,sys; print(json.load(sys.stdin)["permission"])'
}

allow() {
  python3 "$POLICY" deny <<<"$1" | python3 -c 'import json,sys; assert json.load(sys.stdin)["permission"]=="allow"'
}

[[ "$(deny '{"hook_event_name":"beforeMCPExecution","tool_name":"clean","tool_input":{}}')" == "deny" ]]
[[ "$(deny '{"hook_event_name":"beforeMCPExecution","tool_name":"test_sim","tool_input":{}}')" == "deny" ]]
[[ "$(deny "{\"tool_name\":\"test_sim\",\"tool_input\":{\"testProductsPath\":\"$HOME/Library/Developer/XcodeBuildMCP/workspaces/foo/test-products/x\"}}")" == "deny" ]]
[[ "$(deny "{\"tool_name\":\"build_sim\",\"tool_input\":{\"buildForTesting\":true}}")" == "deny" ]]

foreign="$(mktemp -d)"
foreign_base="$(basename "$foreign")"
foreign_proj="$foreign/${foreign_base}.xcodeproj"
mkdir -p "$foreign/.xcodebuildmcp" "$foreign_proj"
touch "$foreign_proj/project.pbxproj"
cat >"$foreign/.xcodebuildmcp/config.yaml" <<YAML
schemaVersion: 1
sessionDefaults:
  projectPath: $foreign_proj
  scheme: ${foreign_base}
YAML
[[ "$(deny "{\"tool_name\":\"test_sim\",\"tool_input\":{\"testProductsPath\":\"$DD/OtherHostTests.xctestproducts\"},\"workspace_roots\":[\"$foreign\"]}")" == "deny" ]]
rm -rf "$foreign"

HARNESS="$(find_harness_checkout "$MONOREPO_ROOT")"
[[ -n "$HARNESS" ]]
python3 - "$POLICY" "$HARNESS" <<'PY'
import json, subprocess, sys
from pathlib import Path

policy, host = sys.argv[1], Path(sys.argv[2])
text = (host / ".xcodebuildmcp" / "config.yaml").read_text()
project = None
scheme = None
for line in text.splitlines():
    if line.strip().startswith("projectPath:"):
        project = line.split(":", 1)[1].strip()
    if line.strip().startswith("scheme:") and "Tests" in line:
        scheme = line.split(":", 1)[1].strip()
stem = Path(project).stem
dd = Path.home() / "Library/Developer/Xcode/DerivedData" / f"{stem}-abcdefghijklmnopqrstuvwxyzabcd"
payload = {
    "tool_name": "test_sim",
    "tool_input": {"testProductsPath": str(dd / f"{scheme}.xctestproducts")},
    "workspace_roots": [str(host)],
}
out = subprocess.check_output(["python3", policy, "deny"], input=json.dumps(payload).encode())
assert json.loads(out)["permission"] == "allow", out
PY

allow "{\"tool_name\":\"build_sim\",\"tool_input\":{\"buildForTesting\":true},\"session_defaults\":{\"extraArgs\":[\"-testProductsPath\",\"$DD/Scheme.xctestproducts\"]}}"

allow "{\"tool_name\":\"build_sim\",\"tool_input\":{}}"
allow "{\"tool_name\":\"test_sim\",\"tool_input\":{\"testProductsPath\":\"$DD/Scheme.xctestproducts\"}}"

echo "gate-deny PASS"
