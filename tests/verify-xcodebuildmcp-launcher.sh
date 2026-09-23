#!/usr/bin/env bash
set -euo pipefail

fail=0

if pgrep -f "xcodebuildmcp/build/cli\\.js mcp" >/dev/null; then
  echo "launcher: ok (xcodebuildmcp cli.js)"
elif pgrep -f "xcodebuildmcp-mcp-entry\\.py mcp" >/dev/null; then
  echo "launcher: ok (mcp-entry.py)"
elif pgrep -f "xcodebuildmcp-with-xcode-derived-data\\.sh" >/dev/null; then
  echo "launcher: ok (wrapper bash)"
else
  echo "launcher: FAIL expected wrapper, mcp-entry.py, or cli.js mcp; got:"
  pgrep -fl "xcodebuildmcp|mcp-entry" || echo "  (no xcodebuildmcp process)"
  fail=1
fi

if pgrep -f "npm exec xcodebuildmcp" >/dev/null || pgrep -f "_npx/.*/xcodebuildmcp mcp" >/dev/null; then
  echo "launcher: FAIL still using npx xcodebuildmcp (old MCP process — Stop server in Cursor MCP settings)"
  fail=1
fi

if [[ "$fail" -eq 0 ]]; then
  echo "verify-xcodebuildmcp-launcher PASS"
else
  echo "verify-xcodebuildmcp-launcher FAIL"
  exit 1
fi
