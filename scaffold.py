#!/usr/bin/env python3
"""Scaffold AI assembles AI agent/skill assets with tool-specific frontmatter into a workspace.

Reads content files (pure Markdown, no frontmatter) from content/ and injects
per-tool metadata from config/agents.yml and config/skills.yml at runtime.
Supports merging additional content from a pre-cloned external repository.
"""
import argparse
import hashlib
import json
import pathlib
import re
import shutil
import subprocess
import sys

import yaml


class _Dumper(yaml.Dumper):
    pass


_Dumper.add_representer(
    list,
    lambda dumper, data: dumper.represent_sequence("tag:yaml.org,2002:seq", data, flow_style=True),
)


def _write_with_frontmatter(dest: pathlib.Path, meta: dict, body: str) -> None:
    dest.write_text(f"---\n{yaml.dump(meta, Dumper=_Dumper, default_flow_style=False, allow_unicode=True, sort_keys=False, width=float('inf'))}---\n\n{body}")


def _copy_extra(feature_dir: pathlib.Path, ws: pathlib.Path, ef: dict) -> None:
    src = feature_dir / ef["source"]
    dst = ws / ef["dest"]
    if not src.exists():
        print(f"  │  [WARN] missing extra file: {src}")
        return
    if dst.exists():
        print(f"  │  [skip] {dst.relative_to(ws)}  (already exists)")
        return
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)
    print(f"  │  [copy] {src.name}  →  {dst.relative_to(ws)}")


def _update_agents_md(
    ws: pathlib.Path,
    feature_dir: pathlib.Path,
    content_repo_path: pathlib.Path | None,
    skill_keys: list[str],
    agent_keys: list[str],
) -> None:
    """Inject or update the scaffold-ai managed block in AGENTS.md."""
    agents_md = ws / "AGENTS.md"
    start = "<!-- [scaffold-ai:START] managed by scaffold-ai, do not edit manually -->"
    end = "<!-- [scaffold-ai:END] -->"

    parts: list[str] = []

    public_content = feature_dir / "content" / "agents.scaffold-ai.md"
    if public_content.exists():
        parts.append(public_content.read_text().strip())

    if content_repo_path and content_repo_path.exists():
        private_content = content_repo_path / "agents.scaffold-ai.md"
        if private_content.exists():
            parts.append(private_content.read_text().strip())

    if skill_keys:
        skill_list = "\n".join(f"- `{k}`" for k in skill_keys)
        parts.append(f"### Installed skills\n\n{skill_list}")

    if agent_keys:
        agent_list = "\n".join(f"- `{k}`" for k in agent_keys)
        parts.append(f"### Installed agents\n\n{agent_list}")

    block = start + "\n\n" + "\n\n".join(parts) + "\n\n" + end

    if agents_md.exists():
        content = agents_md.read_text()
        if start in content:
            new_content = re.sub(
                rf"{re.escape(start)}.*?{re.escape(end)}",
                block,
                content,
                flags=re.DOTALL,
            )
            agents_md.write_text(new_content)
            print(f"  [agents.md] updated managed block")
        else:
            sep = "\n" if content.endswith("\n") else "\n\n"
            agents_md.write_text(content + sep + block + "\n")
            print(f"  [agents.md] appended managed block to existing AGENTS.md")
    else:
        agents_md.write_text(block + "\n")
        print(f"  [agents.md] created AGENTS.md with scaffold-ai block")


def _update_gitignore(ws: pathlib.Path, entries: list[str]) -> None:
    gitignore = ws / ".gitignore"
    start = "# [START] Scaffold AI"
    end = "# [END] Scaffold AI"
    block = start + "\n" + "\n".join(entries) + "\n" + end

    if gitignore.exists():
        content = gitignore.read_text()
        if start in content:
            new_content = re.sub(
                rf"{re.escape(start)}.*?{re.escape(end)}",
                block,
                content,
                flags=re.DOTALL,
            )
            gitignore.write_text(new_content)
            print(f"  [gitignore] updated block in .gitignore")
        else:
            sep = "\n" if content.endswith("\n") else "\n\n"
            gitignore.write_text(content + sep + block + "\n")
            print(f"  [gitignore] appended block to .gitignore")
    else:
        gitignore.write_text(block + "\n")
        print(f"  [gitignore] created .gitignore with scaffold block")


