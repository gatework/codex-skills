#!/usr/bin/env python3
"""Validate skill metadata and local links (requires PyYAML; installs nothing)."""

import argparse
from collections import Counter
from pathlib import Path
import re
from urllib.parse import unquote, urlsplit

import yaml


def anchors(text):
    counts = Counter()
    result = set()
    # Fenced code can contain headings that are not document anchors.
    text = re.sub(r"```.*?```", "", text, flags=re.S)
    for title in re.findall(r"^#{1,6}\s+(.+?)\s*#*\s*$", text, re.M):
        slug = re.sub(r"[^\w\s-]", "", title.lower()).replace(" ", "-")
        occurrence = counts[slug]
        counts[slug] += 1
        result.add(slug if occurrence == 0 else f"{slug}-{occurrence}")
    return result


def check(root):
    root = root.resolve()
    errors = []
    entry = root / "SKILL.md"
    text = entry.read_text()
    match = re.match(r"\A---\n(.*?)\n---\n", text, re.S)
    if not match:
        return ["missing frontmatter"]
    metadata = yaml.safe_load(match[1])
    if not isinstance(metadata, dict):
        return ["frontmatter must be a mapping"]
    name = metadata.get("name", "")
    if not isinstance(name, str) or not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", name) or len(name) > 64:
        errors.append("invalid skill name")
    if name != root.name:
        errors.append("name differs from package folder")
    if not isinstance(metadata.get("description"), str) or not metadata["description"].strip():
        errors.append("missing description")

    agent_file = root / "agents/openai.yaml"
    if agent_file.exists():
        agent = yaml.safe_load(agent_file.read_text())
        interface = agent.get("interface", {})
        description = interface.get("short_description", "")
        if not 25 <= len(description) <= 64:
            errors.append("short_description must be 25–64 characters")
        for key in ("icon_small", "icon_large"):
            if key in interface and not (root / interface[key]).is_file():
                errors.append(f"missing {key}: {interface[key]}")

    documents = [entry]
    for folder in ("references", "tests"):
        if (root / folder).exists():
            documents.extend(sorted((root / folder).rglob("*.md")))
    for document in documents:
        body = re.sub(r"```.*?```", "", document.read_text(), flags=re.S)
        for target in re.findall(r"!?\[[^\]]*\]\(([^)]+)\)", body):
            target = target.strip().strip("<>")
            url = urlsplit(target)
            if url.scheme or url.netloc:
                continue
            path = (document.parent / unquote(url.path)).resolve() if url.path else document
            if not path.is_relative_to(root):
                errors.append(f"{document.relative_to(root)}: link escapes package: {target}")
                continue
            if not path.exists():
                errors.append(f"{document.relative_to(root)}: missing link: {target}")
            elif url.fragment and path.suffix == ".md" and unquote(url.fragment) not in anchors(path.read_text()):
                errors.append(f"{document.relative_to(root)}: missing anchor: {target}")
    if not errors:
        print(f"PASS {name}: metadata and local links in {len(documents)} documents")
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("packages", type=Path, nargs="+")
    args = parser.parse_args()
    errors = []
    for package in args.packages:
        errors.extend(f"{package}: {message}" for message in check(package))
    if errors:
        raise SystemExit("\n".join(errors))


if __name__ == "__main__":
    main()
