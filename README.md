# scaffold-ai

Devcontainer feature that scaffolds AI agent and skill assets (Claude, GitHub Copilot) into a workspace. Each asset is assembled from tool-agnostic content files with per-tool YAML frontmatter injected at runtime.

Nothing is vendored into the published feature. A single script, `cli.sh`, does the actual work — it's fetched at runtime (pinned to the feature version in the devcontainer, or from `main` for standalone use) and it clones this repo to get `scaffold.py` and the content it needs. The devcontainer and the `curl | bash` installer run the exact same file.

Configuration follows one rule: **`.scaffold-ai/config.yaml` in your workspace wins.** Devcontainer feature options and CLI flags are just the fallback for whatever the YAML doesn't set.

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
    "ghcr.io/fabriziocafolla/scaffold-ai/scaffold-ai:0.4.0": { "...": "..." }
  }
}
```

For CLI usage, ensure `python3 >= 3.9` is in your PATH.

### uv (optional)

Only needed if you enable Headroom or wikictl (`uv tool install` under the hood). Without it, those installs are skipped with a warning; everything else works.

---

## How it works

**Devcontainer:**

1. `install.sh` runs once at image build. It doesn't install anything — it just checks Python, reads the feature's `version`, and writes `/usr/local/bin/scaffoldai`, a small launcher with that version baked in as the pinned ref.
2. `postCreateCommand: scaffoldai install` runs on first container create: fetches `cli.sh` at the pinned ref, resolves `.scaffold-ai/config.yaml`, installs whatever's enabled (RTK/Headroom/wikictl), and runs the first scaffold.
3. `postStartCommand: scaffoldai sync` runs on every later start: fetches `cli.sh` again, but only re-scaffolds if content actually changed (a cheap `git ls-remote` hash check) — no binary reinstalls.
4. Both exit 0 on failure. Offline, GitHub down, whatever — container start is never blocked.

**Standalone CLI:** `cli.sh` is fetched via `curl | bash`, clones scaffold-ai at `--ref` (default `main`), resolves config the same way, and runs the scaffold. It's literally the same script the devcontainer uses.

---

## Usage

### Devcontainer

```json
{
  "features": {
    "ghcr.io/devcontainers/features/python:1": { "version": "3.13" },
    "ghcr.io/fabriziocafolla/scaffold-ai:0.4.0": {
      "createFileMCP": true,
      "createFileHooks": true,
      "createFileSetting": true,
      "updateGitignore": true,
      "installDefaults": true,
      "installRtk": true,
      "installHeadroom": true,
      "installWikictl": false
    }
  }
}
```

#### Options

| Option              | Type    | Default  | Description                                                                                                                   |
| ------------------- | ------- | -------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `createFileMCP`     | boolean | `true`   | Create shared `.mcp.json` at workspace root. Skipped if already exists. Serves Claude, VS Code, and Copilot                     |
| `createFileHooks`   | boolean | `true`   | Deploy and manage hooks files for active tools. Always updated on scaffold runs. Overridable via content repo                   |
| `createFileSetting` | boolean | `true`   | Copy settings templates. Skipped if already exist                                                                                |
| `updateGitignore`   | boolean | `true`   | Add scaffold-managed paths to `.gitignore`                                                                                       |
| `installDefaults`   | boolean | `true`   | Install bundled default agents and skills. Set `false` to use only the content repo                                             |
| `installRtk`        | boolean | `true`   | Install [RTK](https://github.com/rtk-ai/rtk) and register its Claude Code `PreToolUse` hook in the scaffolded hooks template     |
| `installHeadroom`   | boolean | `true`   | Install the Headroom CLI (request-level context compression). Not auto-active; activate per-session with `headroom wrap claude` |
| `installWikictl`    | boolean | `false`  | Install [wikictl](#wikictl) — a file-based AI memory layer (CLI + MCP server + `wikictl-*` skills). Off by default              |

That's the full option list — all booleans. `tools` and the content repo aren't feature options; they live in `.scaffold-ai/config.yaml` (see [Configuration](#configuration)).

### CLI

```bash
# defaults (Claude only) — `install` is the default subcommand
curl -fsSL https://raw.githubusercontent.com/FabrizioCafolla/scaffold-ai/main/cli.sh | bash

