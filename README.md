# scaffold-ai

Devcontainer feature that scaffolds AI agent and skill assets (Claude, GitHub Copilot) into a workspace. Each asset is assembled from tool-agnostic content files with per-tool YAML frontmatter injected at runtime.

Works both as a **devcontainer feature** (automatic, runs only when content changes) and as a **standalone CLI** (no container required).

---

## Prerequisites

### Supported base images

scaffold-ai requires **bash** and **Python 3.9+** (which includes `venv` out of the box).

| Base                   | Supported | Notes                                          |
| ---------------------- | --------- | ---------------------------------------------- |
| Debian / Ubuntu        | Yes       | All `mcr.microsoft.com/devcontainers/*` images |
| RHEL / Fedora / CentOS | Yes       | bash and python3 available via dnf/yum         |
| Alpine                 | No        | No bash by default (busybox sh only)           |

### Python 3.9+

scaffold-ai does **not** install Python you must provide it via the base image or the devcontainer Python feature.

For devcontainers, add the Python feature **before** scaffold-ai:

```json
{
  "features": {
    "ghcr.io/devcontainers/features/python:1": { "version": "3.13" },
    "ghcr.io/fabriziocafolla/scaffold-ai/scaffold-ai:0": { "...": "..." }
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
      "createFileHooks": true,
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

| Option              | Type    | Default  | Description                                                                                                                            |
| ------------------- | ------- | -------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `tools`             | string  | `claude` | Comma-separated tools to scaffold: `claude`, `copilot`                                                                                 |
| `createFileMCP`     | boolean | `true`   | Create shared `.mcp.json` at workspace root. Skipped if already exists. Serves Claude, VS Code, and Copilot                           |
| `createFileHooks`   | boolean | `true`   | Deploy and manage hooks files for active tools. Always updated on scaffold runs. Overridable via content repo                          |
| `createFileSetting` | boolean | `true`   | Copy settings templates. Skipped if already exist                                                                                      |
| `updateGitignore`   | boolean | `true`   | Add scaffold-managed paths to `.gitignore`                                                                                             |
| `installDefaults`   | boolean | `true`   | Install bundled default agents and skills. Set `false` to use only `contentRepo`                                                       |
| `installRtk`        | boolean | `true`   | Install [RTK](https://github.com/rtk-ai/rtk) and register its Claude Code `PreToolUse` hook in the scaffolded hooks template           |
| `installWikictl`    | boolean | `false`  | Install [wikictl](#wikictl) — a file-based AI memory layer (CLI + MCP server + `wikictl-*` skills). Off by default                      |
| `contentRepo`       | string  | `""`     | GitHub repo URL with additional agents/skills (and optional hooks/mcp overrides) merged on top of defaults                            |
| `contentRepoRef`    | string  | `main`   | Branch or tag of the content repo                                                                                                      |

#### Claude Code usability extras

Scaffolded automatically when `claude` is in `tools`:

- **Statusline** (`.claude/statusline.sh` + `statusLine` in the `settings.json` template): model, directory, git branch, context window % with color-coded bar, token counts, session cost (API billing only — hidden on Pro/Max plans where `rate_limits` is present), lines added/removed, 5-hour rate limit, and token-saving tool indicators (`⚡rtk` / `🪨caveman`, green = active, dim = installed). Requires `jq` in the container; degrades to a minimal line without it. Skipped if the workspace already has `.claude/statusline.sh` / `settings.json`.
- **Caveman skill** ([upstream](https://github.com/JuliusBrussee/caveman)): bundled in the default skills, deployed to `.claude/skills/caveman`. Compresses Claude's prose replies (~65% of output tokens). Activate per session with `/caveman` (`lite|full|ultra`); disable with "stop caveman". Refresh the bundled copy from upstream with `just update-caveman`.
- **RTK** (enabled by default, `installRtk: false` to disable): installs the binary to `/usr/local/bin` and injects the `PreToolUse` hook into the Claude hooks template, so every scaffold run merges it into `.claude/settings.json`. Bash commands are then transparently rewritten to token-compressed `rtk` equivalents (60-90% savings on `git status`, test runners, `find`, …). Check savings with `rtk gain`.

#### wikictl

**wikictl** (`installWikictl: false` by default) is a file-based memory layer for AI agents — a wiki of Markdown entries with YAML frontmatter, queried over MCP. The source is vendored with the feature. When enabled, scaffold-ai provisions three things:

- **CLI** — installed via `uv tool install` from the vendored path (requires `uv`; warns and continues if missing). Provides `wikictl create|read|list|search|tags|edit|move|delete|schema|index|serve`.
- **MCP server** — a gated `wikictl` entry (`http://127.0.0.1:8000/mcp/`, started by `wikictl serve`) is merged into `.mcp.json` only when `installWikictl` is true. The server encodes a metadata-first protocol and exposes `get_schema` (the entry metadata contract). The `wikictl-*` skills are always deployed alongside the other default skills.

Enable it in a devcontainer:

```json
{
  "features": {
    "ghcr.io/fabriziocafolla/scaffold-ai/scaffold-ai:0": {
      "tools": "claude",
      "installWikictl": true
    }
  }
}
```

Or from the CLI: `bash cli.sh --workspace . --tools claude --wikictl`.

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

