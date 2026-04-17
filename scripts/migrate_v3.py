"""rakis v2 → v3 볼트 마이그레이션.

- raw/repos/*/graph-report.md · analysis.md → outputs/archive-v2/
- frontmatter에서 confidence 제거
- raw/repos/*/ 에 meta.json 없으면 생성
- Home.md → wiki/overview.md 리네이밍
- outputs/ 디렉토리 생성
- log.md에 마이그레이션 기록 한 줄 삽입

Usage:
    python3 migrate_v3.py <vault-path> [--dry-run]
"""
from __future__ import annotations
import argparse
import json
import os
import shutil
import sys
from datetime import date
from pathlib import Path


MIGRATION_DATE_ENV = "RAKIS_MIGRATION_DATE"


def today_str() -> str:
    override = os.environ.get(MIGRATION_DATE_ENV)
    return override if override else date.today().isoformat()


def archive_legacy_artifacts(vault: Path, dry_run: bool) -> int:
    count = 0
    for legacy_name in ("graph-report.md", "analysis.md"):
        for src in vault.glob(f"raw/repos/*/{legacy_name}"):
            rel = src.relative_to(vault)
            dst = vault / "outputs/archive-v2" / rel.relative_to("raw")
            if dry_run:
                print(f"MOVE  {src} → {dst}")
            else:
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.move(str(src), str(dst))
            count += 1
    return count


def ensure_meta_json(vault: Path, dry_run: bool) -> int:
    count = 0
    for repo_dir in vault.glob("raw/repos/*"):
        if not repo_dir.is_dir():
            continue
        meta = repo_dir / "meta.json"
        if meta.exists():
            continue
        source_files = [f for f in ("repomix.txt", "source.md", "source.pdf")
                        if (repo_dir / f).exists()]
        src = source_files[0] if source_files else "unknown"
        size = (repo_dir / src).stat().st_size if src != "unknown" else 0
        data = {
            "type": "repo",
            "source_url": "",
            "captured_at": "",
            "contributor": "raki-1203",
            "slug": repo_dir.name,
            "size_bytes": size,
            "source_file": src,
        }
        if dry_run:
            print(f"CREATE {meta}")
        else:
            meta.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
        count += 1
    return count


def strip_confidence_all(vault: Path, dry_run: bool) -> int:
    count = 0
    for md in list(vault.glob("wiki/**/*.md")) + list(vault.glob("raw/**/*.md")):
        text = md.read_text(encoding="utf-8")
        if "\nconfidence:" in text or text.startswith("confidence:"):
            new = "".join(
                line for line in text.splitlines(keepends=True)
                if not line.lstrip().startswith("confidence:")
            )
            if dry_run:
                print(f"STRIP {md}")
            else:
                md.write_text(new, encoding="utf-8")
            count += 1
    return count


def promote_home_to_overview(vault: Path, dry_run: bool) -> bool:
    home = vault / "Home.md"
    overview = vault / "wiki/overview.md"
    if not home.exists() or overview.exists():
        return False
    original = home.read_text(encoding="utf-8")
    d = today_str()
    new_body = (
        "---\n"
        "title: \"Vault Overview\"\n"
        "type: index\n"
        "sources: []\n"
        "related: []\n"
        f"created: {d}\n"
        f"updated: {d}\n"
        "description: \"볼트 대시보드\"\n"
        "---\n\n"
        f"{original}\n\n"
        "## 통계\n\n"
        "(wiki-lint가 자동 갱신)\n"
    )
    if dry_run:
        print(f"MOVE  {home} → {overview} (with v3 template)")
        return True
    overview.parent.mkdir(parents=True, exist_ok=True)
    overview.write_text(new_body, encoding="utf-8")
    home.unlink()
    return True


def ensure_outputs_dir(vault: Path, dry_run: bool) -> bool:
    outputs = vault / "outputs"
    if outputs.exists():
        return False
    if dry_run:
        print(f"MKDIR {outputs}")
    else:
        outputs.mkdir(parents=True, exist_ok=True)
    return True


def append_log(vault: Path, archived: int, stripped: int, dry_run: bool) -> None:
    log = vault / "log.md"
    existing = log.read_text(encoding="utf-8") if log.exists() else ""
    line = f"## [{today_str()}] migrate-v3 | v2 → v3 마이그레이션 완료 (archived {archived}, frontmatter {stripped})\n"
    new = line + existing
    if dry_run:
        print(f"PREPEND {log}: {line.rstrip()}")
    else:
        log.write_text(new, encoding="utf-8")


def write_marker(vault: Path, dry_run: bool) -> None:
    marker = vault / ".rakis-v3-migrated"
    if marker.exists():
        return
    if dry_run:
        print(f"TOUCH {marker}")
    else:
        marker.write_text(today_str() + "\n", encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("vault")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    vault = Path(args.vault).expanduser().resolve()
    if not vault.exists():
        print(f"error: {vault} not found", file=sys.stderr)
        return 2
    if (vault / ".rakis-v3-migrated").exists():
        print("already migrated — marker present, aborting", file=sys.stderr)
        return 0

    archived = archive_legacy_artifacts(vault, args.dry_run)
    ensure_meta_json(vault, args.dry_run)
    stripped = strip_confidence_all(vault, args.dry_run)
    promote_home_to_overview(vault, args.dry_run)
    ensure_outputs_dir(vault, args.dry_run)
    append_log(vault, archived, stripped, args.dry_run)
    if not args.dry_run:
        write_marker(vault, args.dry_run)

    if args.dry_run:
        print("\nDRY RUN — no files modified")
    else:
        print(f"\nMigration complete: archived {archived}, stripped confidence from {stripped} files")
        print("\nNext steps:")
        print(f'  rm -rf "{vault}/graphify-out/"   # v2 그래프 캐시 삭제')
        print(f'  cd "{vault}" && /graphify wiki    # v3 풀 빌드')
    return 0


if __name__ == "__main__":
    sys.exit(main())
