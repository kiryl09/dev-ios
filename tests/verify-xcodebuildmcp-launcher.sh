#!/usr/bin/env bash
set -euo pipefail

fail=0

if pgrep -f "xcodebuildmcp-mcp-entry\\.mjs mcp" >/dev/null; then
  echo "launcher: ok (mcp-entry.mjs)"
elif pgrep -f "xcodebuildmcp-with-xcode-derived-data\\.sh" >/dev/null; then
  echo "launcher: ok (wrapper bash)"
else
  echo "launcher: FAIL expected wrapper or mcp-entry.mjs; got:"
  pgrep -fl "xcodebuildmcp|mcp-entry" || echo "  (no xcodebuildmcp process)"
  fail=1
fi

if pgrep -f "npm exec xcodebuildmcp" >/dev/null || pgrep -f "_npx/.*/xcodebuildmcp mcp" >/dev/null; then
  echo "launcher: FAIL still using npx xcodebuildmcp (old MCP process — Stop server in Cursor MCP settings)"
  fail=1
fi

pid="$(pgrep -f "xcodebuildmcp mcp" | head -1 || true)"
if [[ -n "$pid" ]]; then
  if ps eww -p "$pid" 2>/dev/null | tr ' ' '\n' | grep -q '^XCODEBUILDMCP_PINNED_TEST_PRODUCTS_PATH='; then
    echo "env: ok (XCODEBUILDMCP_PINNED_TEST_PRODUCTS_PATH set)"
  else
    echo "env: FAIL XCODEBUILDMCP_PINNED_TEST_PRODUCTS_PATH missing on pid $pid"
    fail=1
  fi
fi

if [[ "$fail" -eq 0 ]]; then
  echo "verify-xcodebuildmcp-launcher PASS"
else
  echo "verify-xcodebuildmcp-launcher FAIL"
  exit 1
fi
