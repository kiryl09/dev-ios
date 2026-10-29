# Build and test the open app

You are in **someone else’s iOS app** (the workspace that is open). Build and test **that** `.xcodeproj`. Do not open, edit, or build the dev-ios / CursorPlugins repo. Do not stage plugin files into the app. Do not Reload Window to compile the app.

## Simulator UI forbidden

Never open Simulator.app and never launch an app in the Simulator. Allowed XcodeBuildMCP tools are `build_sim` and `test_sim` only. `test_sim` runs unit tests with mocks. Do not call `boot_sim`, `open_sim`, `build_run_sim`, `install_app_sim`, `launch_app_sim`, `stop_app_sim`, `screenshot`, `snapshot_ui`, `tap`, `touch`, `long_press`, `swipe`, `drag`, `gesture`, `button`, `key_press`, `key_sequence`, `type_text`, `wait_for_ui`, `record_sim_video`, or `debug_attach_sim`. Do not run `serve-sim`, `swiftui-preview-browser.py`, `open -a Simulator`, `simctl boot`, or `simctl launch`. If a task needs the Simulator window, stop and say this plugin does not launch Simulator UI.

The plugin starts XcodeBuildMCP with session defaults **off**. Do **not** call `session_clear_defaults`, `session_set_defaults`, `session_show_defaults`, or `session_use_defaults_profile`. Do not learn the call by retrying `build_sim`.

## How to build or test this app

Working directory for the two scripts is the **app repo** (the folder that contains the `.xcodeproj`). The scripts themselves live next to this skill in the installed plugin (`skills/build-ios-apps/scripts/`). Do not look for them inside the app repo.

1. If the app has `docs/testing.md`, read it for scheme names and which tests to run. The MCP arguments still come from the steps below.
2. If the app has no `.xcodebuildmcp/config.yaml` next to its `.xcodeproj`, run `bootstrap-xcodebuildmcp-config.sh` (optional `--xcodeproj`), then `resolve-derived-data-path.sh --sync-config`. That writes yaml in the **app** repo.
3. If yaml exists but paths may be stale (another machine, Xcode upgrade), restart **XcodeBuildMCP** (launcher runs `resolve-derived-data-path.sh --sync-config` on start) or run that script once from the app directory.
4. Read `sessionDefaultsProfiles.app` (compile) or `.tests` (unit tests) from **that** yaml. Paste those values into the MCP call.
5. On the first `build_sim` of the chat, the tool schema must include `scheme`, `projectPath`, `simulatorId`, and `derivedDataPath`. If it does not, stop and ask the user to restart **XcodeBuildMCP**. Do not call `build_sim` with a short schema.

**Compile** (`app` profile) — one `build_sim` call (never launch the app). Pass all of these:

```json
{
  "projectPath": "<yaml app.projectPath>",
  "scheme": "<yaml app.scheme>",
  "configuration": "<yaml app.configuration>",
  "simulatorId": "<yaml app.simulatorId>",
  "derivedDataPath": "<yaml app.derivedDataPath>"
}
```

Use that object for `build_sim` only.

**Unit tests** (`tests` profile) — two calls, in order:

```json
{
  "projectPath": "<yaml tests.projectPath>",
  "scheme": "<yaml tests.scheme>",
  "configuration": "<yaml tests.configuration>",
  "simulatorId": "<yaml tests.simulatorId>",
  "derivedDataPath": "<yaml tests.derivedDataPath>",
  "buildForTesting": true,
  "testProductsPath": "<yaml tests.testProductsPath>"
}
```

That object is `build_sim` only. Then `test_sim` with only:

```json
{
  "testProductsPath": "<path chosen below>",
  "simulatorId": "<same tests.simulatorId>"
}
```

Choose `testProductsPath` for `test_sim` after `build_sim` returns. List the directories inside the yaml `tests.testProductsPath`.

1. If that yaml path is a symlink, pass the yaml path.
2. Otherwise, if it contains directories named `<tests.scheme>_yyyy-MM-dd_HH-mm-ss.xctestproducts`, pass the newest one by that timestamp.
3. Otherwise pass the yaml path.

Every `test_sim` until the next `build_sim` uses that same chosen path. The next `build_sim` still receives the yaml path. Choose again after that build returns.

Do not pass a timestamped child to `build_sim`. Do not write a timestamped child into yaml `testProductsPath`. The chosen path is the yaml path or a child of it, under the same DerivedData folder.

