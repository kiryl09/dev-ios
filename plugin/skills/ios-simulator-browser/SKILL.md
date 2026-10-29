---
name: ios-simulator-browser
description: Simulator status, simulator shutdown, browser mirror, and optional Swift Package preview hot reload. Use for booted-simulator inventory and shutting down booted devices, watching or interacting with an app in the browser, or capturing browser-visible simulator proof. Load only when dev-ios-scope is active (iOS workspace).
---

# iOS Simulator Browser

Load this skill for **simulator status** (inventory and stale **Simulator.app** detection), **simulator shutdown** (`simctl shutdown` of booted devices), and **browser mirror** or **Swift Package preview** workflows. Pair with `ios-debugger-agent` when build, test, or launch must run first.

## Simulator status

XcodeBuildMCP has no `shutdown_sim` tool. Inventory is `simulator-status.sh`. Device shutdown is `simulator-shutdown.sh`. Do not use ad-hoc `simctl` or MCP `list_sims` text.

**Do not rely on `list_sims` formatted output** to decide whether simulators are off. It can show every device as `(Shutdown)` while **Simulator.app** still has open windows and CoreSimulator keeps consuming CPU. Parallel test clones (`Clone 1 of …`) appear in `simctl` JSON and may be missing from the MCP list.

Use `status` when inventory or load is unclear. **Agents must never** send signals to `xcodebuild`, `kill` PIDs from `status`, call MCP `clean`, or delete `DerivedData` / `SourcePackages`. **Never** start a second build or boot a second simulator.

```bash
plugins/dev-ios/skills/ios-simulator-browser/scripts/simulator-status.sh status
plugins/dev-ios/skills/ios-simulator-browser/scripts/simulator-status.sh status --json
```

| Command | Effect |
| --- | --- |
| `status` | Lists simulators plus CPU/RAM for project `xcodebuild` and CoreSimulator processes; sets `background_load` when the host is likely to feel slow |

Options: `--json`, `--check` (exit `1` when `background_load=true`), `--stale-seconds N` (default `7200`; inventory only — long SPM resolve is normal, not a kill signal).

| `status` signal | Meaning |
| --- | --- |
| `background_load=true` | Load signal only — do not start another build while `xcodebuild_count` > 0 |
| `simulator_cpu_percent` / `project_xcodebuild_cpu_percent` | Quick read on what is making the Mac feel slow |
| `orphan_coresimulator_load` in `background_load_reasons` | CoreSimulator still using CPU with no booted device; if booted devices exist and `xcodebuild_count=0`, run `simulator-shutdown.sh shutdown-all`; if `active_device_count=0`, report and ask the user |
| `active_device_count` > 0 | One or more devices are `Booted`, `Booting`, or `Shutting Down` in `simctl`. |
| `simulator_app_running=true` with `active_device_count=0` | Stale Simulator windows with no booted device — report and ask the user |
| `xcodebuild_count` > 0 | A project `xcodebuild` is still alive (often after MCP `-32001`, including multi-hour SPM resolve). Wait or ask the user; do not start another `build_sim` / `test_sim` / `build_run_sim`; do not call `simulator-shutdown.sh`; do not send a signal |
| `stale_xcodebuild_count` > 0 | Inventory only: process older than `--stale-seconds`. Still wait or ask the user in Xcode — never kill, never wipe `SourcePackages`. |
| `clone=yes` on a line | Parallel testing left a clone; if `xcodebuild_count=0`, run `simulator-shutdown.sh shutdown` |

Host docs may say which signed-in session to keep. They do **not** allow a second booted simulator or a second `xcodebuild`.

## Simulator shutdown

After a verification pass **and** `simulator-status.sh status` shows `xcodebuild_count=0`, run `simulator-shutdown.sh shutdown` (or `shutdown-all` when no signed-in runtime session must be preserved). The script refuses shutdown while project `xcodebuild` is still running. It does not quit **Simulator.app** or send signals.

```bash
plugins/dev-ios/skills/ios-simulator-browser/scripts/simulator-shutdown.sh shutdown
plugins/dev-ios/skills/ios-simulator-browser/scripts/simulator-shutdown.sh shutdown-all
```

| Command | Effect |
| --- | --- |
| `shutdown` | Shuts down all booted devices except `tests.simulatorId`; does not quit **Simulator.app** or send signals |
| `shutdown-all` | Shuts down every booted device; does not quit **Simulator.app** or send signals |

Options: `--keep-udid <UUID>`, `--all` (same as `shutdown-all` for configured device), `--stale-seconds N`.

## Simulator lifecycle

- Use only the UDID from host yaml per [session-defaults.md](../build-ios-apps/references/session-defaults.md). Do not `boot_sim`, `open_sim`, or `discover_projs`.
- Do not call `boot_sim` or `open_sim`. `test_sim` and `build_run_sim` boot the configured device when needed.
- `test_sim` is sequential: one call at a time on that same UDID. Do not shut it down between those runs.
- If `status` shows more than the yaml UDID or a clone, stop and ask the user when `xcodebuild_count` > 0; when `xcodebuild_count=0`, use `simulator-shutdown.sh` per host policy.

