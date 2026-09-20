# Testing the plugin

Maintainer verification lives under `tests/` at the monorepo root. Shipped vs harness boundaries: [README](../README.md#quick-boundaries). Sync before Cursor-side checks: [README](../README.md#ios-dev).

Per-family procedures live in **`docs/tests/`** (one file per test family; do not duplicate them here).

## Families

| Doc | `tests/` source | Cursor / Simulator |
| --- | --- | --- |
| [tests/gates.md](tests/gates.md) | `tests/gates/run-gate-*.sh` | No |
| [tests/mcp-launcher.md](tests/mcp-launcher.md) | `verify-xcodebuildmcp-launcher.sh` | MCP running |
| [tests/sample-app.md](tests/sample-app.md) | `xcode-sample_project/` | Yes |
| [tests/agent-hooks.md](tests/agent-hooks.md) | (manual in chat) | Yes |
| [tests/mcp-storage.md](tests/mcp-storage.md) | `observe-mcp-storage.sh` | Optional |
| [tests/workflows.md](tests/workflows.md) | — | Which families to run when |

Run [gates](tests/gates.md) on every substantive change. Run launcher + sample app (+ agent-hooks when hooks change) before merge.
