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
│   ├── mcp.wikictl.json        # Gated wikictl MCP entry (merged into .mcp.json when wikictl is enabled)
│   ├── config.default.yaml     # Starter .scaffold-ai/config.yaml template (copy-once)
│   ├── claude/
│   │   ├── hooks.json          # Claude hooks template (always-managed; installRtk injects the rtk hook here)
│   │   ├── settings.json       # Claude settings (copy-once, includes statusLine)
│   │   ├── settings.local.json # Claude local settings (copy-once, gitignored)
│   │   └── statusline.sh       # Claude statusline (copy-once → .claude/statusline.sh)
│   └── copilot/
│       ├── hooks.json          # Copilot hooks template (always-managed)
│       └── config.json         # Copilot config (copy-once)
├── wikictl/                    # wikictl package source (fetched at runtime, never vendored into the feature)
│   ├── pyproject.toml          # Standalone pip-installable package
│   └── src/wikictl/            # CLI + MCP server + render-only web UI
├── scaffold.py                 # Main Python scaffolder
├── install.sh                  # Devcontainer entrypoint — minimal, generates the scaffoldai launcher only
├── cli.sh                      # Single implementation: install/sync subcommands, used by devcontainer AND curl
├── Makefile                    # Local test commands
└── devcontainer-feature.json   # Feature manifest (boolean options only)
```

## How It Works

Nothing about scaffold-ai is vendored into the published feature. `cli.sh` is the single implementation of both the devcontainer path and the standalone curl path; on every run it fetches (or, for local dev, uses `--local-path` against) `scaffold.py` + `content/` + `wikictl/` from this repo at a `--ref`, pinned to the feature version for the devcontainer.

**Devcontainer path:**

1. `install.sh` runs at image build: verifies Python, reads the feature `version` from `devcontainer-feature.json`, and generates `/usr/local/bin/scaffoldai` — a small launcher with that version baked in as `REF`. It installs no binary and vendors nothing.
2. `postCreateCommand: scaffoldai install` fetches `cli.sh`@REF and runs its `install` subcommand: resolves `.scaffold-ai/config.yaml`, installs enabled binaries, runs `scaffold.py`.
3. `postStartCommand: scaffoldai sync` fetches `cli.sh`@REF and runs `sync`: a hash-check that only re-scaffolds when content changed, skipping binary installs.
4. Both `scaffoldai` invocations `|| exit 0` — a failed fetch (offline, GitHub outage) never blocks container start.

**CLI path:**

1. `cli.sh` is fetched via `curl | bash` (defaults to the `install` subcommand if none given)
2. It clones scaffold-ai at `--ref` (default `main`; `--local-path DIR` uses a local checkout instead — required to test uncommitted changes)
3. It resolves `.scaffold-ai/config.yaml` in the target workspace on top of CLI flags, installs enabled binaries, optionally clones a `--content-repo`, then runs `scaffold.py`

**Configuration precedence:** for every setting, `.scaffold-ai/config.yaml` (workspace) > feature boolean option / CLI flag (baked into the `scaffoldai` launcher, or passed directly to `cli.sh`) > built-in default. The workspace config is copy-once seeded from whatever resolved before it existed.

**Optional components (gated by `.scaffold-ai/config.yaml` → `install.*`, or the matching feature option / CLI flag):**

- **RTK** (`install.rtk` / `installRtk` / `--no-rtk`, default on) — token-compressing Bash `PreToolUse` hook.
- **Headroom** (`install.headroom` / `installHeadroom` / `--no-headroom`, default on) — request-level context compression CLI; installed but inactive until `headroom wrap claude`.
- **wikictl** (`install.wikictl` / `installWikictl` / `--wikictl`, default **off**) — file-based AI memory layer. The source lives at `wikictl/` in this repo, fetched at the pinned ref and installed with `uv tool install "${SCAFFOLD_SRC}/wikictl[serve]"`; warns and continues if `uv` is missing. `cli.sh` passes `--install-wikictl` to `scaffold.py`, which then merges the gated `config/mcp.wikictl.json` server entry into `.mcp.json`. The `wikictl-*` skills live in `content/skills/` and deploy unconditionally (like `caveman`).
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
