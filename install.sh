#!/usr/bin/env bash
set -euo pipefail

FEATURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSETS_DIR="/usr/local/share/scaffold-ai"
TOOLS="${TOOLS:-claude}"
CREATE_FILE_MCP="${CREATEFILEMCP:-true}"
CREATE_FILE_MCP_VSCODE="${CREATEFILEMCPVSCODE:-false}"
CREATE_FILE_SETTING="${CREATEFILESETTING:-true}"
UPDATE_GITIGNORE="${UPDATEGITIGNORE:-true}"
INSTALL_DEFAULTS="${INSTALLDEFAULTS:-true}"
CONTENT_REPO="${CONTENTREPO:-}"
CONTENT_REPO_REF="${CONTENTREPOREF:-main}"

# ---------------------------------------------------------------------------
# Verify Python 3.9+ with venv support.
# This is a prerequisite — scaffold-ai does NOT install Python.
# The user must provide it via base image or the devcontainer python feature.
# ---------------------------------------------------------------------------
if ! command -v python3 &>/dev/null; then
  echo "[ERROR] scaffold-ai requires Python 3.9+ but python3 was not found."
  echo ""
  echo "  Add the Python devcontainer feature BEFORE scaffold-ai:"
  echo ""
  echo '    "features": {'
  echo '      "ghcr.io/devcontainers/features/python:1": { "version": "3.13" },'
  echo '      "ghcr.io/fabriziocafolla/scaffold-ai/scaffold-ai:0": { ... }'
  echo '    }'
  echo ""
  exit 1
fi

PY_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
PY_MAJOR=$(python3 -c 'import sys; print(sys.version_info.major)')
PY_MINOR=$(python3 -c 'import sys; print(sys.version_info.minor)')
if [[ "${PY_MAJOR}" -lt 3 ]] || [[ "${PY_MAJOR}" -eq 3 && "${PY_MINOR}" -lt 9 ]]; then
  echo "[ERROR] scaffold-ai requires Python 3.9+, found ${PY_VERSION}."
  exit 1
fi
echo "[OK] Python ${PY_VERSION} found"

# Copy entire feature directory to persistent location
rm -rf "${ASSETS_DIR}"
cp -R "${FEATURE_DIR}" "${ASSETS_DIR}"

# Create isolated venv and install pyyaml inside it
python3 -m venv "${ASSETS_DIR}/venv"
"${ASSETS_DIR}/venv/bin/pip" install --quiet pyyaml \
  || { echo "[ERROR] Failed to install pyyaml in venv."; exit 1; }
echo "[OK] pyyaml installed in isolated venv"

# ---------------------------------------------------------------------------
# Shared helpers embedded into both wrapper scripts at install time.
#
# _get_remote_sha URL REF
#   Returns the HEAD SHA of REF via git ls-remote (no clone needed).
#   Outputs empty string on failure so callers can treat it as a cache miss.
#
# _clone_content_repo URL REF DEST
#   Shallow-clones the content repo with auth resolution:
#   GITHUB_TOKEN env var > gh CLI token > anonymous.
# ---------------------------------------------------------------------------
read -r -d '' CLONE_HELPER <<'HELPER' || true
_get_remote_sha() {
  local url="$1" ref="$2"
  local auth_url="${url}"

  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    auth_url="https://x-access-token:${GITHUB_TOKEN}@${url#https://}"
  elif command -v gh &>/dev/null && gh auth token &>/dev/null 2>&1; then
    local token
    token=$(gh auth token)
    auth_url="https://x-access-token:${token}@${url#https://}"
  fi

  git ls-remote --exit-code "${auth_url}" "refs/heads/${ref}" 2>/dev/null | cut -f1 || echo ""
}

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

  rm -rf "${dest}"
  if ! git clone --quiet --depth 1 --filter=blob:none --sparse \
      --branch "${ref}" "${auth_url}" "${dest}" 2>/dev/null; then
    echo "[ERROR] Failed to clone content repo: ${url} (ref: ${ref})" >&2
    echo "[ERROR] For private repos, set the GITHUB_TOKEN secret in your devcontainer." >&2
    exit 1
  fi
  git -C "${dest}" sparse-checkout set agents skills agents.scaffold-ai.md 2>/dev/null || true
  echo "[OK] Content repo cloned (ref: ${ref})"
}
HELPER

# ---------------------------------------------------------------------------
# scaffold-ai-cmd  (postStartCommand — runs on every container start)
#
# Fast path: uses git ls-remote to get the remote SHA without cloning.
# Passes it to scaffold.py --check-only for a pure hash comparison against
# the lock file. Only clones the content repo and runs the full scaffold
# when the hash has actually changed.
# ---------------------------------------------------------------------------
cat > /usr/local/bin/scaffold-ai-cmd <<EOF
#!/usr/bin/env bash
set -euo pipefail

