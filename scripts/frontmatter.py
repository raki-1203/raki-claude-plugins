"""rakis v3 frontmatter 검증 및 수정 유틸.

Usage:
    python3 frontmatter.py validate <file.md>
    python3 frontmatter.py strip-confidence <file.md>
"""
from __future__ import annotations
import sys
import re
from pathlib import Path

VALID_TYPES = {
    "source-summary", "project", "concept",
    "entity", "comparison", "index",
}
REQUIRED = ["title", "type", "sources", "related", "created", "updated", "description"]

FM_PATTERN = re.compile(r"^---\n(.*?)\n---\n", re.DOTALL)


def parse(text: str) -> tuple[dict, str, int, int]:
    m = FM_PATTERN.match(text)
    if not m:
        raise ValueError("no frontmatter block")
    body = text[m.end():]
    fm_text = m.group(1)
    fm: dict[str, str] = {}
    for line in fm_text.splitlines():
        if ":" in line and not line.startswith((" ", "-", "\t")):
            key, _, val = line.partition(":")
            fm[key.strip()] = val.strip()
    return fm, body, m.start(1), m.end(1)


def validate(path: Path) -> list[str]:
    text = path.read_text(encoding="utf-8")
    try:
        fm, _, _, _ = parse(text)
    except ValueError as e:
        return [f"{path}: {e}"]
    errs: list[str] = []
    if "confidence" in fm:
        errs.append(f"{path}: confidence field is removed in v3")
    for key in REQUIRED:
        if key not in fm:
            errs.append(f"{path}: missing required field '{key}'")
    t = fm.get("type", "")
    if t and t not in VALID_TYPES:
        errs.append(f"{path}: invalid type '{t}' (expected one of {sorted(VALID_TYPES)})")
    return errs


def strip_confidence(path: Path) -> bool:
    text = path.read_text(encoding="utf-8")
    new = re.sub(r"^confidence:.*\n", "", text, flags=re.MULTILINE)
    if new != text:
        path.write_text(new, encoding="utf-8")
        return True
    return False


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: frontmatter.py {validate|strip-confidence} <file>", file=sys.stderr)
        return 2
    cmd, filearg = sys.argv[1], sys.argv[2]
    path = Path(filearg)
    if not path.exists():
        print(f"error: {path} not found", file=sys.stderr)
        return 2
    if cmd == "validate":
        errs = validate(path)
        for e in errs:
            print(e, file=sys.stderr)
        return 0 if not errs else 1
    if cmd == "strip-confidence":
        changed = strip_confidence(path)
        print("stripped" if changed else "no change")
        return 0
    print(f"error: unknown command {cmd}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
