# Sample app (XcodeBuildMCP)

Harness directory: `tests/xcode-sample_project/` (`PluginProbe.xcodeproj`, schemes `PluginProbe` / `PluginProbeTests`, `.xcodebuildmcp/config.yaml`).

Integration tests for real Simulator build, run, and unit test via XcodeBuildMCP. **Do not** reference PluginProbe in shipped `ios-dev/` skills or rules.

## Prerequisites

1. [Sync + reload](../../README.md#ios-dev).
2. Open this monorepo or `tests/xcode-sample_project` in Cursor (ios-dev scope active; shallowest `.xcodeproj` under git root is the harness).
3. [MCP launcher](mcp-launcher.md) PASS.

## Align DerivedData in yaml

After clone or Xcode upgrade, from the harness:

```bash
cd tests/xcode-sample_project
../../ios-dev/skills/build-ios-apps/scripts/resolve-derived-data-path.sh \
  --sync-config --repo-root "$(git -C ../.. rev-parse --show-toplevel)"
```

Update machine-specific `simulatorId` if needed. Keep `testProductsPath` under the same DerivedData folder as `derivedDataPath`.

Offline harness shape: `tests/gates/run-gate-miniap.sh` ([gates.md](gates.md)).

## MCP smoke

Use XcodeBuildMCP only (not Shell `xcodebuild`).

1. Per [session-defaults.md](../../ios-dev/skills/build-ios-apps/references/session-defaults.md): prep profile `app`, then `build_sim`.
2. `build_run_sim`.
3. Prep profile `tests`, then `test_sim` (pinned `testProductsPath`; hooks deny source-mode test).

Optional: `snapshot_ui` after launch ([ios-debugger-agent](../../ios-dev/skills/ios-debugger-agent/SKILL.md)).

## xcode-tools (optional)

Open the harness in Xcode, then `DocumentationSearch`, `XcodeListNavigatorIssues`, `RenderPreview` on `ContentView.swift` — validates `mcp.json` `xcrun mcpbridge`.

## Disk side effects

Long sessions: [mcp-storage.md](mcp-storage.md).
