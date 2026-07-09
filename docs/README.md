# Forge Research: Multi-Subagent Orchestration with Git Worktrees

**Subject:** the coding-agent instruction system in
[`mock-server/mockserver-monorepo`](https://github.com/mock-server/mockserver-monorepo)
(`.opencode/`, `.claude/`, `AGENTS.md`, `docs/operations/ai-sdlc-integration-spec.md`).

**Evidence baseline:** repository cloned at commit `7febd65f0815caf57855fae54ba3df3915376cc6`
(2026-07-06). All file/line citations in this bundle refer to that commit. GitHub links use
`master` and may drift; the hash-pinned citations are authoritative.

## TL;DR

MockServer runs an **autonomous, parallel-first AI development system** they call
**DVRR** (Decompose · Verify · Review · Reintegrate). Its defining moves:

1. **The orchestrator delegates almost everything.** The main agent's job is routing —
   each subagent carries an explicit model / temperature / reasoning-effort choice, which
   is treated as the primary lever for inference cost and determinism.
2. **Worktree isolation is between *sessions*, not within one.** Every independent
   session (interactive window, autonomous run) gets a fresh git worktree on a local-only
   branch — even for read-only work. But helper subagents *share* their parent's worktree,
   deliberately, so reviewers can see uncommitted in-flight diffs.
3. **Machines gate, humans set policy.** A fail-closed gate chain (tests → lint →
   adversarial review → re-verify) *replaces* human pre-approval for normal changes; the
   agent commits and pushes to `master` autonomously once it passes. Changes to the
   controls themselves (prompts, rules, gates) are a higher-scrutiny class that always
   requires human approval plus a regression eval suite for the AI components.
4. **Concurrency is coordinated with boring, reliable primitives:** `flock` on a rebase
   lock for linear fast-forward-only merges to `master`, a PID-stamped commit lock file,
   sentinel files for an operator kill-switch, and a one-line activity file per worktree
   feeding an `/agent-status` dashboard.
5. **The system measures itself.** Decision logs with machine-readable telemetry blocks,
   serialisation-cause taxonomies, and golden-task evals that must pass before any prompt
   or rule change ships.

**Bottom line for us:** the *workload is implementable* on Claude Code — the repo itself
dual-targets Claude Code and opencode from the same rule set — and Claude Code provides
several of the hardest pieces natively (worktree isolation, deterministic orchestration,
token budgets, hooks for mechanical enforcement). What Claude Code does **not** provide,
and what is genuinely worth stealing, is the **governance content**: the review
constitution with citable principle IDs, the fail-closed gate chain, the
control-integrity ("no gaming the gates") rule, risk-based autonomy classes, and evals
for prompt changes. Details and a phased adoption plan are in docs 04 and 05.

## Bundle contents

| Doc | Contents |
|-----|----------|
| [01-system-overview.md](01-system-overview.md) | What the system is: spec → rules → agents architecture, the DVRR operating model, model/temperature routing, evidence map |
| [02-worktree-orchestration.md](02-worktree-orchestration.md) | Deep dive: per-session worktrees, the helper-subagent exception, the 4-gate merge chain, flock rebase lock, commit lock, failure modes, observability |
| [03-quality-and-governance.md](03-quality-and-governance.md) | The adversarial review constitution, iteration protocol, risk/authority classes, control integrity, operator halt, untrusted input, evaluation harness, telemetry |
| [04-claude-code-comparison.md](04-claude-code-comparison.md) | What Claude Code already does for free, what must be built, and where Claude Code is ahead of the studied system |
| [05-recommendations.md](05-recommendations.md) | What to adopt for our work, what to adapt, what to skip; feasibility verdict and a phased implementation sketch |
| [06-discussion-outcome.md](06-discussion-outcome.md) | **Decision record:** wholesale adoption of the system + one-command installer design (supersedes doc 05's selective stance) |

## Method

Shallow clone of the repo; full read of `.opencode/rules/` (17 rules, ~208 KB total with
agents/scripts), `.opencode/agents/` + `.claude/agents/` definitions, `.claude/commands/`
(`/worktree`, `/worktree-merge`, `/agent-status`), coordination scripts
(`acquire-commit-lock.sh`, `agent-status.sh`, `check-halt.sh`,
`aggregate-telemetry.sh`), `opencode.jsonc`, `.claude/settings.json`, root `AGENTS.md`,
and the heading structure of the 94 KB normative spec
`docs/operations/ai-sdlc-integration-spec.md`. Findings below cite specific files and
line ranges.
