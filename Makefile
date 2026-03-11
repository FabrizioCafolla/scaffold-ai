.PHONY: test clean

WORKSPACE := test

# Run a full local scaffold into ./test/ as if it were a real workspace root.
# Uses uv to run scaffold.py with pyyaml available without polluting system Python.
PHONY: test
test:
	@echo "==> Creating test workspace: $(WORKSPACE)/"
	mkdir -p $(WORKSPACE)
	@echo "==> Running Scaffold AI..."
	uv run --with pyyaml scaffold.py \
		--workspace $(WORKSPACE) \
		--copilot true \
		--claude true \
		--create-file-mcp true \
		--create-file-setting true \
		--update-gitignore true
	@echo ""

PHONY: clean
clean:
	@echo "==> Removing test workspace..."
	rm -rf $(WORKSPACE)
