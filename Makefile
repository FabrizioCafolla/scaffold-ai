.PHONY: test test-claude test-copilot test-both test-content-repo test-no-defaults clean

WORKSPACE := test

# Run a full local scaffold into ./test/ as if it were a real workspace root.
# Uses uv to run scaffold.py with pyyaml available without polluting system Python.
UV := uv run --with pyyaml scaffold.py

## test: default scaffold Claude only (mirrors devcontainer default)
test: clean
	@echo "==> Creating test workspace: $(WORKSPACE)/"
	mkdir -p $(WORKSPACE)
	@echo "==> Running scaffold (tools: claude)..."
	$(UV) \
		--workspace $(WORKSPACE) \
		--tools claude \
		--create-file-mcp true \
		--create-file-mcp-vscode false \
		--create-file-setting true \
		--update-gitignore true \
		--install-defaults true
	@echo ""

## test-copilot: scaffold Copilot only
test-copilot: clean
	@echo "==> Running scaffold (tools: copilot)..."
	mkdir -p $(WORKSPACE)
	$(UV) \
		--workspace $(WORKSPACE) \
		--tools copilot \
		--create-file-mcp true \
		--create-file-mcp-vscode false \
		--create-file-setting false \
		--update-gitignore true \
		--install-defaults true
	@echo ""

## test-both: scaffold Claude + Copilot + VSCode MCP
test-both: clean
	@echo "==> Running scaffold (tools: claude,copilot + vscode mcp)..."
	mkdir -p $(WORKSPACE)
	$(UV) \
		--workspace $(WORKSPACE) \
		--tools claude,copilot \
		--create-file-mcp true \
		--create-file-mcp-vscode true \
		--create-file-setting true \
		--update-gitignore true \
		--install-defaults true
	@echo ""

## test-no-defaults: scaffold with installDefaults=false (content repo only)
test-no-defaults: clean
	@echo "==> Running scaffold (no defaults, no content repo should produce empty output)..."
	mkdir -p $(WORKSPACE)
	$(UV) \
		--workspace $(WORKSPACE) \
		--tools claude \
		--create-file-mcp false \
		--create-file-mcp-vscode false \
		--create-file-setting false \
		--update-gitignore false \
		--install-defaults false
	@echo ""

## test-idempotent: run scaffold twice, second run must be a no-op
test-idempotent: clean
	@echo "==> First run..."
	mkdir -p $(WORKSPACE)
	$(UV) --workspace $(WORKSPACE) --tools claude --install-defaults true
	@echo ""
	@echo "==> Second run (should skip hash unchanged)..."
	$(UV) --workspace $(WORKSPACE) --tools claude --install-defaults true
	@echo ""

## clean: remove test workspace
clean:
	@echo "==> Removing test workspace..."
	rm -rf $(WORKSPACE)
