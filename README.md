# Forge — replicable AI-SDLC agent operating system

A vendored, installable copy of the MockServer AI-SDLC system (DVRR: Decompose · Verify
· Review · Reintegrate) — per-session git-worktree isolation, a fail-closed commit/merge
gate chain, adversarial review with a binding constitution, risk-scaled autonomy,
operator kill-switch, and a golden-task eval harness for the AI components themselves.

**Operating manual: [OPERATING-MANUAL.md](OPERATING-MANUAL.md)** — install flow, daily
workflows with diagrams, review system, safety rails, troubleshooting.

Research and decision record: [docs/](docs/) (start with `docs/README.md`; the adoption
decision and installer design are in `docs/06-discussion-outcome.md`).
Upstream provenance and deliberate deviations: [system/UPSTREAM](system/UPSTREAM)
(Apache-2.0, `mock-server/mockserver-monorepo`).

## Install into a repo

From the target repository root:

```
/forge-init          # in Claude Code — full install + per-project initialization
```

or mechanically only (leaves gates fail-closed until init):

```bash
/Users/nixlim/Sync/PROJECTS/foundry_zero/forge/bin/forge-install.sh \
    [--project-name NAME] [--branch BRANCH] [--target DIR]
```

`/forge-init` = `forge-install.sh` (copy + token/branch substitution + `.gitignore` +
manifest) **plus** the judgment layer: stack detection → validation tables, Gate-1 test
command + blast-radius suite, project review triggers, `AGENTS.md` project sections,
agent/skill project context, eval fixtures + baselines — finishing with the system's own
gate chain on the install diff (control-class change: `review-final` + evals + explicit
human approval; never auto-committed).

## Layout

| Path | What |
|------|------|
| `system/engine/` | Tier-1 payload — byte-close to upstream for diffable syncs |
| `system/template/` | Tier-2 payload — upstream files with `{{FORGE_*}}` tokens and `<!-- FORGE:REGION ... -->` blocks that `/forge-init` fills (defaults fail closed) |
| `system/seeds/` | Tier-3 source material — eval-task templates, per-stack validation snippets, brownfield exploration protocol |
| `system/UPSTREAM` | provenance manifest: upstream commit, deviations, sync procedure |
| `system/LICENSE-upstream` | Apache-2.0 license of the upstream repo |
| `bin/forge-install.sh` | mechanical installer (idempotent) |
| `docs/` | research bundle + decision records |

The canonical `/forge-init` command is versioned at `commands/forge-init.md`; install it
to user scope on each machine so it works in any repo:

- Claude Code: `cp commands/forge-init.md ~/.claude/commands/forge-init.md`
- Codex: `cp -R skills/forge-init ~/.agents/skills/` — Codex deprecated custom
  prompts in favour of skills; invoke as `$forge-init` (list with `/skills`).

(Both load at session startup — restart the session after copying. The skill body is
generated from `commands/forge-init.md`; keep the two in sync.)

## Model routing (decision, 2026-07-09)

| Harness | Strong (implementer, review-final, security-auditor, debugger) | Weak (everything else) |
|---------|---------------------------------------------------------------|------------------------|
| opencode | `zai/glm-5.2` | `minimax/MiniMax-M3` |
| Claude Code | `fable` | `opus` |
| Codex | `gpt-5` | `gpt-4o` / `gpt-4o-mini` (upstream kept) |

Per-agent temperatures (opencode) and reasoning efforts (Claude) are kept verbatim from
upstream. Codex is a first-class third harness (forge-original, no upstream counterpart):
per-agent model/effort in `.codex/agents/*.toml`, kill-switch deny-list as execpolicy
rules in `.codex/rules/forge.rules`, Stop-hook telemetry in `.codex/hooks.json`, and
`/commit` + `/worktree-merge` as skills in `.agents/skills/` (invoke as `$commit` /
`$worktree-merge`, or Codex picks them implicitly from their descriptions). Codex loads
a repo's `.codex/` layer only after the operator trusts the repo (fail-closed until
then); skills in `.agents/skills/` are outside that trust gate.
Changing routing after install is a control-class change inside the installed
system (evals + `review-final` + human approval).

## Syncing with upstream

`system/engine/` is kept byte-identical to upstream wherever possible; deliberate edits
carry a `forge: modified from upstream` marker. To sync: clone upstream, `diff -r`
against `engine/` (path-mapped), review hunks, pull what applies, bump the hash in
`system/UPSTREAM`.
