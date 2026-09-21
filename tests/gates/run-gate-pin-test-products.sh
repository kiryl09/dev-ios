#!/usr/bin/env bash
set -euo pipefail

MONOREPO_ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
ROOT="$MONOREPO_ROOT/dev-ios"
SCRIPT_DIR="$ROOT/skills/build-ios-apps/scripts"
PIN="/tmp/dev-ios-gate-pinned.xctestproducts"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
cd "$tmpdir"
npm init -y >/dev/null 2>&1
PIN_VERSION="$(tr -d '[:space:]' <"$SCRIPT_DIR/xcodebuildmcp-pinned-version")"
npm install "xcodebuildmcp@${PIN_VERSION}" --silent >/dev/null 2>&1

"$SCRIPT_DIR/patch-xcodebuildmcp-pinned-test-products.sh" "$tmpdir/node_modules/xcodebuildmcp"
export XCODEBUILDMCP_PINNED_TEST_PRODUCTS_PATH="$PIN"
unset NODE_OPTIONS

out="$(node --input-type=module -e "import { createDefaultTestProductsPath } from './node_modules/xcodebuildmcp/build/utils/test-products-path.js'; console.log(createDefaultTestProductsPath('build_sim'));")"
[[ "$out" == "$PIN" ]]
echo "gate-pin-test-products PASS"
