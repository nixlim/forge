# 05 — Conclusions & Recommendations for Our Work

**Context:** foundry_zero already carries a substantial agentic toolkit — `grill-spec` /
`grill-code` (adversarial review skills), `plan-spec`, `taskify` (+ taskify-agent),
`design-council`, `work` (multi-LLM quorum orchestrator), `skill-creator` (with evals),
plus native Claude Code worktree/Workflow/hooks. Several MockServer components are
conceptual siblings of ours (their `taskify-agent`, `design-council` command, review
agents). The question is not "build vs. not" but "which of their disciplines upgrade
what we already have."

## Conclusions

1. **The workload is implementable — proven, not argued.** The repo dual-runs the same
   system on Claude Code and opencode (doc 04). Nothing in it requires capabilities we
   lack; two of its admitted gaps (budget enforcement, mechanical gating) are actually
   stronger on Claude Code.
2. **The durable value is governance content, not orchestration plumbing.** Worktrees,
   subagents, and fan-out are commodity (native here). What compounds is: citable review
   principles, fail-closed gates, no-gaming rules, risk-scaled autonomy, and regression
   evals for prompts.
3. **Their single best architectural decision:** isolation between *sessions*, helper
   subagents *sharing* the primary's tree so reviewers see uncommitted diffs. Naive
   "worktree per subagent" designs silently break review. Claude Code's defaults already
   match this — preserve it; don't over-isolate.
4. **Their single best cultural practice: rules-as-postmortems.** Incidents (shared-tree
   data loss, integration-branch mess, TLS-proxy hangs, Buildkite log-scope trap) are
   folded into the rules with the *why* attached. The instruction system is a living
   knowledge base, versioned and reviewed like code.
5. **Their honest weakness:** nearly everything rests on agent compliance. They
   compensate with evals + telemetry + a config validator. We can do one better with
   hooks.

## Adopt (high value, low cost)

1. **Binary verdicts + citable principle IDs + iteration cap** → upgrade `grill-code` /
   `grill-spec`. PASS/BLOCK with no hedging; findings as
   `[ID] severity / location / evidence / recommendation`; a hard iteration cap (theirs: 8)
   after which the agent must record residual risk and escalate instead of converging by
   exhaustion; agents may not self-disposition findings above minor. IDs make findings
   greppable and let us aggregate which principles fire most — that feeds checklist
   evolution.
2. **Project-specific review triggers.** The generic 8 lenses matter less than the salt:
   *our* per-project failure-mode tables ("pattern X in a diff MUST trigger check Y")
   with IDs. Start each project's table from its actual bug history; grow it via the
   postmortem rule below.
3. **Control-integrity rule ("no gaming the gates").** Verbatim-portable. Ban
   pass-by-lowering-the-bar (deleting tests, loosening assertions, regenerating goldens,
   suppressing lint, routing to a weaker model to get an easier PASS); classify changes
   to rules/skills/agents/settings as a higher-scrutiny class needing separate review
   and explicit human approval. Directly relevant to us because our skills *are* our
   controls.
