#!/usr/bin/env python3
"""Launch pinned XcodeBuildMCP CLI via Node (MCP stdio entry)."""

from __future__ import annotations

import os
import sys
from pathlib import Path


def main(argv: list[str] | None = None) -> None:
    if argv is None:
        argv = sys.argv[1:]
    script_dir = Path(__file__).resolve().parent
    cache_root = Path(
        os.environ.get("XCODEBUILDMCP_NPM_CACHE", script_dir / "xcodebuildmcp-npm-cache")
    )
    cli_path = cache_root / "node_modules/xcodebuildmcp/build/cli.js"
    if not cli_path.is_file():
        print(f"error: xcodebuildmcp cli not found at {cli_path}", file=sys.stderr)
        raise SystemExit(1)
    os.execvp("node", ["node", str(cli_path), *argv])


if __name__ == "__main__":
    main()
