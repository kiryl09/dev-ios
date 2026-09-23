#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
PLUGIN="$ROOT/plugin"
CURSOR="$ROOT/.cursor"

rm -rf "$CURSOR/skills" "$CURSOR/hooks"
mkdir -p "$CURSOR"

rsync -a --delete "$PLUGIN/skills/" "$CURSOR/skills/"
rsync -a --delete "$PLUGIN/hooks/" "$CURSOR/hooks/"

export ROOT
python3 <<'PY'
import json
import os
from pathlib import Path

root = Path(os.environ["ROOT"])
cursor = root / ".cursor"
hooks_src = json.loads((root / "plugin" / "hooks" / "hooks.json").read_text())

def rewrite(cmd: str) -> str:
    if cmd.startswith("hooks/"):
        return ".cursor/" + cmd
    return cmd

for section, entries in hooks_src.get("hooks", {}).items():
    for entry in entries:
        if "command" in entry:
            entry["command"] = rewrite(entry["command"])

(cursor / "hooks.json").write_text(json.dumps(hooks_src, indent=2) + "\n")

mcp = {
    "mcpServers": {
        "XcodeBuildMCP": {
            "command": "bash",
            "args": [
                ".cursor/skills/build-ios-apps/scripts/xcodebuildmcp-with-xcode-derived-data.sh"
            ],
            "env": {
                "XCODEBUILDMCP_ENABLED_WORKFLOWS": "simulator,ui-automation,debugging,logging",
                "XCODEBUILDMCP_DISABLE_XCODE_AUTO_SYNC": "true",
                "NODE_OPTIONS": "",
            },
        }
    }
}
(cursor / "mcp.json").write_text(json.dumps(mcp, indent=2) + "\n")
PY

echo "Staged plugin into $CURSOR"
echo "Ask user for Developer: Reload Window before XcodeBuildMCP or hook checks."
