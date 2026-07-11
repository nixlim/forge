---
name: forge-init
description: Install and initialize the forge agent operating system (DVRR worktrees, gate chain, adversarial review, evals) in the current repo. Use when asked to run forge-init, install forge, or initialize the forge system.
---

<!-- forge: generated from commands/forge-init.md (body verbatim). Keep in sync. -->

Install the forge agent operating system into the current repository and fill in its
per-project layer. The system is vendored at
`/Users/nixlim/Sync/PROJECTS/foundry_zero/forge/system/` (see its `UPSTREAM` file for
provenance) with installer `/Users/nixlim/Sync/PROJECTS/foundry_zero/forge/bin/forge-install.sh`.

Follow these phases in order. **Fail closed**: if a phase cannot complete, stop, say
what is missing, and leave the FORGE:REGION defaults in place (they fail closed by
design) rather than guessing.

## Phase 0 — Preconditions

1. Confirm the CWD is a git repository root. If not a repo, offer to `git init` first.
2. If `.forge-manifest` already exists, this is a **re-init — safe and idempotent**:
   the installer carries forward every FILLED region (a region is "filled" once its
   `forge-init:` instruction comment has been removed) and preserves
   `init_completed`/`region:` manifest lines; only regions still holding their
   fail-closed default are refreshed from the template. Read the manifest, tell the
   user what is already installed and which regions are filled vs unfilled
   (`grep -rln "forge-init:" .opencode .claude AGENTS.md` lists files with UNFILLED
   regions), then process ONLY the unfilled ones in Phase 2 and skip existing eval
   fixtures in Phase 3. Do not re-fill filled regions unless the user asks.
3. Confirm with the user: project name (default: directory name) and default branch
   (default: auto-detected). These are the installer's substitution parameters.
4. Check `command -v flock`. It is absent on stock macOS; the worktree merge then uses
   the rule's `mkdir`-based mutex fallback. Tell the user, and suggest
   `brew install flock` for the primary path. Not a blocker either way.

## Phase 1 — Mechanical install

Run:
```bash
/Users/nixlim/Sync/PROJECTS/foundry_zero/forge/bin/forge-install.sh \
    --project-name "<name>" --branch "<branch>"
```
Review its output. If it reports preserved files (`*.forge-new`), tell the user those
need manual merge and include them in Phase 5's summary. Verify with `git status` that
the expected tree appeared (`.opencode/`, `.claude/`, `AGENTS.md`, `CLAUDE.md`,
`opencode.jsonc`, `.forge-manifest`).

## Phase 1.5 — Explore the existing repo (brownfield)

If the repo has existing code, CI, or conventions, run the exploration protocol in
`/Users/nixlim/Sync/PROJECTS/foundry_zero/forge/system/seeds/brownfield-exploration.md`
BEFORE filling any region. **Principle: mirror the repo's existing reality — never
invent a parallel one.** In brief:

1. **CI mining** — read the actual pipeline definitions (GitHub Actions, GitLab,
   Buildkite, Jenkins, CircleCI…); the commands CI runs are the source of truth for
   `stack-validations` and `gate1-test-command`, so a local PASS predicts a green
   pipeline.
2. **Convention mining** — existing linters/formatters (never introduce different
   ones), commit/PR conventions, changelog reality, CODEOWNERS, protected-branch
   required checks. If history shows merge commits or a PR-merge process, surface
   the conflict with the system's linear-history rule and record the user's decision.
3. **History mining** — recurring fix/revert patterns become `project-triggers` rows
   with real citations; the hottest depended-on module is the blast-radius candidate.
4. **Docs indexing** — build the `project-docs` table from docs that actually exist;
   map module layout into per-agent `agent-project-context` regions; detect monorepos
   (path-scoped validations).
5. **Existing agent tooling** — read any pre-existing `AGENTS.md`/`.claude/`/
   `.opencode/` content (preserved as `*.forge-new` by the installer) and propose a
   merge; never discard existing agent instructions unread.

For large repos, fan these out to parallel read-only exploration subagents and
synthesize. Record in the Phase 5 summary both what was found and what was looked
for but absent. A greenfield repo (no code yet) skips this phase — say so.

## Phase 2 — Per-project layer (the judgment work)

Fill every `<!-- FORGE:REGION ... -->` block **from the Phase 1.5 findings** — every
filled region should be traceable to something the exploration found. Find them all
first:
```bash
grep -rn "FORGE:REGION" --include="*.md" --include="*.jsonc" --include="*.toml" .opencode .claude .codex AGENTS.md opencode.jsonc 2>/dev/null | grep BEGIN
```

For each region, replace the default content BETWEEN the BEGIN/END markers. Two
invariants make re-init idempotent — keep both:

- **Keep the BEGIN/END markers** — they let re-init and forge-sync find the regions.
- **Delete the region's `<!-- forge-init: ... -->` instruction comment when you fill
  it.** Its presence is the machine-readable "unfilled" signal: the installer refreshes
  regions that still contain it and preserves regions that don't. A filled region that
  keeps the comment would be clobbered on the next re-install.

Skip regions that are already filled (no `forge-init:` comment) — this makes re-runs
no-ops for completed work:

1. **Stack detection first.** Identify the stack(s) from manifests (`package.json`,
   `pyproject.toml`, `go.mod`, `Cargo.toml`, `pom.xml`, `build.gradle*`, `*.tf`,
   `Dockerfile*`, `Chart.yaml`). Read the repo's own scripts (package.json scripts,
   Makefile, justfile) — prefer them over generic commands.
2. `file-categories` + `stack-validations` (in `.opencode/rules/commit-workflow.md`):
   assemble from `/Users/nixlim/Sync/PROJECTS/foundry_zero/forge/system/seeds/validation-snippets/stacks.md`,
   adapted to the repo's actual commands. Keep the upstream shape: numbered steps,
   executable verification preferred, "fix before committing".
