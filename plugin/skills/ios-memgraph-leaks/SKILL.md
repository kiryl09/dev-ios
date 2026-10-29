---
name: ios-memgraph-leaks
description: Capture and inspect iOS leaks and memgraphs. Use when debugging leaked objects, retain cycles, memory growth, or before/after leak evidence. Load only when dev-ios-scope is active (iOS workspace).
---

# iOS Memgraph Leaks

## Simulator UI forbidden

Never open Simulator.app and never launch an app in the Simulator. Allowed XcodeBuildMCP tools are `build_sim` and `test_sim` only. `test_sim` runs unit tests with mocks. Do not call `boot_sim`, `open_sim`, `build_run_sim`, `install_app_sim`, `launch_app_sim`, `stop_app_sim`, `screenshot`, `snapshot_ui`, `tap`, `touch`, `long_press`, `swipe`, `drag`, `gesture`, `button`, `key_press`, `key_sequence`, `type_text`, `wait_for_ui`, `record_sim_video`, or `debug_attach_sim`. Do not run `serve-sim`, `swiftui-preview-browser.py`, `open -a Simulator`, `simctl boot`, or `simctl launch`. If a task needs the Simulator window, stop and say this plugin does not launch Simulator UI.

Use this skill to prove iOS leaks from a live simulator process or an existing `.memgraph`. Do not launch the app and do not drive UI. Do not invent a second build path. Bundled scripts under this skill may run when this skill is loaded. Prefer simulator UDID and bundle id from `list_sims` and `get_app_bundle_id` rather than ad-hoc `xcrun simctl` as the first choice.

## Core Workflow

1. Do not launch the app. Read an existing `.memgraph` only. If none exists, stop.
2. Summarize leaks with `scripts/summarize_memgraph_leaks.py`.
3. For each app-owned leaked type, inspect ownership with `leaks --traceTree=<address> <file.memgraph>` and grouped leak evidence.
4. Make the smallest root-cause patch, then re-run `build_sim` / `test_sim` when verification is needed.
5. Report proof: before/after leak counts, disappeared root types, remaining leaks, memgraph paths, and test/build results.

Do not claim a leak fix from a smaller memgraph alone. A credible fix explains the ownership path that kept the object alive and shows that the same path or type disappears after the patch.

## Capture

Do not capture from a running simulator process via this plugin. Use an existing `.memgraph` file only.

## Summarize

Summarize an existing memgraph:

```bash
"$SKILL_DIR/scripts/summarize_memgraph_leaks.py" \
  /path/to/app.memgraph \
  --trace-limit 5 \
  --out /path/to/leak-summary.md
```

Use `--trace-limit` sparingly. Trace trees are useful root-cause evidence, but large memgraphs can produce noisy output. If a trace tree says `Found 0 roots referencing`, treat it as an unreachable/self-retained leak candidate and use the summary's grouped leak tree or `leaks --groupByType <file.memgraph>` to identify the retained fields and payload chain.

## Root Cause Rules

- Identify the first app-owned leaked type in the leak output or trace.
- Determine the intended lifetime: process, session, account, view, request, or task.
- Treat lazy or deferred allocation as a scope reduction, not a leak fix, unless the original eager allocation itself violated the intended lifetime.
- Prove retain-cycle claims with either a `traceTree` ownership path or an isolated reproduction.
- For unreachable/self-cycle leaks, `traceTree` may have no root path; use `leaks --groupByType` plus source verification to find the self-retaining edge.
- Do not claim success just because total leak count went down; prove the specific type or path disappeared.
- Separate real root-cause branches from candidate/noise branches.
- Prefer deleting the retaining edge over adding broad cleanup code.

## Report

A useful leak report includes:

- the exact flow and simulator/app build
- the memgraph and summary paths
- app-owned leaked types and counts
- at least one ownership path, or grouped leak tree evidence when the object is unreachable from roots
- the smallest proposed or applied retaining-edge fix
- before/after evidence when a fix was made

If the memgraph shows only framework/runtime noise, say that and recommend the next narrower capture rather than inventing an app leak.
