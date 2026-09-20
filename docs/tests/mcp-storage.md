# MCP storage observation

Script: `tests/observe-mcp-storage.sh`

Snapshots forbidden trees under `~/Library/Developer/XcodeBuildMCP` and free space on the `$HOME` volume. Use after long MCP build/test sessions or when investigating duplicate DerivedData / disk pressure.

## Usage

```bash
tests/observe-mcp-storage.sh before /tmp/ios-dev-observe.state
# … MCP build/test session …
tests/observe-mcp-storage.sh after /tmp/ios-dev-observe.state
tests/observe-mcp-storage.sh check
```

`after` exits 1 if new workspace `DerivedData` / `test-products` / `result-bundles` dirs appear under `XcodeBuildMCP/workspaces` or free space drops unexpectedly.

`run-gate-miniap.sh` also runs a no-op before/after pair when the observe script path is valid ([gates.md](gates.md)).
