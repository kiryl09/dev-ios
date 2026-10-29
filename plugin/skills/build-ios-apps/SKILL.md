---
name: build-ios-apps
description: Build, profile, debug, and refine iOS apps with SwiftUI, App Intents, and Xcode workflows. Use when building or debugging on Simulator, profiling performance, or investigating leaks. Load only when dev-ios-scope is active (iOS workspace).
---

# Build iOS Apps

## Simulator UI forbidden

Never open Simulator.app and never launch an app in the Simulator. Allowed XcodeBuildMCP tools are `build_sim` and `test_sim` only. `test_sim` runs unit tests with mocks. Do not call `boot_sim`, `open_sim`, `build_run_sim`, `install_app_sim`, `launch_app_sim`, `stop_app_sim`, `screenshot`, `snapshot_ui`, `tap`, `touch`, `long_press`, `swipe`, `drag`, `gesture`, `button`, `key_press`, `key_sequence`, `type_text`, `wait_for_ui`, `record_sim_video`, or `debug_attach_sim`. Do not run `serve-sim`, `swiftui-preview-browser.py`, `open -a Simulator`, `simctl boot`, or `simctl launch`. If a task needs the Simulator window, stop and say this plugin does not launch Simulator UI.

Cursor router for iOS/watchOS work. Read this skill first, then read every specialist skill it names for the request. MCP roles must not overlap; routing detail is in `plugins/dev-ios/rules/ios-workflow.mdc`.

**Scope:** Use this skill only when `dev-ios-scope.mdc` is active (iOS workspace). For macOS-only or other hosts, do not load dev-ios skills or MCP build paths.

## Pick a skill

| Task | Skill |
| --- | --- |
| Build, compile verify, unit tests, logs | `ios-debugger-agent` and `ios-simulator-browser` (status and shutdown) |
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
| Simulator build and unit test | `XcodeBuildMCP` | `build_sim` (compile only; profile `app`), `test_sim` only. Do not call `build_run_sim` or UI tools. Explicit args from host yaml ([session-defaults.md](references/session-defaults.md)). Call short names (`list_sims`), not `mcp__XcodeBuildMCP__…`. |
| File read/write/search, build logs, `.xcresult` | Cursor native tools | Read, Write, Grep, Glob on source and on paths under yaml `derivedDataPath` / MCP-returned log paths. |

Do not add Sweetpad, xcode-build-server, or Shell `xcodebuild` / `xcrun` / `simctl` as an agent path.

## Project defaults and yaml args

The open workspace is the app. Start at **How to build or test this app** in [references/session-defaults.md](references/session-defaults.md). Do not build the plugin repo and do not learn the MCP shape by retrying tools.

**Before every** `build_sim` or `test_sim`, follow [references/session-defaults.md](references/session-defaults.md) and [references/checkout-environment.md](references/checkout-environment.md) (canonical; do not paraphrase elsewhere). Read this host’s yaml and pass the full profile in **tool_input** on every build call. Profile `app` → `build_sim`; profile `tests` → `build_sim` (`buildForTesting: true` + full tests profile) then `test_sim` (path from [session-defaults.md](references/session-defaults.md) + simulator only). **One** `xcodebuild` and **one** booted simulator (configured UDID). Sequential `test_sim` only. Host docs do not override that.

**Verification:** For the open app, a passing `build_sim` / `test_sim` with args from that app’s yaml is the result. Shell `xcodebuild` does not count.

## Xcode DerivedData (one host folder per repo)

Each host keeps yaml beside its `.xcodeproj` and Xcode DerivedData for **that** `projectPath`. Do not copy yaml or `derivedDataPath` from another project. A `derivedDataPath` / `testProductsPath` whose DerivedData folder stem does not match this yaml `projectPath` is another checkout — do not build it.

If the open app has no yaml yet: run `bootstrap-xcodebuildmcp-config.sh` from the app directory (optional `--xcodeproj`). That writes `.xcodebuildmcp/config.yaml` in the app. No Reload Window. Bootstrap refuses directories inside the shipped plugin tree.

Host yaml is refreshed on each XcodeBuildMCP start via the launcher; run `resolve-derived-data-path.sh --sync-config` from the app directory only when MCP was not restarted after a machine or Xcode change.

Unit tests use that same DerivedData folder. `build_sim` with `buildForTesting: true` passes the yaml `tests` profile, including `testProductsPath`, in one tool call. `test_sim` passes the path [session-defaults.md](references/session-defaults.md) chooses, plus `simulatorId` (never source-only; no `derivedDataPath` on prepared `test_sim`). `tests` profile `extraArgs` go on `test_sim` only. Do not delete DerivedData folders as a “fix”.

Do not call source-mode `test_sim` (no `testProductsPath`). Do not call `clean` or erase DerivedData / `SourcePackages` unless the user asks. Refusals: [references/checkout-environment.md](references/checkout-environment.md). After MCP timeout, wait for the existing `xcodebuild`; a second `build_sim` during package resolve corrupts SPM checkouts. Watch disk with `df`; incremental builds should not drop Avail like a full second copy.

Simulator status: `simulator-status.sh`. Simulator shutdown: `simulator-shutdown.sh`. Load `ios-simulator-browser`.

## Bundled scripts (`build-ios-apps`)

| Script | When to run |
| --- | --- |
| `scripts/resolve-derived-data-path.sh [--write-local] [--sync-config]` | Resolve Xcode DD; `--sync-config` writes yaml profiles before prep/build |
| `scripts/bootstrap-xcodebuildmcp-config.sh` | Create `.xcodebuildmcp/config.yaml`; host pick via `xcodebuildmcp-host-dir.sh` (README) |
| `scripts/xcodebuildmcp-with-xcode-derived-data.sh` | MCP entry in `mcp.json` (pinned npm; `XCODEBUILDMCP_DISABLE_SESSION_DEFAULTS=true`) |

Host test-scope rows belong in the host project's `docs/testing.md`, not this plugin. Simulator status and shutdown commands live in `ios-simulator-browser`. Parallel builds/simulators are forbidden here.

## Host test-specific rules (knowledge base)

When default `test_sim` is not enough for some scopes, the **host project** maintains a separate doc (suggested: `docs/testing-specific-rules-by-classes.md`) with concrete parameters and verified outcomes. The plugin does not ship project-specific rows.

- **Policy vs overrides:** `docs/testing.md` = default procedure and how to decide the next step; specific-rules file = named scopes and copy-pasteable parameters.
- **When to create or extend:** see [references/test-specific-rules.md](references/test-specific-rules.md).
- **Agent rule:** if you discover working parameters not yet documented, add or update a row in the host specific-rules file before reporting verification complete. Do not change product code to work around MCP limits unless the user asks.

Read `references/test-specific-rules.md` when setting up a new repo or when `test_sim` failures repeat for the same scope.

## After every code change

Before reporting a task complete, run at least **`build_sim`** on the touched scheme(s) through XcodeBuildMCP (explicit yaml args in [references/session-defaults.md](references/session-defaults.md)). Same bar as **After every code change** in `plugins/dev-ios/rules/ios-workflow.mdc`: no “should compile”, no skipping the build because the user asked a different question next.
