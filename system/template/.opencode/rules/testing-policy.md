# Testing Policy

## Post-Change Testing

After making code changes, ALWAYS run unit tests for the affected module(s).

- Identify which module(s) were modified based on file paths (see the
  `test-commands` region below for this project's path → module / suite mapping)
- Run the project's unit-test command targeting the specific module(s) — see the
  `test-commands` region
- If tests fail, fix the issues before considering the task complete
- When a specific test fails, re-run just that single test (narrow to the one
  test class / method rather than the whole suite — see the `test-commands` region)
- Do NOT run integration tests automatically — they are slow and run in CI
- If changes span multiple modules, run tests for ALL affected modules

## Environment-Gated Tests

Some tests are guarded by an environment-availability assumption (an
`assume`/skip guard for Docker, a live broker, a GPU, network access, etc.) so
the suite degrades gracefully where that environment is absent.

- When the gated environment IS available in your local validation context,
  **actually run** such a change and confirm it PASSES — not merely that it
  skips. A test that only skips is not evidence the change works.
- **Keep the availability gating in place regardless.** It is still correct so
  the suite degrades gracefully on machines / CI agents without the environment.
  The environment being present changes how you *validate*, not how you *write*
  the tests.

## Before Committing (MANDATORY)

Follow the full pre-commit workflow in `commit-workflow.md`. That workflow covers
all file types. This file covers the language / module-specific testing details.

When the user asks to commit code changes:
1. **Run unit tests** for all affected modules. Fix failures before committing.
2. **Adversarial review** — launch `review-cheap` subagent (see
   `commit-workflow.md` Step 4; control / AI-component changes use `review-final`
   + gated approval).
3. **Only then commit.**

**Skip condition:** If user explicitly says to skip (e.g., "skip tests", "just commit"), skip corresponding steps.

If unit tests already passed earlier in this conversation for the exact same changes (no further edits since), skip re-running.

## Test Commands & Module Layout

<!-- FORGE:REGION test-commands BEGIN -->
<!-- forge-init: replace with this project's test layout — document the path → module/suite mapping, the exact unit-test / single-test / multi-module commands, and which suite is the always-run blast-radius gate. -->

**No test commands are configured yet.** The pre-commit and worktree gate chains
are **fail-closed**: until this region is populated by `/forge-init`, treat the
test gate as **unsatisfiable** — do NOT substitute an ad-hoc command and do NOT
record code changes as "tested" or commit them as validated. Run `/forge-init` first.

This region MUST document, for this project:

- the **test layout** — how source paths map to modules / packages / suites;
- the exact **commands** — run one module's unit tests, re-run a single test,
  and run several modules' tests at once;
- which suite is the **always-run blast-radius gate** — the suite run on every
  change regardless of what was touched (see [[worktree-workflow]] Gate 1).
<!-- FORGE:REGION test-commands END -->

## Test Quality

- **New tests:** Follow existing test patterns in the module — match the test
  framework, assertion style, and naming the surrounding module already uses.
- **Flaky tests:** Never just re-run — investigate root cause. Common causes: port contention, timing-dependent assertions, shared mutable state.
- Descriptive test names that explain the expected behavior.
