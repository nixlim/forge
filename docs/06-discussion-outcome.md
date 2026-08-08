# 06 — Discussion Outcome: Wholesale Adoption + One-Command Installer

**Date:** 2026-07-09
**Status:** Decided (design approved in discussion; implementation not yet started)
**Supersedes:** the selective "adopt / adapt / skip" stance in
[05-recommendations.md](05-recommendations.md). That doc remains useful as an analysis
of *which parts carry the value*, but the adoption strategy is now wholesale.

## Decision

1. **Copy the MockServer AI-SDLC system exactly** — the full DVRR operating model, all
   rules, agents, commands, scripts, evals, and dual-harness configuration — rather than
   cherry-picking components.
2. **Package it as a replicable installer**: a single command that installs the system
   into any repo the user works in, ready for a new project.

**Rationale (user):** agreement with the design choices as made; the author (James
Bloom) is a colleague; the repo is Apache-2.0 open source, so borrowing wholesale and
modifying is legitimate.

**Licensing note:** MockServer is Apache-2.0 (`LICENSE.md` @ `7febd65f`). Wholesale copying
and modification is permitted; the license requires retaining attribution/notice. The
vendored system should carry a `NOTICE`/provenance header (source repo, commit hash,
license) — which we want anyway for upstream syncing (see below).

## Answer: can this be done?

**Yes.** Three facts make it straightforward:

1. **The system is file-based and self-contained.** Everything lives in `.opencode/`,
   `.claude/`, `AGENTS.md`, and a handful of `docs/operations/` pages. No services, no
   build step, no external state. Installation is fundamentally "copy files, substitute
   project parameters, append `.gitignore` entries, commit."
2. **The coordination scripts are already repo-agnostic.** Verified at `7febd65f`:
   `acquire-commit-lock.sh`, `release-commit-lock.sh`, `agent-status.sh`,
   `check-halt.sh`, and `aggregate-telemetry.sh` resolve everything via
   `git rev-parse` and relative paths — the only project reference is the word
   "MockServer" in one error string per lock script. They run unmodified in any git repo.
3. **The system already separates engine from project configuration** — imperfectly, but
   along visible seams. The porting work is not rewriting; it is *templating* a known,
   small set of project-specific regions (inventory below).

## Inventory: what copies verbatim vs. what must be parameterized

Grep-verified against `7febd65f` (`mockserver|MockServer|mvnw|Maven|Buildkite` across
rules, scripts, commands).

### Tier 1 — copies verbatim (the engine, ~75% of the system)

| Component | Files | Notes |
|---|---|---|
| Operating model | `rules/operating-model.md` | fully generic (references spec §s — keep) |
| Governance | `rules/control-integrity.md`, `risk-authority-classification.md`, `operator-halt.md`, `untrusted-input.md`, `git-safety.md`, `multi-pass-temperature.md`, `subagent-routing.md`, `decision-log.md`, `metrics.md`, `evaluation-harness.md`, `tmp-directory.md`, `local-plans.md`, `licence-provenance.md`, `mermaid-diagrams.md`, `report-formatting.md`, `coding-principles.md`, `commit-locking.md` | generic as written |
| Scripts | all 5 in `.opencode/scripts/` | fix one error-message string |
| Commands | `/worktree`, `/agent-status`, most others | generic |
| Agents | 12 agent prompts (both `.opencode/agents/` and `.claude/agents/`) | bodies mostly generic; strip "MockServer conventions" phrases and the per-project Required Reading lists into template slots |
| Eval runner | `.opencode/evals/run-evals.sh`, README | generic harness |
| Harness config | `.claude/settings.json` (permissions, Stop hook), `opencode.jsonc` skeleton | model routing is a parameter, mechanism is generic |
| `.gitignore` block | `.worktrees/`, `.tmp/`, `AGENT_HALT*`, `*.local.md`, `.tmp/.commit-lock` | verbatim |

### Tier 2 — generic skeleton with project-specific regions (templating targets)

