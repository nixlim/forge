# Per-stack validation snippets

Source material for `/forge-init` when filling the `file-categories` and
`stack-validations` regions of `.opencode/rules/commit-workflow.md`. Detect stacks from
the markers below; adapt commands to the repo's actual scripts (prefer the repo's own
`package.json` scripts / Makefile / justfile targets over the raw defaults here). Every
generated section must keep the upstream principle: **prefer executable verification
over static inspection**, and **fix before committing**.

Always include the generic `bash`, `docs`, `config`, and `control` categories from the
template — they are stack-independent.

---

## node (marker: `package.json`; lockfiles: `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`, `bun.lockb`)

Category row: `| \`npm\` | \`package.json\`, lockfiles, \`*.js\`, \`*.ts\`, \`*.tsx\`, \`*.jsx\` |`

Validation steps:
1. Install with the repo's package manager if `node_modules` is stale (`npm ci` / `pnpm install --frozen-lockfile` / `yarn --immutable` / `bun install`)
2. Lint: repo's `lint` script if present (`npm run lint`)
3. Types: `typecheck` script or `npx tsc --noEmit` when `tsconfig.json` exists
4. Tests: repo's `test` script
5. Build when the package builds: `npm run build`

## python (markers: `pyproject.toml`, `requirements*.txt`, `setup.py`; tools: uv/poetry/pip)

Category row: `| \`python\` | \`*.py\`, \`pyproject.toml\`, \`requirements*.txt\` |`

Validation steps:
1. Environment: `uv sync` / `poetry install` / `python3 -m venv .venv && .venv/bin/pip install -e '.[dev]'` per repo tooling
2. Lint/format: `ruff check` (and `ruff format --check`) if configured; else configured linter
3. Types: `mypy`/`pyright` when configured
4. Tests: `pytest` (repo's configured runner)

## go (marker: `go.mod`)

Category row: `| \`go\` | \`*.go\`, \`go.mod\`, \`go.sum\` |`

Validation steps:
1. `go build ./...`
2. `go vet ./...` (plus `staticcheck ./...` when configured)
3. `go test ./...` (targeted packages for large repos, plus any designated blast-radius package always)

## rust (marker: `Cargo.toml`)

Category row: `| \`rust\` | \`*.rs\`, \`Cargo.toml\`, \`Cargo.lock\` |`

Validation steps:
1. `cargo check --all-targets`
2. `cargo clippy --all-targets -- -D warnings` when clippy is configured
3. `cargo fmt --check`
4. `cargo test` (targeted `-p <crate>` for workspaces, plus the designated blast-radius crate always)

## java-maven (markers: `pom.xml`, `mvnw`)

Category row: `| \`java\` | \`*.java\`, \`pom.xml\` |`

Validation steps:
1. Identify affected modules from file paths
2. `./mvnw test -pl <module1>,<module2>`
3. `./mvnw verify -pl <module>` for integration-test-bearing modules
4. Always additionally run the designated blast-radius module's suite

## java-gradle / kotlin (markers: `build.gradle`, `build.gradle.kts`, `gradlew`)

Category row: `| \`jvm\` | \`*.java\`, \`*.kt\`, \`build.gradle*\` |`

Validation steps:
1. `./gradlew build -x test` (compile + static checks)
2. `./gradlew test` (module-scoped `:module:test` for multi-project builds)

## terraform (marker: `*.tf`)

Category row: `| \`terraform\` | \`*.tf\`, \`*.tfvars.example\` |`

Validation steps (upstream-proven sequence):
1. `terraform fmt -check -recursive`
2. `terraform init -backend=false` if `.terraform/` missing
3. `terraform validate` per affected module
4. `terraform plan` with placeholder variables when real credentials are unavailable

## docker (markers: `Dockerfile*`, `docker-compose*.yml`)

Category row: `| \`docker\` | \`Dockerfile*\`, \`docker-compose*.yml\` |`

Validation steps (upstream-proven sequence):
1. `docker build` every changed Dockerfile with the correct context
2. `hadolint <Dockerfile>` when available
3. Smoke-run the built image when feasible (`--version`, startup help)

## helm (markers: `Chart.yaml`)

Category row: `| \`helm\` | \`helm/**\`, \`Chart.yaml\`, \`values.yaml\` |`

Validation steps: `helm lint` then `helm template` on the chart directory.

---

## Gate-1 command derivation (for `gate1-test-command` regions)

Compose from the detected stacks: the targeted test command(s) for changed paths, plus
one **always-run blast-radius suite** — the package/module/crate the rest of the repo
depends on most (upstream analog: "the full mockserver-core suite, always run"). Ask the
user to confirm the blast-radius choice during init; record it in
`.opencode/rules/testing-policy.md`'s `test-commands` region.
