---
name: build-ios-apps
description: Build, profile, debug, and refine iOS apps with SwiftUI, App Intents, and Xcode workflows. Use when building or debugging on Simulator, reviewing SwiftUI UI, profiling performance, investigating leaks, or capturing visual proof. Load only when ios-dev-scope is active (iOS workspace).
---

# Build iOS Apps

Cursor router for iOS/watchOS work. Read this skill first, then read every specialist skill it names for the request. MCP roles must not overlap; routing detail is in `plugins/ios-dev/rules/ios-workflow.mdc`.

**Scope:** Use this skill only when `ios-dev-scope.mdc` is active (iOS workspace). For macOS-only or other hosts, do not load ios-dev skills or MCP build paths.

## Pick a skill

| Task | Skill |
| --- | --- |
| Build, run, test, tap, logs, simulator UI, debug | `ios-debugger-agent` and `ios-simulator-browser` (hygiene) |
| Live simulator mirror, simulator hygiene, or SPM preview hot reload | `ios-simulator-browser` |
| SwiftUI preview screenshot from this `.xcodeproj` | `ios-simulator-browser` (xcodeproj branch) + `xcode-tools` `RenderPreview` |
| ETTrace CPU profiling | `ios-ettrace-performance` (pair `ios-debugger-agent`) |
| Memgraph leak investigation | `ios-memgraph-leaks` (pair `ios-debugger-agent`) |
| App Intents / Shortcuts / Siri | `ios-app-intents` |
| SwiftUI UI patterns | `swiftui-ui-patterns` |
| View refactor / MV structure | `swiftui-view-refactor` |
| Liquid Glass (OS 26+) | `swiftui-liquid-glass` |
| Performance audit from code or traces | `swiftui-performance-audit` |

## MCP routing

| Need | Server | Tools / role |
| --- | --- | --- |
| Simulator list/boot/build/run/test, UI automation, screenshots, debug | `XcodeBuildMCP` | Default Simulator surface: `session_show_defaults`, `session_use_defaults_profile`, `build_run_sim`, `test_sim`, `snapshot_ui`, `tap`, `debug_*`, and related tools. Call short names (`list_sims`), not `mcp__XcodeBuildMCP__…`. |
| SwiftUI preview, Apple docs, Issue Navigator, GetBuildLog; optional in-window build/test | `xcode-tools` (`xcrun mcpbridge`) | `RenderPreview`, `DocumentationSearch`, `GetBuildLog`, `XcodeListNavigatorIssues`, `XcodeRefreshCodeIssuesInFile`. Optional `BuildProject` / `RunAllTests` / `RunSomeTests` / `GetTestList` only against the already-open Xcode window. Not the primary Simulator runner. Requires Xcode 26.3+, project open, Xcode Tools enabled. |
| File read/write/search | Cursor native tools | Read, Write, Grep, Glob. Do not use xcode-tools `XcodeRead` / `XcodeWrite` / `XcodeGrep` / `XcodeGlob` / `XcodeLS` / `XcodeMakeDir` / `XcodeRM` / `XcodeMV`. |
| `serve-sim` localhost mirror | Cursor Browser Tab or `cursor-ide-browser` | After `build_run_sim` and `serve-sim`. |

Do not add Sweetpad, xcode-build-server, or Shell `xcodebuild` / `xcrun` / `simctl` as an agent path.

## Project defaults and session prep

**Before every** `build_sim`, `build_run_sim`, or `test_sim`, follow [references/session-defaults.md](references/session-defaults.md) (canonical; do not paraphrase elsewhere). Profile `app` → app launch/compile; profile `tests` → unit tests. **One** `xcodebuild` and **one** booted simulator (configured UDID). Sequential `test_sim` only. Host docs do not override that.

## Xcode DerivedData (one host folder per repo)

Each host keeps yaml beside its `.xcodeproj` and Xcode DerivedData for **that** `projectPath`. Do not copy yaml or `derivedDataPath` from another project. A `derivedDataPath` / `testProductsPath` whose DerivedData folder stem does not match this yaml `projectPath` is another checkout — do not build it.

