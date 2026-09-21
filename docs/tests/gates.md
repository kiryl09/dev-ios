# Shell gates

Offline scripts under `tests/gates/`. They read `dev-ios/` from the git checkout (not the Cursor install copy). No Simulator, no sync required unless you also run Cursor-side checks afterward.

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
| `run-gate-deny.sh` | `mcp_dd_policy.py` / `deny-mcp-derived-data-copy`: deny `clean`, source-mode `test_sim`, foreign DerivedData; allow pinned host `test_sim` / `buildForTesting` |
| `run-gate-witness.sh` | Witness policy: new dirs under `XcodeBuildMCP/workspaces/.../DerivedData` after MCP build → deny |
| `run-gate-wrapper.sh` | `xcodebuildmcp-with-xcode-derived-data.sh --dry-run`: `XCODEBUILDMCP_CWD`, `derivedDataPath`, bootstrap, no yaml mutation on unrelated checkouts |
| `run-gate-sync.sh` | `resolve-derived-data-path.sh --sync-config` rewrites yaml DerivedData to Xcode-style path under `~/Library/Developer/Xcode/DerivedData/` |
| `run-gate-pin-derived-data.sh` | Patch + env so prepared `test-without-building` uses pinned DerivedData (npm version from `xcodebuildmcp-pinned-version`) |
| `run-gate-pin-test-products.sh` | Patch + `XCODEBUILDMCP_PINNED_TEST_PRODUCTS_PATH` overrides default test products path |
| `run-gate-edges.sh` | Hygiene/policy invariants (no `kill-xcodebuild` in hygiene), `deny-xcode-bypass` allow/deny samples, resolve idempotency, `mcp.json` wiring, skill/bootstrap grep checks |
| `run-gate-miniap.sh` | Harness has `.xcodeproj` + valid `.xcodebuildmcp/config.yaml` (`projectPath` under harness, profiles present) |

`find-harness-checkout.sh` resolves `tests/xcode-sample_project` when harness yaml exists.

## When to run

Run the full loop on every substantive `dev-ios/` change. For targeted edits, see [workflows.md](workflows.md).

Add or extend a gate when you introduce a new invariant; document it in this file in the same change.
