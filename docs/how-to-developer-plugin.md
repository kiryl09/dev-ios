# Documentation and authoring rules

**Mandatory for the whole repository:** do not duplicate procedures, policies, checklists, or step-by-step workflows across files. Each topic has exactly one authoritative home. Every other mention must be **one short sentence plus a markdown link**, not a second copy of the steps.

This is a **merge blocker** for changes under `plugin/` and `docs/`: parallel instructions are wrong even if wording differs slightly.

Applies to:

- **`plugin/`** — agent-facing skills, rules, and references.
- **`docs/`** — maintainer and contributor documentation (this file for the docs canonical map).
- **Boundaries** — do not paste `plugin/` workflow detail into `docs/` or vice versa; link across the boundary. Harness names and paths stay in `tests/` and `docs/tests/` only, not in `plugin/`.

## Forbidden duplication (any tree)

- Numbered or bulleted **how-to** sequences (staging `.cursor/`, Reload Window, MCP prep, gate runs, verification smoke, hook debugging).
- **Normative policies** stated fully in two files (e.g. README and `docs/tests/gates.md`).
- **Tables** that repeat the same inventory (skills list, hook list, gate list) without adding new information.
- **“Reminder”** or **“Quick reference”** blocks that restate a full procedure from another doc.
- Copying the README **rsync** / staging table or MCP stale recovery steps into other docs — link [README § dev-ios](../README.md#dev-ios) instead.

## Allowed

- **Index pages** (`docs/tests.md`) — family names and links only; no per-family steps.
- **One-line obligations** plus a link (e.g. “Run gates on every substantive change — [gates.md](tests/gates.md)”).

## Canonical map (`docs/`)

| Topic | Only here | Elsewhere |
| --- | --- | --- |
| How the plugin behaves on a host project (numbered functional requirements) | [plugin-functional-requirements.md](plugin-functional-requirements.md) | README links; do not restate the list |
| Install, marketplace, `.cursor/` staging, manual reload, MCP stale recovery, shipped vs `tests/` boundaries, no host names in `plugin/` | [README.md](../README.md) | Link only |
| Testing index (which family doc to open); untested changes are not complete | [tests.md](tests.md) | Steps in `docs/tests/<family>.md` |
| Offline gates | [tests/gates.md](tests/gates.md) | Not in README body |
| MCP launcher check | [tests/mcp-launcher.md](tests/mcp-launcher.md) | — |
| Harness Simulator smoke | [tests/sample-app.md](tests/sample-app.md) | Not in `plugin/` |
| Manual hook checks in chat | [tests/agent-hooks.md](tests/agent-hooks.md) | — |
| XcodeBuildMCP disk / storage | [tests/mcp-storage.md](tests/mcp-storage.md) | — |
| Which test families to run when | [tests/workflows.md](tests/workflows.md) | — |
| This policy (docs + cross-tree dedup) | **This file** | README links here |

When you add a test script or gate, add or update the matching `docs/tests/<family>.md` in the **same** change. Do not describe that family again in [tests.md](tests.md) beyond the index row.

## Functional requirements

Numbered behavior of the plugin on a host project lives only in [plugin-functional-requirements.md](plugin-functional-requirements.md). Do not put authoring rules there. Shipped tree vs `tests/`, host-agnostic wording in `plugin/`, and local install sync stay in [README § dev-ios](../README.md#dev-ios). Dedup and same-change doc updates stay in this file.

When someone proposes a **new** functional requirement:

1. Compare it against every existing numbered item in that file for conflict (contradiction, overlap that implies different behavior, or incompatible obligations).
2. If there is a conflict, **ask the user** how to resolve it (replace, narrow, merge, or reject one side) before changing the list.
3. After resolution (or if there is no conflict), add the requirement as the next numbered item and keep wording precise and testable.

## Editing discipline

1. Before adding text, search `docs/` and `plugin/` for the topic; **edit the canonical file** or remove the duplicate you are about to create.
2. If you touch a file that still contains a copied procedure, **replace it with a link** in the same change when reasonable.
3. New cross-cutting maintainer topics get **one** new `docs/tests/<family>.md` or an extension to an existing canonical doc — not a second home in README.

## After editing `plugin/` or `docs/`

- Update the canonical doc for that topic in the same change.
- Grep for key phrases you added; dedupe before merge.
