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

# Verify Python 3.9+ is available
if ! command -v python3 &>/dev/null; then
  echo "[ERROR] scaffold-ai requires Python 3.9+, but python3 was not found."
  exit 1
fi
PY_MAJOR=$(python3 -c 'import sys; print(sys.version_info.major)')
PY_MINOR=$(python3 -c 'import sys; print(sys.version_info.minor)')
PY_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
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
# Shared clone helper — written as a here-doc snippet included in both wrappers
# ---------------------------------------------------------------------------
read -r -d '' CLONE_HELPER <<'HELPER' || true
_clone_content_repo() {
  local url="$1" ref="$2" dest="$3"
  local auth_url="${url}"

  # Auth resolution: GITHUB_TOKEN > gh CLI > anonymous
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    local host
    host=$(echo "${url}" | sed 's|https://||' | cut -d'/' -f1)
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
  git -C "${dest}" sparse-checkout set agents skills 2>/dev/null || true
  echo "[OK] Content repo cloned (ref: ${ref})"
}
HELPER

# ---------------------------------------------------------------------------
# scaffold-ai-install  (onCreateCommand — runs once on first container create)
# Always runs a full scaffold, ignoring the lock file.
# ---------------------------------------------------------------------------
cat > /usr/local/bin/scaffold-ai-install <<EOF
#!/usr/bin/env bash
set -euo pipefail

WORKSPACE="\${1:-\${CONTAINER_WORKSPACE_FOLDER:-\$(pwd)}}"
CONTENT_REPO_PATH=""

${CLONE_HELPER}

if [[ -n "${CONTENT_REPO}" ]]; then
  CONTENT_REPO_TMP="\$(mktemp -d)"
  trap 'rm -rf "\${CONTENT_REPO_TMP}"' EXIT
  _clone_content_repo "${CONTENT_REPO}" "${CONTENT_REPO_REF}" "\${CONTENT_REPO_TMP}/content-repo"
  CONTENT_REPO_PATH="\${CONTENT_REPO_TMP}/content-repo"
fi

# Remove lock to force a fresh scaffold on first create
rm -f "\${WORKSPACE}/.scaffold-ai.lock"

exec "${ASSETS_DIR}/venv/bin/python3" "${ASSETS_DIR}/scaffold.py" \\
  --workspace "\${WORKSPACE}" \\
  --tools "${TOOLS}" \\
  --create-file-mcp "${CREATE_FILE_MCP}" \\
  --create-file-mcp-vscode "${CREATE_FILE_MCP_VSCODE}" \\
  --create-file-setting "${CREATE_FILE_SETTING}" \\
  --update-gitignore "${UPDATE_GITIGNORE}" \\
  --install-defaults "${INSTALL_DEFAULTS}" \\
  \${CONTENT_REPO_PATH:+--content-repo-local-path "\${CONTENT_REPO_PATH}"}
EOF

chmod +x /usr/local/bin/scaffold-ai-install

# ---------------------------------------------------------------------------
# scaffold-ai-cmd  (postStartCommand — runs on every container start)
# Hash check inside scaffold.py exits fast if nothing changed.
# ---------------------------------------------------------------------------
cat > /usr/local/bin/scaffold-ai-cmd <<EOF
#!/usr/bin/env bash
set -euo pipefail

WORKSPACE="\${1:-\${CONTAINER_WORKSPACE_FOLDER:-\$(pwd)}}"
CONTENT_REPO_PATH=""

${CLONE_HELPER}

if [[ -n "${CONTENT_REPO}" ]]; then
  CONTENT_REPO_TMP="\$(mktemp -d)"
  trap 'rm -rf "\${CONTENT_REPO_TMP}"' EXIT
  _clone_content_repo "${CONTENT_REPO}" "${CONTENT_REPO_REF}" "\${CONTENT_REPO_TMP}/content-repo"
  CONTENT_REPO_PATH="\${CONTENT_REPO_TMP}/content-repo"
fi

exec "${ASSETS_DIR}/venv/bin/python3" "${ASSETS_DIR}/scaffold.py" \\
  --workspace "\${WORKSPACE}" \\
  --tools "${TOOLS}" \\
  --create-file-mcp "${CREATE_FILE_MCP}" \\
  --create-file-mcp-vscode "${CREATE_FILE_MCP_VSCODE}" \\
  --create-file-setting "${CREATE_FILE_SETTING}" \\
  --update-gitignore "${UPDATE_GITIGNORE}" \\
  --install-defaults "${INSTALL_DEFAULTS}" \\
  \${CONTENT_REPO_PATH:+--content-repo-local-path "\${CONTENT_REPO_PATH}"}
EOF

chmod +x /usr/local/bin/scaffold-ai-cmd