def _compute_content_hash(
    feature_dir: pathlib.Path,
    content_repo_path: pathlib.Path | None,
    content_repo_sha: str | None = None,
) -> str:
    """Compute a deterministic hash of the scaffold-ai identity + content repo identity.

    scaffold-ai identity: HEAD SHA when available (git clone), version string as fallback
    (devcontainer feature installed from tarball, no .git dir).

    Content repo identity: pre-computed SHA string (from git ls-remote, avoids a clone)
    takes precedence over local git; both are equivalent since they represent the same commit.
    """
    h = hashlib.sha256()

    try:
        sha = subprocess.check_output(
            ["git", "-C", str(feature_dir), "rev-parse", "HEAD"],
            stderr=subprocess.DEVNULL,
        ).strip()
        h.update(sha)
    except subprocess.CalledProcessError:
        version_file = feature_dir / "devcontainer-feature.json"
        if version_file.exists():
            data = json.loads(version_file.read_text())
            h.update(data.get("version", "unknown").encode())

    if content_repo_sha:
        h.update(content_repo_sha.strip().encode())
    elif content_repo_path and content_repo_path.exists():
        try:
            sha = subprocess.check_output(
                ["git", "-C", str(content_repo_path), "rev-parse", "HEAD"],
                stderr=subprocess.DEVNULL,
            ).strip()
            h.update(sha)
        except subprocess.CalledProcessError:
            pass

    return h.hexdigest()


def _read_lock(ws: pathlib.Path) -> str:
    lock = ws / ".scaffold-ai.lock"
    return lock.read_text().strip() if lock.exists() else ""


def _write_lock(ws: pathlib.Path, digest: str) -> None:
    (ws / ".scaffold-ai.lock").write_text(digest + "\n")


_MANIFEST_FILE = ".scaffold-ai.manifest.json"


def _read_manifest(ws: pathlib.Path) -> dict:
    p = ws / _MANIFEST_FILE
    if not p.exists():
        return {}
    try:
        return json.loads(p.read_text())
    except (json.JSONDecodeError, OSError):
        return {}


def _write_manifest(ws: pathlib.Path, manifest: dict) -> None:
    (ws / _MANIFEST_FILE).write_text(json.dumps(manifest, indent=2) + "\n")


def _cleanup_stale(
    ws: pathlib.Path,
    tool: str,
    tool_paths: dict,
    current_skill_keys: set[str],
    current_agent_keys: set[str],
    manifest: dict,
) -> None:
    """Remove skill/agent dirs and files that were managed in a previous run but are no longer in metadata."""
    prev = manifest.get(tool, {})
    base = ws / tool_paths["base_dir"]

    stale_skills = set(prev.get("skills", [])) - current_skill_keys
    if stale_skills:
        skills_base = base / tool_paths["skills"]["dir"]
        for key in sorted(stale_skills):
            stale_dir = skills_base / key
            if stale_dir.exists():
                shutil.rmtree(stale_dir)
                print(f"  │  [cleanup] removed stale skill dir: {stale_dir.relative_to(ws)}/")

    stale_agents = set(prev.get("agents", [])) - current_agent_keys
    if stale_agents:
        agents_dir = base / tool_paths["agents"]["dir"]
        suffix = tool_paths["agents"]["suffix"]
        for key in sorted(stale_agents):
            stale_file = agents_dir / f"{key}{suffix}"
            if stale_file.exists():
                stale_file.unlink()
                print(f"  │  [cleanup] removed stale agent file: {stale_file.relative_to(ws)}")


def _load_content(
    feature_dir: pathlib.Path,
    install_defaults: bool,
    content_repo_path: pathlib.Path | None,
) -> tuple[dict, dict, dict]:
    """Return (paths_cfg, agents_cfg, skills_cfg) merged from defaults and/or content repo."""

    def _load_yaml(p: pathlib.Path) -> dict:
        return yaml.safe_load(p.read_text()) if p.exists() else {}

    paths_cfg: dict = _load_yaml(feature_dir / "content" / "paths.yml") if install_defaults else {}
    agents_cfg: dict = _load_yaml(feature_dir / "content" / "agents" / "metadata.yml") if install_defaults else {"agents": {}, "default": {}}
    skills_cfg: dict = _load_yaml(feature_dir / "content" / "skills" / "metadata.yml") if install_defaults else {"skills": {}, "default": {}}

    if content_repo_path and content_repo_path.exists():
        remote_paths = _load_yaml(content_repo_path / "paths.yml")
        for tool, cfg in remote_paths.items():
            if tool not in paths_cfg:
                paths_cfg[tool] = cfg

        remote_agents = _load_yaml(content_repo_path / "agents" / "metadata.yml")
        if not paths_cfg and remote_paths:
            paths_cfg = remote_paths
        for key, val in remote_agents.get("agents", {}).items():
            agents_cfg.setdefault("agents", {})[key] = val

        remote_skills = _load_yaml(content_repo_path / "skills" / "metadata.yml")
        for key, val in remote_skills.get("skills", {}).items():
            skills_cfg.setdefault("skills", {})[key] = val

    return paths_cfg, agents_cfg, skills_cfg


