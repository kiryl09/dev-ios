# Host project: test-specific execution rules

Use this reference when a host project's default unit-test workflow (`build_sim` with `buildForTesting: true` plus full yaml `tests` profile in tool args, then `test_sim` with the path from [session-defaults.md](session-defaults.md) and `simulatorId`) is not enough for some scopes. The plugin stays generic; **each repo owns its knowledge base** for overrides.

## Two-document split

| Document | Location (convention) | Contents |
| --- | --- | --- |
| **Testing policy** | `docs/testing.md` (or project equivalent) | Default procedure, budgets, hygiene, **how to decide** the next filter when something fails. No per-test recipes. |
| **Test-specific rules** | `docs/testing-specific-rules-by-classes.md` (suggested name) | **Concrete** scopes, extra parameters, verified outcomes, fallbacks. Living document. |

Link them both ways: policy → "overrides live in specific-rules"; specific-rules → "decision logic lives in policy".

Mention the specific-rules file in the host project's agent guide (`AGENTS.md` or equivalent) and in the testing policy overview.

## When to create the file

Create or extend the specific-rules file when verification shows a scope needs more than the default policy:

- Repeated `-32001` without pass/fail for a suite or full target
- Suite filter still times out → per-test split required
- `signal kill`, Mach errors, or bootstrap failures tied to run pattern (parallel `test_sim`, clones, wedged simulator)
- Multiple `-only-testing` flags in one call cause crashes
- A scope needs a non-default flag, env var, or `simulator-shutdown.sh shutdown-all`
- `TEST_HOST` or scheme settings make a suite systematically slow

Do **not** create rows preemptively for tests that pass under the default procedure.

## What to record (table row)

Each row is one **test scope** (full target, suite, or single test identifier). Use copy-pasteable parameters agents can run without reinterpretation.

| Column | Write |
| --- | --- |
| **Test scope** | Swift Testing / XCTest identifier: `Target/Suite`, `Target/Suite/testName()`, or `(full target)` |
| **Why default run is heavy** | Factual: MCP timeout, clone spawn, launch cost, async length, flaky host state — not opinions |
| **Additional parameters / constraints** | Exact `extraArgs`, filter strings, one-run-per-call rules, warm-up order, shutdown steps, fallback tool |

Optional trailing sections in the same file:

- **Shared baseline** — pointer back to policy + plugin scripts every row inherits
- **Verification research notes** — dated findings, symptom → action tables, "what not to do"
- **Agent workflow** — if discovery fails, update this file before reporting done

## Decision flow (belongs in testing policy, not here)

Teach agents to narrow in order: full target (only when required) → one suite → one test per `test_sim`. Never two `test_sim` or two simulators at once. After one `build_sim` (`buildForTesting: true` with yaml paths in tool args), reuse the `test_sim` path from [session-defaults.md](session-defaults.md) for sequential `test_sim` calls in that pass. Record successful narrowing in **this** file when the same scope fails again.

## Agent obligation (living document)

If an agent finds working parameters for a scope **not listed** in the host specific-rules file:

1. Run the default policy first.
2. Adjust until pass/fail evidence or a clear blocker.
3. **Add or update a row** in the specific-rules file before finishing the task.
4. Do not treat one-off runs as team knowledge.

Remove a row when the default policy alone is sufficient again.

## Starter template

Copy into the host repo (adjust paths and target name):

```markdown
# Test-specific execution rules

Concrete overrides for scopes that need more than [Testing policy](testing.md).
Decision logic stays in the policy; record what worked here.

**Living document.** Add or update a row when verification discovers new parameters.
Do not only run ad-hoc overrides in the session.

## Shared baseline

Apply [Testing policy](testing.md) and `build-ios-apps` ([session-defaults.md](session-defaults.md): `build_sim` with `buildForTesting: true` and the full yaml `tests` profile, then `test_sim` with the path that file chooses and `simulatorId` only). Simulator status and shutdown: `ios-simulator-browser`.

## Rules by test scope

| Test scope | Why default run is heavy | Additional parameters / constraints |
| --- | --- | --- |
| `<TestTarget>` (full target) | … | … |
| `<TestTarget>/<Suite>` | … | … |
| `<TestTarget>/<Suite>/<testName>()` | … | … |

## When to add or update a row

- `-32001` without pass/fail after default procedure
- Narrowing (suite → per-test) was required
- Documented fallback (`simulator-shutdown.sh shutdown-all`, extra `extraArgs`) was required

## References

- [Testing policy](testing.md)
- Plugin: `plugins/dev-ios/skills/build-ios-apps/SKILL.md`
```

## Plugin scripts (inherit in every row)

Unless a row says otherwise, host specific-rules should reference:

- `resolve-derived-data-path.sh` (`build-ios-apps`) — `derivedDataPath` and yaml `testProductsPath` sync
- Unit tests: `build_sim` (`buildForTesting: true` + yaml paths in tool args) → `test_sim` (path from [session-defaults.md](session-defaults.md))
- `simulator-status.sh` (`ios-simulator-browser`) — authoritative booted state via `status`
- `simulator-shutdown.sh` (`ios-simulator-browser`) — `shutdown` / `shutdown-all`
- Anti-clone `test_sim` flags come from yaml `tests.extraArgs` after `resolve-derived-data-path.sh --sync-config` (`-parallel-testing-enabled` `NO`, `-maximum-parallel-testing-workers` `1`)

The plugin forbids parallel `xcodebuild` and a second booted simulator. Host policy does not raise that cap.
