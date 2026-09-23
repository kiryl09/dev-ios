#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
  esac
done

XBMCP_CACHE="${XCODEBUILDMCP_NPM_CACHE:-$SCRIPT_DIR/xcodebuildmcp-npm-cache}"
XBMCP_PIN_VERSION="$(tr -d '[:space:]' <"$SCRIPT_DIR/xcodebuildmcp-pinned-version")"
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
export XCODEBUILDMCP_NPM_CACHE="$XBMCP_CACHE"
export NODE_PATH="$XBMCP_CACHE/node_modules${NODE_PATH:+:$NODE_PATH}"

"$SCRIPT_DIR/resolve-derived-data-path.sh" --sync-config >/dev/null 2>&1 || true

echo "xcodebuildmcp launcher ready (explicit tool args; session defaults disabled)"

if [[ "$DRY_RUN" -eq 1 ]]; then
  exit 0
fi

exec python3 "$SCRIPT_DIR/xcodebuildmcp-mcp-entry.py" mcp
