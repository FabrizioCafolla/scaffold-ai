#!/usr/bin/env bash
# =============================================================================
# scaffold-ai CLI
#
# Standalone script: clones scaffold-ai from GitHub, runs the scaffolder
# against the current (or specified) workspace, then cleans up.
#
# Usage:
#   # one-liner from any project root:
#   curl -fsSL https://raw.githubusercontent.com/FabrizioCafolla/scaffold-ai/main/cli.sh | bash
#
#   # or download and run with custom options:
#   curl -fsSL https://raw.githubusercontent.com/FabrizioCafolla/scaffold-ai/main/cli.sh -o scaffold-ai.sh
#   bash scaffold-ai.sh [OPTIONS]
#
# Options:
#   --workspace DIR              Target workspace directory (default: current dir)
#   --tools claude|copilot|...   Comma-separated tools to scaffold (default: claude)
#   --no-mcp                     Skip .mcp.json creation
#   --no-hooks                   Skip hooks file management
#   --no-settings                Skip settings file creation
#   --no-gitignore               Skip .gitignore update
#   --no-defaults                Skip bundled default content (use only --content-repo)
#   --content-repo URL           GitHub repo URL with additional agents/skills
#   --content-repo-ref REF       Branch or tag of the content repo (default: main)
#   --ref BRANCH|TAG             scaffold-ai git ref to clone (default: main)
#   --interactive                Guided prompt mode (mirrors devcontainer options)
#   -h, --help                   Show this help
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
WORKSPACE="${PWD}"
TOOLS="claude"
CREATE_FILE_MCP="true"
CREATE_FILE_HOOKS="true"
CREATE_FILE_SETTING="true"
UPDATE_GITIGNORE="true"
INSTALL_DEFAULTS="true"
CONTENT_REPO=""
CONTENT_REPO_REF="main"
GIT_REF="main"
INTERACTIVE="false"
readonly REPO_URL="https://github.com/FabrizioCafolla/scaffold-ai.git"
SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME

TEMP_DIR=""

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
cleanup() {
    if [[ -n "${TEMP_DIR:-}" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
die()  { echo "[ERROR] $*" >&2; exit 1; }
info() { echo "  $*"; }
warn() { echo "[WARN]  $*" >&2; }

usage() {
    cat <<EOF
scaffold-ai  scaffold AI agent/skill assets into any workspace

Usage: $SCRIPT_NAME [OPTIONS]
       curl -fsSL https://raw.githubusercontent.com/FabrizioCafolla/scaffold-ai/main/cli.sh | bash -s -- [OPTIONS]

Options:
  --workspace DIR         Target workspace directory (default: current dir)
  --tools LIST            Comma-separated tools: claude, copilot (default: claude)
  --no-mcp                Skip .mcp.json creation
  --no-hooks              Skip hooks file management
  --no-settings           Skip settings file creation
  --no-gitignore          Skip .gitignore update
  --no-defaults           Skip bundled default content
  --content-repo URL      GitHub repo URL with additional agents/skills
  --content-repo-ref REF  Branch or tag for content repo (default: main)
  --ref BRANCH|TAG        scaffold-ai git ref to clone (default: main)
  --interactive           Guided prompt mode
  -h, --help              Show this help
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Interactive mode pure bash prompts, mirrors devcontainer option names
# ---------------------------------------------------------------------------
_prompt() {
    local question="$1" default="$2" varname="$3"
    local answer
    printf "  %s [%s]: " "${question}" "${default}"
    read -r answer
    answer="${answer:-${default}}"
    printf -v "${varname}" '%s' "${answer}"
}

_prompt_bool() {
    local question="$1" default="$2" varname="$3"
    local display answer
    display=$([ "${default}" = "true" ] && echo "Y/n" || echo "y/N")
    printf "  %s? [%s]: " "${question}" "${display}"
    read -r answer
    case "${answer,,}" in
        y|yes) printf -v "${varname}" '%s' "true" ;;
        n|no)  printf -v "${varname}" '%s' "false" ;;
        *)     printf -v "${varname}" '%s' "${default}" ;;
    esac
}

run_interactive() {
    echo ""
    echo "  scaffold-ai interactive setup"
    echo "  ─────────────────────────────────────────"
    _prompt       "tools (comma-separated: claude, copilot)" "${TOOLS}"          TOOLS
    _prompt_bool  "createFileMCP"                             "${CREATE_FILE_MCP}"      CREATE_FILE_MCP
    _prompt_bool  "createFileHooks"                           "${CREATE_FILE_HOOKS}"    CREATE_FILE_HOOKS
    _prompt_bool  "createFileSetting"                         "${CREATE_FILE_SETTING}"  CREATE_FILE_SETTING
    _prompt_bool  "updateGitignore"                           "${UPDATE_GITIGNORE}"     UPDATE_GITIGNORE
    _prompt_bool  "installDefaults"                           "${INSTALL_DEFAULTS}"     INSTALL_DEFAULTS
    _prompt       "contentRepo (GitHub URL, leave blank to skip)" "" CONTENT_REPO
    if [[ -n "${CONTENT_REPO}" ]]; then
        _prompt   "contentRepoRef" "${CONTENT_REPO_REF}" CONTENT_REPO_REF
    fi
    echo ""
}

# ---------------------------------------------------------------------------
# Content repo clone
# ---------------------------------------------------------------------------
_clone_content_repo() {
    local url="$1" ref="$2" dest="$3"
    local auth_url="${url}"

    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        auth_url="https://x-access-token:${GITHUB_TOKEN}@${url#https://}"
    elif command -v gh &>/dev/null && gh auth token &>/dev/null 2>&1; then
        local token
        token=$(gh auth token)
        auth_url="https://x-access-token:${token}@${url#https://}"
    fi

    if ! git clone --quiet --depth 1 \
        --branch "${ref}" "${auth_url}" "${dest}" 2>/dev/null; then
        die "Failed to clone content repo: ${url} (ref: ${ref}). For private repos, set GITHUB_TOKEN."
    fi
    info "Content repo cloned (ref: ${ref})"
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --workspace)          WORKSPACE="$2";             shift 2 ;;
        --tools)              TOOLS="$2";                 shift 2 ;;
        --no-mcp)             CREATE_FILE_MCP="false";    shift ;;
        --no-hooks)           CREATE_FILE_HOOKS="false";  shift ;;
        --no-settings)        CREATE_FILE_SETTING="false"; shift ;;
        --no-gitignore)       UPDATE_GITIGNORE="false";   shift ;;
        --no-defaults)        INSTALL_DEFAULTS="false";   shift ;;
        --content-repo)       CONTENT_REPO="$2";          shift 2 ;;
        --content-repo-ref)   CONTENT_REPO_REF="$2";      shift 2 ;;
        --ref)                GIT_REF="$2";               shift 2 ;;
        --interactive)        INTERACTIVE="true";          shift ;;
        -h|--help)            usage ;;
        *) die "Unknown option: $1. Use -h for help." ;;
    esac
