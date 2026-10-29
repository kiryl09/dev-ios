# Checkout and DerivedData (agent playbook)

Use this when the workspace is an iOS host checkout (not when editing the dev-ios plugin repo itself). The plugin does not deny these calls; follow this procedure yourself.

## One DerivedData folder per host

- **Canonical path:** `derivedDataPath` in this checkout’s `.xcodebuildmcp/config.yaml` (run `resolve-derived-data-path.sh --sync-config` once if paths may be stale).
- **Rule:** At most **one** `~/Library/Developer/Xcode/DerivedData/<ProjectStem>-*` folder for this `projectPath`. Extra folders mean some MCP call ran **without** yaml `derivedDataPath` in **tool_input**.
- **Every** `build_sim` and `test_sim`: pass **`derivedDataPath`** from the active yaml profile in **tool_input**, plus `projectPath`, `scheme`, `configuration`, and `simulatorId` on build tools. For tests, also pass **`testProductsPath`** on `build_sim` with `buildForTesting: true`; `test_sim` uses the path from [session-defaults.md](session-defaults.md) and simulator only.
- Do not delete arbitrary DerivedData folders as a fix unless the user asks.

## Switching to this checkout (another project was open before)

1. Read **this** `.xcodebuildmcp/config.yaml` (`app` or `tests` profile for the next tool).
2. On the next MCP call, pass **only** fields from that profile (absolute paths). Do not use `session_*` tools.
3. If a build still targets another project’s `projectPath` or DerivedData stem, ask the user to restart **XcodeBuildMCP** in MCP settings (not Shell `xcodebuild`), then retry with this yaml.
4. See [session-defaults.md](session-defaults.md) for the full argument list.

Do not use Reload Window as a substitute for reading this yaml.

## Calls to refuse

Nothing in the plugin blocks these. Do not make the call:

- Do not call MCP `clean`.
- Do not call `build_sim` or `test_sim` without `projectPath`, `scheme`, `simulatorId`, and `derivedDataPath` from this host yaml on build tools.
- Do not pass `derivedDataPath`, `testProductsPath`, or result bundles under `XcodeBuildMCP/workspaces`, or under a DerivedData folder whose stem belongs to another `.xcodeproj`.
- Do not call source-mode `test_sim` (no `testProductsPath` under this checkout’s Xcode DerivedData).
- Do not pass a timestamped `*.xctestproducts` child to `build_sim`, and do not write that child into yaml `testProductsPath`. Which path `test_sim` uses: [session-defaults.md](session-defaults.md).
- If a build created a new directory under `~/Library/Developer/XcodeBuildMCP/workspaces/`, stop. Rebuild only with yaml paths in tool_input per [session-defaults.md](session-defaults.md).

Simulator Shell limits: `rules/xcode-mcp-only.mdc`.
