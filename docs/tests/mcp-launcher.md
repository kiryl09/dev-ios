# MCP launcher

Script: `tests/verify-xcodebuildmcp-launcher.sh`

Confirms Cursor is running XcodeBuildMCP through the plugin wrapper (not stock `npx`). Requires the MCP server to be running in Cursor after [staging `mcp.json` and launcher scripts into the project `.cursor/` and a manual Reload Window](../../README.md#dev-ios).

## Run

```bash
tests/verify-xcodebuildmcp-launcher.sh
```

Expect `verify-xcodebuildmcp-launcher PASS`.

## What it checks

- Process is `xcodebuildmcp/build/cli.js mcp` (via `xcodebuildmcp-mcp-entry.py`), `xcodebuildmcp-mcp-entry.py mcp`, or `xcodebuildmcp-with-xcode-derived-data.sh`, not `npm exec xcodebuildmcp` / `_npx/.../xcodebuildmcp mcp`
## Common failures

| Symptom | Fix |
| --- | --- |
| Old npx process | Stop XcodeBuildMCP in Cursor MCP settings, [re-stage into the project `.cursor/` and wait for a manual Reload Window](../../README.md#dev-ios), restart server |
| Missing pinned env | Wrapper not used — check `plugin/mcp.json` points at `xcodebuildmcp-with-xcode-derived-data.sh` |
| No MCP process | Open a workspace with dev-ios; enable XcodeBuildMCP |

Pair with [sample-app.md](sample-app.md) after `mcp.json` or launcher script changes.