# pass args after `bash -s --`
curl -fsSL https://raw.githubusercontent.com/FabrizioCafolla/scaffold-ai/main/cli.sh | bash -s -- install --tools claude,copilot --no-gitignore
```

Or download once and reuse:

```bash
curl -fsSL https://raw.githubusercontent.com/FabrizioCafolla/scaffold-ai/main/cli.sh -o scaffold-ai.sh
bash scaffold-ai.sh [install|sync] [OPTIONS]
```

#### Subcommands

| Subcommand | Description                                                                                              |
| ---------- | ---------------------------------------------------------------------------------------------------------- |
| `install`  | Resolve config, install enabled binaries (RTK/Headroom/wikictl), run the scaffold. Default when omitted.  |
| `sync`     | Fast path: skip binary installs, hash-check before re-scaffolding.                                        |

#### Options

| Option                   | Default     | Description                                                                       |
| ------------------------ | ----------- | ---------------------------------------------------------------------------------- |
| `--workspace DIR`        | current dir | Target workspace directory                                                        |
| `--tools LIST`           | `claude`    | Comma-separated tools: `claude`, `copilot`                                        |
| `--no-mcp`               |             | Skip `.mcp.json` creation                                                          |
| `--no-hooks`             |             | Skip hooks file management                                                        |
| `--no-settings`          |             | Skip settings file creation                                                       |
| `--no-gitignore`         |             | Skip `.gitignore` update                                                          |
| `--no-defaults`          |             | Skip bundled default content                                                      |
| `--content-repo URL`     |             | GitHub repo with additional agents, skills, hooks or mcp                          |
| `--content-repo-ref REF` | `main`      | Branch or tag for content repo                                                     |
| `--ref BRANCH\|TAG`      | `main`      | scaffold-ai git ref to clone (the devcontainer pins this to the feature version)  |
| `--local-path DIR`       |             | Use a local scaffold-ai checkout instead of cloning (dev/test, implies `--force`) |
| `--no-rtk`               |             | Skip RTK install and Claude `PreToolUse` hook                                     |
| `--no-headroom`          |             | Skip the Headroom CLI install                                                     |
| `--wikictl`              |             | Install [wikictl](#wikictl) (off by default)                                     |
| `--force`                |             | Ignore the `.scaffold-ai.lock` hash and re-scaffold                              |
| `--interactive`          |             | Guided prompt mode                                                                |

Every option here has an equivalent in `.scaffold-ai/config.yaml`, which takes priority when present — see [Configuration](#configuration).

**Requirements:** `git`, `python3 >= 3.9` with `venv` module (pyyaml is installed automatically in an isolated venv if missing).

#### Interactive mode

```bash
bash scaffold-ai.sh install --interactive
```

Prompts for each option, using devcontainer option names as question labels. Flags passed before `--interactive` set the defaults shown in the prompts. `.scaffold-ai/config.yaml`, if present, still wins over whatever you answer.

---

## Configuration

`.scaffold-ai/config.yaml` in the target workspace is the single source of truth, shared by both the devcontainer and the CLI. It's created copy-once on the first `scaffoldai install` (seeded from whatever feature options or CLI flags resolved before it existed), and from then on any key it sets overrides the matching feature option or CLI flag.

```yaml
version: 1
tools: [claude]              # claude, copilot
install:
  rtk: true
  headroom: true
  wikictl: false
scaffold:
  createFileMCP: true
  createFileHooks: true
  createFileSetting: true
  updateGitignore: true
  installDefaults: true
contentRepo:
  url: ""
  ref: main