If this checkout has no yaml yet, the wrapper creates `.xcodebuildmcp/config.yaml` on MCP start (README → `xcodebuildmcp-host-dir.sh`). If MCP still exits: `bootstrap-xcodebuildmcp-config.sh` (optional `--xcodeproj`), then **Developer: Reload Window**. Bootstrap refuses host dirs inside the shipped `ios-dev/` plugin tree; `tests/` harness is fine.

After a plugin update, ask for **Developer: Reload Window** so the wrapper re-runs `resolve-derived-data-path.sh --sync-config`.

Unit tests must overwrite stable paths in that same DerivedData folder:

1. Wrapper sets `XCODEBUILDMCP_DERIVED_DATA_PATH`, `XCODEBUILDMCP_PINNED_TEST_PRODUCTS_PATH`, and patches XcodeBuildMCP so `build_sim` with `buildForTesting: true` writes to `$DD/<testsScheme>.xctestproducts` (not MCP `test-products/`). `tests` profile `extraArgs` hold `-resultBundlePath` under `$DD/Logs/` (`--sync-config`). Delete stale `.xcresult` there if xcodebuild refuses to overwrite.
2. `test_sim` with the same `testProductsPath` under that Xcode DD (never source-only). Prepared `test-without-building` also gets `-derivedDataPath` from env (MCP cannot pass both tool args). Do not delete DerivedData folders as a “fix”.

Source-mode `test_sim` (no `testProductsPath`) is blocked by hooks. Do not call `clean` or erase DerivedData / `SourcePackages` unless the user asks. After MCP timeout, wait for the existing `xcodebuild`; a second `build_sim` during package resolve corrupts SPM checkouts. Watch disk with `df`; incremental builds should not drop Avail like a full second copy.

Simulator inventory, shutdown, lifecycle, and stale **Simulator.app** detection: load `ios-simulator-browser` (`simulator-hygiene.sh`).

## Bundled scripts (`build-ios-apps`)

| Script | When to run |
| --- | --- |
| `scripts/resolve-derived-data-path.sh [--write-local] [--sync-config]` | Resolve Xcode DD; `--sync-config` writes yaml profiles (wrapper runs this at MCP start) |
| `scripts/bootstrap-xcodebuildmcp-config.sh` | Create `.xcodebuildmcp/config.yaml`; host pick via `xcodebuildmcp-host-dir.sh` (README) |
| `scripts/xcodebuildmcp-with-xcode-derived-data.sh` | MCP entry in `mcp.json` (pins `xcodebuildmcp@2.7.0`, `XCODEBUILDMCP_CWD`, DD + test products env) |
| `scripts/patch-xcodebuildmcp-prepared-test-derived-data.sh` | Wrapper-only disk patch for prepared `test-without-building` `-derivedDataPath` |
| `scripts/xcodebuildmcp-pin-test-products.mjs` | Node import hook (used by wrapper; not called directly) |

Host test-scope rows belong in the host project's `docs/testing.md`, not this plugin. Simulator hygiene commands live in `ios-simulator-browser`. Parallel builds/simulators are forbidden here.

## Host test-specific rules (knowledge base)

When default `test_sim` is not enough for some scopes, the **host project** maintains a separate doc (suggested: `docs/testing-specific-rules-by-classes.md`) with concrete parameters and verified outcomes. The plugin does not ship project-specific rows.

- **Policy vs overrides:** `docs/testing.md` = default procedure and how to decide the next step; specific-rules file = named scopes and copy-pasteable parameters.
- **When to create or extend:** see [references/test-specific-rules.md](references/test-specific-rules.md).
- **Agent rule:** if you discover working parameters not yet documented, add or update a row in the host specific-rules file before reporting verification complete. Do not change product code to work around MCP limits unless the user asks.

Read `references/test-specific-rules.md` when setting up a new repo or when `test_sim` failures repeat for the same scope.

## After every code change

Before reporting a task complete, run at least **`build_sim`** on the touched scheme(s) through XcodeBuildMCP (session prep in [references/session-defaults.md](references/session-defaults.md)). Same bar as **After every code change** in `plugins/ios-dev/rules/ios-workflow.mdc`: no “should compile”, no skipping the build because the user asked a different question next.

Optional follow-ups (only when the task requires them): `test_sim`, `build_run_sim`, Issue Navigator refresh, `RenderPreview` for a single Canvas preview in the open `.xcodeproj`.
