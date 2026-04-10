# scaffold-ai

Devcontainer feature that scaffolds AI agent and skill assets (Claude, GitHub Copilot) into a workspace. Each asset is assembled from tool-agnostic content files with per-tool YAML frontmatter injected at runtime.

Works both as a **devcontainer feature** (automatic, runs only when content changes) and as a **standalone CLI** (no container required).

---

## Prerequisites

### Supported base images

scaffold-ai requires **bash** and **Python 3.9+** (which includes `venv` out of the box).

| Base                              | Supported | Notes                                          |
| --------------------------------- | --------- | ---------------------------------------------- |
| Debian / Ubuntu                   | Yes       | All `mcr.microsoft.com/devcontainers/*` images |
| RHEL / Fedora / CentOS           | Yes       | bash and python3 available via dnf/yum         |
| Alpine                            | No        | No bash by default (busybox sh only)           |

### Python 3.9+

scaffold-ai does **not** install Python — you must provide it via the base image or the devcontainer Python feature.

For devcontainers, add the Python feature **before** scaffold-ai:

```json
{
  "features": {
    "ghcr.io/devcontainers/features/python:1": { "version": "3.13" },
    "ghcr.io/fabriziocafolla/scaffold-ai/scaffold-ai:0": { "..." : "..." }
  }
}
```

For CLI usage, ensure `python3 >= 3.9` is in your PATH.

---

## Usage

### Devcontainer

Add the feature to your `.devcontainer/devcontainer.json`:

```json
{
  "features": {
    "ghcr.io/devcontainers/features/python:1": { "version": "3.13" },
    "ghcr.io/fabriziocafolla/scaffold-ai:0": {
      "tools": "claude",
      "createFileMCP": true,
      "createFileMcpVscode": false,
      "createFileSetting": true,
      "updateGitignore": true,
      "installDefaults": true,
      "contentRepo": "",
      "contentRepoRef": "main"
    }
  }
}
```

Assets are scaffolded automatically on first container create (`onCreateCommand`). Subsequent restarts skip the scaffold unless content has changed (`postStartCommand` with hash check).

#### Options

| Option                | Type    | Default  | Description                                                                      |
| --------------------- | ------- | -------- | -------------------------------------------------------------------------------- |
| `tools`               | string  | `claude` | Comma-separated tools to scaffold: `claude`, `copilot`                           |
| `createFileMCP`       | boolean | `true`   | Copy MCP config template. Skipped if already exists                              |
| `createFileMcpVscode` | boolean | `false`  | Copy `.vscode/mcp.json` template. Skipped if already exists                      |
| `createFileSetting`   | boolean | `true`   | Copy settings templates. Skipped if already exist                                |
| `updateGitignore`     | boolean | `true`   | Add scaffold-managed paths to `.gitignore`                                       |
| `installDefaults`     | boolean | `true`   | Install bundled default agents and skills. Set `false` to use only `contentRepo` |
| `contentRepo`         | string  | `""`     | GitHub repo URL with additional agents/skills (merged on top of defaults)        |
| `contentRepoRef`      | string  | `main`   | Branch or tag of the content repo                                                |

#### Private content repos

Set `GITHUB_TOKEN` as a devcontainer secret. The feature resolves auth automatically: `GITHUB_TOKEN` → `gh` CLI → anonymous (public repos only).

```json
{
  "secrets": ["GITHUB_TOKEN"]
}
```

---

### CLI

Run directly from any project root without installing anything:

```bash
# defaults (Claude only)
curl -fsSL https://raw.githubusercontent.com/FabrizioCafolla/scaffold-ai/main/cli.sh | bash

# with custom options pass args after `bash -s --`
curl -fsSL https://raw.githubusercontent.com/FabrizioCafolla/scaffold-ai/main/cli.sh | bash -s -- --tools claude,copilot --no-gitignore
```

Or download for repeated use:

```bash
curl -fsSL https://raw.githubusercontent.com/FabrizioCafolla/scaffold-ai/main/cli.sh -o scaffold-ai.sh
bash scaffold-ai.sh [OPTIONS]
```

#### Options

| Option                   | Default     | Description                                |
| ------------------------ | ----------- | ------------------------------------------ |
| `--workspace DIR`        | current dir | Target workspace directory                 |
| `--tools LIST`           | `claude`    | Comma-separated tools: `claude`, `copilot` |
| `--mcp-vscode`           |             | Create `.vscode/mcp.json` template         |
| `--no-mcp`               |             | Skip MCP config file creation              |
| `--no-settings`          |             | Skip settings file creation                |
| `--no-gitignore`         |             | Skip `.gitignore` update                   |
| `--no-defaults`          |             | Skip bundled default content               |
| `--content-repo URL`     |             | GitHub repo with additional agents/skills  |
| `--content-repo-ref REF` | `main`      | Branch or tag for content repo             |
| `--ref BRANCH\|TAG`      | `main`      | scaffold-ai git ref to clone               |
| `--interactive`          |             | Guided prompt mode                         |

**Requirements:** `git`, `python3 >= 3.9` with `venv` module (pyyaml is installed automatically in an isolated venv).

#### Interactive mode

```bash
bash scaffold-ai.sh --interactive
```

Prompts for each option, using devcontainer option names as question labels. Flags passed before `--interactive` set the defaults shown in the prompts.

#### Content repo

Point to any GitHub repo that follows the `content/` structure (agents and/or skills subdirectories). Remote content is merged on top of bundled defaults same key = remote wins.

```bash
# public repo
bash scaffold-ai.sh --content-repo https://github.com/myorg/ai-content

# private repo
GITHUB_TOKEN=$(gh auth token) bash scaffold-ai.sh --content-repo https://github.com/myorg/private-ai-content

# use only content repo, skip bundled defaults
bash scaffold-ai.sh --no-defaults --content-repo https://github.com/myorg/ai-content
```

---

## Content repo structure

A content repo must follow the same layout as `content/` in this project:

```
your-content-repo/
├── agents/
│   ├── metadata.yml    # per-tool frontmatter for each agent
│   └── my-agent.md     # agent content (no frontmatter)
└── skills/
    ├── metadata.yml    # per-tool frontmatter for each skill
    └── my-skill/
        └── SKILL.md    # skill content (no frontmatter)
```

You can include only `agents/`, only `skills/`, or both. Anything absent falls back to bundled defaults (unless `--no-defaults` / `installDefaults: false`).
