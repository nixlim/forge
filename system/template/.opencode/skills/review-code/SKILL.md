---
name: review-code
description: >
  Deep adversarial code review using the 8-lens review constitution. Examines
  diffs for correctness, security, completeness, and project-specific concerns.
  Use when performing pre-commit reviews, quality-loop iterations, or on-demand
  code audits. Loaded by review-cheap and review-final agents.

---

# Adversarial Code Review

You are performing a deep adversarial review of code changes. Your job is to find
defects, not to reassure the author. The code is wrong until proven right.

## Step 1: Load the Review Constitution

Read `.opencode/rules/review-constitution.md` in full. This is the 8-lens
framework you MUST apply. Do not skip any lens.

## Step 2: Gather the Diff

If you have not already been given the diff, obtain it:

```bash
git diff --cached                              # staged changes
git diff                                       # unstaged changes
git ls-files --others --exclude-standard       # untracked new files
```

Read all three. The union of staged changes, unstaged changes, and untracked
files is the review scope. For untracked files, read their full contents.

## Step 3: Read Surrounding Context

For every changed file, read enough surrounding context (imports, class
declaration, neighbouring methods) to understand:

- What frameworks and libraries are in use
- What conventions the file follows
- Whether referenced methods/types actually exist (COR-07 hallucination check)

## Step 4: Apply All 8 Lenses

Work through each lens from the constitution. For each lens:

1. List the principles that are applicable to this change
2. Evaluate the code against each applicable principle
3. Record any violations as findings using the constitution's finding format
4. If a lens is not applicable, state why (e.g., "Lens 4 (Infeasibility): N/A — no dependency changes or language-version concerns")

### Lens Priority for Code Reviews

Focus effort on these high-impact areas:

**Incorrectness (Lens 7) — highest priority:**
- Logic errors, off-by-one, null dereferences (COR-02)
- Hallucinated function/method names (COR-07)
- Race conditions in concurrent code (COR-06)
- Module boundary violations (COR-08)

**Insecurity (Lens 5):**
- Secrets in logs, URLs, or error messages (SEC-06)
- Input validation on control plane / privileged endpoints (SEC-05, SEC-11)
- Template injection prevention (SEC-12)
- Authentication/authorization enforcement (SEC-01, SEC-02)

**Incompleteness (Lens 2):**
- Missing error handling for external calls (INC-01)
- Missing timeout values for blocking operations (INC-07)

**Infeasibility (Lens 4):**
- Module dependencies respect architecture (COR-08)

**Overcomplexity (Lens 8):**
- Unnecessary abstractions (CPX-01)
- Premature abstraction for hypothetical future needs (CPX-01, CPX-04)
- Optimizations without measured bottlenecks (CPX-10)

Project-specific review focus — resource lifecycle, framework-level invariants,
compatibility/version policies, consumer-doc and client-library mirroring — is
defined in the project context region below (Step 5). Apply those principles
with the same priority as the generic ones above.

<!-- forge: removed upstream MockServer-specific Lens Priority bullets (Netty ByteBuf leak COR-10, ring buffer power-of-two COR-11, javax/jakarta compatibility FEA-06, consumer-docs/client-library mirroring INC-11/OPS-09/CON-08); relocated to the skill-project-context region in Step 5 -->

## Step 5: Project-Specific Review Focus

<!-- FORGE:REGION skill-project-context BEGIN -->

Apply deep inspection to the review focus areas and code patterns that matter
most for this project. When any of these patterns appear in the diff, perform
the corresponding deep checks.

| Pattern | Required Checks |
|---------|----------------|
| _(none configured yet)_ | _(none configured yet)_ |

<!-- forge-init: Replace this region with the project's architecture-doc
references, review focus areas, and high-risk code patterns. Follow the shape of
the upstream trigger table — one `Pattern | Required Checks` row per project-
specific concern, e.g.: resource lifecycle / leak balance (allocate vs free in
error paths); framework pipeline or handler ordering; configuration-property
defaults plus consumer-doc updates; data-structure invariants (e.g. buffer
sizing); control-plane vs data-plane separation; certificate / TLS handling;
serialization round-trip plus client-library mirroring; dependency version /
compatibility policy; privileged-endpoint auth and audit logging;
template / injection sandboxing. Cite the project's architecture docs and repo
coordinates so reviewers can verify module boundaries and that referenced
symbols actually exist. -->

<!-- FORGE:REGION skill-project-context END -->

## Step 6: LLM-Specific Failure Patterns

The code under review may have been written by an LLM. Hunt for these patterns:

1. **Hallucinated names** — methods, classes, or packages that don't exist in the codebase
2. **Plausible-but-wrong logic** — code that reads well but is subtly incorrect
3. **Incomplete error handling** — happy path covered, error paths missing
4. **Copy-paste drift** — code duplicated from elsewhere with incomplete adaptation
5. **Missing test assertions** — tests that exercise code but don't assert outcomes
6. **Over-mocking** — tests that mock so much they test nothing real
7. **Global state contamination** — tests that modify static/global state without cleanup

## Step 7: Review Completeness Check

Before returning your verdict, verify ALL of these:

- [ ] Every lens applied (or explicitly marked N/A with justification)
- [ ] Every finding has a specific file:line reference
- [ ] Every finding has a concrete, actionable recommendation
- [ ] Findings classified by severity (CRITICAL, MAJOR, MINOR, OBSERVATION)
- [ ] No false reassurance language ("looks good", "seems fine", "probably works")
- [ ] Referenced classes/methods/packages verified to actually exist
- [ ] Project-specific review focus (Step 5 region) applied
- [ ] Module dependencies respect architecture (see the project's architecture docs)

<!-- forge: removed upstream MockServer-specific completeness item ("Checked for Netty ByteBuf leaks (retain/release balance)"); covered by the skill-project-context region in Step 5 -->

## Step 8: Return Verdict

Return exactly ONE of:

- **PASS** — All findings are OBSERVATION or MINOR with low risk
- **BLOCK** — One or more CRITICAL or MAJOR findings exist

Do NOT use "PASS with reservations" or similar hedging. Either it passes or it blocks.

### Finding Format

Every finding MUST follow this structure:

```
[PRINCIPLE-ID] Severity: CRITICAL|MAJOR|MINOR|OBSERVATION

Location: file/path:line

Finding: <Concise description>

Evidence: <Quote from code or "verified in codebase">

Recommendation: <Specific, actionable fix>
```

### Output Structure

```markdown
## Adversarial Code Review

**Files reviewed:** <count>
**Lines changed:** +<added> / -<removed>
**Verdict:** PASS | BLOCK

### Findings

<findings in severity order: CRITICAL first, then MAJOR, MINOR, OBSERVATION>

### Lens Application Summary

<for each lens: applicable/N/A with brief justification>

### Review Completeness Check

<checklist with pass/fail for each item>
```
