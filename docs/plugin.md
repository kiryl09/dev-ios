# dev-ios plugin

Product code for iOS work in Cursor: skills, rules, hooks, and MCP wiring. Source: `dev-ios/`.

Install copy, sync, and what may ship in the plugin: [README](../README.md).

## Layout

| Path | Role |
| --- | --- |
| `skills/` | Agent skills (`SKILL.md` + optional `scripts/`, `references/`) |
| `rules/` | Always-applied or scoped `.mdc` rules |
| `hooks/` | `hooks.json` and hook scripts (`lib/` for shared Python) |
| `mcp.json` | XcodeBuildMCP wrapper + `xcode-tools` (`xcrun mcpbridge`) |

Host identity for real work is the **user’s** iOS checkout: `.xcodebuildmcp/config.yaml` beside that checkout’s `.xcodeproj`.

Prefer **rules and skills** over growing hooks and shell scripts. Hooks and scripts guard safety and wire MCP; workflow detail belongs in documentation.

## Rules

| File | Purpose |
| --- | --- |
| `dev-ios-scope.mdc` | When dev-ios is active (iOS targets, `.cursor/dev-ios`, or `.xcodebuildmcp/config.yaml`) |
| `ios-workflow.mdc` | MCP routing, build/test obligations, skill scripts (active only in iOS scope) |
| `xcode-mcp-only.mdc` | Blocks Shell bypass of Simulator build/test/launch (active only in iOS scope) |

## Skills

Router: **`build-ios-apps`** — read first for MCP and specialist routing.

| Skill | When to use |
| --- | --- |
| `build-ios-apps` | Build, profile, debug, DerivedData/MCP bootstrap |
| `ios-debugger-agent` | Simulator build/run/test, UI automation, logs, debug |
| `ios-simulator-browser` | Hygiene, live mirror, SwiftUI preview browser |
| `ios-ettrace-performance` | ETTrace CPU profiles (pair with debugger agent) |
| `ios-memgraph-leaks` | Leaks and memgraphs (pair with debugger agent) |
| `ios-app-intents` | App Intents, Shortcuts, Siri, widgets |
| `swiftui-ui-patterns` | Navigation, layouts, controls, composition |
| `swiftui-view-refactor` | Split views, Observation, MV structure |
| `swiftui-liquid-glass` | Liquid Glass (OS 26+) |
| `swiftui-performance-audit` | Rendering/scroll/update performance from code |

Cross-platform SwiftUI skills apply when Xcode is open; iOS-only skills and XcodeBuildMCP apply only when `dev-ios-scope` is active.

How to change skills: [skills.md](skills.md).

## Hooks

Registered in `hooks/hooks.json`. Behavior and how to add hooks: [hooks.md](hooks.md).

| Script | Events | Purpose |
| --- | --- | --- |
| `deny-dev-ios-out-of-scope.sh` | Shell, MCP, read, preToolUse | Blocks XcodeBuildMCP and iOS-only skills when workspace is not iOS-scoped |
| `deny-xcode-bypass.sh` | Shell, read (soft), preToolUse | Blocks `xcodebuild` / `simctl` / cache writes via Shell or file tools |
| `deny-mcp-derived-data-copy.sh` | beforeMCP (build/test/clean) | Denies source-mode `test_sim` and foreign DerivedData paths |
| `witness-mcp-derived-data-copy.sh` | before/after MCP (build/test) | Witnesses MCP build/test against host yaml policy |
| `agent-session-lifecycle.sh` | Shell/MCP before/after, stop, sessionEnd | Records shell PIDs per chat; stops agent-started shells on stop/session end; MCP build diagnostics |

Shared libraries: `hooks/lib/ios_scope.py`, `dev_ios_gate.py`, `mcp_dd_policy.py`, `project_xcodebuild.py`.

## MCP

- **XcodeBuildMCP** — launched via `skills/build-ios-apps/scripts/xcodebuildmcp-with-xcode-derived-data.sh` (syncs DerivedData into yaml before MCP starts).
- **xcode-tools** — Apple `mcpbridge` for docs, Issue Navigator, `RenderPreview`, optional in-window build/tests.

## Host project discovery

All shell entrypoints that need “which app is this workspace?” source one library:

`skills/build-ios-apps/scripts/xcodebuildmcp-host-dir.sh`

| Step | Rule |
| --- | --- |
| Search anchor | Opened workspace folder: `WORKSPACE_FOLDER_PATHS` (Cursor MCP spawn), else optional `XCODEBUILDMCP_SEARCH_ROOT`, else process `cwd`. Host `.xcodeproj` is chosen only under that folder. Prefer hosts that already have `.xcodebuildmcp/config.yaml`; bootstrap can create yaml when none exists. |
| Build/test guard | Hooks resolve the same host via `mcp_host_resolver.py` + `xcodebuildmcp-host-dir.sh`; deny when there is no configured host or `session_defaults.projectPath` ≠ that host. |
| Project root | Git root from search anchor; if no `.git`, search anchor directory. |
| Search | Every `*.xcodeproj` under project root (recursive). |
| Skip | `Pods/`, `SourcePackages/`, `.git/`. |
| Pick | Parent of project with **smallest depth** below project root. |
| Ambiguity | Same minimum depth → fail; pass `--xcodeproj` to bootstrap. |
| Host directory | Folder containing the chosen `.xcodeproj`. |
| Config | `<host-dir>/.xcodebuildmcp/config.yaml` only (never `~/.xcodebuildmcp`). |

Consumers: `xcodebuildmcp-with-xcode-derived-data.sh`, `resolve-derived-data-path.sh`, `simulator-hygiene.sh`, `bootstrap-xcodebuildmcp-config.sh`.
