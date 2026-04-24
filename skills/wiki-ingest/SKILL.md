---
name: wiki-ingest
description: Use when raw sources have been fetched (via /rakis:source-fetch or manual drop) and need to be compiled into wiki/ pages. Scans raw/ incrementally (only unprocessed sources), creates wiki/sources/{slug}.md, updates affected concept/project pages, and bumps index.md + log.md. Does NOT fetch — upstream work belongs to source-fetch.
---

# wiki-ingest — raw → wiki 컴파일

raw에 수집된 소스 중 아직 위키에 반영되지 않은 것을 찾아 `wiki/sources/{slug}.md`를 만들고, 영향받는 기존 위키 페이지를 업데이트한다.

## Vault 경로 탐지

source-fetch와 동일 — `OBSIDIAN_VAULT_PATH` 환경변수 필수. 없으면 에러 메시지 출력 후 중단.

## 인자

```
/rakis:wiki-ingest [--full]
```

- 기본: 증분 (미처리 소스만)
- `--full`: 전체 재컴파일 (마이그레이션·대규모 재구조화 용)

## Phase 0: 미처리 소스 탐지

```bash
# 1. 전수 스캔
find "$VAULT/raw" -name "meta.json" -type f

# 2. 각 meta.json마다 slug 추출 → wiki/sources/{slug}.md 존재 확인
# 존재하지 않으면 "미처리"로 분류
```

`--full` 플래그 있으면 기존 `wiki/sources/*` 페이지를 삭제하고 전체를 미처리로 취급(단, `index.md`·`overview.md`·`log.md`·`projects/`·`concepts/`·`entities/`는 보존).

미처리 0건이면 "변경 없음" 출력 후 종료.

## Phase 1: 소스 페이지 생성

각 미처리 소스마다:

1. `raw/{type}/{slug}/source.md|source.pdf|repomix.txt` 읽기
2. `raw/{type}/{slug}/notebooklm/briefing.md` 존재 시 핵심 요약 근거로 활용
3. `raw/{type}/{slug}/notebooklm/study-guide.md` 존재 시 주요 질문 추출
4. `wiki/sources/{slug}.md` 생성

Frontmatter (필수):

```yaml
---
title: "{meta.title or slug}"
type: source-summary
sources: ["[[raw/{type}/{slug}]]"]
related: []
created: {meta.captured_at date}
updated: {today}
description: "{한 줄 요약 — 20자 이내}"
comment: "{사용자가 제공했으면 기록. 없으면 생략}"
---
```

본문 구조 (섹션):
- **요약**: 3-5줄
- **핵심 개념**: 순차 bullet
- **주요 인용/발췌**: briefing.md 기반 (있을 때)
- **연관 질문**: study-guide.md 기반 (있을 때)
- **원본**: `[[raw/.../source...]]`

## Phase 2: 기존 페이지 업데이트 (index.md 기반 연결)

1. `$VAULT/index.md` 읽기
2. 새 소스의 핵심 키워드(`description`, 상위 개념)로 index 섹션 매칭
3. 매칭된 기존 wiki 페이지에 대해:
   - 해당 페이지 frontmatter `related:`에 `[[sources/{slug}]]` 추가 (중복 방지)
   - 해당 페이지 본문에 "관련 소스" 섹션이 있으면 한 줄 append, 없으면 섹션 생성
4. 매칭되는 프로젝트 있으면 `wiki/projects/{name}.md`의 섹션(Decisions/Patterns/Gotchas 중 적합한 곳)에 한 줄 추가
5. 새 개념이 등장했는데 `wiki/concepts/*`에 없으면 사용자 승인 후 신규 페이지 생성

## Phase 3: index.md · log.md 갱신

- `index.md`:
  - `sources/` 섹션에 `- [[sources/{slug}]] — {description}` 추가 (알파벳 정렬)
  - 새로 생성한 `concepts/`·`projects/` 페이지가 있으면 해당 섹션에도 추가
- `log.md`:
  - 위쪽에 `## [{YYYY-MM-DD}] {slug} | ingest — {description}` 한 줄 삽입

## Phase 4: 출력 + graphify 안내

출력:
```
✓ N개 소스 반영
  - sources/{slug1}.md (신규)
  - sources/{slug2}.md (신규)
  - concepts/{name}.md (업데이트)
  - projects/{name}.md (업데이트)

그래프 증분 업데이트 권장:
  cd "{VAULT}" && /graphify wiki --update
```

## 에러 처리

| 상황 | 대응 |
|------|------|
| raw meta.json 파싱 실패 | 해당 소스 건너뛰고 경고 출력, 계속 진행 |
| 대상 wiki 페이지 쓰기 실패 | 트랜잭션처럼 롤백 어려움 — 실패 지점까지 보고 후 종료 |
| `--full` 실행 중 중단 | 기존 sources/ 디렉터리는 이미 삭제됐으므로 다시 `--full` 재실행 권장 안내 |

## frontmatter 검증

모든 신규·업데이트 페이지는 쓰기 직후 검증:

```bash
uv run python3 "$PLUGIN_ROOT/scripts/frontmatter.py" validate "{path}"
```

실패 시 해당 파일을 `.broken.md`로 이름 변경하고 경고 출력.