WORKSPACE="\${1:-\${CONTAINER_WORKSPACE_FOLDER:-\$(pwd)}}"

${CLONE_HELPER}

# Resolve content repo SHA via ls-remote (cheap — no clone)
CONTENT_REPO_SHA=""
if [[ -n "${CONTENT_REPO}" ]]; then
  CONTENT_REPO_SHA=\$(_get_remote_sha "${CONTENT_REPO}" "${CONTENT_REPO_REF}")
fi

# Fast check: exit early if nothing has changed
if "${ASSETS_DIR}/venv/bin/python3" "${ASSETS_DIR}/scaffold.py" \\
    --workspace "\${WORKSPACE}" \\
    --check-only \\
    \${CONTENT_REPO_SHA:+--content-repo-sha "\${CONTENT_REPO_SHA}"}; then
  exit 0
fi

# Hash changed — clone content repo and run full scaffold
CONTENT_REPO_PATH=""
if [[ -n "${CONTENT_REPO}" ]]; then
  CONTENT_REPO_TMP="\$(mktemp -d)"
  trap 'rm -rf "\${CONTENT_REPO_TMP}"' EXIT
  _clone_content_repo "${CONTENT_REPO}" "${CONTENT_REPO_REF}" "\${CONTENT_REPO_TMP}/content-repo"
  CONTENT_REPO_PATH="\${CONTENT_REPO_TMP}/content-repo"
fi

"${ASSETS_DIR}/venv/bin/python3" "${ASSETS_DIR}/scaffold.py" \\
  --workspace "\${WORKSPACE}" \\
  --tools "${TOOLS}" \\
  --create-file-mcp "${CREATE_FILE_MCP}" \\
  --create-file-mcp-vscode "${CREATE_FILE_MCP_VSCODE}" \\
  --create-file-setting "${CREATE_FILE_SETTING}" \\
  --update-gitignore "${UPDATE_GITIGNORE}" \\
  --install-defaults "${INSTALL_DEFAULTS}" \\
  \${CONTENT_REPO_SHA:+--content-repo-sha "\${CONTENT_REPO_SHA}"} \\
  \${CONTENT_REPO_PATH:+--content-repo-local-path "\${CONTENT_REPO_PATH}"}
EOF

chmod +x /usr/local/bin/scaffold-ai-cmd

# ---------------------------------------------------------------------------
# scaffold-ai-install  (utility — forces a full scaffold, ignoring the lock)
#
# Use this to manually re-run the scaffold after making changes to the
# content repo or scaffold-ai itself, without rebuilding the container.
# ---------------------------------------------------------------------------
cat > /usr/local/bin/scaffold-ai-install <<EOF
#!/usr/bin/env bash
set -euo pipefail

WORKSPACE="\${1:-\${CONTAINER_WORKSPACE_FOLDER:-\$(pwd)}}"

${CLONE_HELPER}

CONTENT_REPO_PATH=""
CONTENT_REPO_SHA=""
if [[ -n "${CONTENT_REPO}" ]]; then
  CONTENT_REPO_TMP="\$(mktemp -d)"
  trap 'rm -rf "\${CONTENT_REPO_TMP}"' EXIT
  _clone_content_repo "${CONTENT_REPO}" "${CONTENT_REPO_REF}" "\${CONTENT_REPO_TMP}/content-repo"
  CONTENT_REPO_PATH="\${CONTENT_REPO_TMP}/content-repo"
  CONTENT_REPO_SHA=\$(git -C "\${CONTENT_REPO_PATH}" rev-parse HEAD 2>/dev/null || echo "")
fi

# Remove lock to force a fresh scaffold
rm -f "\${WORKSPACE}/.scaffold-ai.lock"

"${ASSETS_DIR}/venv/bin/python3" "${ASSETS_DIR}/scaffold.py" \\
  --workspace "\${WORKSPACE}" \\
  --tools "${TOOLS}" \\
  --create-file-mcp "${CREATE_FILE_MCP}" \\
  --create-file-mcp-vscode "${CREATE_FILE_MCP_VSCODE}" \\
  --create-file-setting "${CREATE_FILE_SETTING}" \\
  --update-gitignore "${UPDATE_GITIGNORE}" \\
  --install-defaults "${INSTALL_DEFAULTS}" \\
  \${CONTENT_REPO_SHA:+--content-repo-sha "\${CONTENT_REPO_SHA}"} \\
  \${CONTENT_REPO_PATH:+--content-repo-local-path "\${CONTENT_REPO_PATH}"}
EOF

chmod +x /usr/local/bin/scaffold-ai-install
