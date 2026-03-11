#!/usr/bin/env bash
set -euo pipefail

FEATURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSETS_DIR="/usr/local/share/scaffold-ai"
COPILOT_ENABLED="${COPILOT:-true}"
CLAUDE_ENABLED="${CLAUDE:-true}"
CREATE_FILE_MCP="${CREATEFILEMCP:-true}"
CREATE_FILE_SETTING="${CREATEFILESETTING:-true}"
UPDATE_GITIGNORE="${UPDATEGITIGNORE:-true}"

# Verify Python 3.9+ is available
if ! command -v python3 &>/dev/null; then
  echo "[ERROR] scaffold-ai requires Python 3.9+, but python3 was not found."
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

# Install Python dependency for the scaffolder
pip install --quiet pyyaml

# Copy entire feature directory to persistent location
rm -rf "${ASSETS_DIR}"
cp -R "${FEATURE_DIR}" "${ASSETS_DIR}"

# Generate scaffold-ai-cmd wrapper (option values captured at install time)
cat > /usr/local/bin/scaffold-ai-cmd <<EOF
#!/usr/bin/env bash
set -euo pipefail

WORKSPACE="\${1:-\${CONTAINER_WORKSPACE_FOLDER:-\$(pwd)}}"

exec python3 "${ASSETS_DIR}/scaffold.py" \
  --workspace "\${WORKSPACE}" \
  --copilot "${COPILOT_ENABLED}" \
  --claude "${CLAUDE_ENABLED}" \
  --create-file-mcp "${CREATE_FILE_MCP}" \
  --create-file-setting "${CREATE_FILE_SETTING}" \
  --update-gitignore "${UPDATE_GITIGNORE}"
EOF

chmod +x /usr/local/bin/scaffold-ai-cmd
