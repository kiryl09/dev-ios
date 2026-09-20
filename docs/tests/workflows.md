# Test workflows

Cross-family order of operations. Per-family detail: sibling files in this directory.

## Quick pass (offline)

[gates.md](gates.md) — run all `tests/gates/run-gate-*.sh`.

## Pre-merge (MCP + hooks)

1. All gates.
2. [Sync + reload](../../README.md#ios-dev).
3. [mcp-launcher.md](mcp-launcher.md).
4. [sample-app.md](sample-app.md) — `build_sim`, `test_sim`.
5. [agent-hooks.md](agent-hooks.md) — if `hooks.json` or bypass logic changed.

## Change → minimum checks

| Change area | Minimum |
| --- | --- |
| `hooks/` or `hooks/lib/*.py` | All [gates](gates.md); [agent-hooks](agent-hooks.md) bypass + MCP deny |
| `hooks/hooks.json` | Gates + agent lifecycle if lifecycle matchers changed |
| `skills/build-ios-apps/scripts/` | `run-gate-sync`, `run-gate-wrapper`, pin gates, `run-gate-edges`; launcher + sample app |
| `mcp.json`, entry/patch scripts | `run-gate-edges`, pin gates, launcher, sample app |
| `tests/xcode-sample_project/` | `run-gate-miniap`, sample app |
| Skills/rules only (no scripts/hooks) | Gates optional; sample app if MCP routing text changed |

When you add a test script or gate, add or update the matching `docs/tests/<family>.md` in the same change.
