---
name: migrate-v3
description: Use once per vault to upgrade from rakis v2.x structure to v3.0 — archives raw/ LLM artifacts (graph-report/analysis.md), strips confidence frontmatter, promotes Home.md to wiki/overview.md, creates outputs/ dir, and writes a one-shot marker. Idempotent — safe to re-run, but aborts if marker exists.
---

# migrate-v3 — v2 → v3 볼트 마이그레이션

## 언제 쓰나

- v2.x rakis를 쓰던 사용자가 v3.0으로 업그레이드한 직후 1회
- 마커 파일(`.rakis-v3-migrated`)이 이미 있으면 건너뜀

## 인자

```
/rakis:migrate-v3 [--dry-run]
```

- `--dry-run`: 파일 수정 없이 변경 예정 리스트만 출력 (강력 권장)

## 실행 순서

1. **Vault 경로 탐지** (source-fetch와 동일 로직)
2. **마커 확인**: `.rakis-v3-migrated` 있으면 "이미 완료" 출력 후 종료
3. **백업 권장** — 사용자에게 다음 중 하나 실행 권고:
   - `cd "$VAULT" && git add -A && git commit -m "pre-migrate-v3 snapshot"` (git 관리 시)
   - `cp -R "$VAULT" "$VAULT-backup-v2"` (그 외)
4. **영향 범위 리포트**:
   ```bash
   uv run python3 "$PLUGIN_ROOT/scripts/migrate_v3.py" "$VAULT" --dry-run
   ```
   출력 확인 후 사용자 승인 대기
5. **실제 실행**:
   ```bash
   uv run python3 "$PLUGIN_ROOT/scripts/migrate_v3.py" "$VAULT"
   ```
6. **완료 후 안내**:
   ```
   ✓ 마이그레이션 완료.

   다음 단계:
     rm -rf "$VAULT/graphify-out/"   # v2 그래프 캐시 삭제
     cd "$VAULT" && /graphify wiki    # v3 기준 풀 빌드
   ```

## 롤백

자동 롤백 없음. 복구 옵션:
- `git reset --hard HEAD~1` (사전 git commit 했을 때)
- `cp -R "$VAULT-backup-v2/." "$VAULT/"` (사전 디렉토리 백업 했을 때)

## 멱등성

- 마커 파일이 존재하면 즉시 종료
- `--dry-run`은 파일을 수정하지 않으므로 안전

## 상세

> `references/checks.md` — Pre-flight 체크 / 경계 케이스 대응
