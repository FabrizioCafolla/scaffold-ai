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
#   --local-path DIR             Use a local scaffold-ai checkout instead of cloning (dev/test, implies --force)
#   --no-rtk                     Skip RTK install and Claude PreToolUse hook (installed by default, mirrors devcontainer)
#   --no-headroom                Skip the Headroom CLI install (installed by default; activate per-session with 'headroom wrap claude')
#   --force                      Ignore the .scaffold-ai.lock hash and re-scaffold
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
LOCAL_PATH=""
INSTALL_RTK="true"
INSTALL_HEADROOM="true"
FORCE="false"
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
  --local-path DIR        Use a local scaffold-ai checkout instead of cloning (dev/test, implies --force)
  --no-rtk                Skip RTK install and Claude hook (installed by default, mirrors devcontainer)
  --no-headroom           Skip the Headroom CLI install (installed by default; activate per-session with 'headroom wrap claude')
  --force                 Ignore the .scaffold-ai.lock hash and re-scaffold
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
    _prompt_bool  "installRtk"                                "${INSTALL_RTK}"          INSTALL_RTK
    _prompt_bool  "installHeadroom"                           "${INSTALL_HEADROOM}"     INSTALL_HEADROOM
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
        --local-path)         LOCAL_PATH="$2";            shift 2 ;;
        --no-rtk)             INSTALL_RTK="false";        shift ;;
        --no-headroom)        INSTALL_HEADROOM="false";   shift ;;
        --force)              FORCE="true";               shift ;;
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

if [[ -n "${LOCAL_PATH}" ]]; then
    [[ -f "${LOCAL_PATH}/scaffold.py" ]] \
        || die "--local-path '${LOCAL_PATH}' is not a scaffold-ai checkout (scaffold.py not found)."
    info "Using local scaffold-ai checkout: ${LOCAL_PATH}"
    cp -R "${LOCAL_PATH}" "${TEMP_DIR}/scaffold-ai"
else
    git clone --quiet --depth 1 --branch "${GIT_REF}" "${REPO_URL}" "${TEMP_DIR}/scaffold-ai" \
        || die "Failed to clone ${REPO_URL}. Check your internet connection."
fi

# ---------------------------------------------------------------------------
# RTK (optional) — install binary and register the Claude PreToolUse hook in
# the staged hooks template, so the scaffold merges it into .claude/settings.json
# ---------------------------------------------------------------------------
if [[ "${INSTALL_RTK}" == "true" ]]; then
    if ! command -v rtk &>/dev/null; then
        info "Installing RTK..."
        case "$(uname -m)" in
            x86_64 | amd64) RTK_ARCH="x86_64" ;;
            aarch64 | arm64) RTK_ARCH="aarch64" ;;
            *) die "RTK: unsupported arch $(uname -m)" ;;
        esac
        RTK_BIN_DIR="/usr/local/bin"
        [[ -w "${RTK_BIN_DIR}" ]] || RTK_BIN_DIR="${HOME}/.local/bin"
        mkdir -p "${RTK_BIN_DIR}"
        curl -fsSL \
            "https://github.com/rtk-ai/rtk/releases/latest/download/rtk-${RTK_ARCH}-unknown-linux-gnu.tar.gz" \
            | tar xz -C "${RTK_BIN_DIR}" rtk \
            || die "Failed to install RTK."
        chmod 755 "${RTK_BIN_DIR}/rtk"
        info "RTK installed to ${RTK_BIN_DIR}/rtk"
    fi

    RTK_HOOKS_FILE="${TEMP_DIR}/scaffold-ai/config/claude/hooks.json" "${PYTHON}" - <<'PYEOF'
import json, os

path = os.environ["RTK_HOOKS_FILE"]
with open(path) as f:
    hooks = json.load(f)

entry = {
    "matcher": "Bash",
    "hooks": [{"type": "command", "command": "rtk hook claude"}],
}
pre = hooks.setdefault("PreToolUse", [])
if not any(
    h.get("command") == "rtk hook claude"
    for item in pre
    for h in item.get("hooks", [])
):
    pre.append(entry)
    with open(path, "w") as f:
        json.dump(hooks, f, indent=2)
        f.write("\n")
    print("  RTK PreToolUse hook added to Claude hooks template")
PYEOF
fi

# ---------------------------------------------------------------------------
# Headroom (installed by default) — request-level context compression CLI
#
# Python tool installed via uv. Not a hook and not auto-active: activate
# per-session with `headroom wrap claude`. RTK stays the active input-side
# layer; Headroom only stacks on top when explicitly wrapped.
#
# [proxy] (~430MB) covers wrap/proxy; [all] (~5.5GB) adds ML/eval and is only
# for local training/benchmarking — escalate with `uv tool install --reinstall`.
# ---------------------------------------------------------------------------
if [[ "${INSTALL_HEADROOM}" == "true" ]]; then
    if command -v headroom &>/dev/null; then
        info "Headroom already installed: $(headroom --version 2>/dev/null || echo 'unknown version') (inactive until 'headroom wrap claude')"
    elif command -v uv &>/dev/null; then
        info "Installing Headroom CLI..."
        uv tool install "headroom-ai[proxy]" \
            && info "Headroom installed: $(headroom --version 2>/dev/null || echo 'unknown version') (inactive until 'headroom wrap claude')" \
            || warn "Headroom install failed, continuing without it"
    else
        warn "Headroom requires uv (not found), skipping"
    fi
fi

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
# The lock hash is identity-based (scaffold-ai HEAD SHA + content repo SHA),
# so uncommitted local changes never alter it: a local checkout always forces.
if [[ "${FORCE}" == "true" || -n "${LOCAL_PATH}" ]]; then
    if [[ -f "${WORKSPACE}/.scaffold-ai.lock" ]]; then
        info "Forcing re-scaffold (removing .scaffold-ai.lock)"
        rm -f "${WORKSPACE}/.scaffold-ai.lock"
    fi
fi

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