3. `gate1-test-command` (in `.opencode/rules/worktree-workflow.md`,
   `.claude/commands/worktree-merge.md`, and `.agents/skills/worktree-merge/SKILL.md`): the
   targeted test command plus one **always-run blast-radius suite** (the module the
   rest depends on most). **Ask the user to confirm the blast-radius choice**
   (AskUserQuestion, recommended option first). All three files must carry the same
   command.
4. `test-commands` (in `.opencode/rules/testing-policy.md`): document the test layout,
   runners, and the confirmed blast-radius suite.
5. `project-triggers` + `completeness-project-items` (in
   `.opencode/rules/review-constitution.md`): seed 3–8 project-specific review triggers
   from (a) the stack's classic failure modes, (b) `git log` — recurring fix/revert
   patterns, (c) any existing docs on known pitfalls. Add project-specific principles
   into the lens tables with IDs continuing each lens's numbering, marked
   "Project-specific:". Cite real file paths/patterns from THIS repo.
6. `review-prompt-project-focus` (in `.opencode/rules/commit-workflow.md`): 3–5 bullets
   pointing the reviewer at the triggers from step 5, with principle IDs.
7. `changelog-policy` (in `.opencode/rules/commit-workflow.md`): if the repo keeps a
   changelog, write the upstream-style rule (unreleased section, user-facing test,
   entry format); otherwise keep the explicit "no changelog gate" default.
8. `agent-project-context` (in `.claude/agents/*.md`, `.opencode/agents/*.md`, and
   `.codex/agents/*.toml` — in the TOMLs the region sits inside the
   `developer_instructions` string; edit between the markers, keep valid TOML):
   per agent, list this repo's key docs, conventions, module layout, and test commands
   relevant to that agent's role. Keep it short (3–8 lines each). Fill all three
   harness copies of each agent identically.
9. `skill-project-context` (in `.opencode/skills/*/SKILL.md`): same, per skill.
10. `project-overview`, `project-docs`, `project-policies` (in `AGENTS.md`): write the
    project overview (stack, CI, infra, repo host), the "Document | When to consult"
    table from the repo's actual docs, and any compatibility/versioning/release
    policies (or state none).
11. `opencode.jsonc`: verify the model IDs against this machine
    (`opencode models` if opencode is installed; otherwise leave the VERIFY comment in
    place and tell the user).
12. Codex (if the `codex` CLI is installed): validate the payload —
    `python3 -c 'import tomllib,glob; [tomllib.load(open(p,"rb")) for p in glob.glob(".codex/**/*.toml", recursive=True)]'`
    then `codex execpolicy check --rules .codex/rules/forge.rules -- git push --force`
    (expect `forbidden`). Tell the user to open Codex in the repo once and TRUST it —
    the `.codex/` layer (config, agents, rules, hooks) is skipped until trusted, and
    and that `/commit` + `/worktree-merge` are available in Codex as skills from
    `.agents/skills/` (`$commit`, `$worktree-merge` — list with `/skills`).

Before leaving Phase 2, verify the customization against reality (protocol §6): run
the assembled validation and Gate-1 commands once on the clean tree — they must pass
(a gate that fails on untouched code is miscalibrated); confirm every command cited
in a region actually exists in the repo; time Gate-1 and split targeted vs
blast-radius if it is too slow for a per-merge gate.

## Phase 3 — Eval baselines

1. Create `.opencode/evals/tasks/` fixtures from the three templates in
   `/Users/nixlim/Sync/PROJECTS/foundry_zero/forge/system/seeds/eval-tasks/`:
   concretize each against THIS repo (real language, realistic diff, a bug class from
   this repo's history where possible). Keep the frontmatter format. **Idempotency:
   never overwrite an existing fixture or `.result` baseline** — on re-init, only
   create fixtures that are missing.
2. Establish baselines: for each fixture, run the named agent (spawn `review-cheap` via
   the Agent tool with the fixture's Input diff, exactly as `commit-workflow.md` Step 4
   invokes it), read its verdict, write it to `tasks/<id>.result`.
3. Run `bash .opencode/evals/run-evals.sh` — it must exit 0. If a recorded verdict does
   not match the expectation, the fixture (or the reviewer) needs work — investigate,
   do not massage the `.result` to pass ([[control-integrity]]).

## Phase 4 — Gate chain on the install itself

The installed system is, by its own rules, a **control-class change** (gated approval,
never autonomous — see `.opencode/rules/risk-authority-classification.md`):

1. Run `STRICT=1 bash .opencode/evals/run-evals.sh`.
2. Spawn the `review-final` agent (fresh context) on the full install diff
   (`git add -N . && git diff` or stage explicitly and use `git diff --cached`) with the
   review prompt from `commit-workflow.md` Step 4. Its verdict is binding.
3. Verify no region is still unfilled unless the user chose to defer it:
   `grep -rn "forge-init:" .opencode .claude AGENTS.md` must return nothing (or only
   the user's explicitly deferred regions — list those as residual risk).
4. Update `.forge-manifest`: set `init_completed: true` and add a
   `region: <name> (<file>)` line per filled region (the installer carries these
   lines forward on re-installs).

## Phase 5 — Present for approval (do NOT auto-commit)

Summarise: files installed, regions filled (and how), blast-radius suite chosen, eval
baseline results, review-final verdict, preserved `*.forge-new` files needing manual
merge, residual risks. Then ask the user for explicit approval to commit. On approval,
follow `.opencode/rules/commit-workflow.md` (stage explicit paths; the install commit
message records the upstream commit hash from `.forge-manifest`).

If the user provided additional instructions: $ARGUMENTS