`Info.plist`, `Binaries`, and `Tests` directly inside the yaml path can stay from the first build after later builds add timestamped children. Leave them. Do not set `SWIFT_ENABLE_INCREMENTAL_COMPILATION=NO`, delete `.o` files, delete the test binary, edit the Xcode project, or change test source to force a relink. Do not call `clean` or erase DerivedData.

If the `tests` profile has `extraArgs`, pass them on `test_sim` only. Do not add `scheme`, `projectPath`, or `derivedDataPath` to that `test_sim`.

One simulator (the yaml UDID). One `xcodebuild` at a time. Do not `boot_sim`, `open_sim`, `build_run_sim`, or MCP `clean`.

## Where config lives

- **Authoritative file:** `.xcodebuildmcp/config.yaml` beside the host `.xcodeproj` you are building (not `~/.xcodebuildmcp`).
- **DerivedData:** `derivedDataPath` in yaml must be under `~/Library/Developer/Xcode/DerivedData/`. Run `resolve-derived-data-path.sh --sync-config` from that host directory when paths may be stale. Never use `XcodeBuildMCP/workspaces/...` for builds.
- **Profiles in yaml:** `sessionDefaultsProfiles.app` and `.tests` hold scheme, simulator, and path fields. They are **not** loaded automatically when you open a checkout — read the block and copy values into each MCP call.

Top-level `sessionDefaults` in yaml may still seed the MCP process at startup. Always pass the full argument set from **this** checkout’s profile so another project’s seed cannot leak in.

## Before every build or test

Run **immediately before each** `build_sim` or `test_sim` (including `build_sim` with `buildForTesting: true`). When switching hosts or Cursor workspaces, read **this** host’s yaml again.

1. Read `.xcodebuildmcp/config.yaml` (`sessionDefaultsProfiles.app` or `.tests` for the tool you will call). Resolve paths to absolute.
2. Assert locally (from yaml only):
   - `derivedDataPath` lives under `~/Library/Developer/Xcode/DerivedData/`.
   - DerivedData folder stem matches the `.xcodeproj` stem (e.g. `MyApp-…` with `MyApp.xcodeproj`).
3. Call the build/test tool with **every** required field in **tool_input** (see below). Do not omit `projectPath`, `scheme`, or `simulatorId` expecting session tools to fill them.

## Tool arguments (explicit per call)

### `build_sim` (profile `app`)

Pass on **every** call:

- `projectPath` (or `workspacePath` if the host uses a workspace)
- `scheme`
- `configuration` (from yaml, typically `Debug`)
- `simulatorId` (preferred) or `simulatorName`
- `derivedDataPath`

### Unit tests — `build_sim` (profile `tests`)

Pass on **every** `build_sim` with `buildForTesting: true`:

- `projectPath`, `scheme`, `configuration`, `simulatorId` (or `simulatorName`), `derivedDataPath`
- `testProductsPath` from the `tests` profile (stable path under that DerivedData)

All of the above must appear in the **same** `build_sim` call. Prepared-test mode needs `scheme` and `projectPath` in that call; do not call `build_sim` with only `derivedDataPath` and `testProductsPath`.

### `test_sim` (after build-for-testing)

Pass:

- `testProductsPath` chosen in **Unit tests** above (yaml path, or the newest timestamped child)
- `simulatorId` (or `simulatorName`)

Do **not** pass `scheme`, `projectPath`, `workspacePath`, `configuration`, or `derivedDataPath` with `testProductsPath` (prepared mode rejects source inputs).

Do not use source-mode `test_sim` (no `testProductsPath`).

## Switching checkouts

1. Read **this** checkout’s `.xcodebuildmcp/config.yaml`.
2. Use only that profile’s `projectPath` and `derivedDataPath` on the next MCP call.
3. If a build creates a folder under `~/Library/Developer/XcodeBuildMCP/workspaces/`, stop — a call ran without yaml `derivedDataPath`. Refusals: [checkout-environment.md](checkout-environment.md).

## Agent verification (builds and tests)

A successful build or test of **this app** is an XcodeBuildMCP result from the calls above. Shell `xcodebuild` does not count.

## Quick map

| Intent | Yaml profile | Typical tool |
| --- | --- | --- |
| Compile only | `app` | `build_sim` (full app profile args) |
| Unit tests | `tests` | `build_sim` (`buildForTesting: true` + full tests profile args) then `test_sim` (chosen `testProductsPath` + simulator only) |
