#!/usr/bin/env python3
"""Validate a skill directory against the Agent Skills spec.

Checks:
  - SKILL.md exists at the given path
  - Frontmatter is parseable YAML between '---' markers
  - Required fields: name, description
  - name matches the directory basename
  - name follows the pattern [a-z0-9-]+ (1-64 chars, no leading/trailing/double hyphens)
  - description length 1-1024 characters
  - Optional fields, if present, conform to their constraints

Reference: https://agentskills.io/specification
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


def parse_frontmatter(text: str) -> tuple[dict, str]:
    if not text.startswith("---\n"):
        raise ValueError("missing leading '---' frontmatter marker")
    end = text.find("\n---\n", 4)
    if end == -1:
        raise ValueError("missing closing '---' frontmatter marker")
    raw = text[4:end]
    body = text[end + 5 :]

    # Minimal YAML parser — only handles top-level scalar keys + one nested
    # 'metadata:' block of scalar keys. The spec doesn't require anything fancier.
    fm: dict = {}
    cur_key = None
    for line in raw.splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        if line.startswith("  ") and cur_key is not None:
            k, _, v = line.strip().partition(":")
            if not v:
                raise ValueError(f"nested key '{k}' under '{cur_key}' has no value")
            fm.setdefault(cur_key, {})[k.strip()] = v.strip().strip('"').strip("'")
            continue
        if ":" not in line:
            raise ValueError(f"frontmatter line is not 'key: value': {line!r}")
        k, _, v = line.partition(":")
        k = k.strip()
        v = v.strip()
        if not v:
            fm[k] = {}
            cur_key = k
        else:
            fm[k] = v.strip('"').strip("'")
            cur_key = None
    return fm, body


def validate(skill_dir: Path) -> list[str]:
    errors: list[str] = []
    skill_md = skill_dir / "SKILL.md"
    if not skill_md.is_file():
        return [f"missing SKILL.md at {skill_md}"]
    try:
        fm, body = parse_frontmatter(skill_md.read_text())
    except ValueError as e:
        return [f"{skill_md}: {e}"]

    name = fm.get("name")
    if not name:
        errors.append("frontmatter: 'name' is required")
    else:
        if name != skill_dir.name:
            errors.append(
                f"frontmatter: 'name' ({name!r}) must match directory name ({skill_dir.name!r})"
            )
        if not (1 <= len(name) <= 64):
            errors.append(f"frontmatter: 'name' must be 1-64 chars (got {len(name)})")
        if not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]*[a-z0-9])?", name):
            errors.append(
                f"frontmatter: 'name' must match [a-z0-9-]+ "
                f"(no leading/trailing or consecutive hyphens): {name!r}"
            )
        if "--" in name:
            errors.append("frontmatter: 'name' must not contain consecutive hyphens")

    desc = fm.get("description")
    if not desc:
        errors.append("frontmatter: 'description' is required")
    elif not (1 <= len(desc) <= 1024):
        errors.append(
            f"frontmatter: 'description' must be 1-1024 chars (got {len(desc)})"
        )

    compat = fm.get("compatibility")
    if compat is not None and not (1 <= len(compat) <= 500):
        errors.append(
            f"frontmatter: 'compatibility' must be 1-500 chars (got {len(compat)})"
        )

    if not body.strip():
        errors.append("body is empty (skill must have instructions)")

    return errors


def main(argv: list[str]) -> int:
    if not argv:
        print("usage: validate_skill.py <skill-dir> [<skill-dir> ...]", file=sys.stderr)
        return 2
    failures = 0
    for raw in argv:
        d = Path(raw).resolve()
        errs = validate(d)
        if errs:
            failures += 1
            print(f"✗ {d}")
            for e in errs:
                print(f"  - {e}")
        else:
            print(f"✓ {d}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
