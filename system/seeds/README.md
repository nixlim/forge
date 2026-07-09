# Forge seeds — Tier-3 material generated fresh per install

Nothing in this directory is copied verbatim into a target repo. `/forge-init` uses it
as source material to *generate* the per-project layer:

- `eval-tasks/` — starter golden-task templates for `.opencode/evals/tasks/`. forge-init
  concretizes each one against the target repo (real language, a real planted bug in a
  realistic diff for that codebase), then establishes the baseline by running the named
  agent and recording `tasks/<id>.result`.
- `validation-snippets/` — per-stack file-category rows and validation commands for the
  `FORGE:REGION file-categories` and `FORGE:REGION stack-validations` regions in
  `.opencode/rules/commit-workflow.md`. forge-init detects the stack(s) from the repo
  (lockfiles/manifests) and assembles the regions from the matching snippets, adjusting
  commands to the repo's actual scripts (`package.json` scripts, Makefile targets, etc.).

Conventions: generated eval tasks keep the upstream fixture frontmatter format
(`id` / `category` / `agent` / `expected_verdict`); generated validation sections keep
the upstream commit-workflow shape (numbered steps, "fix before committing", the
executable-verification principle).
