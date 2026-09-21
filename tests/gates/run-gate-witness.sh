#!/usr/bin/env bash
set -euo pipefail

MONOREPO_ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
ROOT="$MONOREPO_ROOT/dev-ios"
POLICY="$ROOT/hooks/lib/mcp_dd_policy.py"
BASE="${HOME}/Library/Developer/XcodeBuildMCP/workspaces/gate-witness-test"
NEW_DIR="$BASE/DerivedData"

rm -rf "$BASE"
mkdir -p "$BASE/logs"
state="/tmp/gate-witness-$$.json"

payload_before='{"conversation_id":"gate-witness","hook_event_name":"beforeMCPExecution","tool_name":"build_sim"}'
payload_after='{"conversation_id":"gate-witness","hook_event_name":"afterMCPExecution","tool_name":"build_sim"}'

python3 "$POLICY" witness-before <<<"$payload_before" >/dev/null
mkdir -p "$NEW_DIR"
result="$(python3 "$POLICY" witness-after <<<"$payload_after")"
python3 -c 'import json,sys; assert json.load(sys.stdin)["permission"]=="deny"' <<<"$result"

rm -rf "$BASE"
echo "gate-witness PASS"
