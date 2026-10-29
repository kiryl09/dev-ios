# Agent + hooks (manual)

Manual chat check after `hooks/` or `hooks.json` changes. Complements [gates.md](gates.md).

## Prerequisites

1. [Stage hooks (and any skills, scripts, or MCP under test) into the project `.cursor/`, then wait for a manual Reload Window](../../README.md#dev-ios). Do not sync `~/.cursor/plugins/local/` unless the user asks.
2. dev-ios active in an iOS-scoped workspace.

## Checks

| Check | How |
| --- | --- |
| Session lifecycle | Stop and sessionEnd do not send signals; registry closes; long-running shell and MCP `xcodebuild` keep running |

Hooks must not deny Shell or MCP. Scope and Simulator limits are skills and rules (`build-ios-apps`, `dev-ios-scope.mdc`, `xcode-mcp-only.mdc`).
