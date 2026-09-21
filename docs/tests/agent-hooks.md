# Agent + hooks (manual)

Manual chat checks after `hooks/`, `hooks.json`, or install-copy hook behavior changes. Complements [gates.md](gates.md) (policy unit tests).

## Prerequisites

1. [Sync + reload](../../README.md#dev-ios).
2. dev-ios active in an iOS-scoped workspace for bypass/MCP checks; separate macOS-only workspace for scope checks.

Hook inventory: [plugin.md](../plugin.md#hooks). Authoring: [hooks.md](../hooks.md).

## Checks

| Check | How |
| --- | --- |
| Shell bypass blocked | ios-scoped workspace: agent Shell `xcodebuild -version` → deny (`deny-xcode-bypass`) |
| Skill scripts allowed | Shell path to `…/dev-ios/skills/.../scripts/simulator-hygiene.sh status` → allow |
| MCP DerivedData policy | `test_sim` without `testProductsPath` → deny; with harness pinned path → allow ([sample-app.md](sample-app.md)) |
| Out of scope | macOS-only repo: XcodeBuildMCP blocked (`deny-dev-ios-out-of-scope`) |
| Session lifecycle | Agent Shell long `sleep`; **Stop** chat → child shell ends; MCP `xcodebuild` not killed |

Run at least bypass + MCP deny when hook scripts or `hooks.json` matchers change.