| Option                   | Default     | Description                                              |
| ------------------------ | ----------- | -------------------------------------------------------- |
| `--workspace DIR`        | current dir | Target workspace directory                               |
| `--tools LIST`           | `claude`    | Comma-separated tools: `claude`, `copilot`               |
| `--no-mcp`               |             | Skip `.mcp.json` creation                                |
| `--no-hooks`             |             | Skip hooks file management                               |
| `--no-settings`          |             | Skip settings file creation                              |
| `--no-gitignore`         |             | Skip `.gitignore` update                                 |
| `--no-defaults`          |             | Skip bundled default content                             |
| `--content-repo URL`     |             | GitHub repo with additional agents, skills, hooks or mcp |
| `--content-repo-ref REF` | `main`      | Branch or tag for content repo                           |
| `--ref BRANCH\|TAG`      | `main`      | scaffold-ai git ref to clone                             |
| `--local-path DIR`       |             | Use a local scaffold-ai checkout instead of cloning (dev/test, implies `--force`) |
| `--no-rtk`               |             | Skip [RTK](https://github.com/rtk-ai/rtk) install and Claude `PreToolUse` hook (installed by default, mirrors devcontainer `installRtk`) |
| `--wikictl`              |             | Install [wikictl](#wikictl) (CLI + MCP server + skills; off by default, mirrors devcontainer `installWikictl`) |
| `--force`                |             | Ignore the `.scaffold-ai.lock` hash and re-scaffold      |
| `--interactive`          |             | Guided prompt mode                                       |

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
├── skills/
│   ├── metadata.yml    # per-tool frontmatter for each skill
│   └── my-skill/
│       └── SKILL.md    # skill content (no frontmatter)
├── hooks/              # optional: override default hook templates
│   ├── claude.json     # replaces config/claude/hooks.json
│   └── copilot.json    # replaces config/copilot/hooks.json
└── mcp.json            # optional: override shared .mcp.json template
```

You can include any subset — anything absent falls back to bundled defaults (unless `--no-defaults` / `installDefaults: false`). Hooks and MCP overrides are full replacements, not merges.

---

## Setting up a private content repo

Keep personal or organization-specific agents and skills in a separate private GitHub repository. scaffold-ai fetches it at scaffold time and merges it on top of the public defaults.

### 1. Create the repository

Create a new **private** GitHub repository (e.g. `my-org/ai-content`), then clone it locally.

### 2. Initialize the structure

Run this one-liner from inside the cloned repo to create the required layout:

```bash
mkdir -p agents skills/my-first-skill && \
  printf 'default:\n  claude:\n  copilot:\n\nagents:\n' > agents/metadata.yml && \
  printf 'default:\n  claude:\n  copilot:\n\nskills:\n' > skills/metadata.yml && \
  printf '# My First Skill\n\nDescribe what this skill does.\n' > skills/my-first-skill/SKILL.md
```

This creates:

```
my-content-repo/
├── agents/
│   └── metadata.yml
└── skills/
    ├── metadata.yml
    └── my-first-skill/
        └── SKILL.md
```

### 3. Add agents and skills

Follow the same conventions as `content/` in this repo:

- Agent body → `agents/<key>.md` (no frontmatter), registered in `agents/metadata.yml`
- Skill body → `skills/<key>/SKILL.md` (no frontmatter), registered in `skills/metadata.yml`

See [AGENTS.md](./AGENTS.md) for the full `metadata.yml` format and content standards.

### 4. Use it with scaffold-ai

**Devcontainer:**

```json
{
  "features": {
    "ghcr.io/fabriziocafolla/scaffold-ai:0": {
      "contentRepo": "https://github.com/my-org/ai-content"
    }
  },
  "secrets": ["GITHUB_TOKEN"]
}
```

**CLI:**

```bash
GITHUB_TOKEN=$(gh auth token) bash scaffold-ai.sh --content-repo https://github.com/my-org/ai-content
```

Remote content is merged on top of bundled defaults same key overrides, missing keys fall back to defaults. Use `--no-defaults` / `installDefaults: false` to skip bundled defaults entirely.

---

## Skill Taxonomy

### Naming conventions

All skills follow one of two prefixes:

| Prefix        | Meaning                                                                                        | Examples                                    |
| ------------- | ---------------------------------------------------------------------------------------------- | ------------------------------------------- |
| `developer-*` | Operative skills used while **building**: language conventions, framework patterns, tool usage | `developer-python`, `developer-kubernetes`  |
| `advisor-*`   | Strategic skills used for **decisions, reviews, and design**                                   | `advisor-sre`, `advisor-cloud-architecture` |

Named exceptions with no prefix: `research-scout`, `skill-creator`, `copilot-agent-creator`, `copilot-skill-creator`.

### Taxonomy metadata

Every entry in `metadata.yml` includes `category` and `subcategory` fields:

```yaml
skills:
  developer-python:
    category: engineering
    subcategory: build-and-quality
    claude: ...
    copilot: ...
```

Valid categories and subcategories:

| Category        | Subcategories                                                                                             |
| --------------- | --------------------------------------------------------------------------------------------------------- |
| `engineering`   | `build-and-quality`, `architecture-and-platform`, `operations-and-reliability`, `technical-documentation` |
| `communication` | `professional-communication`, `editorial-and-content`, `presence-and-ux-writing`                          |
| `delivery`      | `planning-and-prioritization`, `standards-and-decision-making`, `review-and-improvement`                  |
| `reasoning`     | `ideation-and-problem-framing`, `research-and-study`, `teaching-and-speaking`                             |
| `tools`         | `editor-and-ide`, `cli-and-tool-usage`, `automation-and-environment`                                      |
| `meta`          | `skills-and-agents`                                                                                       |
