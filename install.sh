#!/usr/bin/env bash
# =============================================================================
# scaffold-ai devcontainer feature entrypoint.
#
# This is a required entrypoint per the devcontainer Feature spec, but it does
# almost nothing: it verifies Python, reads the feature's own version, and
# generates a thin `scaffoldai` launcher pinned to that version. It installs
# no binary and vendors no scaffold-ai content — `scaffoldai install`
# (postCreateCommand) and `scaffoldai sync` (postStartCommand) do that at
# runtime by fetching cli.sh from the repo at the pinned ref. See cli.sh for
# the actual implementation (shared with the standalone curl installer).
# =============================================================================
set -euo pipefail

FEATURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Feature options — boolean enables only. Structured config (tools,
# contentRepo) lives in the consuming workspace's .scaffold-ai/config.yaml.
CREATE_FILE_MCP="${CREATEFILEMCP:-true}"
CREATE_FILE_HOOKS="${CREATEFILEHOOKS:-true}"
CREATE_FILE_SETTING="${CREATEFILESETTING:-true}"
UPDATE_GITIGNORE="${UPDATEGITIGNORE:-true}"
INSTALL_DEFAULTS="${INSTALLDEFAULTS:-true}"
INSTALL_RTK="${INSTALLRTK:-true}"
INSTALL_HEADROOM="${INSTALLHEADROOM:-true}"
INSTALL_WIKICTL="${INSTALLWIKICTL:-false}"

# ---------------------------------------------------------------------------
# Verify Python 3.9+.
# This is a prerequisite — scaffold-ai does NOT install Python.
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

# ---------------------------------------------------------------------------
# Resolve the feature version — this becomes the pinned ref that scaffoldai
# fetches cli.sh (and scaffold-ai content) at, so behaviour stays reproducible
# for a given feature version instead of tracking a moving `main`.
# ---------------------------------------------------------------------------
FEATURE_VERSION=$(python3 -c "import json; print(json.load(open('${FEATURE_DIR}/devcontainer-feature.json'))['version'])")
echo "[OK] scaffold-ai version ${FEATURE_VERSION}"

# ---------------------------------------------------------------------------
# Bake the boolean feature options into launcher flags. These act as the
# fallback tier: .scaffold-ai/config.yaml in the workspace overrides them.
# ---------------------------------------------------------------------------
BAKED_FLAGS=()
[[ "${INSTALL_RTK}" != "true" ]] && BAKED_FLAGS+=(--no-rtk)
[[ "${INSTALL_HEADROOM}" != "true" ]] && BAKED_FLAGS+=(--no-headroom)
[[ "${INSTALL_WIKICTL}" == "true" ]] && BAKED_FLAGS+=(--wikictl)
[[ "${CREATE_FILE_MCP}" != "true" ]] && BAKED_FLAGS+=(--no-mcp)
[[ "${CREATE_FILE_HOOKS}" != "true" ]] && BAKED_FLAGS+=(--no-hooks)
[[ "${CREATE_FILE_SETTING}" != "true" ]] && BAKED_FLAGS+=(--no-settings)
[[ "${UPDATE_GITIGNORE}" != "true" ]] && BAKED_FLAGS+=(--no-gitignore)
[[ "${INSTALL_DEFAULTS}" != "true" ]] && BAKED_FLAGS+=(--no-defaults)

BAKED_FLAGS_STR=""
for f in "${BAKED_FLAGS[@]+"${BAKED_FLAGS[@]}"}"; do
  BAKED_FLAGS_STR+=" $(printf '%q' "${f}")"
done

# ---------------------------------------------------------------------------
# Generate the scaffoldai launcher. It fetches the real implementation
# (cli.sh) from the repo at the pinned FEATURE_VERSION on every invocation —
# nothing is vendored, so there is no packaging step that can drop an asset.
# A failed fetch or scaffold run must never block container start.
# ---------------------------------------------------------------------------
cat > /usr/local/bin/scaffoldai <<EOF
#!/usr/bin/env bash
set -euo pipefail
REF="${FEATURE_VERSION}"
SUB="install"
if [[ \$# -gt 0 && "\$1" != -* ]]; then
  SUB="\$1"
  shift
fi
curl -fsSL "https://raw.githubusercontent.com/FabrizioCafolla/scaffold-ai/\${REF}/cli.sh" \\
  | bash -s -- "\${SUB}" --ref "\${REF}" --workspace "\${CONTAINER_WORKSPACE_FOLDER:-\$(pwd)}"${BAKED_FLAGS_STR} "\$@" \\
  || exit 0
EOF

chmod +x /usr/local/bin/scaffoldai
echo "[OK] scaffoldai installed (pinned to ${FEATURE_VERSION})"