| Component | Project-specific region |
|---|---|
| `rules/review-constitution.md` | 8 lenses + axioms + iteration protocol + finding format are **generic**; the MockServer principles (`AMB-08`, `INC-13..16`, `SEC-10..13`, `COR-08..12`, `FEA-06..07`, `OPS-09..12`, `CPX-11..12`) and the trigger table are **per-project** — replace with a `<!-- PROJECT TRIGGERS -->` section seeded per repo |
| `rules/commit-workflow.md` | workflow spine is generic; Step 1 file-category table and Step 2 per-category validation commands (Maven/Terraform/Helm/Jekyll…) are per-stack |
| `rules/worktree-workflow.md` | flow is generic; Gate 1's test command (`./mvnw verify -pl :mockserver-core …`) is per-stack; branch name `master` → parameter (`master`/`main`) |
| `rules/testing-policy.md`, `documentation-style.md` | mostly generic with MockServer examples to swap |
| `/worktree-merge`, `/commit` commands | same Gate-1/validation substitutions |
| `AGENTS.md` | Instruction Priority, Agent Operating Model, Git Policy, Parallel Sessions sections are **generic**; Project Overview, docs table, AWS/Buildkite sections are **per-project** |
| `docs/operations/ai-sdlc-integration-spec.md` | copy as the normative reference with a provenance header; it is ~90% generic (MUST/SHOULD requirements) with MockServer examples |

### Tier 3 — per-project, generated fresh at install (not copied)

- **Golden eval tasks** (`evals/tasks/`) — theirs test MockServer fixtures; each install
  seeds 3 starter tasks (planted-bug-must-BLOCK, clean-change-must-PASS,
  injection-must-flag) against the target repo's own code.
- **Review-constitution project triggers** — seeded from the target repo's stack and bug
  history; grown via the rules-as-postmortems habit.
- **Validation command table** — derived from detected stack (package.json → npm; pom →
  Maven; Cargo.toml → cargo; go.mod → go; etc.).
- **Model/effort routing** — our defaults (Claude tiers) rather than their OpenAI ones.
- **Drop entirely:** `rules/aws-ids-file.md`, changelog-specific gate content, Buildkite
  material (unless the target project has an analog).

## Installer design

**Recommended shape: a template payload + a `/forge-init` command (agent-driven
install), backed by a plain script for the mechanical copy.**

```
forge/system/                        ← canonical vendored copy ("the golden master")
├── UPSTREAM                         ← source repo URL + commit hash + license note
├── engine/                          ← Tier-1 files, verbatim (byte-diffable vs upstream)
├── template/                        ← Tier-2 files with {{PLACEHOLDER}} regions
└── seeds/                           ← Tier-3 generators (eval task templates, stack
                                        detection → validation-table snippets)
forge/bin/forge-install.sh           ← mechanical copy + substitution + .gitignore append
~/.claude/commands/forge-init.md     ← the one command: runs the script, then does the
                                        judgment work (stack detection, trigger seeding,
                                        AGENTS.md project section, baseline evals)
```

Why this split:

- **Script for the deterministic part** (copy, substitute `{{DEFAULT_BRANCH}}`,
  `{{PROJECT_NAME}}`, append `.gitignore`, `mkdir .tmp`) — idempotent, testable, no LLM
  variance.
- **Agent command for the judgment part** — detecting the stack, writing the per-category
  validation table, seeding project review triggers from the repo's history, drafting the
  `AGENTS.md` project overview, and establishing eval baselines all require reading the
  target repo. This is exactly what a slash command is for; it also matches the system's
  own rule that its installation is a **control-class change** — the init command should
  finish by running the gate chain on its own output and presenting it for approval.
- The command lives at **user scope** (`~/.claude/commands/`) so it is available in every
  repo immediately — satisfying "run a command in any repo I work in."

Alternatives considered:

| Option | Verdict |
|---|---|
| Pure shell installer (no agent step) | Works for the engine but produces a hollow install — empty trigger tables, no validation commands, PENDING evals. The per-project layer is where the system bites. Keep as the substrate. |
| Claude Code plugin (commands/agents/skills/hooks distributable via marketplace) | Good for *distributing* the `/forge-init` command and user-scope agents; cannot materialize repo files (rules, `AGENTS.md`, scripts) by itself — those must live in the target repo for opencode parity and for teammates. Viable later as the delivery channel for the installer itself. |
| Existing `vault` skill (team distribution of rules/commands/skills via sx) | Same role as the plugin option — a delivery channel, not the templating mechanism. Integrate once the payload exists. |

## Upstream sync strategy

Treat the vendored system as a **tracked fork**, not a snapshot:

1. `forge/system/UPSTREAM` records the source commit (`7febd65f…`, 2026-07-06).
2. Tier-1 engine files stay **byte-identical to upstream where possible** (even keeping
   `.opencode/rules/` paths), so `diff -r` against a fresh clone shows exactly (a) our
   deliberate modifications and (b) upstream improvements to pull.
