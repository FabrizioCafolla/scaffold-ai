## scaffold-ai

[scaffold-ai](https://github.com/FabrizioCafolla/scaffold-ai) is a devcontainer feature that assembles AI skills, agents, and hooks into the workspace at container startup. It reads content from one or two repositories, injects per-tool frontmatter, and writes output to tool-specific paths.

**Generated files must never be edited directly.** On the next scaffold run (container restart or `scaffold-ai-cmd`) they are fully regenerated — any manual change is lost. To change a skill or agent: edit the source in the content repo, not the output. Hooks are also scaffold-managed: customize them via the content repo override.

### Setup

**Devcontainer** (`devcontainer.json`):

```json
{
  "features": {
    "ghcr.io/fabriziocafolla/scaffold-ai:0": {
      "tools": "claude",
      "contentRepo": "https://github.com/your-org/your-private-skills-repo"
    }
  }
}
```

**CLI** (`cli.sh`) — for use outside a devcontainer:

```bash
GITHUB_TOKEN=$(gh auth token) bash cli.sh \
  --workspace /path/to/project \
  --tools claude \
  --content-repo https://github.com/your-org/your-private-skills-repo
```

### Assembly model

At runtime `scaffold.py` merges two sources — private repo wins on key conflicts:

1. **scaffold-ai** (public) — bundled `content/skills/`, `content/agents/`, `config/`
2. **Content repo** (private, optional) — skills, agents, and optional hooks/mcp overrides

**Two deployment modes:**

- **copy-once** — file created on first run, skipped if it already exists (preserves user edits): `settings.json`, `settings.local.json`, `.copilot/config.json`, `.mcp.json`
- **always-managed** — file overwritten on every scaffold run: skills, agents, `AGENTS.md`, `.gitignore`, hooks (`config/claude/hooks.json` → `.claude/settings.json["hooks"]`, `config/copilot/hooks.json` → `.github/hooks/hooks.json`)

### What gets deployed

| Output path                      | Source                        | Mode           |
| -------------------------------- | ----------------------------- | -------------- |
| `.mcp.json`                      | `config/mcp.json`             | copy-once      |
| `.claude/settings.json["hooks"]` | `config/claude/hooks.json`    | always-managed |
| `.claude/settings.json`          | `config/claude/settings.json` | copy-once      |
| `.github/hooks/hooks.json`       | `config/copilot/hooks.json`   | always-managed |
| `.copilot/config.json`           | `config/copilot/config.json`  | copy-once      |

### Private content repositories

| Repository                                                                    | Purpose                                                                                                     |
| ----------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| [scaffold-ai-private](https://github.com/FabrizioCafolla/scaffold-ai-private) | Personal `advisor-*` skills and agents for Fabrizio Cafolla — voice, decision patterns, communication style |

The private repo can also override config templates by placing files at:

| Private repo path    | Overrides                   |
| -------------------- | --------------------------- |
| `mcp.json`           | `config/mcp.json`           |
| `hooks/claude.json`  | `config/claude/hooks.json`  |
| `hooks/copilot.json` | `config/copilot/hooks.json` |

### Skill taxonomy

Skills are organized by category and subcategory. Every entry in `metadata.yml` carries `category` and `subcategory` fields.

| Category        | Subcategory                    | Typical prefix                   |
| --------------- | ------------------------------ | -------------------------------- |
| `engineering`   | `architecture-and-platform`    | `developer-*`, `advisor-*`       |
| `engineering`   | `build-and-quality`            | `developer-*`                    |
| `engineering`   | `technical-documentation`      | `advisor-*`                      |
| `engineering`   | `operations-and-reliability`   | `advisor-*`                      |
| `communication` | `professional-communication`   | `advisor-*`                      |
| `communication` | `editorial-and-content`        | `advisor-*`                      |
| `communication` | `presence-and-ux-writing`      | `advisor-*`                      |
| `reasoning`     | `ideation-and-problem-framing` | `advisor-*`                      |
| `reasoning`     | `research-and-study`           | `advisor-*`                      |
| `reasoning`     | `teaching-and-speaking`        | `advisor-*`                      |
| `delivery`      | `review-and-improvement`       | `advisor-*`                      |
| `meta`          | `skills-and-agents`            | `skill-creator`, `agent-creator` |
