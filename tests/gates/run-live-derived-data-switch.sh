#!/usr/bin/env bash
set -euo pipefail

MONOREPO_ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
HARNESS1="$MONOREPO_ROOT/tests/xcode-sample_project"
HARNESS2="$MONOREPO_ROOT/tests/xcode-sample_project2"

usage() {
  cat <<'EOF'
Live DerivedData switch check (sequential hosts, no kill xcodebuild).

Prerequisites: plugin staged in .cursor/, user confirmed Reload Window, no in-flight xcodebuild.

Uses Shell xcodebuild with yaml DerivedData paths only. Not MCP or plugin sign-off.
Agent verification is XcodeBuildMCP after staging and Reload Window
(docs/tests/verification-mcp.md).
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

read_tests_block() {
  local host="$1"
  python3 - "$host" <<'PY'
import re, sys
from pathlib import Path
text = Path(sys.argv[1], ".xcodebuildmcp/config.yaml").read_text()
block = re.search(
    r"^  tests:\s*\n(.*?)(?=^  [A-Za-z_]+:|^sessionDefaults:|\Z)",
    text,
    re.M | re.S,
)
if not block:
    raise SystemExit("tests profile missing")
body = block.group(1)

def grab(key):
    m = re.search(rf"^    {key}:\s+(\S+)\s*$", body, re.M)
    if not m:
        raise SystemExit(f"missing {key}")
    return m.group(1)

sim = re.search(r"^    simulatorId:\s+(\S+)\s*$", body, re.M)
if not sim:
    raise SystemExit("simulatorId missing in tests profile")
print("\t".join([grab("projectPath"), grab("derivedDataPath"), grab("scheme"), grab("testProductsPath"), sim.group(1)]))
PY
}

resolve_test_products() {
  local products="$1"
  local scheme="$2"
  if [[ -L "$products" ]]; then
    printf '%s\n' "$products"
    return
  fi
  local newest="" child base
  shopt -s nullglob
  for child in "$products/${scheme}"_????-??-??_??-??-??.xctestproducts; do
    [[ -d "$child" ]] || continue
    base="$(basename "$child")"
    if [[ -z "$newest" || "$base" > "$(basename "$newest")" ]]; then
      newest="$child"
    fi
  done
  shopt -u nullglob
  if [[ -n "$newest" ]]; then
    printf '%s\n' "$newest"
  else
    printf '%s\n' "$products"
  fi
}

run_host_tests() {
  local host="$1"
  local project dd scheme products sim_id run_products
  IFS=$'\t' read -r project dd scheme products sim_id < <(read_tests_block "$host")
  local dest="platform=iOS Simulator,id=$sim_id"
  echo "== build-for-testing $(basename "$host") =="
  xcodebuild \
    -project "$project" \
    -scheme "$scheme" \
    -destination "$dest" \
    -derivedDataPath "$dd" \
    -testProductsPath "$products" \
    build-for-testing
  run_products="$(resolve_test_products "$products" "$scheme")"
  echo "== test-without-building $(basename "$host") $run_products =="
  xcodebuild \
    -destination "$dest" \
    -derivedDataPath "$dd" \
    -testProductsPath "$run_products" \
    test-without-building
}

dd1="$(read_tests_block "$HARNESS1" | cut -f2)"
dd_before="$(mktemp)"
ls -1d "$HOME/Library/Developer/Xcode/DerivedData"/PluginProbe-* 2>/dev/null | sort >"$dd_before" || true

run_host_tests "$HARNESS1"
probe1_mtime="$(stat -f '%m' "$dd1")"

run_host_tests "$HARNESS2"
probe1_mtime_after="$(stat -f '%m' "$dd1")"
[[ "$probe1_mtime" == "$probe1_mtime_after" ]] || {
  echo "FAIL: project1 DerivedData mtime changed during project2 build" >&2
  exit 1
}

run_host_tests "$HARNESS1"

dd_after="$(mktemp)"
ls -1d "$HOME/Library/Developer/Xcode/DerivedData"/PluginProbe-* 2>/dev/null | sort >"$dd_after" || true
diff -q "$dd_before" "$dd_after" >/dev/null || {
  echo "FAIL: extra PluginProbe-* DerivedData folders" >&2
  diff "$dd_before" "$dd_after" || true
  exit 1
}

echo "live-derived-data-switch PASS"
