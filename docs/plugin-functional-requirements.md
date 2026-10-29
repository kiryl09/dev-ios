# Plugin behavior on a host project

What the dev-ios plugin must do when it is used on another project. These items are runtime behavior. How to edit this repository is not listed here.

1. Every time the user wants to add changes to the plugin, analyze those changes for conflict with the requirements already in this file. If there is a conflict, ask the user how to resolve it, and add only requirements that are already resolved.
2. All requirements are numbered, and the plugin must satisfy every rule at the same time. No rule may be ignored or only partly satisfied.
3. The agent may start implementing a rule only after that rule has been added to this document.

## Requirements

4. On an active iOS host, the agent must use at most one booted simulator: the UDID from that checkout’s `.xcodebuildmcp/config.yaml`. The agent must not run `simctl clone`, boot a second device, or leave parallel-test clone devices (`Clone N of …`) running.
5. After `resolve-derived-data-path.sh --sync-config`, the `tests` profile’s `extraArgs` in host yaml must include `-parallel-testing-enabled` `NO` and `-maximum-parallel-testing-workers` `1` (with `-resultBundlePath` as today). Those `extraArgs` are passed on `test_sim` only, not on `build_sim`.
6. Host yaml must stay current without user instructions: the XcodeBuildMCP launcher runs `resolve-derived-data-path.sh --sync-config` on every MCP start when it can resolve the open host; `bootstrap-xcodebuildmcp-config.sh` runs the same sync immediately after creating yaml.
7. `build_sim` with `buildForTesting: true` passes the yaml `tests.testProductsPath` (the stable `*.xctestproducts` directory). `test_sim` passes that same path when it is a symlink, or when it contains no child directory named `<tests.scheme>_yyyy-MM-dd_HH-mm-ss.xctestproducts`. When such children exist and the yaml path is not a symlink, `test_sim` passes the newest child by that timestamp. Later `build_sim` calls still receive the yaml path. `test_sim` calls after one `build_sim` reuse the path chosen for that build until the next `build_sim`. The agent must not write a timestamped child into yaml, must not pass a timestamped child to `build_sim`, and must not `clean`, delete `.o` files, delete the test binary, set `SWIFT_ENABLE_INCREMENTAL_COMPILATION=NO`, edit the Xcode project, or change test source to force a relink because the yaml directory’s `Info.plist`, `Binaries`, or `Tests` are older than a timestamped child.
