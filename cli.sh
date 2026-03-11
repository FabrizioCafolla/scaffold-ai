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
#   --workspace DIR         Target workspace directory (default: current dir)
#   --copilot true|false    Scaffold Copilot assets (default: true)
#   --claude  true|false    Scaffold Claude assets   (default: true)
#   --no-mcp                Skip .mcp.json creation
#   --no-settings           Skip settings file creation
#   --no-gitignore          Skip .gitignore update
#   --ref BRANCH|TAG        Git ref to clone (default: main)
#   -h, --help              Show this help
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
WORKSPACE="${PWD}"
COPILOT="true"
CLAUDE="true"
CREATE_FILE_MCP="true"
CREATE_FILE_SETTING="true"
UPDATE_GITIGNORE="true"
GIT_REF="main"
readonly REPO_URL="https://github.com/FabrizioCafolla/scaffold-ai.git"
readonly SCRIPT_NAME="$(basename "$0")"

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

usage() {
    cat <<EOF
scaffold-ai CLI — scaffold AI agent/skill assets into any workspace

Usage: $SCRIPT_NAME [OPTIONS]
       curl -fsSL https://raw.githubusercontent.com/FabrizioCafolla/scaffold-ai/main/cli.sh | bash

Options:
  --workspace DIR         Target workspace directory (default: current dir)
  --copilot true|false    Scaffold Copilot assets (default: true)
  --claude  true|false    Scaffold Claude assets   (default: true)
  --no-mcp                Skip .mcp.json creation
  --no-settings           Skip settings file creation
  --no-gitignore          Skip .gitignore update
  --ref BRANCH|TAG        Git ref to clone (default: main)
  -h, --help              Show this help
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --workspace)    WORKSPACE="$2";       shift 2 ;;
        --copilot)      COPILOT="$2";         shift 2 ;;
        --claude)       CLAUDE="$2";          shift 2 ;;
        --no-mcp)       CREATE_FILE_MCP="false";   shift ;;
        --no-settings)  CREATE_FILE_SETTING="false"; shift ;;
        --no-gitignore) UPDATE_GITIGNORE="false";  shift ;;
        --ref)          GIT_REF="$2";         shift 2 ;;
        -h|--help)      usage ;;
        *) die "Unknown option: $1. Use -h for help." ;;
    esac
done

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
# Clone (temp dir created before pyyaml check so venv can live inside it)
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
# Run scaffold
# ---------------------------------------------------------------------------
echo ""
"${PYTHON}" "${TEMP_DIR}/scaffold-ai/scaffold.py" \
    --workspace  "${WORKSPACE}" \
    --copilot    "${COPILOT}" \
    --claude     "${CLAUDE}" \
    --create-file-mcp     "${CREATE_FILE_MCP}" \
    --create-file-setting "${CREATE_FILE_SETTING}" \
    --update-gitignore    "${UPDATE_GITIGNORE}"
