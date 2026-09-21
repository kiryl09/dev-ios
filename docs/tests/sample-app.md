# Sample app (XcodeBuildMCP)

Harness directory: `tests/xcode-sample_project/` (`PluginProbe.xcodeproj`, schemes `PluginProbe` / `PluginProbeTests`, `.xcodebuildmcp/config.yaml`).

Integration tests for real Simulator build, run, and unit test via XcodeBuildMCP. **Do not** reference PluginProbe in shipped `dev-ios/` skills or rules.

## Prerequisites

1. [Sync + reload](../../README.md#dev-ios).
2. Open this monorepo or `tests/xcode-sample_project` in Cursor (dev-ios scope active; shallowest `.xcodeproj` under git root is the harness).
3. [MCP launcher](mcp-launcher.md) PASS.

## Align DerivedData in yaml

After clone or Xcode upgrade, from the harness:

```bash
cd tests/xcode-sample_project
../../dev-ios/skills/build-ios-apps/scripts/resolve-derived-data-path.sh \
  --sync-config --repo-root "$(git -C ../.. rev-parse --show-toplevel)"
```

Update machine-specific `simulatorId` if needed. Keep `testProductsPath` under the same DerivedData folder as `derivedDataPath`.

Offline harness shape: `tests/gates/run-gate-miniap.sh` ([gates.md](gates.md)).

## MCP smoke

Use XcodeBuildMCP only (not Shell `xcodebuild`).

1. Per [session-defaults.md](../../dev-ios/skills/build-ios-apps/references/session-defaults.md): prep profile `app`, then `build_sim`.
2. `build_run_sim`.
3. Prep profile `tests`, then `build_sim` (`buildForTesting: true` only), then `test_sim` with `testProductsPath` from yaml (hooks deny source-mode test).

Optional: `snapshot_ui` after launch ([ios-debugger-agent](../../dev-ios/skills/ios-debugger-agent/SKILL.md)).

## xcode-tools (optional)

Open the harness in Xcode, then `DocumentationSearch`, `XcodeListNavigatorIssues`, `RenderPreview` on `ContentView.swift` — validates `mcp.json` `xcrun mcpbridge`.

## Disk side effects

Long sessions: [mcp-storage.md](mcp-storage.md).
