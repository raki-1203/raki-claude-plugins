# Changelog

## [3.0.0] — 2026-04-17

### BREAKING CHANGES

- `/rakis:source-analyze` 스킬 제거. `/rakis:source-fetch` + `/rakis:wiki-ingest` 2단계로 분리.
- Vault 구조 변경: `raw/`는 이제 LLM 분석 산출물을 저장하지 않음. 모든 enrich 결과는 `raw/{type}/{slug}/notebooklm/` 하위로 격리.
- frontmatter `confidence` 필드 제거.
- frontmatter `type` 필드가 enum으로 고정: `source-summary | project | concept | entity | comparison | index`.
- `Home.md` → `wiki/overview.md` 리네이밍.
- `outputs/` 디렉토리 추가 (lint 리포트 · archive-v2 · graph-report 시점 스냅샷).

### Added

- `source-fetch` 스킬: 외부 소스를 raw/에 저장. 임계값 기반 자동 NotebookLM enrich (briefing + study-guide + mindmap).
- `migrate-v3` 스킬: v2 → v3 1회성 자동 마이그레이션 (dry-run 지원).
- `wiki-init` 스킬 v3 스키마 반영 (overview.md · outputs/ · CLAUDE.md 스키마 자동 생성).
- `wiki-query --scope project` 플래그: 현재 프로젝트 범위로 탐색 한정.
- `wiki-lint` outputs/ 저장 + overview.md 통계 섹션 자동 갱신.
- 테스트 계층: 유닛 (slug, frontmatter) + golden (마이그레이션) + smoke E2E.

### Changed

- `wiki-ingest`: raw 전수 스캔 + 증분, index.md 기반 연결. `--full` 플래그로 전체 재컴파일 가능.
- `wiki-query`: overview.md를 index.md 이전에 먼저 참조 (답변형 분기).
- graphify 호출 target: `<vault>` → `<vault>/wiki` (코드 덤프 노이즈 제거).

### Migration

기존 v2.x 사용자는 **반드시** 다음 순서로 업그레이드:

```
/rakis:setup                  # v2 감지 시 자동으로 다음 단계 안내
/rakis:migrate-v3 --dry-run   # 영향 범위 확인
/rakis:migrate-v3             # 실제 실행
rm -rf "<vault>/graphify-out/"
cd "<vault>" && /graphify wiki  # v3 풀 빌드
```

## [2.5.2] — 2026-04-14

(이전 버전은 git history 참조)
