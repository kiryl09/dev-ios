# CursorPlugins

Local Cursor plugin sources. Install copies live under `~/.cursor/plugins/local/`.

## dev-ios

Plugin for iOS work in Cursor (skills, rules, hooks, XcodeBuildMCP wrapper). Source in this repo: `dev-ios/`.

**Cursor does not load this folder.** It loads `~/.cursor/plugins/local/dev-ios`. Treat that path as the **runtime** plugin; keep it a **fresh mirror** of `dev-ios/` in this repo (same files, no drift). Edit source here; sync so local always matches.

### Keep `~/.cursor/plugins/local/dev-ios` in sync

After **any** change under `dev-ios/` — and before you trust Cursor, MCP, or chat to reflect those changes — mirror the tree into the install copy:

```bash
cd /path/to/CursorPlugins
rsync -a --delete dev-ios/ ~/.cursor/plugins/local/dev-ios/
```

`--delete` removes files dropped from the repo so local does not keep stale skills, rules, or hooks.

### When the user must reload (agents: block until confirmed)

`rsync` writes the install copy; Cursor still runs the **previous** loaded plugin, rules, hooks, and MCP until the window reloads.

After `rsync`, if **any** row below matches what you changed, you **must** ask the user for **Developer: Reload Window** (Command Palette), then **stop and wait until they explicitly confirm** reload is done. Until then: no XcodeBuildMCP calls, no trusting hook outcomes, no “plugin is updated” claims.

| You changed | Required |
| --- | --- |
| `mcp.json` or `skills/build-ios-apps/scripts/*` (wrapper, MCP entry, patches, pinned version) | Reload Window. If MCP tools or session defaults still look stale after reload → ask user to **restart XcodeBuildMCP** in MCP settings; wait for confirmation again |
| `hooks.json` or anything under `hooks/` | Reload Window |
| `rules/*.mdc` or `.cursor-plugin/plugin.json` | Reload Window |
| `skills/**` (SKILL.md, references, non-wrapper scripts under other skills) | Reload Window before treating instructions as live in chat |
| Any `dev-ios/` file and this task will build/test/verify via MCP or plugin behavior | Reload Window (including “docs-only” diffs under `dev-ios/`) |

Reload **not** required for plugin install when you only changed monorepo paths **outside** `dev-ios/` (for example `tests/`, root `docs/`). You still `rsync` whenever `dev-ios/` itself changed.

**Agents:** run `rsync` in the **same task** whenever you edit `dev-ios/`. `tests/gates/` and wrapper `--dry-run` never replace sync + mandatory reload from the table + user confirmation.

XcodeBuildMCP host discovery uses Cursor’s `WORKSPACE_FOLDER_PATHS` (injected at MCP spawn; no `${workspaceFolder}` in [`dev-ios/mcp.json`](dev-ios/mcp.json)). Optional override: `XCODEBUILDMCP_SEARCH_ROOT` in the environment.

### Documentation

Do **not** copy the same procedures or policies into multiple `docs/*.md` files. Each topic has one canonical home; everywhere else, link.

| Doc | Canonical for |
| --- | --- |
| **This README** | Install path, sync + reload, MCP stale recovery, shipped vs `tests/` boundaries |
| [docs/plugin.md](docs/plugin.md) | Layout, rules, skills/hooks inventory, MCP, host discovery |
| [docs/skills.md](docs/skills.md) | Editing and adding skills |
| [docs/hooks.md](docs/hooks.md) | Hook I/O, events, per-script behavior, adding hooks |
| [docs/tests.md](docs/tests.md) | Testing index; each family in `docs/tests/<family>.md` |

When you change `dev-ios/`, hooks, or `tests/`, update the matching doc in the same change. Link sync steps here; do not paste the full `rsync` block into other docs.

### Quick boundaries

- **Shipped:** only `dev-ios/` (no `tests/`, no sample `.xcodeproj` inside the plugin).
- **Verification:** monorepo `tests/` — see [docs/tests.md](docs/tests.md).
