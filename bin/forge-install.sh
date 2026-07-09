#!/usr/bin/env bash
# forge-install.sh — install the forge agent operating system into a target repo.
#
# Mechanical layer only: copies engine/ + template/ files, substitutes tokens,
# rewrites branch references when the default branch is not `master`, appends the
# .gitignore block, prepares .tmp/, and writes .forge-manifest. The judgment layer
# (stack detection, project triggers, eval baselines) is done afterwards by the
# /forge-init command — this script leaves those FORGE:REGION blocks fail-closed.
#
# Usage:
#   forge-install.sh [--target <repo-dir>] [--project-name <name>] [--branch <name>] [--force]
#
# Defaults: target = current directory (must be a git repo root or --force),
# project-name = basename of target, branch = auto-detected default branch.
#
# Idempotent: re-running refreshes forge-managed files (tracked in .forge-manifest)
# and re-applies substitutions; it never double-appends the .gitignore block.
#
# Preserved files: if AGENTS.md / CLAUDE.md / opencode.jsonc / .claude/settings.json
# already exist and were NOT installed by a previous forge run, they are left
# untouched and the fresh copy is written alongside as <file>.forge-new for manual
# merge.
#
# Upstream provenance: see forge/system/UPSTREAM (Apache-2.0, mock-server/mockserver-monorepo).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEM_DIR="$(cd "${SCRIPT_DIR}/../system" && pwd)"
ENGINE_DIR="${SYSTEM_DIR}/engine"
TEMPLATE_DIR="${SYSTEM_DIR}/template"

TARGET="$(pwd)"
PROJECT_NAME=""
BRANCH=""
FORCE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --target)       TARGET="$2"; shift 2 ;;
        --project-name) PROJECT_NAME="$2"; shift 2 ;;
        --branch)       BRANCH="$2"; shift 2 ;;
        --force)        FORCE=1; shift ;;
        -h|--help)      sed -n '2,20p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
    esac
done

TARGET="$(cd "${TARGET}" && pwd)"

[ -d "${ENGINE_DIR}" ] && [ -d "${TEMPLATE_DIR}" ] || {
    echo "ERROR: forge system payload not found at ${SYSTEM_DIR} (need engine/ and template/)" >&2
    exit 2
}

# --- target must be a git repo root (worktree/lock machinery assumes it)
if git -C "${TARGET}" rev-parse --show-toplevel >/dev/null 2>&1; then
    REPO_ROOT="$(git -C "${TARGET}" rev-parse --show-toplevel)"
    if [ "${REPO_ROOT}" != "${TARGET}" ]; then
        echo "ERROR: ${TARGET} is inside a git repo but not its root (${REPO_ROOT}). Install at the root." >&2
        exit 2
    fi
else
    if [ "${FORCE}" -eq 1 ]; then
        echo "WARNING: ${TARGET} is not a git repository (--force given; worktree/lock features need git)."
    else
        echo "ERROR: ${TARGET} is not a git repository. Run 'git init' first, or pass --force." >&2
        exit 2
    fi
fi

# --- defaults
[ -n "${PROJECT_NAME}" ] || PROJECT_NAME="$(basename "${TARGET}")"
if [ -z "${BRANCH}" ]; then
    BRANCH="$(git -C "${TARGET}" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || true)"
    [ -n "${BRANCH}" ] || BRANCH="$(git -C "${TARGET}" symbolic-ref --short HEAD 2>/dev/null || true)"
    [ -n "${BRANCH}" ] || BRANCH="main"
fi
INSTALL_DATE="$(date +%Y-%m-%d)"
UPSTREAM_COMMIT="$(grep -Eo '^#   commit:  [0-9a-f]+' "${SYSTEM_DIR}/UPSTREAM" | awk '{print $3}')"

MANIFEST="${TARGET}/.forge-manifest"
PREV_INSTALLED=""
[ -f "${MANIFEST}" ] && PREV_INSTALLED="$(sed -n 's/^file: //p' "${MANIFEST}")"

echo "forge-install: target=${TARGET} project='${PROJECT_NAME}' branch=${BRANCH}"

# --- helpers ---------------------------------------------------------------

was_previously_installed() {
    printf '%s\n' "${PREV_INSTALLED}" | grep -qxF "$1"
}

INSTALLED_FILES=""
PRESERVED_FILES=""

