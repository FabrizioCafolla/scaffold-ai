workspace := "test"
uv       := "uv run --with pyyaml scaffold.py"

# List available recipes
default:
    @just --list

# Scaffold Claude only — mirrors devcontainer default
test: clean
    @echo "==> Creating test workspace: {{workspace}}/"
    mkdir -p {{workspace}}
    @echo "==> Running scaffold (tools: claude)..."
    {{uv}} \
        --workspace {{workspace}} \
        --tools claude \
        --create-file-mcp true \
        --create-file-hooks true \
        --create-file-setting true \
        --update-gitignore true \
        --install-defaults true

# Scaffold Copilot only
test-copilot: clean
    @echo "==> Running scaffold (tools: copilot)..."
    mkdir -p {{workspace}}
    {{uv}} \
        --workspace {{workspace}} \
        --tools copilot \
        --create-file-mcp true \
        --create-file-hooks true \
        --create-file-setting false \
        --update-gitignore true \
        --install-defaults true

# Scaffold Claude + Copilot with hooks
test-both: clean
    @echo "==> Running scaffold (tools: claude,copilot + hooks)..."
    mkdir -p {{workspace}}
    {{uv}} \
        --workspace {{workspace}} \
        --tools claude,copilot \
        --create-file-mcp true \
        --create-file-hooks true \
        --create-file-setting true \
        --update-gitignore true \
        --install-defaults true

# Scaffold with installDefaults=false — expects empty output without a content repo
test-no-defaults: clean
    @echo "==> Running scaffold (no defaults, no content repo)..."
    mkdir -p {{workspace}}
    {{uv}} \
        --workspace {{workspace}} \
        --tools claude \
        --create-file-mcp false \
        --create-file-hooks false \
        --create-file-setting false \
        --update-gitignore false \
        --install-defaults false

# Run scaffold twice — second run must be a no-op (hash unchanged)
test-idempotent: clean
    @echo "==> First run..."
    mkdir -p {{workspace}}
    {{uv}} --workspace {{workspace}} --tools claude --install-defaults true
    @echo ""
    @echo "==> Second run (should skip)..."
    {{uv}} --workspace {{workspace}} --tools claude --install-defaults true

# Verify hooks override from a simulated private content repo
test-hooks: clean
    @echo "==> Setting up simulated private repo with hooks override..."
    mkdir -p {{workspace}} /tmp/scaffold-test-private/hooks
    echo '{"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "echo pre-tool-use-from-private"}]}], "PostToolUse": [], "UserPromptSubmit": [], "Stop": [], "Notification": []}' \
        > /tmp/scaffold-test-private/hooks/claude.json
    echo '{"version": 1, "hooks": {"sessionStart": [{"type": "command", "command": {"unix": "echo session-start-from-private"}}], "sessionEnd": [], "userPromptSubmitted": [], "preToolUse": [], "postToolUse": [], "errorOccurred": []}}' \
        > /tmp/scaffold-test-private/hooks/copilot.json
    @echo "==> Running scaffold with private content repo..."
    {{uv}} \
        --workspace {{workspace}} \
        --tools claude,copilot \
        --create-file-mcp true \
        --create-file-hooks true \
        --create-file-setting true \
        --update-gitignore true \
        --install-defaults true \
        --content-repo-local-path /tmp/scaffold-test-private
    @echo "==> Verifying private hooks applied..."
    grep -q "pre-tool-use-from-private" {{workspace}}/.claude/settings.json \
        && echo "  [OK] Claude hooks: private override applied" \
        || echo "  [FAIL] Claude hooks: private override NOT applied"
    grep -q "session-start-from-private" {{workspace}}/.github/hooks/hooks.json \
        && echo "  [OK] Copilot hooks: private override applied" \
        || echo "  [FAIL] Copilot hooks: private override NOT applied"
    rm -rf /tmp/scaffold-test-private

# Scaffold with a simulated local content repo (private skills + hooks)
test-content-repo: clean
    @echo "==> Setting up simulated content repo..."
    mkdir -p /tmp/scaffold-test-content/agents \
              /tmp/scaffold-test-content/skills/my-private-skill \
              /tmp/scaffold-test-content/hooks
    printf 'default:\n  claude:\n  copilot:\n\nagents:\n' \
        > /tmp/scaffold-test-content/agents/metadata.yml
    printf 'default:\n  claude:\n  copilot:\n\nskills:\n  my-private-skill:\n    category: engineering\n    subcategory: build-and-quality\n    claude:\n      name: my-private-skill\n      description: Test private skill\n    copilot:\n      name: my-private-skill\n      description: Test private skill\n' \
        > /tmp/scaffold-test-content/skills/metadata.yml
    printf '# My Private Skill\nThis is a test private skill.' \
        > /tmp/scaffold-test-content/skills/my-private-skill/SKILL.md
    @echo "==> Running scaffold with content repo..."
    {{uv}} \
        --workspace {{workspace}} \
        --tools claude \
        --create-file-mcp true \
        --create-file-hooks true \
        --create-file-setting true \
        --update-gitignore true \
        --install-defaults true \
        --content-repo-local-path /tmp/scaffold-test-content
    @echo "==> Verifying private skill installed..."
    test -f {{workspace}}/.claude/skills/my-private-skill/SKILL.md \
        && echo "  [OK] private skill installed" \
        || echo "  [FAIL] private skill NOT installed"
    rm -rf /tmp/scaffold-test-content

# Remove test workspace
clean:
    @echo "==> Removing test workspace..."
    rm -rf {{workspace}}
