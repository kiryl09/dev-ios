---
name: ios-debugger-agent
description: Build and unit-test iOS apps with XcodeBuildMCP. Do not launch Simulator UI. Load only when dev-ios-scope is active (iOS workspace).
---

# iOS Debugger Agent

## Simulator UI forbidden

Never open Simulator.app and never launch an app in the Simulator. Allowed XcodeBuildMCP tools are `build_sim` and `test_sim` only. `test_sim` runs unit tests with mocks. Do not call `boot_sim`, `open_sim`, `build_run_sim`, `install_app_sim`, `launch_app_sim`, `stop_app_sim`, `screenshot`, `snapshot_ui`, `tap`, `touch`, `long_press`, `swipe`, `drag`, `gesture`, `button`, `key_press`, `key_sequence`, `type_text`, `wait_for_ui`, `record_sim_video`, or `debug_attach_sim`. Do not run `serve-sim`, `swiftui-preview-browser.py`, `open -a Simulator`, `simctl boot`, or `simctl launch`. If a task needs the Simulator window, stop and say this plugin does not launch Simulator UI.

XcodeBuildMCP tools allowed here are `build_sim` and `test_sim` only. Pair with `ios-simulator-browser` for simulator status and shutdown.

Call tools by short names (`list_sims`), not `mcp__XcodeBuildMCP__list_sims`. Never boot, shutdown, or test via ad-hoc Shell `xcrun`, `simctl`, or `xcodebuild`. The open workspace is the app. Follow **How to build or test this app** in `build-ios-apps` → [references/session-defaults.md](../build-ios-apps/references/session-defaults.md) before the first build or test. For simulator inventory and shutdown rules, load `ios-simulator-browser` (`simulator-status.sh` and `simulator-shutdown.sh`, not raw `simctl`).

## One at a time

Never run two Simulator builds, tests, or devices at once — not in this chat, not across chats, not via Xcode plus MCP.

- At most **one** `xcodebuild` (`build_sim` / `test_sim`). If `xcodebuild_count` > 0 or a previous MCP call is in flight, **wait**. Do not start another.
- At most **one** booted simulator (yaml UDID); no clones or second devices — see `plugins/dev-ios/rules/ios-workflow.mdc`.
- `test_sim` calls are **sequential**. One filter per call. Do not fire several `test_sim` in one turn.
- Host docs do **not** raise this cap.

## Session rules

1. Never terminate `xcodebuild`, never `kill` PIDs from `status`, never MCP `clean`, never delete `SourcePackages` / DerivedData. Use `simulator-status.sh status` when inventory is unclear. After the last run in a verification pass **and** `xcodebuild_count=0`, run `simulator-shutdown.sh shutdown` or `shutdown-all` when host policy requires it.
2. Never switch simulators or run a second device. Never call `boot_sim`, `open_sim`, or `build_run_sim`.
3. If the build fails, use the MCP tool error output first. Read build logs under yaml `derivedDataPath` (`Logs/`, `.xcresult`) with Cursor file tools when you need more detail. Escalate to the user.

## Unit tests

`test_sim` runs the unit-test scheme. It does not present the app UI. Do not ask the user to sign in, finish onboarding, or tap the product during `test_sim`. Unit tests must use mocks or fixtures.

Unit tests: follow [session-defaults.md](../build-ios-apps/references/session-defaults.md) before each `build_sim` (`buildForTesting: true` with full `tests` profile fields in tool args) and `test_sim` (the `testProductsPath` that file chooses, plus `simulatorId`). Never source-only `test_sim`.

When `test_sim` returns a real pass/fail for a scope listed in the host project's test-specific rules doc, follow that file. How to create and maintain that file: `plugins/dev-ios/skills/build-ios-apps/references/test-specific-rules.md`. Do **not** treat MCP `-32001` or an in-flight `xcodebuild` as a reason to switch runners or kill the process.

## MCP timeout (`-32001`) on `test_sim`

Cursor aborts the tool call while `xcodebuild` or CoreSimulator may still be running. This is not a test failure. Do not switch to `build_sim` or Shell while that process is alive. Do not start another `test_sim` or `build_sim` until `xcodebuild_count` is 0. License, “not agreed”, or first-launch text in any MCP error: stop and ask the user to finish that UI in Xcode.

After the first `-32001`, run `plugins/dev-ios/skills/ios-simulator-browser/scripts/simulator-status.sh status` (do not rely on `list_sims` text alone). Do **not** run `simulator-shutdown.sh` before the in-flight `xcodebuild` exits. If `xcodebuild_count` or `stale_xcodebuild_count` > 0, wait or ask the user — SPM resolve can take hours; killing it corrupts `SourcePackages` (submodules/artifacts). Do not start another `build_sim`. Do not `rm` DerivedData or SourcePackages. Full decision tree: `ios-simulator-browser`.

## Logs

There is no `start_sim_log_cap` or `stop_sim_log_cap`. `test_sim` returns a log file path when MCP provides one. Read that file for console output from the current run.

For a **prior** crash or console history (including after MCP timeout), read on-disk logs with Cursor file tools — allowed and expected:

- Log path from the last `test_sim` when MCP returned one
- `~/Library/Logs/CoreSimulator/<simulator-udid>/` (simulator system log)
- `~/Library/Logs/DiagnosticReports/` (`.ips` crash reports for Simulator and macOS)
- `~/Library/Developer/CoreSimulator/Devices/<simulator-udid>/data/Library/Logs/CrashReporter/` and `…/data/tmp/` when present
- Build/test logs and `.xcresult` under yaml `derivedDataPath` when MCP output is truncated

Use `simulatorId` from host yaml or `list_sims` when needed; do not use Shell `simctl` to discover paths.

## Coverage

When a coverage report is requested after tests: `get_coverage_report`, `get_file_coverage`.

## Troubleshooting

- Keep the simulator from session defaults unless the user asks otherwise.
