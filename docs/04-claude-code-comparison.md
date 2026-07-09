# 04 — What Claude Code Already Does For Free vs. What Must Be Built

**Comparison basis:** the MockServer system @ `7febd65f` vs. Claude Code as of this
research (July 2026 harness: Agent tool, Workflow tool, worktree isolation, hooks,
custom agents/skills/commands). Feature names below refer to current Claude Code; verify
availability in your target install before relying on any single one.

## TL;DR

The proof that this workload is implementable on Claude Code is in the studied repo
itself: it **dual-targets Claude Code and opencode from one rule set**, with `.claude/`
agents, commands, settings, and hooks already present. Claude Code natively covers the
*mechanics* — subagents with per-agent model/effort/tool routing, worktree isolation as
a first-class option, deterministic multi-agent orchestration, token budgets, and hooks
that can make gates *mechanical* rather than instruction-based (an upgrade over what the
repo can do on opencode). What Claude Code does **not** ship is the *content*: the
review constitution, gate-chain definition, risk classes, control-integrity policy,
eval suite, and cross-session coordination (locks) — all of which are portable markdown
and bash.

## A. Free in Claude Code (native equivalents)

| MockServer mechanism | Claude Code native equivalent | Notes |
|---|---|---|
| Subagent registry with per-agent model + temperature (`opencode.jsonc:60-172`) | `.claude/agents/*.md` frontmatter: `model`, `effort`, `tools`; Agent tool `model`/`effort` overrides; Workflow `agent()` opts | Temperature is not exposed; **reasoning effort is the sanctioned analog** — the repo itself documents this mapping (multi-pass-temperature.md:26-30) and sets `effort:` on every `.claude/agents/` file. |
| Hand-rolled `/worktree` (bash: `git worktree add` + branch + pointer file) | **`EnterWorktree`/`ExitWorktree` tools** for the session; **`isolation: "worktree"`** on the Agent tool and on Workflow `agent()` calls (auto-created, auto-removed if unchanged) | Native isolation covers creation/cleanup. The repo's extra semantics (local-only branch discipline, resume pointer, ownership rule) remain convention. |
| Helper subagents share the primary's tree (worktree-workflow.md:46-53) | **Default Agent-tool behaviour** — subagents run in the caller's working directory unless `isolation` is requested | Exact match. Claude Code's default is precisely the repo's "deliberate exception," including the reviewer-sees-uncommitted-diff property. |
| DVRR "heavy path" — large fan-outs, decompose→verify→review→reintegrate (operating-model.md:184-189) | **Workflow tool**: `pipeline()`/`parallel()`, phases, JSON-schema-validated structured output, per-agent model/effort/isolation, journal + resume | The repo explicitly frames the Workflow tool as "the heavier, opt-in expression of the same model." Adversarial-verify and judge-panel patterns are documented first-class Workflow idioms. |
| Budget/liveness as unenforced convention — "framework-limited today: opencode does not yet expose a token/step-accounting API" (operating-model.md:96-100) | **Workflow `budget` object** — `budget.total/spent()/remaining()`, hard ceiling (agent() throws past it); 1000-agent backstop; concurrency caps | **Claude Code is ahead here.** The repo's admitted biggest enforcement gap is a solved problem on this harness, at least within a Workflow run. |
| Parallelism hard cap ≤10, queue don't exceed (operating-model.md:61-75) | Workflow cap `min(16, cores−2)` with automatic queueing; Agent-tool fan-outs are explicit and countable | Built-in queueing beats "please don't exceed 10." A policy cap below the mechanical cap still needs stating in instructions. |
| `/agent-status` dashboard + `.tmp/agent-activity` (agent-status.sh) | Background task tracking, task notifications, `/workflows` live progress, `SendMessage` to running agents | Covers *intra-session* visibility. **Cross-session** visibility (independent terminals) is not native — the repo's file-based convention still earns its keep there. |
| Permission policy: allow `Bash(*)`, deny `git push --force*`, `git reset --hard*`, `rm -rf /` variants (opencode.jsonc:37-51) | `settings.json` `permissions.allow/deny` — the repo's `.claude/settings.json:2-18` already does this verbatim | Identical mechanism, zero porting effort. |
| Telemetry aggregation after each turn | **Hooks** — the repo's `.claude/settings.json:19-34` registers a `Stop` hook running `aggregate-telemetry.sh` | Already implemented on the Claude side of the repo. |
| Structured escalation ("Clarify Well, Rarely", operating-model.md:157-168) | **`AskUserQuestion` tool** — the rule references it by name | Direct match: recommended-option-first, impact-stated questions. |
| Slash commands `/worktree`, `/worktree-merge`, `/commit` | `.claude/commands/*.md` — already present in the repo | Same mechanism. |
| Session-start setup (worktree by default) | **`SessionStart` hooks** can inject context or run setup | The repo relies on the agent remembering to `/worktree`; a hook can automate or at least prompt it. |
| Long autonomous runs (`/loop`, schedules) | `/loop`, scheduled agents, background Bash, `Monitor` | Parity or better. |
| Review machinery | `/code-review` (multi-agent, adversarial verify, `ReportFindings`), `/security-review`, custom read-only reviewer agents (tool-restricted frontmatter) | The repo's `review-final` least-privilege pattern (read-only tools) is expressible directly in agent frontmatter. |
| Context preservation for the orchestrator | Subagent architecture + auto-compaction | Same motivation; free. |

