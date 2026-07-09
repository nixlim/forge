# 02 — Worktree Orchestration: How Parallel Agents Share One Repo Safely

**Sources:** `.opencode/rules/worktree-workflow.md`, `.opencode/rules/commit-workflow.md`,
`.opencode/rules/commit-locking.md`, `.claude/commands/worktree.md`,
`.claude/commands/worktree-merge.md`, `.opencode/scripts/agent-status.sh` — all @ `7febd65f`.

## TL;DR

The isolation unit is the **session, not the subagent**. Independent sessions each create
a fresh worktree on a local-only branch and never touch the bare checkout; helper
subagents spawned *within* a session deliberately share its worktree so they can review
uncommitted work. Reintegration to `master` is rebase + fast-forward only (linear
history, no merge commits), serialized through a `flock` lock, and gated by a fail-closed
4-gate chain. A separate PID-stamped commit lock serializes the commit ritual itself.
Everything is observable via a per-worktree activity file and a status dashboard.

## The isolation model — the key design insight

Most naive multi-agent designs isolate *every subagent* in its own worktree. This system
explicitly rejects that:

> "Helper subagents are the one deliberate exception. A subagent spawned by a primary …
> **shares the primary's tree** and is *not* isolated — this is required for
> correctness, not convenience: helper subagents (reviewers, investigators) read the
> primary's **uncommitted in-flight diff**; a worktree branched off `origin/master`
> would see only committed state and miss the very changes they exist to analyse,
> silently breaking the commit gate chain. Isolation is **between independent sessions,
> not within one**." (worktree-workflow.md:46-53)

So the topology is:

```
main checkout (bare — no work ever runs here)
├── .worktrees/agent-20260528-141500-abc123   ← Session A (branch agent/…-abc123)
│     ├── implementer subagent   ┐
│     ├── review-final subagent  ├─ share Session A's tree
│     └── test-runner subagent   ┘
└── .worktrees/agent-20260528-141512-def456   ← Session B (independent window)
      └── … its own helper subagents
```

Complementary invariants:

- **No work in the bare checkout — even read-only.** "This holds even when the session
  makes no changes — read-only investigation, analysis, and review work in a worktree
  too" (worktree-workflow.md:9-12). Rationale: isolation is not contingent on intent to
  change; a "read-only" session that later drifts into editing is already safe.
- **One session, one worktree — never adopt another session's.** A pre-existing
  `.tmp/active-worktree` pointer is a *resume marker for the session that wrote it*, not
  an invitation. The rule embeds the incident that motivated it: "a shared tree silently
  dropped a committed, gate-passed unit that was only recovered from the reflog"
  (worktree-workflow.md:15-29). Ownership is proven by the per-session `SHORT_ID`
  embedded in the path/branch name.
- **Worktrees are near-free** (shared `.git` object store), so the isolation is never the
  ceremony that gets skipped — only the merge ceremony scales down for trivial changes
  (worktree-workflow.md:110).

## Session lifecycle

### 1. Create (`/worktree`, `.claude/commands/worktree.md`)

```bash
SHORT_ID="$(date +%Y%m%d-%H%M%S)-$(uuidgen | head -c 6)"
git fetch origin master --quiet
git worktree add --quiet -b "agent/${SHORT_ID}" ".worktrees/agent-${SHORT_ID}" origin/master
echo ".worktrees/agent-${SHORT_ID}" > .tmp/active-worktree   # resume marker
cd ".worktrees/agent-${SHORT_ID}"
```

Timestamp + UUID fragment guarantees collision-free names across concurrent sessions
(worktree-workflow.md:129-141).

### 2. Work

All edits, builds, tests, and incremental commits happen on the worktree branch. The
session advertises what it's doing by overwriting a one-line file:

```bash
echo "Running mvn verify on mockserver-netty" > .tmp/agent-activity
```

Deliberately schema-free: "a single line, free text, overwritten on each update. No
state schema, no JSON" (worktree-workflow.md:158-169). This feeds the dashboard below.

### 3. Merge back (`/worktree-merge`) — the 4-gate chain

All gates are fail-closed; "any failure stops the merge and leaves the worktree intact
for inspection" (worktree-workflow.md:173-174).

| Gate | What | Detail |
|------|------|--------|
| 1 — Tests | targeted tests for touched modules **plus the core suite always** ("the blast-radius gate") | changed modules derived from `git diff --name-only origin/master...` (worktree-workflow.md:176-187) |
| 2 — Lint | checkstyle / `npm run lint` / strict tsc per touched stack | worktree-workflow.md:189-192 |
| 3 — Adversarial review | spawn `review-final` on `git diff origin/master...HEAD`; binary PASS/BLOCK | worktree-workflow.md:194-203 |
| 4 — Summary & proceed | show diff stat + gate results, then **proceed automatically** — "gates 1–3 … are the authority to merge — they replace human pre-approval" | fail-closed if any gate wasn't a clean PASS; a user can interject at any time (worktree-workflow.md:205-212) |

### 4. Atomic reintegration under `flock`