```

Edit it directly to change tools, toggle an install, or point at a content repo. No rebuild needed — just run `scaffoldai install` (or wait for the next `scaffoldai sync`).

---

## Claude Code usability extras

Scaffolded automatically when `claude` is in `tools`:

- **Statusline** (`.claude/statusline.sh` + `statusLine` in the `settings.json` template): model, directory, git branch, context window % with color-coded bar, token counts, session cost (API billing only — hidden on Pro/Max plans where `rate_limits` is present), lines added/removed, 5-hour rate limit, and token-saving tool indicators (`⚡rtk` / `🪨caveman`, green = active, dim = installed). Requires `jq` in the container; degrades to a minimal line without it. Skipped if the workspace already has `.claude/statusline.sh` / `settings.json`.
- **Caveman skill** ([upstream](https://github.com/JuliusBrussee/caveman)): bundled in the default skills, deployed to `.claude/skills/caveman`. Compresses Claude's prose replies (~65% of output tokens). Activate per session with `/caveman` (`lite|full|ultra`); disable with "stop caveman". Refresh the bundled copy from upstream with `just update-caveman`.
- **RTK** (`install.rtk` / `installRtk` / `--no-rtk`, on by default): installs the binary and injects the `PreToolUse` hook into the Claude hooks template, so every scaffold run merges it into `.claude/settings.json`. Bash commands are then transparently rewritten to token-compressed `rtk` equivalents (60-90% savings on `git status`, test runners, `find`, …). Check savings with `rtk gain`.

---

## wikictl

A file-based memory layer for AI agents — a wiki of Markdown entries with YAML frontmatter, queried over MCP. Its source lives at `wikictl/` in this repo and is fetched by `cli.sh` at the pinned ref, same as everything else no separate vendoring step.

Off by default. Enabling it (`install.wikictl: true` in `.scaffold-ai/config.yaml`, `installWikictl: true` on the feature, or `--wikictl` on the CLI) provisions:

- **CLI** — installed via `uv tool install` from the fetched checkout (requires `uv`; warns and continues if missing). Provides `wikictl create|read|list|search|tags|edit|move|delete|schema|index|serve`.
- **MCP server** — a gated `wikictl` entry (`http://127.0.0.1:8000/mcp/`, started by `wikictl serve`) merged into `.mcp.json`. The server encodes a metadata-first protocol and exposes `get_schema` (the entry metadata contract).

The `wikictl-*` skills deploy unconditionally alongside the other default skills, regardless of whether wikictl itself is enabled.

```yaml
install:
  wikictl: true
```

---

## Content repo

Point at any GitHub repo that follows the `content/` structure to merge additional (or private) agents and skills on top of the bundled defaults.

### Layout

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

You can include any subset anything absent falls back to bundled defaults (unless `installDefaults: false` / `--no-defaults`). Hooks and MCP overrides are full replacements, not merges. Remote content wins on key conflicts with the bundled defaults.

### Using it

Set the content repo in `.scaffold-ai/config.yaml` (not as a feature option):

```yaml
contentRepo:
  url: https://github.com/my-org/ai-content
  ref: main
```

For private repos, set `GITHUB_TOKEN` as a devcontainer secret:

```json
{
  "secrets": ["GITHUB_TOKEN"]
}
```

Auth resolves automatically: `GITHUB_TOKEN` env var → `gh` CLI token → anonymous (public repos only).

From the CLI, the equivalent is a flag instead of YAML:

```bash
GITHUB_TOKEN=$(gh auth token) bash scaffold-ai.sh install --content-repo https://github.com/my-org/ai-content
```

### Bootstrapping a new content repo

```bash
mkdir -p agents skills/my-first-skill && \
  printf 'default:\n  claude:\n  copilot:\n\nagents:\n' > agents/metadata.yml && \
  printf 'default:\n  claude:\n  copilot:\n\nskills:\n' > skills/metadata.yml && \
  printf '# My First Skill\n\nDescribe what this skill does.\n' > skills/my-first-skill/SKILL.md
```

Follow the same conventions as `content/` in this repo: agent body → `agents/<key>.md`, skill body → `skills/<key>/SKILL.md`, both registered in the matching `metadata.yml`. See [AGENTS.md](./AGENTS.md) for the full `metadata.yml` format and content standards.

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
