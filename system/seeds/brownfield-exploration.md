# Brownfield exploration protocol

How `/forge-init` explores a repo that already has code, CI, and conventions before
filling any region. **Principle: mirror the repo's existing reality — never invent a
parallel one.** A gate that runs different commands than CI, a changelog rule the
project doesn't follow, or triggers for failure modes the project never has, all
erode trust in the system. Every region filled must be traceable to something found
in this exploration.

For large repos, fan the read-only steps out to exploration subagents (one per area
below) and synthesize; for small repos do it inline. Record what was found — and what
was looked for but absent — in the init summary.

## 1. CI mining (highest value)

Find and read the real pipeline definitions:

| CI system | Look for |
|-----------|----------|
| GitHub Actions | `.github/workflows/*.yml` |
| GitLab | `.gitlab-ci.yml`, `.gitlab/` |
| Buildkite | `.buildkite/` |
| Jenkins | `Jenkinsfile*` |
| CircleCI | `.circleci/config.yml` |
| Azure | `azure-pipelines.yml` |

Extract the **exact commands** CI runs for test, lint, typecheck, build, and any
matrix dimensions (versions, OSes). These become the source of truth for:

- `stack-validations` (commit-workflow Step 2) — the local gate runs what CI runs, so
  a local PASS predicts a green pipeline;
- `gate1-test-command` — the merge gate is the CI test job (or its fast subset),
  plus the blast-radius suite;
- `AGENTS.md` `project-overview` — name the CI system and its trigger model.

If local execution of a CI command is impossible (needs services, secrets, cloud),
say so in the region and choose the strongest safe local substitute — never silently
substitute a weaker check.

## 2. Convention mining

- **Lint/format configs**: `.eslintrc*`, `biome.json`, `ruff.toml`/`pyproject [tool.*]`,
  `.golangci.yml`, `clippy.toml`, `checkstyle*.xml`, `.editorconfig`, `prettier*` —
  cite the configured tools in validations; never introduce a different linter.
- **Commit/PR conventions**: `commitlint`/conventional-commits evidence in
  `git log --oneline -50`, PR templates, `CODEOWNERS`, `CONTRIBUTING.md` — fold into
  the commit-workflow's message guidance and `/pr-review`'s classification context.
- **Changelog**: `CHANGELOG.md`/`changelog.md` present and maintained? Mirror its
  actual format in `changelog-policy`; if absent or abandoned, keep the explicit
  "no changelog gate" default.
- **Branch/merge conventions**: `git log --merges -20` — if history shows merge
  commits or the host enforces PR merges, **surface the conflict with the system's
  linear-history rule to the user** and record their decision (adopt rebase-FF going
  forward, or adapt the worktree-merge flow to the repo's PR process). Do not
  silently impose either.
- **Protected branches / required checks**: `gh api repos/{owner}/{repo}/branches/<default>/protection`
  (or the host equivalent) — required status checks belong in Gate-1/validations.

## 3. History mining (triggers and blast radius)

- **Bug-fix patterns**: `git log --oneline --grep='fix' -100` (also `revert`,
  `regression`, `leak`, `race`, `CVE`); read a sample of the fix diffs. Recurring
  defect classes become `project-triggers` rows and lens-table principles with real
  file/pattern citations.
- **Churn / coupling**: `git log --format= --name-only -200 | sort | uniq -c | sort -rn | head -20`
  — the hottest heavily-depended-on module is the **blast-radius suite candidate**;
  confirm with the user.
- **Reverts within 14 days** of the original commit indicate weak verification areas
  — note them in `testing-policy` as places needing stronger gates.

## 4. Docs and architecture indexing

- Inventory `README*`, `docs/`, `ARCHITECTURE*`, `ADR*`/`adr/`, wikis referenced from
  the README. Build the `project-docs` "Document | When to consult" table **from what
  exists** — do not fabricate docs entries.
- Module layout (workspaces, packages, crates, Maven modules) → per-agent
  `agent-project-context` regions: implementer gets conventions + module map;
  reviewers get architecture-doc references for boundary checks (COR-08);
  test-runner gets the test-command-per-module table.
- **Monorepo**: detect workspace manifests (`pnpm-workspace.yaml`, `workspaces` in
  package.json, Cargo workspace, multi-module poms). Validations and Gate-1 must be
  **path-scoped per package** with the blast-radius suite on top.

## 5. Existing agent-tooling detection

If the repo already has `.claude/`, `.opencode/`, `AGENTS.md`, `CLAUDE.md`, or
`.cursor/` content, the installer preserves clashes as `*.forge-new`. During
exploration: read the existing files, identify rules/commands worth keeping, and
propose a merge to the user (their project-specific knowledge is exactly what the
regions want). Never discard existing agent instructions unread.

## 6. Verification of the exploration itself

Before finishing Phase 2, prove the customization against reality:

1. Run the assembled `stack-validations` commands once on the clean tree — they must
   pass (a gate that fails on untouched code is miscalibrated).
2. Run the assembled `gate1-test-command` once — same requirement. Time it; if it is
   too slow for a per-merge gate, split into targeted + blast-radius parts and note
   the full-suite escape hatch.
3. Cross-check: every command cited in a region exists in the repo (script name,
   Makefile target, workflow job) — a region citing a nonexistent command is a
   defect, not a placeholder.
