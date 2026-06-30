# Scaffold AI Developer Guide

scaffold-ai is a devcontainer feature and standalone CLI that scaffolds AI agent and skill assets (Claude, GitHub Copilot) into a workspace. Content is tool-agnostic Markdown; per-tool YAML frontmatter is injected at scaffold time.

## Repository Layout

```
scaffold-ai/
├── content/                    # Tool-agnostic Markdown content
│   ├── paths.yml               # Output paths per tool (copilot / claude)
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
│   ├── mcp.json                # Shared .mcp.json template (Claude, VS Code, Copilot)
│   ├── mcp.wikictl.json        # Gated wikictl MCP entry (merged into .mcp.json when installWikictl)
│   ├── claude/
│   │   ├── hooks.json          # Claude hooks template (always-managed; installRtk injects the rtk hook here)
│   │   ├── settings.json       # Claude settings (copy-once, includes statusLine)
│   │   ├── settings.local.json # Claude local settings (copy-once, gitignored)
│   │   └── statusline.sh       # Claude statusline (copy-once → .claude/statusline.sh)
│   └── copilot/
│       ├── hooks.json          # Copilot hooks template (always-managed)
│       └── config.json         # Copilot config (copy-once)
├── wikictl/                    # Vendored wikictl package (installed when installWikictl)
│   ├── pyproject.toml          # Standalone pip-installable package
│   └── src/wikictl/            # CLI + MCP server + render-only web UI
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
2. It clones scaffold-ai (or the specified `--ref`; with `--local-path DIR` it uses a local checkout instead — required to test uncommitted changes, since the default always pulls from GitHub), optionally clones a `--content-repo`, then runs `scaffold.py` directly
3. By default it also installs the RTK binary and injects the `rtk hook claude` PreToolUse entry into the staged Claude hooks template before scaffolding (opt out with `--no-rtk`; mirrors the devcontainer `installRtk` default)

**Optional components (gated install flags):**

- **RTK** (`installRtk` / `--no-rtk`, default on) — token-compressing Bash `PreToolUse` hook.
- **Headroom** (`installHeadroom`, default on) — request-level context compression CLI; installed but inactive until `headroom wrap claude`.
- **wikictl** (`installWikictl` / `--wikictl`, default **off**) — file-based AI memory layer. The source is vendored at `wikictl/` and installed with `uv tool install "${ASSETS_DIR}/wikictl[serve]"` (devcontainer) / `"${TEMP_DIR}/scaffold-ai/wikictl[serve]"` (CLI); warns and continues if `uv` is missing. `install.sh`/`cli.sh` pass `--install-wikictl` to `scaffold.py`, which then merges the gated `config/mcp.wikictl.json` server entry into `.mcp.json`. The `wikictl-*` skills live in `content/skills/` and deploy unconditionally (like `caveman`).
  - Agents using wikictl read the metadata-first protocol from the MCP server itself: scan with `list_entries`/`search_entries` (metadata only), evaluate relevance from `description`/`tags`, then `read_entry` only what's needed. `get_schema` returns the entry metadata contract (field names, types, required/optional, validation rules) and works on an empty wiki.

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
| `wikictl`                         | reasoning   | research-and-study        |
| `wikictl-read`                    | reasoning   | research-and-study        |
| `wikictl-create`                  | reasoning   | research-and-study        |
| `wikictl-edit`                    | reasoning   | research-and-study        |
| `wikictl-mcp`                     | reasoning   | research-and-study        |
| `copilot-agent-creator`           | meta        | skills-and-agents         |
| `copilot-skill-creator`           | meta        | skills-and-agents         |

### SKILL.md rules

- **No YAML frontmatter** in SKILL.md name and description come exclusively from `metadata.yml`
- Body under 500 lines; use `references/` subdirectory for overflow content
- Description in `metadata.yml` should be specific about when to trigger lean "pushy" to avoid under-triggering

## Content Repo Format

Private or supplemental content repos can contain:

```text
your-content-repo/
├── agents/
│   ├── metadata.yml    # per-tool frontmatter
│   └── <key>.md        # agent body (no frontmatter)
├── skills/
│   ├── metadata.yml    # per-tool frontmatter
│   └── <skill-key>/
│       └── SKILL.md    # skill body (no frontmatter)
├── hooks/              # optional config overrides
│   ├── claude.json     # full replacement for config/claude/hooks.json
│   └── copilot.json    # full replacement for config/copilot/hooks.json
└── mcp.json            # optional: full replacement for config/mcp.json
```

Key rules:

- No frontmatter in `.md` files — frontmatter comes exclusively from `metadata.yml`
- `metadata.yml` must start with a `default:` block followed by an `agents:` or `skills:` key
- Same key in both repos → content repo wins; absent key → falls back to bundled defaults
- `hooks/` and `mcp.json` are full replacements, not merged with defaults

## Config Templates

Files under `config/` are deployed to the workspace based on the active options:

| Source                              | Destination                   | Option              | Behavior       |
| ----------------------------------- | ----------------------------- | ------------------- | -------------- |
| `config/mcp.json`                   | `.mcp.json`                   | `createFileMCP`     | copy-once      |
| `config/claude/hooks.json`          | `.claude/settings.json[hooks]`| `createFileHooks`   | always-managed |
| `config/claude/settings.json`       | `.claude/settings.json`       | `createFileSetting` | copy-once      |
| `config/claude/settings.local.json` | `.claude/settings.local.json` | `createFileSetting` | copy-once      |
| `config/claude/statusline.sh`       | `.claude/statusline.sh`       | `createFileSetting` | copy-once      |
| `config/copilot/hooks.json`         | `.github/hooks/hooks.json`    | `createFileHooks`   | always-managed |
| `config/copilot/config.json`        | `.copilot/config.json`        | `createFileSetting` | copy-once      |

**copy-once**: file is created on first scaffold run; skipped if destination already exists (preserves user edits).

**always-managed**: file is written on every scaffold run regardless of whether it exists. Hooks are scaffold-owned — customize them via the content repo override, not by editing the deployed file directly.

### Content repo overrides

A private content repo can override config templates by placing files at these paths:

| Content repo path    | Overrides                   |
| -------------------- | --------------------------- |
| `mcp.json`           | `config/mcp.json`           |
| `hooks/claude.json`  | `config/claude/hooks.json`  |
| `hooks/copilot.json` | `config/copilot/hooks.json` |

## Local Testing

```bash
just test               # scaffold Claude only into ./test/
just test-both          # scaffold Claude + Copilot with hooks
just test-hooks         # verify hooks override from a simulated private repo
just test-content-repo  # verify private skills from a simulated content repo
just test-idempotent    # run twice — second run must be a no-op
just clean              # remove ./test/
```