3. A small `forge-sync` helper (later) re-clones upstream, diffs the engine, and
   presents adoptable upstream changes. James's repo is actively evolving —
   the profile-set versioning and telemetry sections have visible recent churn — so this
   will pay off quickly.
4. Local modifications to engine files get a one-line `<!-- forge: modified from
   upstream — reason -->` marker so syncs stay tractable.

## Consciously accepted trade-offs

- **We inherit their ceremony level.** Doc 05's concerns (telemetry discipline, autonomy
  posture, 10-cap) are accepted as-is per the wholesale decision; the system's own
  "scale the ceremony to the task" rule and earned-autonomy mechanism are the built-in
  relief valves. Divergence, if needed, happens later as normal control-class changes
  *inside* the installed system.
- **Dual-harness files ship even for Claude-only repos.** Keeping `.opencode/` parity
  costs a few files and preserves the option to run opencode (the user has opencode
  projects); the rules are shared either way.
- **The 94 KB spec ships with the install.** It is the system's constitution; rules
  cite it by section. Copying it with a provenance header is cheaper than rewriting
  every citation.

## Next steps

1. ~~Build `forge/system/`~~ — **done 2026-07-09**: engine (53 files), template
   (39 files, 31 balanced FORGE:REGION blocks), seeds (5 files).
2. ~~Write `forge-install.sh`~~ — **done**: idempotent; tokens + branch rewrite
   (perl, not BSD sed), `.gitignore` marker guard, preserved-file `.forge-new`
   semantics, `.forge-manifest`, memory-plugin-dropping exclusions.
