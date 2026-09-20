# CursorPlugins

Local Cursor plugin sources. Install copies live under `~/.cursor/plugins/local/`.

## ios-dev

Plugin for iOS work in Cursor (skills, rules, hooks, XcodeBuildMCP wrapper). Source: `ios-dev/`.

**After every change** to `ios-dev/`, sync into Cursor’s install copy before you test or rely on it in chat:

```bash
rsync -a --delete /Users/logout/Projects/CursorPlugins/ios-dev/ ~/.cursor/plugins/local/ios-dev/
```

Cursor loads `~/.cursor/plugins/local/ios-dev`, not this checkout. Then **Developer: Reload Window** (restart XcodeBuildMCP in MCP settings if still stale).

**Agents:** after `rsync`, ask for reload and **wait until the user confirms** before claiming MCP works or using XcodeBuildMCP in chat. `tests/gates/` and wrapper `--dry-run` do not replace reload.

XcodeBuildMCP host discovery uses `XCODEBUILDMCP_SEARCH_ROOT` (`${workspaceFolder}` in [`ios-dev/mcp.json`](ios-dev/mcp.json)), not the MCP process `cwd`.

### Documentation

Do **not** copy the same procedures or policies into multiple `docs/*.md` files. Each topic has one canonical home; everywhere else, link.

| Doc | Canonical for |
| --- | --- |
| **This README** | Install path, sync + reload, MCP stale recovery, shipped vs `tests/` boundaries |
| [docs/plugin.md](docs/plugin.md) | Layout, rules, skills/hooks inventory, MCP, host discovery |
| [docs/skills.md](docs/skills.md) | Editing and adding skills |
| [docs/hooks.md](docs/hooks.md) | Hook I/O, events, per-script behavior, adding hooks |
| [docs/tests.md](docs/tests.md) | Testing index; each family in `docs/tests/<family>.md` |

When you change `ios-dev/`, hooks, or `tests/`, update the matching doc in the same change. Do not paste README sync steps into other docs.

### Quick boundaries

- **Shipped:** only `ios-dev/` (no `tests/`, no sample `.xcodeproj` inside the plugin).
- **Verification:** monorepo `tests/` — see [docs/tests.md](docs/tests.md).