```bash
.opencode/scripts/check-halt.sh || exit 1          # operator kill-switch first
flock --timeout 300 .git/agent-rebase.lock bash -c '
    set -euo pipefail
    git fetch origin master --quiet
    git rebase origin/master        # rebase, never merge
    git push origin HEAD:master     # always a fast-forward after the rebase
'
```

(worktree-workflow.md:216-232; an `mkdir`-based mutex fallback is given for systems
without `flock`, :243-254.)

**Linear history is a hard rule.** Forbidden: `git merge` into master (incl. `--no-ff`),
non-rebasing `git pull`, and intermediate "integration branches" merged from several
worktrees — a pattern they used, got burned by, and retired (worktree-workflow.md:55-77).
Rebasing local-only, never-pushed branches is what makes history rewriting safe here.
When several worktrees finish together they rebase **one at a time under the lock**, each
onto the previous result.

**Post-integration re-verification.** If the rebase pulled in other units' commits, Gate
1 re-runs against the integrated tip before cleanup — "defects can emerge from the
*combination* even when each unit passed in isolation" (worktree-workflow.md:238-241).
This is the classic semantic-merge-conflict defence, encoded as a rule.

### 5. Cleanup — only after a successful push

Worktree removed, branch deleted, resume marker cleared. "The invariant: **no failed
merge ever destroys work**. The worktree is deleted only after a successful push"
(worktree-workflow.md:304-305).

## The second lock: commit serialization

Independent of the rebase lock, the commit *ritual* (status → stage explicit paths →
commit) is serialized with `.tmp/.commit-lock`, a `PID TIMESTAMP` file with:

- stale detection: lock whose PID is dead is auto-removed (commit-locking.md:136-149);
- 5-minute poll-wait with actionable timeout messaging (commit-locking.md:54-63);
- ownership check on release — a session refuses to release another PID's lock
  (commit-locking.md:69-90);
- an acquire-and-always-release bash pattern (commit-locking.md:96-116);
- `OPENCODE_SESSION_PID=$$` exported so subshells lock as the parent session
  (commit-locking.md:117-119).

The design-rationale section (commit-locking.md:266-304) is a model of decision
documentation: why not git's own locks (too fine-grained — they don't stop one session
staging another's files), why not Redis/DynamoDB (filesystem matches problem scope,
fails safe via `ps`), why 5 minutes, why PID+timestamp.

**Scope discipline:** the lock is acquired only *after* validation and review pass, right
before staging — "Never hold the lock during validation or review as this blocks other
sessions unnecessarily" (commit-workflow.md:17).

Companion hygiene rules for shared-repo safety (commit-workflow.md:28-34): stage explicit
paths only (never `git add .`), re-read files before editing, commit only this session's
files, `git pull --rebase` before push.

## Beyond the filesystem

Worktrees only isolate files. The rules extend the same discipline to shared mutable
state outside the tree — databases, cloud infra, CI, registries: **partition** per
session, **lock/serialise** mutations (Terraform's DynamoDB state lock is cited as the
same pattern), or target dedicated non-prod instances; contention risk feeds the dynamic
concurrency limit (worktree-workflow.md:84-99).

## Observability

- `/agent-status` renders a table per active worktree: ID, branch, age, current activity
  (from `.tmp/agent-activity`, truncated to 32 chars), commits ahead of master, and
  whether it appears to hold the rebase lock (`agent-status.sh:1-111`).
- As a side effect, every invocation appends a `timestamp,active_worktree_count,lock_held`
  sample to `.tmp/parallelism-samples.csv` — concurrency-over-time telemetry riding on a
  command people run anyway (`agent-status.sh:113-126`).
- Lock waits and rebase-conflict time are recorded per unit as
  `serialisation.merge_lock_s` / `serialisation.contention_s` in the decision-log
  telemetry block, so "the dominant reason parallelism is lost can be ranked"
  (worktree-workflow.md:277-282; see doc 03).

## Failure-mode table (worktree-workflow.md:292-302)

Every failure leaves the worktree intact: test/lint failure blocks the rebase; a review
BLOCK preserves the tree and hands the verdict to the user; a `flock` timeout names the
holder; a rebase conflict is resolved in-tree or handed back. The one destructive
scenario — two sessions in one tree — is documented with its recovery procedure
(`git reflog` → re-`cherry-pick` → re-verify) and its prevention rule.

## Assessment

Strengths: the session-vs-subagent isolation split is exactly right (reviewers must see
dirty state); linear history + local-only branches makes rebase safe by construction;
locks are boring POSIX primitives with stale-detection; every failure mode is enumerated
with a preservation guarantee; real incidents are folded back into the rules.

Weaknesses: enforcement is instruction-level — nothing *mechanically* stops an agent
from committing without the lock or merging without gates (they compensate with evals
and telemetry; a hook-capable harness can do better — see doc 04). Gate 1's module
selection is path-regex-based and the rule itself flags smarter dependency-graph
selection as future work (worktree-workflow.md:325-334).
