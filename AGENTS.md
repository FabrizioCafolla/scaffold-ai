# Scaffold AI Developer Guide

scaffold-ai is a devcontainer feature and standalone CLI that scaffolds AI agent and skill assets (Claude, GitHub Copilot) into a workspace. Content is tool-agnostic Markdown; per-tool YAML frontmatter is injected at scaffold time.

## Repository Layout

```
scaffold-ai/
├── content/                    # Tool-agnostic Markdown content
│   ├── paths.yml               # Output paths per tool (copilot / claude / vscode)
│   ├── agents/
│   │   ├── metadata.yml        # Per-tool frontmatter for each agent
│   │   └── <key>.md            # Agent body (no frontmatter)
│   ├── skills/
│   │   ├── metadata.yml        # Per-tool frontmatter for each skill
│   │   └── <skill-key>/
│   │       ├── SKILL.md        # Skill body (no frontmatter)
│   │       └── references/     # Optional reference docs
│   └── prompts/                # Future use
├── config/                     # Per-tool config templates
│   ├── claude/                 # mcp.json, settings.json, settings.local.json
│   ├── copilot/                # config.json, mcp-config.json
│   └── vscode/                 # mcp.json
├── scaffold.py                 # Main Python scaffolder
├── install.sh                  # Devcontainer install script
├── cli.sh                      # Standalone CLI (curl | bash usage)
├── Makefile                    # Local test commands
└── devcontainer-feature.json   # Feature manifest
```

## How It Works

**Devcontainer path:**

1. `install.sh` runs at image build installs pyyaml, copies the feature to `/usr/local/share/scaffold-ai/`, writes `/usr/local/bin/scaffold-ai-cmd`
2. On `onCreateCommand` `scaffold-ai-cmd` runs `scaffold.py`, which merges content + metadata and writes assembled files to the workspace
3. `postStartCommand` re-runs only when a content hash has changed (no-op on clean restarts)

**CLI path:**

1. `cli.sh` is fetched via `curl | bash`
2. It clones scaffold-ai (or the specified `--ref`), optionally clones a `--content-repo`, then runs `scaffold.py` directly

**scaffold.py reads:**

- `content/paths.yml` where to write output files per tool
- `content/agents/metadata.yml` frontmatter for each agent, per tool
- `content/skills/metadata.yml` frontmatter for each skill, per tool
- Markdown bodies from `content/agents/` and `content/skills/`
- Remote content-repo files merged on top (same key = remote wins)

## Adding an Agent

1. Create `content/agents/<key>.md` Markdown body only, no frontmatter
2. Register it in `content/agents/metadata.yml`:

```yaml
agents:
  <key>:
    copilot:
      name: Display Name
      description: 'When Copilot should activate this agent.'
      tools: [read, edit, execute, search, web, agent, todo, filesystem/*]
    claude:
      name: Display Name
      description: 'When Claude should activate this agent.'
      allowedTools: [Read, Edit, Bash]
```

## Adding a Skill

### Naming convention

All skills follow one of two prefixes:

| Prefix        | Meaning                                                                                  | Examples                                    |
| ------------- | ---------------------------------------------------------------------------------------- | ------------------------------------------- |
| `developer-*` | Operative used while **building** (language conventions, framework patterns, tool usage) | `developer-python`, `developer-kubernetes`  |
| `advisor-*`   | Strategic used for **decisions, reviews, design**                                        | `advisor-sre`, `advisor-cloud-architecture` |

Named exceptions with no prefix: `research-scout`, `skill-creator`, `copilot-agent-creator`, `copilot-skill-creator`.

### Steps

1. Create `content/skills/<key>/SKILL.md` Markdown body only, **no frontmatter**
2. (Optional) Add reference docs under `content/skills/<key>/references/`
3. Register it in `content/skills/metadata.yml` with `category`, `subcategory`, and tool blocks:

```yaml
skills:
  developer-example:
    category: engineering # See taxonomy below
    subcategory: build-and-quality
    copilot:
      name: developer-example
      description: 'When Copilot should invoke this skill.'
    claude:
      name: developer-example
      description: 'When Claude should invoke this skill.'
```

### Taxonomy

| Category        | Subcategories                                                                                             |
| --------------- | --------------------------------------------------------------------------------------------------------- |
| `engineering`   | `build-and-quality`, `architecture-and-platform`, `operations-and-reliability`, `technical-documentation` |
| `communication` | `professional-communication`, `editorial-and-content`, `presence-and-ux-writing`                          |
| `delivery`      | `planning-and-prioritization`, `standards-and-decision-making`, `review-and-improvement`                  |
| `reasoning`     | `ideation-and-problem-framing`, `research-and-study`, `teaching-and-speaking`                             |
| `tools`         | `editor-and-ide`, `cli-and-tool-usage`, `automation-and-environment`                                      |
| `meta`          | `skills-and-agents`                                                                                       |

### Public skill inventory

| Key                               | Category    | Subcategory               |
| --------------------------------- | ----------- | ------------------------- |
| `developer-python`                | engineering | build-and-quality         |
| `developer-shell`                 | engineering | build-and-quality         |
| `developer-javascript`            | engineering | build-and-quality         |
| `developer-typescript`            | engineering | build-and-quality         |
| `developer-framework-astro`       | engineering | build-and-quality         |
| `developer-go`                    | engineering | build-and-quality         |
| `developer-docker`                | engineering | build-and-quality         |
| `developer-microservices-and-api` | engineering | build-and-quality         |
| `developer-github-actions`        | engineering | build-and-quality         |
| `developer-terraform`             | engineering | architecture-and-platform |
| `developer-kubernetes`            | engineering | architecture-and-platform |
| `developer-github-cli`            | tools       | cli-and-tool-usage        |
| `copilot-agent-creator`           | meta        | skills-and-agents         |
| `copilot-skill-creator`           | meta        | skills-and-agents         |

### SKILL.md rules

- **No YAML frontmatter** in SKILL.md name and description come exclusively from `metadata.yml`
- Body under 500 lines; use `references/` subdirectory for overflow content
- Description in `metadata.yml` should be specific about when to trigger lean "pushy" to avoid under-triggering

## Content Repo Format

Private or supplemental content repos must follow the same layout as `content/`:

```text
your-content-repo/
├── agents/
│   ├── metadata.yml    # per-tool frontmatter
│   └── <key>.md        # agent body (no frontmatter)
└── skills/
    ├── metadata.yml    # per-tool frontmatter
    └── <skill-key>/
        └── SKILL.md    # skill body (no frontmatter)
```

Key rules:

- No frontmatter in `.md` files frontmatter comes exclusively from `metadata.yml`
- `metadata.yml` must start with a `default:` block followed by an `agents:` or `skills:` key
- Same key in both repos → content repo wins; absent key → falls back to bundled defaults

## Config Templates

Files under `config/` are copied to the workspace when the corresponding feature option is enabled:

| Source                              | Destination                   | Option                |
| ----------------------------------- | ----------------------------- | --------------------- |
| `config/claude/mcp.json`            | `.mcp.json`                   | `createFileMCP`       |
| `config/claude/settings.json`       | `.claude/settings.json`       | `createFileSetting`   |
| `config/claude/settings.local.json` | `.claude/settings.local.json` | `createFileSetting`   |
| `config/copilot/mcp-config.json`    | `.copilot/mcp-config.json`    | always                |
| `config/vscode/mcp.json`            | `.vscode/mcp.json`            | `createFileMcpVscode` |

## Local Testing

```bash
make test    # scaffold into ./test/ with all flags enabled
make clean   # remove ./test/
```