After MCP `-32001` on `test_sim` or `build_run_sim`, that run is **not evidence**. Do not start another `test_sim` or `build_sim`. Run `simulator-status.sh status` (do not rely on `list_sims` text alone), then:

1. If `xcodebuild_count` > 0 for this project → wait or ask the user. Do **not** start another `build_sim`. Never terminate `xcodebuild` or delete `SourcePackages`.
2. A device is `Booting` or `Shutting Down` → wait, run `status` again, then continue when only the configured UDID is `Booted` (or none). Do not call `boot_sim`.
3. `active_device_count` above the host limit, clone devices, or wedged state → only if `xcodebuild_count=0`: `simulator-shutdown.sh shutdown-all`, wait 30s, then continue. If SPM/checkout/submodule errors appear, **stop and ask the user**; do not retry the same resolve and do not `rm` checkouts.
4. **Narrow** before retry — do not retry the **same** `-only-testing` filter. Host order: full target → one suite → one test identifier (`docs/testing.md`; host `docs/testing-specific-rules-by-classes.md` when present).
5. **If already one test identifier** and `-32001` repeats after steps 1–3: warm the simulator with the fastest test in the same suite, then retry the target identifier once; increase the MCP wait for that call (start at 120s). Host specific-rules may document higher waits.
6. UDID missing from `status`, runtime install in progress, or `status` itself hangs → stop. Ask the user to check Xcode Components, license Agree, or first launch. Do not create another simulator.

## Bundled scripts

| Script | When to run |
| --- | --- |
| `scripts/simulator-status.sh status` | After `-32001`; when verifying simulator budget or checking background load |
| `scripts/simulator-shutdown.sh shutdown` | After verification pass; before next pass when extras are booted |
| `scripts/simulator-shutdown.sh shutdown-all` | Full reset when clones or no signed-in runtime session to preserve |
| `scripts/swiftui-preview-browser.py` | Swift Package preview hot reload (see below) |

## Browser Workflow

1. Obtain an explicit Simulator UDID from host yaml or `list_sims` (prefer the project's configured simulator). Do not use `xcrun simctl` as the primary path.
2. Start `serve-sim` in a long-running terminal pinned to that simulator:

   ```bash
   SIM="<simulator-udid>"
   npx --yes serve-sim@latest "$SIM"
   ```

   If a mirror for this UDID is already running, stop and ask the user.

3. Open the exact local preview URL printed by `serve-sim`:
   - **Cursor Browser Tab** — Settings → Tools & MCP → Browser Automation → Browser Tab, with **Show Localhost Links in Browser** enabled; open the URL from chat or terminal.
   - **Browser MCP** — `browser_navigate` to the URL, then `browser_snapshot` to confirm a real simulator frame is rendering.
4. Verify that a real frame is rendering before reporting success. A loaded page alone is not proof that the simulator stream is healthy.

- Keep the terminal alive while the browser mirror is in use. When finished, stop the terminal and wait for it to exit.

## `.xcodeproj` UI (no Canvas preview)

Do not use Xcode Canvas preview (disk-heavy). For `#Preview` content inside the app target, use **Browser Workflow** after `build_run_sim`, or `snapshot_ui` / `screenshot` from XcodeBuildMCP.

## SwiftUI Preview Workflow (Swift Package)

Use the bundled launcher when the requested previews live in an importable Swift package. Point it at the package manifest and select the target whose previews should be displayed. It generates a disposable host project outside the user's source tree, installs and launches that host in Simulator, and watches the package for edits.

```bash
python3 plugins/dev-ios/skills/ios-simulator-browser/scripts/swiftui-preview-browser.py \
  /absolute/path/to/Package.swift \
  --package-target "<target>" \
  --device "<simulator-udid>"
```

- Watch mode is enabled by default. On a Swift package source edit, the launcher rebuilds a generated dylib and hot-swaps it into the running host without relaunching the app.
- The generated host shows every preview variant discovered in the selected Swift Package target with in-simulator page controls. To show a subset instead, pass `--preview-filter <regex[, ...]>`; it matches display names and code identifiers such as `StatusRowView_Previews`.
- Once the launcher prints the selected Simulator UDID, start `serve-sim` for that same UDID and open its printed URL in Cursor Browser Tab or browser MCP.

## Support Boundary

- Support Swift Package-backed `PreviewProvider` and `#Preview` declarations through the generated host.
- Do not edit the user's `.xcodeproj`, `.xcworkspace`, `Package.swift`, schemes, or build settings to force preview support.

## Proof

For browser or preview QA, capture a browser snapshot showing the simulator frame. For hot reload QA, also report the launcher's `hot reloaded package preview ... in pid ...` output and show the changed frame after editing.
