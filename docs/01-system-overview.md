# 01 — System Overview: The MockServer AI-SDLC Instruction System

**Repo:** `mock-server/mockserver-monorepo` @ `7febd65f` (2026-07-06)

## TL;DR

The system is a three-layer architecture: a **normative spec** (94 KB,
RFC-2119 MUST/SHOULD language) → **17 rule files** that implement it → **12 agent
definitions + commands + scripts** that execute it. It dual-targets two harnesses
(opencode and Claude Code) from the same rule set. The operating model, DVRR, makes the
main agent an orchestrator whose default is to delegate everything to model-routed
subagents, run them in parallel (hard cap 10), verify and adversarially review every
unit, and reintegrate autonomously onto a linear `master` once a fail-closed gate chain
passes.

## Layered architecture

```
docs/operations/ai-sdlc-integration-spec.md     ← authoritative spec (§1–§22, MUST/SHOULD)
        │  "the .opencode/rules/ implement it"      (AGENTS.md:73)
        ▼
.opencode/rules/*.md        ← 17 rules; each phase of the model "points at the rule
        │                      that owns the detail" (operating-model.md:21-22)
        ▼
AGENTS.md                   ← orchestrator-facing digest + routing table (AGENTS.md:307-326)
.opencode/agents/*.md       ← 12 subagent prompts (shared text)
opencode.jsonc              ← opencode: per-agent model + temperature + tool limits
.claude/agents/*.md         ← Claude Code: same agents, model + effort frontmatter
.claude/commands/*.md       ← /worktree, /worktree-merge, /agent-status, /commit, …
.opencode/scripts/*.sh      ← locks, halt check, status dashboard, telemetry aggregator
.opencode/evals/            ← golden-task regression suite for the AI components
```

Instruction priority is explicit: user > `.opencode/rules/` > `AGENTS.md` > skills
(`AGENTS.md:3-8`). Rules cross-reference each other with `[[wiki-links]]`, and each rule
opens by citing the spec section it conforms to — the spec is treated as the single
source of truth, the rules as its implementation.

## The DVRR operating model

Source: `.opencode/rules/operating-model.md` (the "spine" rule).

> "The main agent's primary job is to orchestrate subagents, not to execute … because
> that is where the right **model, temperature, and reasoning effort** are chosen for
> each task (the primary lever for inference cost and determinism) and where the
> orchestrator's context is preserved." (operating-model.md:6-11)

Phases, each owned by a dedicated rule (operating-model.md:50-59):

| Phase | Meaning | Owning rule/tool |
|-------|---------|-------------------|
| Decompose | smallest units implementable/verifiable/reviewable/committable independently | `taskify-agent` |
| Delegate | orchestrator hands "overwhelming majority" of work to subagents, in parallel | `subagent-routing` |
| Isolate | no work in the bare checkout; per-*session* worktrees | `worktree-workflow` |
| Verify | tests, build, lint, static analysis, dry-runs — "if it can be safely verified, verify it" | `testing-policy`, `commit-workflow` |
| Review | adversarial review on fresh context / different model, 8-lens constitution, ≤8 iterations | `review-constitution` |
| Re-verify | any review-driven fix re-triggers verification ("fixes regress") | `commit-workflow` |
| Commit | one coherent unit → one commit | `commit-workflow` |
| Reintegrate | rebase onto `master` + fast-forward push under a `flock` lock; never a merge commit | `worktree-workflow` |

Three properties make it more than a checklist:

1. **Autonomy with a machine gate.** "The gate chain is the authority to ship — not a
   human prompt." Once classify → validate → changelog → adversarial-review-PASS →
   re-verify passes, the agent commits and pushes to `master` **without asking**
   (operating-model.md:104-113). The gates are "mandatory and fail-closed": any gate that
   can't run or doesn't return a clean PASS blocks the commit
   (operating-model.md:123-127).
2. **Bounded parallelism.** Hard caps: ≤10 active subagents, ≤10-way parallelism; queue
   or defer rather than exceed, and record the effective limit and its rationale when
   running below cap (operating-model.md:61-75).
3. **Ceremony scales with risk.** Full DVRR for substantial work; a lightweight path for
   small changes; direct edit for trivia — but the worktree itself is *never* skipped,
   only the merge ceremony scales ("the worktree … is near-free"; the table at
   operating-model.md:144-148). Explicit anti-bloat guidance: "Never manufacture ceremony
   that adds no safety" (operating-model.md:152-155).

## Model / temperature / effort routing