def _resolve_content_file(
    feature_dir: pathlib.Path,
    content_repo_path: pathlib.Path | None,
    relative: str,
) -> pathlib.Path | None:
    """Find a content file, preferring the content repo over bundled defaults."""
    if content_repo_path:
        remote = content_repo_path / relative
        if remote.exists():
            return remote
    bundled = feature_dir / "content" / relative
    return bundled if bundled.exists() else None


def scaffold(
    workspace: str,
    tools: list[str],
    create_file_mcp: bool,
    create_file_mcp_vscode: bool,
    create_file_setting: bool,
    update_gitignore: bool,
    install_defaults: bool,
    content_repo_local_path: str | None,
    content_repo_sha: str | None = None,
) -> None:
    feature_dir = pathlib.Path(__file__).parent
    ws = pathlib.Path(workspace)
    content_repo_path = pathlib.Path(content_repo_local_path) if content_repo_local_path else None

    # --- Hash check: skip if nothing changed ---
    digest = _compute_content_hash(feature_dir, content_repo_path, content_repo_sha)
    if _read_lock(ws) == digest:
        print(f"\n scaffold-ai  no changes detected skipping (workspace: {ws})\n")
        return

    paths_cfg, agents_cfg, skills_cfg = _load_content(feature_dir, install_defaults, content_repo_path)

    print(f"\n scaffold-ai  workspace: {ws}")
    enabled = ", ".join(tools) if tools else "none"
    flags = (
        f"mcp={'yes' if create_file_mcp else 'no'}  "
        f"mcp-vscode={'yes' if create_file_mcp_vscode else 'no'}  "
        f"settings={'yes' if create_file_setting else 'no'}  "
        f"gitignore={'yes' if update_gitignore else 'no'}  "
        f"defaults={'yes' if install_defaults else 'no'}"
    )
    print(f"  tools: {enabled}  |  {flags}\n")

    manifest = _read_manifest(ws)
    new_manifest: dict = {}
    gitignore_entries: list[str] = [".scaffold-ai.lock", _MANIFEST_FILE]

    for tool in tools:
        if tool not in paths_cfg:
            print(f"  [WARN] unknown tool '{tool}' no paths config found, skipping.")
            continue

        tool_paths = paths_cfg[tool]
        base = ws / tool_paths["base_dir"]
        extra_files = tool_paths.get("extra_files", {})

        print(f"  ┌─ [{tool.upper()}]  base: {base}")

        current_skill_keys = {k for k, v in skills_cfg.get("skills", {}).items() if tool in v}
        current_agent_keys = {k for k, v in agents_cfg.get("agents", {}).items() if tool in v}
        _cleanup_stale(ws, tool, tool_paths, current_skill_keys, current_agent_keys, manifest)
        new_manifest[tool] = {"skills": sorted(current_skill_keys), "agents": sorted(current_agent_keys)}

        # --- Agents ---
        # Only overwrite files for managed agents — do not wipe the entire directory.
        # Unmanaged agent files (created outside scaffold-ai) are preserved.
        agents_dir = base / tool_paths["agents"]["dir"]
        agents_dir.mkdir(parents=True, exist_ok=True)
        suffix = tool_paths["agents"]["suffix"]

        agent_keys = list(agents_cfg.get("agents", {}).keys())
        print(f"  │  agents ({len(agent_keys)}): {', '.join(agent_keys) or 'none'}")
        agent_defaults = agents_cfg.get("default", {}).get(tool, {}) or {}
        for key, agent in agents_cfg.get("agents", {}).items():
            if tool not in agent:
                continue
            meta = {**agent_defaults, **agent[tool]}
            out = agents_dir / f"{key}{suffix}"
            gitignore_entries.append(str(out.relative_to(ws)))
            content_file = _resolve_content_file(feature_dir, content_repo_path, f"agents/{key}.md")
            if not content_file:
                print(f"  │  [WARN] missing content for agent '{key}'")
                continue
            body = content_file.read_text()
            _write_with_frontmatter(out, meta, body)

        # --- Skills ---
        # Only replace directories for managed skills — do not wipe the entire base.
        # Unmanaged skill directories (created outside scaffold-ai) are preserved.
        skills_base = base / tool_paths["skills"]["dir"]
        skills_base.mkdir(parents=True, exist_ok=True)
        filename = tool_paths["skills"]["filename"]

        skill_keys = list(skills_cfg.get("skills", {}).keys())
        print(f"  │  skills  ({len(skill_keys)}): {', '.join(skill_keys) or 'none'}")
        skill_defaults = skills_cfg.get("default", {}).get(tool, {}) or {}
        for key, skill in skills_cfg.get("skills", {}).items():
            if tool not in skill:
                continue
            meta = {**skill_defaults, **skill[tool]}
            skill_dir = skills_base / key
            shutil.rmtree(skill_dir, ignore_errors=True)
            skill_dir.mkdir(parents=True, exist_ok=True)
            gitignore_entries.append(str(skill_dir.relative_to(ws)) + "/")

            content_file = _resolve_content_file(feature_dir, content_repo_path, f"skills/{key}/{filename}")
            if not content_file:
                print(f"  │  [WARN] missing content for skill '{key}'")
                continue
            body = content_file.read_text()
            out = skill_dir / filename
            _write_with_frontmatter(out, meta, body)

            refs_src = (content_repo_path or feature_dir / "content") / "skills" / key / "references"
            if not refs_src.exists():
                refs_src = feature_dir / "content" / "skills" / key / "references"
            if refs_src.exists():
                shutil.copytree(refs_src, skill_dir / "references", dirs_exist_ok=True)

        # --- MCP file ---
        if create_file_mcp:
            for ef in extra_files.get("mcp", []):
                _copy_extra(feature_dir, ws, ef)
                if ef.get("ignore", False):
                    gitignore_entries.append(ef["dest"])

        # --- Settings files ---
        if create_file_setting:
            for ef in extra_files.get("settings", []):
                _copy_extra(feature_dir, ws, ef)
                if ef.get("ignore", False):
                    gitignore_entries.append(ef["dest"])

        print(f"  └─ [{tool.upper()}] done\n")

    # --- VSCode MCP (not tool-specific) ---
    if create_file_mcp_vscode:
        vscode_mcp_src = feature_dir / "config" / "vscode" / "mcp.json"
        vscode_mcp_dst = ws / ".vscode" / "mcp.json"
        if vscode_mcp_dst.exists():
            print(f"  [skip] .vscode/mcp.json  (already exists)")
        elif vscode_mcp_src.exists():
            vscode_mcp_dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(vscode_mcp_src, vscode_mcp_dst)
            print(f"  [copy] config/vscode/mcp.json  →  .vscode/mcp.json")
        else:
            print(f"  [WARN] missing config/vscode/mcp.json template")

    if update_gitignore and gitignore_entries:
        _update_gitignore(ws, list(dict.fromkeys(gitignore_entries)))

    all_skill_keys = list(skills_cfg.get("skills", {}).keys())
    all_agent_keys = list(agents_cfg.get("agents", {}).keys())
    _update_agents_md(ws, feature_dir, content_repo_path, all_skill_keys, all_agent_keys)

    _write_manifest(ws, new_manifest)
    _write_lock(ws, digest)
    print(f"  scaffold-ai complete\n")


