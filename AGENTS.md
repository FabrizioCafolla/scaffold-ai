# Scaffold AI

A tool-agnostic devcontainer feature that scaffolds AI agent/skill assets into the workspace at container start.

## Architecture

```
apps/scaffold-ai/
  content/               # Pure Markdown — zero frontmatter, tool-agnostic
    agents/              # One .md per agent (key matches config entry)
    skills/              # One subdir per skill, each with SKILL.md
      <skill-key>/
        SKILL.md
        references/      # Optional reference files (e.g. terraform/)
    prompts/             # Placeholder (future use)
  config/                # Per-tool metadata (frontmatter injected at runtime)
    paths.yml            # Output paths per tool (copilot / claude)
    agents.yml           # Agent frontmatter for each tool
    skills.yml           # Skill frontmatter for each tool
    prompts.yml          # Placeholder
    mcp.json             # Template for .mcp.json (used when createFileMCP=true)
    claude-settings.json          # Template for .claude/settings.json
    claude-settings.local.json    # Template for .claude/settings.local.json
  scaffold.py            # Python 3.13 scaffolder: merges content + config, creates files
  install.sh             # Devcontainer install: copies feature, installs pyyaml, writes wrapper
  Makefile               # Local test runner (make test / make clean)
  devcontainer-feature.json
```

## How It Works

1. **At build time** (`install.sh` runs):
   - Installs `pyyaml` via pip
   - Copies the entire feature directory to `/usr/local/share/scaffold-ai/`
   - Writes `/usr/local/bin/scaffold-ai-cmd` (shell wrapper around `scaffold.py`)

2. **At container start** (`postStartCommand` calls `scaffold-ai-cmd`):
   - `scaffold.py` reads `config/paths.yml`, `config/agents.yml`, `config/skills.yml`
   - For each enabled tool (`copilot`, `claude`), it:
     - Reads the pure Markdown body from `content/`
     - Prepends the tool-specific YAML frontmatter
     - Writes assembled files to the workspace (`.github/` for Copilot, `.claude/` for Claude)
   - If `--create-file-mcp true`: copies `config/mcp.json` → `<workspace>/.mcp.json`
   - If `--create-file-setting true`: copies settings templates → `.claude/settings.json` and `.claude/settings.local.json`

## Feature Options

| Option              | Type    | Default | Description                                                      |
| ------------------- | ------- | ------- | ---------------------------------------------------------------- |
| `copilot`           | boolean | `true`  | Scaffold Copilot assets (`.github/agents/`, `.github/skills/`)   |
| `claude`            | boolean | `true`  | Scaffold Claude assets (`.claude/agents/`, `.claude/skills/`)    |
| `createFileMCP`     | boolean | `true`  | Create `.mcp.json` at workspace root with MCP server definitions |
| `createFileSetting` | boolean | `true`  | Create `.claude/settings.json` and `.claude/settings.local.json` |

## Local Testing

```bash
make test    # scaffold into ./test/ with all flags enabled
make clean   # remove ./test/
```

## Adding a New Agent

1. Create `content/agents/<key>.md` — pure Markdown body, no frontmatter
2. Add an entry under `config/agents.yml`:
   ```yaml
   agents:
     <key>:
       copilot:
         name: Display Name
         description: '...'
         tools: [read, edit, ...]
       claude:
         name: Display Name
         description: '...'
         allowedTools: [Read, Edit]
   ```

## Adding a New Skill

1. Create `content/skills/<key>/SKILL.md` — pure Markdown body, no frontmatter
2. (Optional) Add `content/skills/<key>/references/` for reference files
3. Add an entry under `config/skills.yml`:
   ```yaml
   skills:
     <key>:
       copilot:
         name: <key>
         description: '...'
       claude:
         name: <key>
         description: '...'
   ```

## Running Manually

````bash
python3 /usr/local/share/scaffold-ai/scaffold.py \
  --workspace /path/to/workspace \
  --copilot true \
  --claude true \
  --create-file-mcp true \
  --create-file-setting true

# or via the installed wrapper:
scaffold-ai-cmd /path/to/workspace
```scaffold-ai-cmd /path/to/workspace
````