Routing is configuration, not prose: "Routing policy must live in routing configuration,
not in skill descriptions" (subagent-routing.md:3). The per-agent settings in
`opencode.jsonc:60-172` are described as "the primary inference-cost lever":

| Agent | Model (opencode) | Temp | Role |
|-------|------------------|------|------|
| `test-runner` | gpt-4o-mini | 0.0 | mechanical test execution, read-only |
| `code-reviewer` | gpt-4o | 0.1 | quick pre-commit check, read-only |
| `review-cheap` | gpt-4o | 0.1 | intermediate deep review — non-authoritative PASS |
| `review-final` | gpt-5 | 0.1 | **binding PASS/BLOCK verdict**, read-only |
| `security-auditor` | gpt-5 | 0.1 | security audit, read-only |
| `implementer` | gpt-5 | 0.2 | writes production code + tests |
| `debugger` / `pipeline-investigator` | gpt-5 | 0.2 | investigation |
| `taskify-agent` | gpt-4o | 0.3 | decomposition |
| `docs-writer` | gpt-4o | 0.4 | technical writing |
| `council-seat` | gpt-4o-mini | 0.7 | divergent design-debate seat, no tools |

Two patterns worth noting:

- **A cheap/authoritative review split.** `review-cheap` (mid-tier model) is the
  per-commit gate; `review-final` (top-tier model) is escalated to for merge-to-master
  and for any change to the control system itself (commit-workflow.md:170).
- **Descending-temperature pipeline.** For exploratory work: explore at high temp →
  refine at low → validate at very low; a high-temperature stage "MUST NOT emit the final
  output directly" (multi-pass-temperature.md:14-19). Where per-subagent temperature is
  unavailable — i.e. on Claude Code — "**reasoning effort plays the analogous
  determinism/quality role**… it is set explicitly on every `.claude/agents/` definition"
  (multi-pass-temperature.md:26-30). And indeed `.claude/agents/implementer.md:4-5`
  carries `model: claude-opus-4-8` / `effort: high` frontmatter.

## Dual-harness targeting

The same system runs on both harnesses:

- `.opencode/agents/*.md` and `.claude/agents/*.md` contain the same 12 agents; the
  opencode side gets model/temperature from `opencode.jsonc`, the Claude side embeds
  `model:`/`effort:`/`tools:` frontmatter (e.g. `.claude/agents/review-final.md:1-11`
  restricts to Read/Bash/Glob/Grep/LS — reviewer least-privilege).
- `.claude/settings.json` mirrors `opencode.jsonc` permissions: `Bash(*)` allowed, with
  targeted denies for `git push --force*`, `git reset --hard*`, `git clean -fd*`,
  `rm -rf /` variants (settings.json:2-18 vs opencode.jsonc:37-51).
- `.claude/settings.json:19-34` registers a **Stop hook** that fires the telemetry
  aggregator after every turn — governance wired into the harness, not just prose.
- Slash commands are thin pointers into the rules ("Follow the worktree workflow in
  `.opencode/rules/worktree-workflow.md`. This command does **Step 1** of that flow" —
  `.claude/commands/worktree.md:4`), so there is exactly one source of truth per
  behaviour.

## Supporting cast (detailed in docs 02–03)

- **Worktree isolation + locked reintegration** — doc 02.
- **Review constitution** (8 lenses, ~100 citable principle IDs, per-artefact profiles,
  binary PASS/BLOCK) — doc 03.
- **Risk/authority classes** (act-autonomously / gated-approval / advisory / reserved)
  and **control integrity** (no gaming gates; control changes need human approval +
  evals) — doc 03.
- **Operator halt** — sentinel-file kill-switch checked before commits/merges — doc 03.
- **Untrusted-input rule** — prompt-injection resistance with a trust hierarchy — doc 03.
- **Decision log + telemetry + metrics** — machine-readable per-unit telemetry blocks,
  aggregated by script; serialisation causes ranked to target decomposition improvements
  — doc 03.

## Honest self-assessment (a practice in itself)

The rules record their own enforcement gaps instead of pretending: budget/liveness
enforcement "is **framework-limited today**: opencode does not yet expose a token/step
accounting API the orchestrator could trip on automatically. Until it does, the
*control* is this convention plus recording budget/liveness outcomes in the decision-log"
(operating-model.md:96-100; echoed in metrics.md:126-129). Rules also embed real
post-mortems — e.g. the shared-worktree data-loss incident ("this has actually happened…
only recovered from the reflog", worktree-workflow.md:20-24) and a retired
integration-branch anti-pattern (worktree-workflow.md:71-76). **Rules-as-postmortems**
is one of the strongest engineering practices in the repo.
