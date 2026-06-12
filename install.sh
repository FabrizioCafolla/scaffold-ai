#!/usr/bin/env bash
set -euo pipefail

FEATURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSETS_DIR="/usr/local/share/scaffold-ai"
TOOLS="${TOOLS:-claude}"
CREATE_FILE_MCP="${CREATEFILEMCP:-true}"
CREATE_FILE_HOOKS="${CREATEFILEHOOKS:-true}"
CREATE_FILE_SETTING="${CREATEFILESETTING:-true}"
UPDATE_GITIGNORE="${UPDATEGITIGNORE:-true}"
INSTALL_DEFAULTS="${INSTALLDEFAULTS:-true}"
CONTENT_REPO="${CONTENTREPO:-}"
CONTENT_REPO_REF="${CONTENTREPOREF:-main}"
INSTALL_RTK="${INSTALLRTK:-false}"

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

# Create isolated venv and install pyyaml inside it.
# --copies avoids symlinking the interpreter from paths the runtime non-root
# user may not be able to traverse (e.g. /root/.local).
python3 -m venv --copies "${ASSETS_DIR}/venv"
"${ASSETS_DIR}/venv/bin/pip" install --quiet pyyaml \
  || { echo "[ERROR] Failed to install pyyaml in venv."; exit 1; }
chmod -R a+rX "${ASSETS_DIR}"
echo "[OK] pyyaml installed in isolated venv"

# ---------------------------------------------------------------------------
# RTK (optional) — token-saving CLI proxy for Claude Code
#
# Installs the binary to /usr/local/bin and registers the PreToolUse hook in
# the staged Claude hooks template, so scaffold runs merge it into the
# workspace .claude/settings.json.
# ---------------------------------------------------------------------------
if [[ "${INSTALL_RTK}" == "true" ]]; then
  case "$(uname -m)" in
    x86_64 | amd64) RTK_ARCH="x86_64" ;;
    aarch64 | arm64) RTK_ARCH="aarch64" ;;
    *)
      echo "[WARN] RTK: unsupported arch $(uname -m), skipping"
      RTK_ARCH=""
      ;;
  esac

  if [[ -n "${RTK_ARCH}" ]]; then
    if curl -fsSL \
      "https://github.com/rtk-ai/rtk/releases/latest/download/rtk-${RTK_ARCH}-unknown-linux-gnu.tar.gz" \
      -o /tmp/rtk.tar.gz \
      && tar xzf /tmp/rtk.tar.gz -C /usr/local/bin rtk \
      && chmod 755 /usr/local/bin/rtk; then
      rm -f /tmp/rtk.tar.gz
      echo "[OK] RTK installed: $(rtk --version)"

      RTK_HOOKS_FILE="${ASSETS_DIR}/config/claude/hooks.json" python3 - <<'PYEOF'
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
    print("[OK] RTK PreToolUse hook added to Claude hooks template")
else:
    print("[OK] RTK hook already present in hooks template")
PYEOF
    else
      echo "[WARN] RTK install failed, continuing without it"
      rm -f /tmp/rtk.tar.gz
    fi
  fi
fi

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
  git -C "${dest}" sparse-checkout set agents skills hooks mcp.json agents.scaffold-ai.md 2>/dev/null || true
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
  --create-file-hooks "${CREATE_FILE_HOOKS}" \\
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
  --create-file-hooks "${CREATE_FILE_HOOKS}" \\
  --create-file-setting "${CREATE_FILE_SETTING}" \\
  --update-gitignore "${UPDATE_GITIGNORE}" \\
  --install-defaults "${INSTALL_DEFAULTS}" \\
  \${CONTENT_REPO_SHA:+--content-repo-sha "\${CONTENT_REPO_SHA}"} \\
  \${CONTENT_REPO_PATH:+--content-repo-local-path "\${CONTENT_REPO_PATH}"}
EOF

chmod +x /usr/local/bin/scaffold-ai-install
