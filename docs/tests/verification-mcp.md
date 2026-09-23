# MCP verification (maintainers)

Agents building or testing **an app** with the shipped plugin use [session-defaults.md](../../plugin/skills/build-ios-apps/references/session-defaults.md) in the host workspace, not this file.

This doc is for changes **inside the CursorPlugins monorepo**. Simulator proof uses **XcodeBuildMCP only** (`build_sim`, `build_run_sim`, `test_sim`) with explicit arguments from the sample app’s yaml. Do not use Shell `xcodebuild`, `xcrun simctl`, or xcode-tools `BuildProject` / `RunAllTests` / `RunSomeTests` to claim the plugin “works”.

## What does not count as verification

- Offline gate scripts (yaml shape, launcher dry-run) without a live MCP build or test in this session.
- Direct Shell `xcodebuild` using yaml paths. That checks DerivedData folder stability only, not MCP binding.
- Wrapper `--dry-run` without a confirmed Reload Window after staging plugin files into the host workspace.

## Before any MCP verification

1. Stage `plugin/` into this workspace `.cursor/` per [README.md § dev-ios](../../README.md#dev-ios) (`skills/`, `hooks/`, `hooks.json`, `mcp.json` with paths under `.cursor/skills/...`).
2. Ask the user for **Developer: Reload Window** and **stop until they confirm**.
3. Confirm XcodeBuildMCP restarted with `XCODEBUILDMCP_DISABLE_SESSION_DEFAULTS=true` (public `build_sim` schema must list `scheme`, `projectPath`, `simulatorId`, `derivedDataPath`). If those properties are missing, stop and ask to restart XcodeBuildMCP after reload.
4. Do not call `build_sim` / `test_sim` until reload (and MCP restart if needed) is confirmed.

## Two-host switch smoke (optional)

Use when you need to prove explicit args do not leak `projectPath` or `derivedDataPath` between hosts. Pick **two different** iOS `.xcodeproj` trees, each with its own `.xcodebuildmcp/config.yaml`. Run sequentially, one host at a time.

1. **First host:** read yaml → `build_sim` (app) or tests flow with full profile args → assert success. Record `projectPath` and `derivedDataPath` from yaml used in the call.
2. **Second host:** read **that** yaml → tests or app build via MCP with **that** profile’s args. `projectPath` and DerivedData stem in tool_input must match the second host, not the first.
3. **First host again:** read first host yaml → `derivedDataPath` in the next call must match step 1. Under `~/Library/Developer/Xcode/DerivedData/`, do not accumulate extra folders for the first host’s `.xcodeproj` stem beyond the single instance you already use for that project.

Do not run both hosts’ builds in parallel. Do not `kill` in-flight `xcodebuild`.

## When verification is blocked

If XcodeBuildMCP tools are unavailable in the agent session, say so explicitly. Do not substitute Shell `xcodebuild` and report success. Finish offline gates only and list what remains after reload.