# install_file <src-abs> <rel-dest>
install_file() {
    local src="$1" rel="$2" dest tmp
    dest="${TARGET}/${rel}"
    mkdir -p "$(dirname "${dest}")"

    case "${rel}" in
        AGENTS.md|CLAUDE.md|opencode.jsonc|.claude/settings.json)
            if [ -f "${dest}" ] && ! was_previously_installed "${rel}" && ! cmp -s "${src}" "${dest}"; then
                cp "${src}" "${dest}.forge-new"
                substitute_tokens "${dest}.forge-new"
                PRESERVED_FILES="${PRESERVED_FILES}${rel}\n"
                echo "  preserve: ${rel} (existing kept; fresh copy at ${rel}.forge-new)"
                return 0
            fi
            ;;
    esac

    # Region-preserving refresh (idempotent re-init): when overwriting a file WE
    # installed before, carry forward any FORGE:REGION content /forge-init has since
    # filled. A region still holding its default is detected by its embedded
    # "forge-init:" instruction comment and is refreshed from the template instead.
    tmp="${dest}.forgetmp.$$"
    cp "${src}" "${tmp}"
    substitute_tokens "${tmp}"
    if [ -f "${dest}" ] && was_previously_installed "${rel}" \
       && grep -q 'FORGE:REGION' "${tmp}" 2>/dev/null && grep -q 'FORGE:REGION' "${dest}" 2>/dev/null; then
        merge_regions "${tmp}" "${dest}"
    fi
    mv "${tmp}" "${dest}"
    INSTALLED_FILES="${INSTALLED_FILES}${rel}\n"
}

# merge_regions <new-file> <old-file> — splice the old file's FILLED region bodies
# into the new file in place. Old bodies still containing a "forge-init:" instruction
# comment are unfilled defaults and are NOT carried forward (template default wins).
merge_regions() {
    perl -0777 -e '
        my ($newf, $oldf) = @ARGV;
        local $/;
        open my $oh, "<", $oldf or exit 0;
        my $old = <$oh>; close $oh;
        my %filled;
        while ($old =~ /<!-- FORGE:REGION (\S+) BEGIN -->(.*?)<!-- FORGE:REGION \1 END -->/gs) {
            my ($name, $body) = ($1, $2);
            $filled{$name} = $body unless $body =~ /forge-init:/;
        }
        exit 0 unless %filled;
        open my $nh, "<", $newf or exit 0;
        my $new = <$nh>; close $nh;
        $new =~ s/(<!-- FORGE:REGION (\S+) BEGIN -->).*?(<!-- FORGE:REGION \2 END -->)/
            exists $filled{$2} ? "$1$filled{$2}$3" : $&/ges;
        open my $out, ">", $newf or exit 1;
        print $out $new; close $out;
    ' "$1" "$2"
}

# substitute_tokens <file> — tokens + branch rewrite; portable sed -i via .bak
substitute_tokens() {
    local f="$1" logical
    # match the file-type check on the LOGICAL name: working copies carry
    # .forgetmp.<pid> / .forge-new suffixes that would defeat the extension case
    logical="${f%.forgetmp.*}"
    logical="${logical%.forge-new}"
    case "${logical}" in
        *.md|*.json|*.jsonc|*.txt|*.ts)  : ;;   # text files that may carry tokens
        *.sh)                            : ;;   # scripts carry no tokens but keep branch refs literal? (no — scripts are branch-agnostic)
        *) return 0 ;;
    esac
    sed -i.forgebak \
        -e "s/{{FORGE_PROJECT_NAME}}/${PROJECT_NAME}/g" \
        -e "s/{{FORGE_INSTALL_DATE}}/${INSTALL_DATE}/g" \
        "${f}"
    if [ "${BRANCH}" != "master" ]; then
        # perl, not sed: BSD sed lacks \b word boundaries and would silently no-op.
        # Scripts included: agent-status.sh counts commits against origin/master.
        perl -pi -e "s/\bmaster\b/${BRANCH}/g" "${f}"
    fi
    rm -f "${f}.forgebak"
}

# --- copy payload: engine first, template over it ---------------------------

