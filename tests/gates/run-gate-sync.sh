#!/usr/bin/env bash
set -euo pipefail

MONOREPO_ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
ROOT="$MONOREPO_ROOT/plugin"
RESOLVE="$ROOT/skills/build-ios-apps/scripts/resolve-derived-data-path.sh"
FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT

fixture_base="$(basename "$FIXTURE")"
proj="$FIXTURE/${fixture_base}.xcodeproj"
mkdir -p "$proj" "$FIXTURE/.xcodebuildmcp"
touch "$proj/project.pbxproj"

OTHER_DD="$HOME/Library/Developer/Xcode/DerivedData/OtherHost-abcdefghijklmnopqrstuvwxyzabcd"
cat >"$FIXTURE/.xcodebuildmcp/config.yaml" <<YAML
schemaVersion: 1
activeSessionDefaultsProfile: app
sessionDefaultsProfiles:
  app:
    projectPath: $proj
    derivedDataPath: $OTHER_DD
    scheme: $fixture_base
  tests:
    projectPath: $proj
    derivedDataPath: $OTHER_DD
    scheme: ${fixture_base}Tests
sessionDefaults:
  projectPath: $proj
  scheme: $fixture_base
YAML

cd "$FIXTURE"
dd_path="$("$RESOLVE" --sync-config --repo-root "$FIXTURE")"
[[ "$dd_path" == "$HOME/Library/Developer/Xcode/DerivedData/${fixture_base}-"* ]]

python3 - "$FIXTURE/.xcodebuildmcp/config.yaml" "$dd_path" "$OTHER_DD" "$fixture_base" <<'PY'
import sys
from pathlib import Path
text = Path(sys.argv[1]).read_text()
dd, other, base = sys.argv[2], sys.argv[3], sys.argv[4]
assert dd in text
assert other not in text
assert "-resultBundlePath" in text
assert f"{base}Tests.xcresult" in text
assert "-parallel-testing-enabled" in text
assert "-maximum-parallel-testing-workers" in text
print("sync_ok")
PY

echo "gate-sync PASS"
