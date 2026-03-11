#!/usr/bin/env python3
"""Scaffold AI — assembles AI agent/skill assets with tool-specific frontmatter into a workspace.

Reads content files (pure Markdown, no frontmatter) from content/ and injects
per-tool metadata from config/agents.yml and config/skills.yml at runtime.
Optional flags control creation of .mcp.json and Claude settings files.
"""
import argparse
import pathlib
import re
import shutil

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


def scaffold(
    workspace: str,
    tools: list[str],
    create_file_mcp: bool,
    create_file_setting: bool,
    update_gitignore: bool,
) -> None:
    feature_dir = pathlib.Path(__file__).parent

    paths_cfg: dict = yaml.safe_load((feature_dir / "content" / "paths.yml").read_text())
    agents_cfg: dict = yaml.safe_load((feature_dir / "content" / "agents" / "metadata.yml").read_text())
    skills_cfg: dict = yaml.safe_load((feature_dir / "content" / "skills" / "metadata.yml").read_text())

    ws = pathlib.Path(workspace)

    print(f"\n scaffold-ai  workspace: {ws}")
    enabled = ", ".join(tools) if tools else "none"
    flags = f"mcp={'yes' if create_file_mcp else 'no'}  settings={'yes' if create_file_setting else 'no'}  gitignore={'yes' if update_gitignore else 'no'}"
    print(f"  tools: {enabled}  |  {flags}\n")

    gitignore_entries: list[str] = []

    for tool in tools:
        tool_paths = paths_cfg[tool]
        base = ws / tool_paths["base_dir"]
        extra_files = tool_paths.get("extra_files", {})

        print(f"  ┌─ [{tool.upper()}]  base: {base}")

        # --- Agents ---
        agents_dir = base / tool_paths["agents"]["dir"]
        shutil.rmtree(agents_dir, ignore_errors=True)
        agents_dir.mkdir(parents=True, exist_ok=True)
        suffix = tool_paths["agents"]["suffix"]

        agent_keys = list(agents_cfg["agents"].keys())
        print(f"  │  agents ({len(agent_keys)}): {', '.join(agent_keys)}")
        agent_defaults = agents_cfg.get("default", {}).get(tool, {}) or {}
        for key, agent in agents_cfg["agents"].items():
            meta = {**agent_defaults, **agent[tool]}
            content_file = feature_dir / "content" / "agents" / f"{key}.md"
            if not content_file.exists():
                print(f"  │  [WARN] missing content for agent '{key}': {content_file}")
                continue
            body = content_file.read_text()
            out = agents_dir / f"{key}{suffix}"
            _write_with_frontmatter(out, meta, body)
            gitignore_entries.append(str(out.relative_to(ws)))

        # --- Skills ---
        skills_base = base / tool_paths["skills"]["dir"]
        shutil.rmtree(skills_base, ignore_errors=True)
        filename = tool_paths["skills"]["filename"]

        skill_keys = list(skills_cfg["skills"].keys())
        print(f"  │  skills  ({len(skill_keys)}): {', '.join(skill_keys)}")
        skill_defaults = skills_cfg.get("default", {}).get(tool, {}) or {}
        for key, skill in skills_cfg["skills"].items():
            meta = {**skill_defaults, **skill[tool]}
            skill_dir = skills_base / key
            skill_dir.mkdir(parents=True, exist_ok=True)

            content_file = feature_dir / "content" / "skills" / key / filename
            if not content_file.exists():
                print(f"  │  [WARN] missing content for skill '{key}': {content_file}")
                continue
            body = content_file.read_text()
            out = skill_dir / filename
            _write_with_frontmatter(out, meta, body)

            refs_src = feature_dir / "content" / "skills" / key / "references"
            if refs_src.exists():
                shutil.copytree(refs_src, skill_dir / "references", dirs_exist_ok=True)
            gitignore_entries.append(str(skill_dir.relative_to(ws)) + "/")

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

    if update_gitignore and gitignore_entries:
        _update_gitignore(ws, list(dict.fromkeys(gitignore_entries)))

    print(f"  scaffold-ai complete\n")


def _flag(value: str) -> bool:
    return value.lower() == "true"


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Scaffold AI: assemble AI assets with tool-specific frontmatter."
    )
    parser.add_argument("--workspace", required=True, help="Target workspace directory")
    parser.add_argument("--copilot", default="true", help="Enable Copilot assets (true/false)")
    parser.add_argument("--claude", default="true", help="Enable Claude assets (true/false)")
    parser.add_argument("--create-file-mcp", default="true", help="Create .mcp.json (true/false)")
    parser.add_argument("--create-file-setting", default="true", help="Create Claude settings files (true/false)")
    parser.add_argument("--update-gitignore", default="true", help="Add scaffold paths to .gitignore (true/false)")
    args = parser.parse_args()

    enabled_tools = [
        tool
        for tool, flag in [("copilot", args.copilot), ("claude", args.claude)]
        if _flag(flag)
    ]

    scaffold(
        workspace=args.workspace,
        tools=enabled_tools,
        create_file_mcp=_flag(args.create_file_mcp),
        create_file_setting=_flag(args.create_file_setting),
        update_gitignore=_flag(args.update_gitignore),
    )
