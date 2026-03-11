# scaffold-ai

Devcontainer feature that scaffolds AI agent and skill assets (GitHub Copilot, Claude) into a workspace at container start. Each asset is assembled from tool-agnostic content files with per-tool YAML frontmatter injected at runtime.

Works both as a **devcontainer feature** (automatic) and as a **standalone CLI** (no container required).

---

## Usage

### Devcontainer

Add the feature to your `.devcontainer/devcontainer.json`:

```json
{
  "features": {
    "ghcr.io/fabriziocafolla/scaffold-ai:0": {
      "copilot": true,
      "claude": true,
      "createFileMCP": true,
      "createFileSetting": true,
      "updateGitignore": true
    }
  }
}
```

Assets are scaffolded automatically on every container start via `postStartCommand`.

### CLI

Run directly from any project root without installing anything:

```bash
# defaults
curl -fsSL https://raw.githubusercontent.com/FabrizioCafolla/scaffold-ai/main/cli.sh | bash

# with custom options — pass args after `bash -s --`
curl -fsSL https://raw.githubusercontent.com/FabrizioCafolla/scaffold-ai/main/cli.sh | bash -s -- --claude false --no-gitignore
```

Or download for repeated use:

```bash
curl -fsSL https://raw.githubusercontent.com/FabrizioCafolla/scaffold-ai/main/cli.sh -o scaffold-ai.sh

bash scaffold-ai.sh [OPTIONS]
```

| Option                  | Default     | Description                   |
| ----------------------- | ----------- | ----------------------------- |
| `--workspace DIR`       | current dir | Target workspace directory    |
| `--copilot true\|false` | `true`      | Scaffold Copilot assets       |
| `--claude true\|false`  | `true`      | Scaffold Claude assets        |
| `--no-mcp`              | —           | Skip MCP config file creation |
| `--no-settings`         | —           | Skip settings file creation   |
| `--no-gitignore`        | —           | Skip `.gitignore` update      |
| `--ref BRANCH\|TAG`     | `main`      | Git ref to clone              |

**Requirements:** `git`, `python3 ≥ 3.9` (pyyaml is installed automatically in an isolated venv).