## B. Not free — must be built (and how the repo does it)

1. **Cross-session mutual exclusion.** Nothing in any harness coordinates two independent
   Claude Code processes on one repo. The repo's answer — `flock` rebase lock
   (worktree-workflow.md:216-232) and PID-stamped commit lock with stale detection
   (commit-locking.md) — is the right shape: boring POSIX, fails safe, zero
   dependencies. Port as-is if we ever run multiple independent sessions against one
   repo.
2. **The governance content.** Review constitution + per-artefact profiles, gate-chain
   definition, risk/authority classes, control-integrity, untrusted-input, decision-log
   format. All markdown; all portable; none shipped by any harness. This is the bulk of
   the system's value and the bulk of the porting work (mostly editing for our domain).
3. **Eval harness for prompt/agent changes.** No harness ships golden-task regression
   for *your* agent definitions. The repo's `run-evals.sh` + fixtures + committed
   `.result` baselines is ~simple bash. (Note: our `skill-creator` skill already has an
   eval/benchmark facility — a natural integration point.)
4. **Fail-closed gate *enforcement*.** On opencode the gate chain is purely
   instruction-based. Claude Code **hooks can make it mechanical**: a `PreToolUse` hook
   matching `git commit`/`git push` can run `check-halt.sh`, verify lock ownership, or
   require a gate-passed marker file, and hard-block otherwise. This would be an
   *improvement over the studied system*, closing its "relies on agent compliance"
   weakness (docs 02–03).
5. **Per-subagent temperature.** Not exposed on Claude Code. Use effort tiers +
   explore/refine/validate staging via prompts (the repo's documented fallback).
6. **Cross-session dashboard.** `/agent-status` equivalent — port the script verbatim;
   it's plain git + filesystem.
7. **Telemetry discipline.** The decision-log telemetry block is convention; agents
   forget. Hooks (Stop/PostToolUse) can capture some of it mechanically; the rest stays
   best-effort ("omit, don't guess").

## C. Verdict: can this workload be implemented?

**Yes — demonstrably.** The studied repo already runs it on Claude Code: same agents
(`.claude/agents/`, with `model`/`effort`/`tools` frontmatter), same commands, same
locks, a Stop-hook for telemetry, and permission denies mirroring opencode's. The
mapping is:

```
/worktree                    → EnterWorktree (or keep the command for its branch/pointer semantics)
helper subagents share tree  → Agent tool default (no isolation)
isolated parallel implementers→ Agent/Workflow with isolation: "worktree"
big fan-outs w/ verification → Workflow tool (pipeline + adversarial verify + budget)
review-cheap / review-final  → custom agents, tool-restricted, effort-tiered
gate chain                   → command/skill + PreToolUse hooks for hard enforcement
operator halt                → sentinel files + check script, callable from hooks
commit/rebase locks          → port scripts verbatim (only needed for multi-session use)
evals for prompts            → port run-evals.sh; wire into the control-change gate
```

Two places Claude Code is *ahead* of the studied system: **enforced token budgets**
(Workflow `budget` vs. their unenforced OP5 convention) and **hook-based mechanical
gating** (vs. their instruction-only fail-closed rule). One place it is behind:
**per-subagent temperature** (use effort). Cross-session coordination is a tie — neither
harness provides it; filesystem locks are the answer on both.