done

# ---------------------------------------------------------------------------
# Interactive mode (runs after flag parsing so flags set the defaults)
# ---------------------------------------------------------------------------
if [[ "${INTERACTIVE}" == "true" ]]; then
    run_interactive
fi

# ---------------------------------------------------------------------------
# Dependency checks
# ---------------------------------------------------------------------------
for cmd in git python3; do
    command -v "$cmd" &>/dev/null || die "'$cmd' is required but not found."
done

PY_MAJOR=$(python3 -c 'import sys; print(sys.version_info.major)')
PY_MINOR=$(python3 -c 'import sys; print(sys.version_info.minor)')
if [[ "$PY_MAJOR" -lt 3 ]] || [[ "$PY_MAJOR" -eq 3 && "$PY_MINOR" -lt 9 ]]; then
    PY_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
    die "Python 3.9+ required, found ${PY_VERSION}."
fi

# ---------------------------------------------------------------------------
# Setup: temp dir, venv, clone scaffold-ai
# ---------------------------------------------------------------------------
TEMP_DIR="$(mktemp -d)"
info "Cloning scaffold-ai (ref: ${GIT_REF})..."

PYTHON="python3"
if ! python3 -c 'import yaml' 2>/dev/null; then
    info "Installing pyyaml in isolated venv..."
    python3 -m venv "${TEMP_DIR}/venv"
    "${TEMP_DIR}/venv/bin/pip" install --quiet pyyaml \
        || die "Failed to install pyyaml inside venv."
    PYTHON="${TEMP_DIR}/venv/bin/python3"
fi

git clone --quiet --depth 1 --branch "${GIT_REF}" "${REPO_URL}" "${TEMP_DIR}/scaffold-ai" \
    || die "Failed to clone ${REPO_URL}. Check your internet connection."

# ---------------------------------------------------------------------------
# Content repo clone (if requested)
# ---------------------------------------------------------------------------
CONTENT_REPO_LOCAL_PATH=""
if [[ -n "${CONTENT_REPO}" ]]; then
    info "Cloning content repo (ref: ${CONTENT_REPO_REF})..."
    _clone_content_repo "${CONTENT_REPO}" "${CONTENT_REPO_REF}" "${TEMP_DIR}/content-repo"
    CONTENT_REPO_LOCAL_PATH="${TEMP_DIR}/content-repo"
fi

# ---------------------------------------------------------------------------
# Run scaffold
# ---------------------------------------------------------------------------
echo ""
EXTRA_ARGS=()
[[ -n "${CONTENT_REPO_LOCAL_PATH}" ]] && EXTRA_ARGS+=(--content-repo-local-path "${CONTENT_REPO_LOCAL_PATH}")

"${PYTHON}" "${TEMP_DIR}/scaffold-ai/scaffold.py" \
    --workspace               "${WORKSPACE}" \
    --tools                   "${TOOLS}" \
    --create-file-mcp         "${CREATE_FILE_MCP}" \
    --create-file-hooks       "${CREATE_FILE_HOOKS}" \
    --create-file-setting     "${CREATE_FILE_SETTING}" \
    --update-gitignore        "${UPDATE_GITIGNORE}" \
    --install-defaults        "${INSTALL_DEFAULTS}" \
    "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}"