4. **Eval harness for skill/agent changes.** Golden tasks with committed expected
   verdicts; changing a prompt/skill/constitution must not flip a baseline. Integrate
   with `skill-creator`'s existing eval facility rather than building parallel
   machinery. Also run on model version changes ("a behavioural change, not a silent
   upgrade").
5. **Operator halt via hooks.** Sentinel file + check script, but enforced with a
   `PreToolUse` hook on `git commit|push` and other irreversible actions — mechanical,
   not honor-system. Cheap and valuable for long autonomous runs (`/loop`, schedules).
6. **Untrusted-input rule.** Their trust hierarchy + "quote as data, never obey,
   quarantine, escalate" procedure is the best compact write-up of prompt-injection
   discipline we've seen; adopt into our global rules.
7. **Decision-log-lite.** Full telemetry blocks are heavy, but two habits are cheap and
   compound: (a) commit messages as the durable why/what record; (b) for significant
   units, a short decision file recording model/effort rationale, assumptions, review
   iterations, and discarded approaches. Copy out of worktrees before cleanup (their
   gotcha — the trail dies with the tree, decision-log.md:43-47).

## Adapt (good ideas, adjust to our scale)

- **Gate chain.** classify → validate-per-category → adversarial review → re-verify →
  commit, fail-closed, with their "scale the ceremony to the task" table so trivia
  isn't ritualized. On Claude Code, enforce the load-bearing steps with hooks instead of
  prose where possible. Their autonomous push-to-master posture should be *earned* per
  project (their own "earned autonomy" concept) — start at gated-approval.
- **Worktree flow.** Prefer native `EnterWorktree` / `isolation: "worktree"` over
  hand-rolled scripts. Keep their semantics as rules: fresh worktree per independent
  session, never adopt another session's tree, local-only branches,
  rebase+fast-forward-only reintegration, re-verify after a rebase that pulled in other
  units' commits, never delete a worktree on a failed merge.
- **Locks.** Port `flock` rebase lock + PID commit lock **only when** we actually run
  multiple independent sessions against one repo. Single-session + Workflow-managed
  fan-out doesn't need them (Workflow serializes what it must).
- **Serialisation-cause telemetry.** The full taxonomy is over-engineered for us, but
  the question it encodes — *when work serialized, why?* — is the right lens for tuning
  any orchestration. Even ad-hoc notes ("waited on X because Y") beat cap-tweaking
  blind. Their principle: only cap-bound time argues for more parallelism; everything
  else argues for better decomposition.
- **Effort-tiered review lanes.** Their cheap/authoritative split (mid-model per-commit
  reviewer; top-model binding reviewer at merge) maps to effort tiers here: a
  low/medium-effort fast lane, escalating to high/max-effort binding review for risky or
  control-class changes. Reviewers read-only by tool policy, always distinct from the
  author agent.

## Skip (for now)

- **The 94 KB normative spec.** Right for a governed OSS project with releases and
  infra; for us the rules layer is the useful altitude. Revisit if forge becomes a
  product.
- **Full metrics program** (autonomy rate, routing fitness, monthly cadence, owners).
  Requires collection discipline we won't sustain; the eval suite + review-iteration
  counts give 80% of the signal.
- **Changelog gate, commit-lock ceremony, control-plane category tables** — MockServer
  release-engineering specifics.
- **≤10 hard cap as dogma.** Our harness caps and queues mechanically; state a policy
  cap only when cost or contention demands one.

## Sketch: phased adoption for forge

**Phase 1 — governance content (pure markdown, immediate):** write `forge`'s rule set:
review-verdict protocol (IDs, PASS/BLOCK, iteration cap), control-integrity,
untrusted-input, ceremony-scaling table. Retrofit `grill-code`/`grill-spec` to emit the
verdict protocol.

**Phase 2 — mechanical enforcement (hooks + scripts):** operator-halt sentinel + PreToolUse
hook; gate-marker check before `git commit` on designated repos; port `check-halt.sh`
and (if/when multi-session) the two lock scripts and `agent-status.sh`.

**Phase 3 — evals:** golden tasks for our top 3 skills (planted-bug-must-BLOCK,
clean-change-must-PASS, injection-must-flag), baselines committed, wired into a
control-change checklist via `skill-creator`.

**Phase 4 — orchestrated DVRR:** encode decompose → parallel implement (worktree-isolated
Workflow agents) → verify → adversarial review → locked reintegration as a Workflow
script/skill, with budget guards — the piece the studied system couldn't enforce and we
can.

## Open questions for discussion

1. How autonomous do we want reintegration? Their gates-replace-approval stance is
   coherent but assumes a mature gate chain and real test suites; most foundry_zero
   projects don't have MockServer-grade coverage — autonomy should follow verification
   strength (their own rule).
2. One shared constitution across `grill-*`, `work`, `design-council`, and future forge
   reviews, or per-skill? Their versioned baseline + per-artefact profiles suggests:
   one baseline, thin per-context profiles.
3. Do we want cross-session parallel development at all (multiple terminals, locks,
   dashboards), or is single-orchestrator + Workflow fan-out our steady state? The lock
   layer only pays for itself in the first case.
