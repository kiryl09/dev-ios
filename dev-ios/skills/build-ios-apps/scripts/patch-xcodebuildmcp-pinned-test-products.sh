#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <xcodebuildmcp-package-root>" >&2
  exit 1
fi

target="$1/build/utils/test-products-path.js"
if [[ ! -f "$target" ]]; then
  echo "error: missing $target" >&2
  exit 1
fi

if grep -q 'XCODEBUILDMCP_PINNED_TEST_PRODUCTS_PATH' "$target"; then
  exit 0
fi

python3 - "$target" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
source = path.read_text()
needle = "function createDefaultTestProductsPath(toolName) {"
if needle not in source:
    raise SystemExit("patch target not found")
insert = """function createDefaultTestProductsPath(toolName) {
  const pinned = process.env.XCODEBUILDMCP_PINNED_TEST_PRODUCTS_PATH;
  if (pinned) {
    return pinned;
  }"""
path.write_text(source.replace(needle, insert, 1))
PY
