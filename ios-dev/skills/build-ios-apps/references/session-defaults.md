# XcodeBuildMCP session defaults (canonical)

**Single source of truth** for how agents align XcodeBuildMCP with the **current host checkout** before Simulator build, run, or test. Every other ios-dev skill and rule links here; do not duplicate this procedure elsewhere.

## Where config lives

- **Authoritative file:** `.xcodebuildmcp/config.yaml` beside the host `.xcodeproj` in **this** workspace (not `~/.xcodebuildmcp`). Delete a stale home copy if present; the wrapper does not use it.
- **Host `.xcodeproj` pick:** monorepo README → `skills/build-ios-apps/scripts/xcodebuildmcp-host-dir.sh`.
- **Profiles:** `app` (app scheme → `build_run_sim`, `build_sim`) and `tests` (unit-test scheme → `test_sim`). Select with `session_use_defaults_profile` as part of prep below.
- **Bootstrap:** if yaml is missing, wrapper creates it on MCP start; else `bootstrap-xcodebuildmcp-config.sh`, then ask the user for **Developer: Reload Window**. Do not copy yaml from another checkout.
- **DerivedData:** wrapper `xcodebuildmcp-with-xcode-derived-data.sh` runs `resolve-derived-data-path.sh --sync-config` into yaml before MCP loads. Paths must live under `~/Library/Developer/Xcode/DerivedData/`, never `XcodeBuildMCP/workspaces/...`.

There is **no** MCP command to re-read `config.yaml` at runtime. Session memory is updated only via `session_set_defaults` (or MCP restart).

## Mandatory prep before every build or test

Run this **immediately before each** `build_sim`, `build_run_sim`, or `test_sim` (including `build_sim` with `buildForTesting: true`). No separate ritual when switching projects or profiles; the next build/test performs prep again.

1. **Read expected values** from the active profile block in **this** checkout’s `.xcodebuildmcp/config.yaml` (`sessionDefaults` for `global`, or `sessionDefaultsProfiles.app` / `.tests`). Use absolute paths when yaml stores relative paths (resolve against the yaml directory).
2. **`session_use_defaults_profile`** → `app` or `tests` matching the tool you are about to call.
3. **`session_set_defaults`** with the expected fields from that profile (`persist: false` unless the user explicitly asked to persist).
4. **`session_show_defaults`**.
5. **Assert** MCP memory matches expected for these keys (normalize paths before compare):
   - `projectPath` or `workspacePath` (whichever the profile defines)
   - `scheme`
   - `configuration` (if set in yaml)
   - `derivedDataPath`
   - `testProductsPath` (required for `tests` / `test_sim`)
   - Simulator: at least one of `simulatorId` or `simulatorName` matches yaml (do not fail only because MCP repopulated the other field asynchronously).
6. If assert **passes** → call the build/test tool.
7. If assert **fails** → **stop**. Do not call `build_sim` / `build_run_sim` / `test_sim`. Do not call `discover_projs`. Do not ask the user to disable hooks. Do not retry with `session_clear_defaults` or extra `session_set_defaults` loops. Ask the user to **Developer: Reload Window** (restart XcodeBuildMCP) and retry prep after reload.

`derivedDataPath` missing or under `XcodeBuildMCP/workspaces` after step 4 → same stop + Reload Window; do not build.

## Other session tools

- **`discover_projs`:** only when yaml is missing or host project cannot be determined from the workspace — not as a workaround for failed assert after set/show.
- **Missing profile:** once per checkout, `session_set_defaults` with `createIfNotExists: true` and `persist: true` to recreate the profile in yaml; still run full prep before every build/test afterward.
- **Hooks:** path policy may deny build/test when artifacts point at another project; fixing that is always this prep sequence, not bypassing hooks.

## Quick map

| Intent | Profile | Typical tool |
| --- | --- | --- |
| Launch app | `app` | `build_run_sim` |
| Compile only | `app` | `build_sim` |
| Unit tests | `tests` | `build_sim` (`buildForTesting: true`) then `test_sim` with same `testProductsPath` |
