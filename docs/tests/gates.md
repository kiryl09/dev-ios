# Shell gates

Offline scripts under `tests/gates/`. They read `plugin/` from the git checkout (not a Cursor install copy and not the project `.cursor/`). No Simulator. Cursor-side checks afterward use [project `.cursor` staging and a manual Reload Window](../../README.md#dev-ios), not a sync to `~/.cursor/plugins/local/` unless the user asks.

## Run all

From the monorepo root:

```bash
for g in tests/gates/run-gate-*.sh; do
  echo "== $g =="
  "$g"
done
```

Each script prints `gate-<name> PASS` or exits non-zero.

## Scripts

| Script | Covers |
| --- | --- |
| `run-gate-wrapper.sh` | `xcodebuildmcp-with-xcode-derived-data.sh --dry-run` (no host bind), bootstrap, `resolve-derived-data-path` on harness |
| `run-gate-sync.sh` | `resolve-derived-data-path.sh --sync-config` rewrites yaml DerivedData to Xcode-style path under `~/Library/Developer/Xcode/DerivedData/` |
| `run-gate-derived-data-switch.sh` | Two harness projects: distinct Xcode DerivedData paths that match each yaml |
| `run-gate-edges.sh` | Hygiene invariants (no `kill-xcodebuild`), no deny hooks in `hooks.json`, resolve idempotency, `mcp.json` wiring, skill/bootstrap grep checks |
| `run-gate-miniap.sh` | Harness has `.xcodeproj` + valid `.xcodebuildmcp/config.yaml` (`projectPath` under harness, profiles present) |

`find-harness-checkout.sh` resolves `tests/xcode-sample_project` when harness yaml exists.

## When to run

Run the full loop on every substantive `plugin/` change. For targeted edits, see [workflows.md](workflows.md).

`run-live-derived-data-switch.sh` runs sequential **Shell `xcodebuild`** against both harness projects. It checks DerivedData path stability only. It is **not** plugin or MCP verification. Real smoke is [sample-app.md](sample-app.md) via XcodeBuildMCP after staging and Reload Window ([verification-mcp.md](verification-mcp.md)).

Add or extend a gate when you introduce a new invariant; document it in this file in the same change.
