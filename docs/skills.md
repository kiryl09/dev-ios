# Editing dev-ios skills

Skills live under `dev-ios/skills/<name>/`. Each skill needs a `SKILL.md` with YAML frontmatter (`name`, `description`) and a markdown body the agent reads when the skill is loaded.

## Conventions for this plugin

1. **Scope** — iOS-only skills must state they apply only when `dev-ios-scope.mdc` is active (authoritative list: `IOS_ONLY_SKILLS` in `hooks/lib/dev_ios_gate.py`). SwiftUI skills are cross-platform unless the text says otherwise.

2. **No host fixtures** — Do not hard-code sample app names, scheme names from `tests/xcode-sample_project`, or paths to this monorepo’s harness inside shipped skill text. Refer to “the host project”, `build-ios-apps/references/session-defaults.md`, or host `docs/testing.md`.

3. **Scripts** — Allowed under `skills/<name>/scripts/`. Only `build-ios-apps` and `ios-simulator-browser` ship scripts that agents run in production; other skills may document paths under `plugins/dev-ios/skills/...` for maintainer runs. New orchestration scripts belong in an existing skill’s `scripts/` tree, not ad hoc repo scripts.

4. **References** — Long or stable detail goes in `references/*.md` and is linked from `SKILL.md`. Session/project switching for XcodeBuildMCP lives only in `build-ios-apps/references/session-defaults.md` (see also `test-specific-rules.md`).

5. **Router** — New iOS workflows that change MCP or skill choice should update `build-ios-apps/SKILL.md` “Pick a skill” and, if behavior is binding for all agents, `rules/ios-workflow.mdc`.

6. **Out-of-scope gate** — New iOS-only skill with runnable scripts: add its directory name to `IOS_ONLY_SKILLS` in `hooks/lib/dev_ios_gate.py` ([hooks.md](hooks.md)).

## Frontmatter

Keep `description` specific: what the skill does **and** when to load it (triggers). The agent uses description for routing.

Optional frontmatter keys follow Cursor’s skill format; do not use `~/.cursor/skills-cursor/` for plugin skills.

## After editing

1. [Sync and reload](../README.md#dev-ios) (required before any chat or MCP check).
2. If scripts affect hooks or policy, run [gates](tests/gates.md) (see [workflows](tests/workflows.md)).
3. Update the skills table in [plugin.md](plugin.md) when you add, remove, or rename a skill.

## Checklist for a new skill

- [ ] `dev-ios/skills/<kebab-name>/SKILL.md` with frontmatter
- [ ] Listed in `build-ios-apps` router table if iOS execution-related
- [ ] `IOS_ONLY_SKILLS` updated when iOS-only with agent-run scripts
- [ ] No test-only paths or PluginProbe references in shipped text
- [ ] [plugin.md](plugin.md) skills table updated
