# Sample app (XcodeBuildMCP)

Harness directory: `tests/xcode-sample_project/` (`PluginProbe.xcodeproj`, schemes `PluginProbe` / `PluginProbeTests`, `.xcodebuildmcp/config.yaml`).

Integration tests for real Simulator build, run, and unit test via XcodeBuildMCP. **Do not** reference PluginProbe in shipped `plugin/` skills or rules.

## Prerequisites

1. [Stage skills, hooks, scripts, and MCP into the project `.cursor/`, then wait for a manual Reload Window](../../README.md#dev-ios). Do not sync `~/.cursor/plugins/local/` unless the user asks.
2. Open this monorepo or `tests/xcode-sample_project` in Cursor (dev-ios scope active; shallowest `.xcodeproj` under git root is the harness).
3. [MCP launcher](mcp-launcher.md) PASS.

## Align DerivedData in yaml

After clone or Xcode upgrade, from the harness:

```bash
cd tests/xcode-sample_project
../../plugin/skills/build-ios-apps/scripts/resolve-derived-data-path.sh \
  --sync-config --repo-root "$(git -C ../.. rev-parse --show-toplevel)"
```

Update machine-specific `simulatorId` if needed. Keep `testProductsPath` under the same DerivedData folder as `derivedDataPath`.

Offline harness shape: `tests/gates/run-gate-miniap.sh` ([gates.md](gates.md)).

## MCP smoke

Use XcodeBuildMCP only (not Shell `xcodebuild`). Full bar: [verification-mcp.md](verification-mcp.md).

1. Per [session-defaults.md](../../plugin/skills/build-ios-apps/references/session-defaults.md): `build_sim` with full profile `app` fields from yaml (no `session_*` tools).
2. `build_run_sim` with the same app profile args.
3. `build_sim` (`buildForTesting: true` with full profile `tests` fields from yaml), then `test_sim` per [session-defaults.md](../../plugin/skills/build-ios-apps/references/session-defaults.md) (not source-mode).

Optional: `snapshot_ui` after launch ([ios-debugger-agent](../../plugin/skills/ios-debugger-agent/SKILL.md)).

## Disk side effects

Long sessions: [mcp-storage.md](mcp-storage.md).