def _flag(value: str) -> bool:
    return value.lower() == "true"


def _parse_tools(value: str) -> list[str]:
    """Parse comma-separated tools string into a list."""
    return [t.strip() for t in value.split(",") if t.strip()]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Scaffold AI: assemble AI assets with tool-specific frontmatter."
    )
    parser.add_argument("--workspace", required=True, help="Target workspace directory")
    parser.add_argument("--tools", default="claude", help="Comma-separated tools to scaffold (e.g. claude,copilot)")
    parser.add_argument("--create-file-mcp", default="true", help="Create MCP config file (true/false)")
    parser.add_argument("--create-file-mcp-vscode", default="false", help="Create .vscode/mcp.json (true/false)")
    parser.add_argument("--create-file-setting", default="true", help="Create settings files (true/false)")
    parser.add_argument("--update-gitignore", default="true", help="Add scaffold paths to .gitignore (true/false)")
    parser.add_argument("--install-defaults", default="true", help="Install bundled default content (true/false)")
    parser.add_argument("--content-repo-local-path", default="", help="Local path to pre-cloned content repo")
    parser.add_argument("--content-repo-sha", default="", help="Pre-computed HEAD SHA of the content repo (from git ls-remote); skips a local git call")
    parser.add_argument("--check-only", action="store_true", help="Compare content hash against lock file without running scaffold; exits 0 if up-to-date, 1 if stale")
    args = parser.parse_args()

    if args.check_only:
        _feature_dir = pathlib.Path(__file__).parent
        _ws = pathlib.Path(args.workspace)
        _digest = _compute_content_hash(_feature_dir, None, content_repo_sha=args.content_repo_sha or None)
        if _read_lock(_ws) == _digest:
            print(f"\n scaffold-ai  no changes detected, skipping (workspace: {_ws})\n")
            sys.exit(0)
        sys.exit(1)

    scaffold(
        workspace=args.workspace,
        tools=_parse_tools(args.tools),
        create_file_mcp=_flag(args.create_file_mcp),
        create_file_mcp_vscode=_flag(args.create_file_mcp_vscode),
        create_file_setting=_flag(args.create_file_setting),
        update_gitignore=_flag(args.update_gitignore),
        install_defaults=_flag(args.install_defaults),
        content_repo_local_path=args.content_repo_local_path or None,
        content_repo_sha=args.content_repo_sha or None,
    )
