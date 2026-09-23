# Testing the plugin

Maintainer verification lives under `tests/` at the monorepo root. Shipped vs harness boundaries: [README](../README.md#quick-boundaries). Staging and reload: [README § dev-ios](../README.md#dev-ios) only (do not copy those steps here).

Per-family procedures live in **`docs/tests/`** only — index below, no duplicated steps ([how-to-developer-plugin.md](how-to-developer-plugin.md)).

**Completion:** a change is not finished until you have run the applicable verification for that change area ([workflows.md](tests/workflows.md) and the linked family docs). Untested changes do not count as done.

## Families

| Doc | `tests/` source | Cursor / Simulator |
| --- | --- | --- |
| [tests/gates.md](tests/gates.md) | `tests/gates/run-gate-*.sh` | No |
| [tests/mcp-launcher.md](tests/mcp-launcher.md) | `verify-xcodebuildmcp-launcher.sh` | MCP running |
| [tests/sample-app.md](tests/sample-app.md) | `xcode-sample_project/` | Yes |
| [tests/agent-hooks.md](tests/agent-hooks.md) | (manual in chat) | Yes |
| [tests/mcp-storage.md](tests/mcp-storage.md) | `observe-mcp-storage.sh` | Optional |
| [tests/workflows.md](tests/workflows.md) | — | Which families to run when |
| [tests/verification-mcp.md](tests/verification-mcp.md) | — | MCP smoke bar after staging |

Run [gates](tests/gates.md) on every substantive change. Run launcher + sample app (+ agent-hooks when hooks change) before merge.
