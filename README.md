# CursorPlugins

Monorepo for the **dev-ios** Cursor plugin. Marketplace manifest: [`.cursor-plugin/marketplace.json`](.cursor-plugin/marketplace.json). Shipped plugin source: [`plugin/`](plugin/).

Local install copies live under `~/.cursor/plugins/local/`.

## dev-ios

Plugin for iOS work in Cursor (skills, rules, hooks, XcodeBuildMCP wrapper). Source in this repo: `plugin/`.

**Cursor does not load `plugin/` from this checkout.** The installed plugin, when the user has one, lives at `~/.cursor/plugins/local/dev-ios`. Leave that install copy alone. Sync it only when the user personally asks to update the local plugin.

### Local install sync (only on an explicit user request)

Agents do not mirror `plugin/` into `~/.cursor/plugins/local/` as part of an edit or a test. Run this only after the user asks for that sync:

```bash
cd /path/to/CursorPlugins
rsync -a --delete plugin/ ~/.cursor/plugins/local/dev-ios/
```

`--delete` removes files dropped from the repo so the install copy does not keep stale skills, rules, or hooks. After that requested sync, follow the reload gate below before trusting Cursor, MCP, or chat.

### Testing updates in a project

Cursor-side checks (chat, hooks, MCP, sample app) use the **host project’s** `.cursor/` directory, not the local plugin install. Copy the pieces under test into that project, then make the user reload the window themselves before any check. In this monorepo you can run `tests/scripts/stage-plugin-to-cursor.sh` from the repo root (writes gitignored `.cursor/`).

| From `plugin/` | Into the host project |
| --- | --- |
| `skills/` (including each skill’s `scripts/`) | `.cursor/skills/` |
| `hooks/*.sh`, `hooks/lib/` | `.cursor/hooks/` |
| `hooks/hooks.json` | `.cursor/hooks.json` — rewrite each `command` to a project path such as `.cursor/hooks/<script>.sh` |
| `mcp.json` | `.cursor/mcp.json` — point the XcodeBuildMCP `args` entry at `.cursor/skills/build-ios-apps/scripts/xcodebuildmcp-with-xcode-derived-data.sh` (`${CURSOR_PLUGIN_ROOT}` applies only to a loaded plugin) |

Offline `tests/gates/` read `plugin/` from the git checkout and do not need this copy.

### When the user must reload (agents: block until confirmed)

Cursor keeps the previously loaded skills, hooks, and MCP until the window reloads. After staging into the project `.cursor/` (or after a user-requested local sync), **ask the user** to run **Developer: Reload Window** from the Command Palette **themselves**. Then **stop and wait until they explicitly confirm** the reload is done. Until that confirmation: no XcodeBuildMCP calls, no trusting hook outcomes, no “update is live” claims. Do not reload the window for them.

| You staged | Required before testing |
| --- | --- |
| `.cursor/mcp.json` or `skills/build-ios-apps/scripts/*` (wrapper, MCP entry, pinned npm version) | Manual Reload Window. If MCP tools or session defaults still look stale after reload → ask the user to **restart XcodeBuildMCP** in MCP settings; wait for confirmation again |
| `.cursor/hooks.json` or anything under `.cursor/hooks/` | Manual Reload Window |
| `.cursor/skills/**` | Manual Reload Window before treating instructions as live in chat |
| Any of the above when this task will build, test, or verify via MCP or hook behavior | Manual Reload Window |

`tests/gates/` and wrapper `--dry-run` never replace this staging plus the user’s confirmed reload. Monorepo edits outside `plugin/` (`tests/`, root `docs/`, root `.cursor-plugin/marketplace.json`) do not need a project `.cursor` copy or a reload.

XcodeBuildMCP host discovery uses Cursor’s `WORKSPACE_FOLDER_PATHS` (injected at MCP spawn; no `${workspaceFolder}` in [`plugin/mcp.json`](plugin/mcp.json)). Optional override: `XCODEBUILDMCP_SEARCH_ROOT` in the environment.

### Marketplace

Submit the **repository root** (not the `plugin/` tree URL): `https://github.com/<owner>/<repo>`. Cursor reads [`.cursor-plugin/marketplace.json`](.cursor-plugin/marketplace.json) and loads the entry with `"source": "plugin"`.

### Documentation

**Mandatory:** do not duplicate procedures or policies across `plugin/` or `docs/`. One canonical file per topic; everywhere else, link only. Merge blocker — see [docs/how-to-developer-plugin.md](docs/how-to-developer-plugin.md).

How the plugin must behave on any host project: [docs/plugin-functional-requirements.md](docs/plugin-functional-requirements.md). Add a functional requirement only after the conflict check in [docs/how-to-developer-plugin.md](docs/how-to-developer-plugin.md).

| Doc | Canonical for |
| --- | --- |
| [docs/plugin-functional-requirements.md](docs/plugin-functional-requirements.md) | **Behavior on a host project** (numbered functional requirements) |
| [docs/how-to-developer-plugin.md](docs/how-to-developer-plugin.md) | **Authoring rules** (dedup policy, docs canonical map, cross-tree boundaries) |
| **This README** | Install path, when local sync is allowed, project `.cursor` test staging, manual reload, MCP stale recovery, shipped vs `tests/` boundaries, **no host-specific names in `plugin/`** |
| [docs/tests.md](docs/tests.md) | Testing index; each family in `docs/tests/<family>.md` |

When you change `plugin/`, hooks, or `tests/`, update the matching doc in the same change. Link staging and reload steps here; do not paste the copy table or the `rsync` block into other docs.

### Quick boundaries

- **Shipped:** only `plugin/` (no `tests/`, no sample `.xcodeproj` inside the plugin).
- **Verification:** monorepo `tests/` — see [docs/tests.md](docs/tests.md).

### No host-specific names in `plugin/`

The plugin is installed once and used on **many different** iOS host checkouts. Everything under `plugin/` (rules, skills, hooks, scripts, hook messages, MCP wiring) must stay **host-agnostic**:

- Do **not** mention real app or repo names, scheme names from a particular product, or paths tied to one checkout (including usernames, `~/Projects/...`, or DerivedData folders from a known app).
- Write examples and scripts against **abstract** placeholders: `` `<MyApp>.xcodeproj` ``, `` `<MyAppTests>` ``, `` `<OtherApp>-…` `` under DerivedData, “another workspace that started MCP”, and paths derived from yaml/`projectPath` at runtime — not from a fixed project baked into the plugin.
- Concrete harness apps, sample paths, and gate fixtures live in **`tests/`** and **`docs/tests/`** only. Host projects keep their own `docs/testing.md`; do not copy those names into `plugin/`.

Contributors and agents editing `plugin/`: if you add an example, keep it generic. Review diffs for accidental host identifiers before merge.