3. ~~Write `/forge-init`~~ — **done**: `~/.claude/commands/forge-init.md` (5 phases,
   ends with the system's own gate chain on the install diff; never auto-commits).
4. ~~Test end-to-end~~ — **done** on throwaway repos: main-branch install (91 files,
   zero token/branch leftovers), master-branch control (engine byte-identical),
   idempotent re-run, preserved-AGENTS.md scenario, functional tests (halt engage/
   clear + audit log, commit lock acquire/release, agent-status from inside a
   worktree, run-evals fail-closed pre-init, telemetry aggregation + parallelism
   sampling), and a full worktree lifecycle: create → commit → mutex-locked rebase →
   fast-forward push → cleanup, linear history confirmed. Not yet run on a real
   foundry_zero project.
5. (Later) `forge-sync` upstream-diff helper; optional plugin/vault packaging for
   distribution.

### Implementation notes (2026-07-09)

Three upstream bugs were found by the e2e tests and fixed in our copy (recorded in
`system/UPSTREAM`; worth reporting to James): (1) `agent-status.sh` resolves the
worktree root instead of the main checkout when run from inside a worktree — i.e. from
exactly where sessions live; (2) the rebase-lock path `.git/agent-rebase.lock` is
invalid inside a worktree, where `.git` is a pointer file — fixed to the shared
`--git-common-dir`; (3) `flock` is not "present by default on macOS" as the rule
claimed — availability is now checked and the `mkdir` mutex is the documented standard
fallback. Additionally `subagent-routing.md` moved from engine to template (its
conversational routing table is inherently per-project), and the installer defends
against local memory-plugin `CLAUDE.md`/`.devlog` droppings contaminating the payload.

Post-implementation hardening (2026-07-09, after the initial import):

- **Constitution integrity fix**: the templated review skills cited seven principle
  IDs deleted as "MockServer-specific" (AMB-08, CON-07/08, SEC-11, OPS-09/10,
  COR-08). Re-added as genericized rows with stable IDs; two genuinely
  project-specific citations fixed at the call site. A payload-wide cross-reference
  check now passes (details in `system/UPSTREAM`).
- **Idempotent re-init**: the installer performs a region-preserving refresh —
  filled `FORGE:REGION` blocks (identified by the removal of their `forge-init:`
  instruction comment) survive re-installs verbatim; unfilled ones refresh from the
  template; manifest state, eval fixtures, and baselines are preserved. Verified by
  an 11-point test battery including a byte-identical third run.
- **Brownfield exploration (Phase 1.5)**: `/forge-init` now explores existing repos
  before filling regions — CI mining (local gates run what CI runs), convention and
  history mining, docs indexing, existing-agent-tooling merge, and self-verification
  of assembled gates against the clean tree. Protocol:
  `system/seeds/brownfield-exploration.md`.
- The forge repo is published at `github.com:nixlim/forge` (initial import
  `b29fcc3`; brownfield phase `fc60f0f`), with the canonical `/forge-init` versioned
  at `commands/forge-init.md`.

## Default model routing (resolved 2026-07-09)

Decision: a two-tier **strong / weak** mapping per harness. Upstream's three OpenAI
tiers collapse as: gpt-5 agents → **strong**; gpt-4o and gpt-4o-mini agents → **weak**.

| Harness | Strong | Weak | Notes |
|---|---|---|---|
| opencode | GLM 5.2 | M3 | keep upstream per-agent **temperatures** unchanged; exact provider/model IDs resolved when writing the template `opencode.jsonc` |
| Claude Code | Fable | Opus | keep upstream per-agent **effort** frontmatter unchanged (effort is the temperature analog here) |
| Codex | keep upstream as-is | keep upstream as-is | gpt-5 / gpt-4o / gpt-4o-mini exactly as in upstream `opencode.jsonc` — including the mid tier |

Per-agent result (temperatures from upstream `opencode.jsonc:60-172`):

| Agent | Tier | opencode | Claude Code | Codex (upstream) |
|---|---|---|---|---|
| `review-final` | strong | GLM 5.2, t=0.1 | Fable, effort high | gpt-5, t=0.1 |
| `security-auditor` | strong | GLM 5.2, t=0.1 | Fable, effort high | gpt-5, t=0.1 |
| `implementer` | strong | GLM 5.2, t=0.2 | Fable, effort high | gpt-5, t=0.2 |
| `debugger` | strong | GLM 5.2, t=0.2 | Fable | gpt-5, t=0.2 |
| `pipeline-investigator` | strong | GLM 5.2, t=0.2 | Fable | gpt-5, t=0.2 |
| `review-cheap` | weak | M3, t=0.1 | Opus | gpt-4o, t=0.1 |
| `code-reviewer` | weak | M3, t=0.1 | Opus | gpt-4o, t=0.1 |
| `simplifier` | weak | M3, t=0.1 | Opus | gpt-4o, t=0.1 |
| `taskify-agent` | weak | M3, t=0.3 | Opus | gpt-4o, t=0.3 |
| `docs-writer` | weak | M3, t=0.4 | Opus | gpt-4o, t=0.4 |
| `test-runner` | weak | M3, t=0 | Opus, effort low | gpt-4o-mini, t=0 |
| `council-seat` | weak | M3, t=0.7 | Opus | gpt-4o-mini, t=0.7 |

Properties preserved by the collapse:

- **The cheap/authoritative review split survives on every harness** — `review-cheap`
  is always on the weak tier, `review-final` always on the strong tier, so the
  separation-of-duties economics (fast lane per commit, binding verdict at merge)
  carry over intact.
- On Claude Code the lost mid tier is recovered by **effort** (upstream already sets
  per-agent effort in `.claude/agents/` frontmatter — keep those values, swap only the
  model); on opencode by **temperature** (kept verbatim).
- Any change to this table after install is a **control-class change** in the installed
  system (evals + `review-final` + human approval), including model *version* bumps —
  the eval-harness rule already treats a model swap as a behavioural change.

Two items to verify during step 3 of Next steps:

1. Exact provider/model ID strings for GLM 5.2 and M3 in opencode's provider syntax,
   and Fable/Opus IDs for `.claude/agents/` frontmatter.
2. Codex is a **third harness upstream does not target** — it reads `AGENTS.md` but has
   no per-subagent model registry comparable to `.claude/agents/` or `opencode.jsonc`.
   "Keep what they have" is recorded as the intent (the gpt-5 family tiers); the
   mechanism (whether routing is per-subagent or a documented tier the session requests)
   gets settled when the Codex config file is authored.

   **RESOLVED 2026-07-11** — Codex CLI (verified on 0.144.1) now supports project-scoped
   subagent definitions, so routing is **per-subagent**: `system/template/.codex/agents/*.toml`
   (generated from `.claude/agents/*.md`, bodies verbatim) registered in
   `.codex/config.toml`. Codex agent TOML has no temperature key; `model_reasoning_effort`
   mirrors the Claude Code effort values (same tier-recovery mechanism), with the upstream
   temperature kept as a provenance comment. Reviewer agents get an *enforced*
   `sandbox_mode = "read-only"`. Deny-list ports to execpolicy `forbidden` rules
   (`.codex/rules/forge.rules`); Stop-hook telemetry to `.codex/hooks.json`; `/commit` +
   `/worktree-merge` to Codex skills in `.agents/skills/` (Codex deprecated custom
   prompts in favour of skills). Residual risks recorded in the operating
   manual: Codex hooks/execpolicy are experimental upstream; the `.codex/` layer loads
   only after per-operator repo trust (fail-closed); chained-command splitting for
   execpolicy could not be confirmed on 0.144.1 via `codex execpolicy check` (parity
   caveat: the other harnesses' pattern deny-lists share the same literal-prefix
   character).

## Kimi Code CLI + ZCode harnesses (resolved 2026-07-18)

Decision: **Kimi Code CLI becomes the fourth first-class harness; ZCode (Z.ai) is a
companion harness at the advisory tier.** Mechanism mapping, verified against the
official docs of both products (kimi.com/code/docs, zcode.z.ai/docs):

**Kimi Code CLI (Moonshot).**

- **Roles → skills, not agents.** Kimi has no custom sub-agent registry — the only
  sub-agents are the built-ins `coder` (full tools), `explore` (read-only), and
  `plan` (no shell), and `[subagent]` config exposes only a timeout. The 11 DVRR
  roles therefore ship as project skills in `.kimi-code/skills/<role>/SKILL.md`
  (generated from `.claude/agents/*.md`, bodies verbatim — same derivation rule as
  the Codex TOMLs). Frontmatter `name` + `description` are both mandatory (Kimi's
  parser refuses the skill otherwise). To get an isolated context, dispatch a
  sub-agent that applies the skill; **reviewer roles run on `explore`** — that is
  the only tool-enforced read-only available (a skill prompt cannot enforce it).
- **Routing collapses.** Kimi is a single-model-family harness (`k3`); skills carry
  no per-skill model/temperature/effort. The strong/weak split has no mechanism —
  the cheap/authoritative *separation of duties* survives as distinct skills +
  `explore`, but its economics do not. Recorded in the manual: prefer cross-harness
  `review-final` for control-class changes.
- **Kill-switch has no project-level home.** Kimi reads a single user-level
  `~/.kimi-code/config.toml`; there is no project config file, and permission rules
  and hooks are global-only. The deny-list (`[[permission.rules]]` with
  `Bash(git push --force*)`-style patterns) + Stop-hook telemetry ship as
  `.kimi-code/config-snippet.toml` with a one-time manual merge into the global
  config. Until merged the Kimi harness is **fail-open** — the inverse of Codex's
  trust gate, called out in the manual and the installer's next-steps. The global
  merge is acceptable because every deny-listed command is universally destructive.
- **Hooks fail open** (non-2 exit, timeout, crash ⇒ allow), so permission rules are
  the primary kill-switch and hooks carry only notification + telemetry. Hooks run
  in the session's project directory, so the repo-relative telemetry command no-ops
  outside forge repos.
- **`.agents/skills/` is shared.** Kimi reads the same cross-tool `~/.agents/skills/`
  and repo `.agents/skills/` directories as Codex, so `$commit`/`$worktree-merge`
  and the user-scope `forge-init` skill serve both harnesses from one copy
  (`/skill:<name>` or `/<name>` shorthand on Kimi).
- `.kimi-code/local.toml` (machine-local workspace settings) added to the installed
  `.gitignore` block, per Kimi's own docs.

**ZCode (Z.ai desktop ADE).**

- Desktop-only (no CLI/headless), GLM-5.2 fixed. It reads the repo's `AGENTS.md`
  natively (plus `~/.zcode/AGENTS.md`; CLAUDE.md is only migrated once at
  onboarding, not read) — so the forge instruction layer works with zero install.
- Everything else is user-level only: subagents (`~/.zcode/agents/`, Beta, no
  documented file format, no project scope), skills (`~/.zcode/skills/`), commands
  (`~/.zcode/commands/`). No permission/deny-list mechanism, no enforced read-only
  subagents, no hooks. Nothing for the installer to place beyond what `AGENTS.md`
  already provides.
- Decision: **advisory tier** — usable for exploration/design/implementation
  against the AGENTS.md contract; gate-chain commits happen from a CLI harness.
  Skills can be imported from `.agents/skills/` via Settings → Skills → Import
  (Symlink mode tracks the repo). Revisit if ZCode ships project-level agents (its
  docs mark this "not available yet").

Residual risks recorded: Kimi custom-agent support may land later (revisit the
skills mapping); the global-config merge is manual and unverifiable by the
installer (mitigated by `/forge-init` step 13 and a troubleshooting row); Kimi
hook fail-open semantics are upstream behaviour, not configurable.
