#!/usr/bin/env bash
set -euo pipefail

MONOREPO_ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
ROOT="$MONOREPO_ROOT/plugin"
MONOREPO_ROOT="$(CDPATH= cd -- "$ROOT/.." && pwd)"
# shellcheck source=find-harness-checkout.sh
source "$(dirname "$0")/find-harness-checkout.sh"
HARNESS="$(find_harness_checkout "$MONOREPO_ROOT")"
[[ -n "$HARNESS" ]]

shopt -s nullglob
projs=("$HARNESS"/*.xcodeproj/project.pbxproj)
shopt -u nullglob
[[ ${#projs[@]} -ge 1 ]]
test -f "$HARNESS/.xcodebuildmcp/config.yaml"

python3 - "$HARNESS/.xcodebuildmcp/config.yaml" "$HARNESS" <<'PY'
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text()
root = Path(sys.argv[2]).resolve()
match = re.search(r"projectPath:\s+(\S+)", text)
assert match, "missing projectPath"
assert Path(match.group(1)).resolve().is_relative_to(root)
assert "sessionDefaultsProfiles:" in text
print("yaml_ok")
PY

TESTS_ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
OBSERVE="$TESTS_ROOT/observe-mcp-storage.sh"
chmod +x "$OBSERVE"
"$OBSERVE" check >/dev/null
"$OBSERVE" before /tmp/gate-miniap-observe.state >/dev/null
"$OBSERVE" after /tmp/gate-miniap-observe.state >/dev/null

echo "gate-miniap PASS"
