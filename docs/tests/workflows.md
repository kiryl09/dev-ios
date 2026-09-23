# Test workflows

Cross-family order of operations. Per-family detail: sibling files in this directory.

## Quick pass (offline)

[gates.md](gates.md) — run all `tests/gates/run-gate-*.sh`.

## Pre-merge (MCP + hooks)

1. All gates.
2. [Stage into the project `.cursor/` and wait for a manual Reload Window](../../README.md#dev-ios). Do not sync `~/.cursor/plugins/local/` unless the user asks.
3. [mcp-launcher.md](mcp-launcher.md).
4. [sample-app.md](sample-app.md) — `build_sim`, `test_sim`.
5. [agent-hooks.md](agent-hooks.md) — if the lifecycle hook or `hooks.json` changed.

## Change → minimum checks

| Change area | Minimum |
| --- | --- |
| `hooks/` or `hooks/lib/*.py` | All [gates](gates.md); [agent-hooks](agent-hooks.md) lifecycle check |
| `hooks/hooks.json` | Gates + agent lifecycle if lifecycle matchers changed |
| `skills/build-ios-apps/scripts/` | `run-gate-sync`, `run-gate-wrapper`, pin gates, `run-gate-edges`; launcher + sample app |
| `mcp.json`, entry/launcher scripts | `run-gate-edges`, derived-data-switch gate, launcher, sample app |
| `tests/xcode-sample_project/` | `run-gate-miniap`, sample app |
| Skills/rules only (no scripts/hooks) | Gates optional; sample app if MCP routing text changed |
| `ios-simulator-browser` preview launcher (`swiftui-preview-browser.py`, `lib/xcode_project.py`) | `python3 -m unittest discover -s tests/preview-browser` |

When you add a test script or gate, add or update the matching `docs/tests/<family>.md` in the same change.
