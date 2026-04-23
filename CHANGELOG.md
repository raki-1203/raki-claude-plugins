# Changelog

## [3.4.1] — 2026-04-23

### Changed

- `weekly-report` 출력 포맷 개선 (v1.1.0):
  - 이번주 성과는 주제 단위로 묶어 bullet 1개 + PR 번호 나열로 압축 (20개 PR도 5~8 bullet로 수렴).
  - `다음주 계획 후보` → 세 개 섹션으로 분리:
    - `진행중 항목`: open PR/이슈 자동 + `— 목표: ____` 빈칸
    - `다음주 계획`: 빈 체크박스 3개 (수동 작성)
    - `이번주 일정`: 출장·외근·회의 등 수동 작성 안내

## [3.4.0] — 2026-04-23

### Added

- `weekly-report` 스킬 추가. `/rakis:weekly-report [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--force]`로 CWD 아래 git 레포를 순회해 지난 7일간 본인 커밋/PR/이슈를 수집·요약하고, `~/workspace/weekly-reports/YYYY-W##.md`에 저장.
- `skills/weekly-report/scripts/collect_weekly.sh`: 데이터 수집 스크립트. 다중 GitHub 계정(`hr-son_ktopen`/`raki-1203`)을 owner 기반 `GH_TOKEN` 우선순위 + fallback으로 자동 처리.
- `/rakis:setup` 의존성 체크에 `jq`, `yq` 추가.

## [3.3.0] — 2026-04-21

### Added

- `source-fetch` 스킬에 `--hint "<한 줄>"` 플래그 추가. NotebookLM `generate report` 호출 시 `--append`로 주입되어 briefing/study-guide가 해당 관점에 맞춰 생성된다.
- `meta.json` 스키마에 `domain_hint` 필드 추가 (선택, 재수집 이력 보존).

### Changed

- enrich 단계의 briefing/study-guide 생성 명령이 `DOMAIN_HINT` 환경변수 유무에 따라 `--append`를 조건부로 붙이도록 수정. mind-map은 해당 옵션 미지원이므로 힌트 무관.

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