copy_tree() {
    local root="$1" src rel
    while IFS= read -r src; do
        rel="${src#"${root}"/}"
        case "${rel}" in
            gitignore-block.txt) continue ;;   # handled separately
            */.devlog/*|.devlog/*) continue ;; # local logging-plugin droppings, never payload
            CLAUDE.md|*/CLAUDE.md) continue ;; # pointer is generated below; nested ones are memory-plugin strays
        esac
        # skip memory-plugin droppings regardless of path (claude-mem context stubs)
        if head -1 "${src}" 2>/dev/null | grep -q '<claude-mem-context>'; then continue; fi
        install_file "${src}" "${rel}"
    done < <(find "${root}" -type f | sort)
}

copy_tree "${ENGINE_DIR}"
copy_tree "${TEMPLATE_DIR}"

# CLAUDE.md pointer is generated, not copied: the vendored source attracts local
# memory-plugin contamination; the installed pointer must be exactly the include line.
CLAUDE_SRC="$(mktemp)"
printf '@AGENTS.md\n' > "${CLAUDE_SRC}"
install_file "${CLAUDE_SRC}" "CLAUDE.md"
rm -f "${CLAUDE_SRC}"

chmod +x "${TARGET}"/.opencode/scripts/*.sh "${TARGET}"/.opencode/evals/run-evals.sh 2>/dev/null || true

# --- .gitignore block (marker-guarded, never double-appended) ---------------

GITIGNORE_BLOCK="${ENGINE_DIR}/gitignore-block.txt"
if ! grep -qF -- "--- forge agent system" "${TARGET}/.gitignore" 2>/dev/null; then
    { [ -f "${TARGET}/.gitignore" ] && [ -n "$(tail -c1 "${TARGET}/.gitignore" 2>/dev/null)" ] && echo; } >> "${TARGET}/.gitignore" 2>/dev/null || true
    cat "${GITIGNORE_BLOCK}" >> "${TARGET}/.gitignore"
    echo "  appended: .gitignore block"
fi

# --- scratch dir -------------------------------------------------------------

mkdir -p "${TARGET}/.tmp" "${TARGET}/.tmp/decisions"
touch "${TARGET}/.tmp/.gitkeep"

# --- leftover-token check (regions are HTML comments and are expected) -------

LEFTOVERS="$(grep -rl '{{FORGE_' "${TARGET}/.opencode" "${TARGET}/.claude" "${TARGET}/AGENTS.md" 2>/dev/null || true)"
[ -z "${LEFTOVERS}" ] || {
    echo "WARNING: unsubstituted {{FORGE_ tokens remain in:" >&2
    echo "${LEFTOVERS}" >&2
}

# --- manifest ----------------------------------------------------------------
# Re-installs preserve the init state: filled regions were carried forward above,
# so a completed init stays completed. `region:` lines written by /forge-init are
# carried forward verbatim.

PREV_INIT="false"
PREV_REGIONS=""
if [ -f "${MANIFEST}" ]; then
    grep -q '^init_completed: true' "${MANIFEST}" && PREV_INIT="true"
    PREV_REGIONS="$(grep '^region: ' "${MANIFEST}" || true)"
fi

{
    echo "# forge install manifest — written by forge-install.sh; read by /forge-init and forge-sync"
    echo "forge_version: 1"
    echo "upstream_commit: ${UPSTREAM_COMMIT}"
    echo "installed: ${INSTALL_DATE}"
    echo "project_name: ${PROJECT_NAME}"
    echo "default_branch: ${BRANCH}"
    if [ "${BRANCH}" != "master" ]; then
        echo "deviation: branch references rewritten master -> ${BRANCH} in installed .md/.json/.jsonc files"
    fi
    echo "init_completed: ${PREV_INIT}"
    [ -z "${PREV_REGIONS}" ] || printf '%s\n' "${PREV_REGIONS}"
    printf '%b' "${INSTALLED_FILES}" | sed 's/^/file: /'
    printf '%b' "${PRESERVED_FILES}" | sed 's/^/preserved: /'
} > "${MANIFEST}"

INSTALL_COUNT="$(printf '%b' "${INSTALLED_FILES}" | grep -c . || true)"
echo "forge-install: ${INSTALL_COUNT} files installed. Manifest: .forge-manifest"
echo
echo "Next steps:"
echo "  1. Review the install (git status / git diff)."
echo "  2. Run /forge-init in this repo — it fills the FORGE:REGION blocks (stack"
echo "     validations, Gate-1 test command, project review triggers, AGENTS.md"
echo "     project sections) and establishes eval baselines. Until then the merge"
echo "     and commit gates FAIL CLOSED by design."
echo "  3. Commit the installed system (it is a control-class change: gated approval)."
