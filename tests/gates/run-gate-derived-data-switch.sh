#!/usr/bin/env bash
set -euo pipefail

MONOREPO_ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
ROOT="$MONOREPO_ROOT/plugin"
RESOLVE="$ROOT/skills/build-ios-apps/scripts/resolve-derived-data-path.sh"
HARNESS1="$MONOREPO_ROOT/tests/xcode-sample_project"
HARNESS2="$MONOREPO_ROOT/tests/xcode-sample_project2"

[[ -f "$HARNESS1/.xcodebuildmcp/config.yaml" ]]
[[ -f "$HARNESS2/.xcodebuildmcp/config.yaml" ]]

yaml_dd() {
  python3 -c 'import sys; from pathlib import Path
text = Path(sys.argv[1]).read_text()
found = ""
for line in text.splitlines():
    s = line.strip()
    if s.startswith("derivedDataPath:"):
        found = s.split(":", 1)[1].strip()
if not found:
    raise SystemExit("missing derivedDataPath")
print(found)' "$1/.xcodebuildmcp/config.yaml"
}

dd1="$(cd "$HARNESS1" && "$RESOLVE")"
dd2="$(cd "$HARNESS2" && "$RESOLVE")"
[[ "$dd1" != "$dd2" ]]
[[ "$dd1" == "$HOME/Library/Developer/Xcode/DerivedData/"* ]]
[[ "$dd2" == "$HOME/Library/Developer/Xcode/DerivedData/"* ]]
[[ "$(yaml_dd "$HARNESS1")" == "$dd1" ]]
[[ "$(yaml_dd "$HARNESS2")" == "$dd2" ]]

echo "gate-derived-data-switch PASS"
