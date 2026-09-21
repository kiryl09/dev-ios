#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# shellcheck source=xcodebuildmcp-host-dir.sh
source "$SCRIPT_DIR/xcodebuildmcp-host-dir.sh"
RESOLVE_SCRIPT="$SCRIPT_DIR/resolve-derived-data-path.sh"
export XCODEBUILDMCP_BOOTSTRAP_SCRIPT="$SCRIPT_DIR/bootstrap-xcodebuildmcp-config.sh"
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
  esac
done

if ! project_root="$(xcodebuildmcp_find_host_dir 1)"; then
  echo "error: no .xcodebuildmcp/config.yaml beside a .xcodeproj" >&2
  echo "hint: run bootstrap-xcodebuildmcp-config.sh --xcodeproj <App.xcodeproj> (yaml goes in the same folder as the project)" >&2
  echo "then Developer: Reload Window" >&2
  exit 1
fi

export XCODEBUILDMCP_CWD="$project_root"
cd "$project_root"

if ! derived_path="$("$RESOLVE_SCRIPT" --sync-config --write-local)"; then
  echo "error: could not resolve/sync DerivedData path" >&2
  exit 1
fi

export XCODEBUILDMCP_DERIVED_DATA_PATH="$derived_path"

tests_scheme="$(python3 - "$project_root/.xcodebuildmcp/config.yaml" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text()
block = re.search(
    r"^  tests:\s*\n(.*?)(?=^  [A-Za-z_]+:|^sessionDefaults:|\Z)",
    text,
    re.MULTILINE | re.DOTALL,
)
if not block:
    print("Tests")
    raise SystemExit(0)
match = re.search(r"^    scheme:\s+(\S+)\s*$", block.group(1), re.MULTILINE)
print(match.group(1) if match else "Tests")
PY
)"
export XCODEBUILDMCP_PINNED_TEST_PRODUCTS_PATH="$derived_path/${tests_scheme}.xctestproducts"
mkdir -p "$derived_path/Logs"

XBMCP_CACHE="${XCODEBUILDMCP_NPM_CACHE:-${HOME}/.cache/dev-ios-xcodebuildmcp}"
XBMCP_PIN_VERSION="$(tr -d '[:space:]' <"$SCRIPT_DIR/xcodebuildmcp-pinned-version")"
pin_target="$XBMCP_CACHE/node_modules/xcodebuildmcp/build/utils/test-products-path.js"
test_common_target="$XBMCP_CACHE/node_modules/xcodebuildmcp/build/utils/test-common.js"
if [[ -f "$pin_target" ]]; then
  pin_count="$(grep -c 'const pinned = process.env.XCODEBUILDMCP_PINNED_TEST_PRODUCTS_PATH' "$pin_target" || true)"
  if [[ "$pin_count" -gt 1 ]]; then
    rm -rf "$XBMCP_CACHE/node_modules/xcodebuildmcp"
  fi
fi
if [[ -f "$test_common_target" ]]; then
  dd_pin_count="$(grep -c 'pinnedDd = process.env.XCODEBUILDMCP_DERIVED_DATA_PATH' "$test_common_target" || true)"
  if [[ "$dd_pin_count" -gt 1 ]]; then
    rm -rf "$XBMCP_CACHE/node_modules/xcodebuildmcp"
  fi
fi
xbmcp_pkg_json="$XBMCP_CACHE/node_modules/xcodebuildmcp/package.json"
installed_version=""
if [[ -f "$xbmcp_pkg_json" ]]; then
  installed_version="$(node -p "require(process.argv[1]).version" "$xbmcp_pkg_json" 2>/dev/null || true)"
fi
if [[ ! -f "$XBMCP_CACHE/node_modules/xcodebuildmcp/build/cli.js" ]] || [[ "$installed_version" != "$XBMCP_PIN_VERSION" ]]; then
  rm -rf "$XBMCP_CACHE/node_modules/xcodebuildmcp"
  mkdir -p "$XBMCP_CACHE"
  (cd "$XBMCP_CACHE" && npm init -y >/dev/null 2>&1 && npm install "xcodebuildmcp@${XBMCP_PIN_VERSION}" --silent >/dev/null 2>&1)
fi
"$SCRIPT_DIR/patch-xcodebuildmcp-pinned-test-products.sh" "$XBMCP_CACHE/node_modules/xcodebuildmcp"
"$SCRIPT_DIR/patch-xcodebuildmcp-prepared-test-derived-data.sh" "$XBMCP_CACHE/node_modules/xcodebuildmcp"
export XCODEBUILDMCP_NPM_CACHE="$XBMCP_CACHE"
export NODE_PATH="$XBMCP_CACHE/node_modules${NODE_PATH:+:$NODE_PATH}"

echo "XCODEBUILDMCP_CWD=$XCODEBUILDMCP_CWD"
echo "XCODEBUILDMCP_DERIVED_DATA_PATH=$XCODEBUILDMCP_DERIVED_DATA_PATH"
echo "XCODEBUILDMCP_PINNED_TEST_PRODUCTS_PATH=$XCODEBUILDMCP_PINNED_TEST_PRODUCTS_PATH"
echo "derivedDataPath=$derived_path"

if [[ "$DRY_RUN" -eq 1 ]]; then
  exit 0
fi

# Disk patch pins test products; a stale shell NODE_OPTIONS --import hook double-patches and breaks startup.
if [[ "${NODE_OPTIONS:-}" == *xcodebuildmcp-pin-test-products* ]]; then
  unset NODE_OPTIONS
fi

exec node "$SCRIPT_DIR/xcodebuildmcp-mcp-entry.mjs" mcp
