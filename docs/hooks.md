# Writing dev-ios hooks

Plugin hooks live in `dev-ios/hooks/`, registered by `hooks.json`. Runtime path is the install copy — [sync and reload](../README.md#dev-ios) after edits. Inventory table: [plugin.md](plugin.md#hooks).

## Design principles

1. **Fail closed for safety** — Use `"failClosed": true` on gates that must block bad MCP or Shell use.
2. **Scope first** — `deny-dev-ios-out-of-scope.sh` should stay early in chains so macOS-only workspaces are not forced through iOS MCP rules.
3. **Small surface** — Prefer policy in `hooks/lib/*.py` with thin `*.sh` wrappers that read JSON from stdin (`dd` + `python3`).
4. **No test harness in hooks** — Gates in `tests/gates/` invoke hook scripts and libraries directly; hooks must not depend on `tests/`.

## I/O contract

Command hooks receive one JSON object on stdin (often read via `meta=$(dd bs=65536 count=1)`). Respond with a single JSON line on stdout:

```json
{"permission":"allow"}
```

or

```json
{"permission":"deny","agent_message":"…","user_message":"…"}
```

On parse errors or crashes, `failClosed: true` denies the action.

Use `hooks/lib/dev_ios_gate.py` and `mcp_dd_policy.py` for consistent decisions; unit-style checks live in `tests/gates/run-gate-*.sh`.

## Event map (this plugin)

| Event | Hooks used |
| --- | --- |
| `beforeShellExecution` | out-of-scope, xcode-bypass, session lifecycle |
| `afterShellExecution` | session lifecycle |
| `beforeMCPExecution` | out-of-scope, derived-data deny, witness, lifecycle (matchers on build/test/clean) |
| `afterMCPExecution` | witness, lifecycle |
| `beforeReadFile` | out-of-scope; xcode-bypass for `Read`/`TabRead` (fail open) |
| `preToolUse` | out-of-scope, xcode-bypass for Grep/Glob/Write/Delete/StrReplace |
| `stop`, `sessionEnd` | session lifecycle (timeouts 30s / 60s) |

Matchers limit hot paths — follow existing `hooks.json` patterns when adding MCP hooks.

## `deny-xcode-bypass.sh`

Blocks Shell and file-tool access that bypasses MCP for Simulator/Xcode:

- CLI: `xcodebuild`, `xcrun`, `simctl`, etc.
- Writes/deletes under DerivedData, SourcePackages, CoreSimulator, Xcode.app
- `kill` / `pkill` aimed at `xcodebuild`

**Allowed** Shell: bundled skill scripts under `skills/*/scripts/` (regex in the hook).

## `deny-mcp-derived-data-copy.sh` / `witness-mcp-derived-data-copy.sh`

Policy in `mcp_dd_policy.py` + `mcp_host_resolver.py` (same host discovery as `xcodebuildmcp-host-dir.sh`): deny build/test when the workspace has no iOS host, when `session_defaults.projectPath` ≠ that host, pin `test_sim` to host DerivedData `testProductsPath`, deny `clean` and foreign workspaces, allow pinned `build_sim`/`test_sim` for the active host.

Changing policy requires updating Python **and** `tests/gates/run-gate-deny.sh` (and witness gate if behavior shifts).

## `deny-dev-ios-out-of-scope.sh`

Uses `ios_scope.py` (`plugin_applies`) and `dev_ios_gate.py` to block XcodeBuildMCP and iOS-only skill scripts when the workspace has no iOS scope.

Adding an iOS-only skill with scripts: [skills.md](skills.md) (`IOS_ONLY_SKILLS`).

## `agent-session-lifecycle.sh`

- Registers Shell commands started by the agent (per `conversation_id`) and sends SIGTERM on `stop` / `sessionEnd`.
- Does **not** kill `xcodebuild` or MCP-started builds.
- Records in-flight XcodeBuildMCP build/test/clean for diagnostics.

Keep this hook free of project-specific paths.

## Adding a new hook

1. Implement script under `dev-ios/hooks/` (or extend `lib/`).
2. Register in `hooks.json` with correct event, `matcher`, `failClosed`, `timeout`.
3. Add or extend a gate under `tests/gates/`.
4. Add a row to the hooks table in [plugin.md](plugin.md) and run [gates](tests/gates.md).
