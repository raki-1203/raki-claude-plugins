# rakis v3.0.0 — Karpathy LLM Wiki 정렬 설계

**Date**: 2026-04-17
**Status**: Design (브레인스토밍 완료, 사용자 검토 대기)
**Version Target**: v3.0.0 (Major, Breaking)
**Supersedes**: v2.5.2

---

## 배경

Obsidian graph view에서 `raw/repos/*/graph-report.md` 노드들이 전부 동일한 라벨("Graph Report")로 나타나 어떤 repo의 분석물인지 식별 불가능한 문제가 발생. 표면적 증상은 UI 가독성이지만, 근본 원인은 **rakis v2.5.2의 설계가 Andrej Karpathy의 LLM Wiki 사상과 정렬되지 않은 것**.

구체적으로:
- `source-analyze`가 외부 소스를 **미리 분석**하여 graph-report/analysis.md 같은 LLM 산출물을 `raw/`에 저장 — raw 루트의 "수집한 원본만" 불변성 위반
- 결과적으로 `wiki/`에는 이미 "정제된 결과"가 들어가 있어, Karpathy가 제안한 "LLM이 볼트 컨텍스트에서 compile" 동작 경로가 없음
- NotebookLM을 Q&A 엔진으로 쓰면서 노트북 ID를 추적하는 구조 — 실제로는 wiki에 질의하는 게 더 자연스러움

v3.0.0은 이 근본 불일치를 바로잡는 재설계.

## 북극성 (North Star)

**Karpathy의 3-Layer LLM Wiki 사상에 완전 정렬한다.**
- `raw/` = 불변 원본 수집소 (어떤 LLM 분석물도 raw 루트에 두지 않음)
- `wiki/` = LLM이 볼트 전체 컨텍스트에서 compile한 결과
- Schema(CLAUDE.md) = 위 두 계층의 규약

3대 동작(Ingest/Query/Lint)을 스킬 경계와 일치시킨다.

## 섹션 1: 아키텍처 개요

### 핵심 원칙

1. **raw 불변성**: `raw/`에는 외부에서 수집한 원본과 NotebookLM이 원본을 보강한 파생물(briefing/study-guide/mindmap)만. 모든 파생물은 소스 단위 `notebooklm/` 서브폴더에 격리.
2. **wiki 컴파일성**: `wiki/`는 LLM이 raw를 읽어 볼트 전체 맥락에서 생산한 결과물. 사람·LLM이 수정 가능.
3. **스킬 단일 책임**: 수집과 컴파일을 분리. 하나의 스킬이 "수집 + 분석 + 저장"을 섞지 않음.

### v2 → v3 변화 요약

| 영역 | v2.5.2 | v3.0.0 |
|------|--------|--------|
| 수집-분석 경계 | `source-analyze` 단일 | `source-fetch`(수집) + `wiki-ingest`(컴파일) 분리 |
| raw 위생 | graph-report/analysis.md가 raw 루트에 | 원본 + `notebooklm/` 보강물만 |
| NotebookLM 역할 | Q&A 엔진, 노트북 ID 추적 | briefing/study-guide/mindmap 생성기 |
| wiki 탐색 진입점 | `index.md`만 | `wiki/overview.md`(서술) + `index.md`(목록) |
| 일회성 산출물 | `log.md` 한 줄 | `outputs/{lint,graph-report}-{date}.md` |
| 마이그레이션 | — | `rakis:migrate-v3` 스킬 (idempotent) |
| backward compat | — | 완전 단절 (v2 스킬 제거) |
| graphify target | `<vault>` 전체 | `<vault>/wiki`로 축소 |

### 기본 데이터 흐름

```
source-fetch <url>
  → raw/{type}/{slug}/source.md + meta.json
  → (임계값 충족 시) notebooklm/{briefing,study-guide,mindmap}.md

wiki-ingest
  → raw 스캔 → 미처리 소스 추림 (증분)
  → wiki/sources/{slug}.md 생성
  → 영향받는 wiki/* 페이지 업데이트
  → index.md · log.md 갱신

wiki-query "질문"
  → 답변형: index → overview → 개별 페이지
  → 탐색형: 프로젝트 컨텍스트 압축 → graphify → 3-카테고리

wiki-lint (주 1회)
  → 고아/stale/frontmatter 위반 검사
  → outputs/lint-{date}.md + overview.md 통계 갱신
```

## 섹션 2: 볼트 구조

### 완성형 디렉토리

```
vault/
├── raw/                              # 불변 원본
│   ├── articles/{slug}/
│   │   ├── source.md                 # WebFetch 원문
│   │   ├── meta.json                 # url, captured_at, contributor, size
│   │   └── notebooklm/               # enrich 임계값 충족 시만
│   │       ├── briefing.md
│   │       ├── study-guide.md
│   │       └── mindmap.md
│   ├── repos/{owner}-{repo}/
│   │   ├── repomix.txt
│   │   ├── meta.json
│   │   └── notebooklm/
│   └── papers/{slug}/
│       ├── source.pdf
│       ├── meta.json
│       └── notebooklm/
├── wiki/                             # LLM compile 결과
│   ├── overview.md                   # 볼트 대시보드 (서술형)
│   ├── sources/{slug}.md             # type=source-summary
│   ├── projects/{name}.md            # type=project
│   ├── concepts/{name}.md            # type=concept
│   ├── entities/{name}.md            # type=entity
│   └── comparisons/{a}-vs-{b}.md     # type=comparison
├── outputs/                          # 일회성 산출물 (immutable)
│   ├── lint-{YYYY-MM-DD}.md
│   ├── graph-report-{YYYY-MM-DD}.md
│   └── archive-v2/                   # 마이그레이션 백업
├── graphify-out/                     # graphify 자체 아웃풋
├── index.md                          # 전체 페이지 목록
├── log.md                            # 시간순 한 줄 기록
├── CLAUDE.md                         # 스키마/규칙
└── Home.md → overview.md             # (선택) 하위호환 리다이렉트
```

### frontmatter 표준

```yaml
---
title: "페이지 제목"
type: source-summary | project | concept | entity | comparison | index
sources: ["[[raw/repos/yamadashy-repomix]]"]
related: ["[[concepts/knowledge-graph]]"]
created: 2026-04-17
updated: 2026-04-17
description: "한 줄 요약 (query 매칭용)"
# 선택 필드
comment: "왜 수집했는지 (Gold In Gold Out)"
# projects/ 전용
tech_stack: [Python, FastAPI]
repo: "git@github.com:..."
---
```

- `confidence:` 필드 제거
- `type:` enum 고정
- 나머지 필드는 유지 (description·comment·tech_stack·repo는 활용되고 있음)

### 네이밍 규칙

- **slug**: kebab-case, ASCII only, 최대 60자
  - 한글 제목 → 로마자 변환 (python-slugify 등)
  - 사용자 지정 가능: `--slug <name>` 플래그
- **repo**: `{owner}-{repo}` (슬래시 금지)
- **comparison**: 알파벳순 `{a}-vs-{b}` (중복 방지)
- **날짜 suffix**: `YYYY-MM-DD` (정렬 용이)

### 예외 규칙

- **wrap-up 저장**: 대화 기반 지식(세션 중 결정·삽질·학습)은 raw를 거치지 않고 wiki·log에 직접 쓴다. 이때 `log.md`가 출처 역할을 겸한다. CLAUDE.md 스키마에 명시.

## 섹션 3: 스킬 구성

v3 스킬 7개:

### 1. `source-fetch` (신규)

- **트리거**: `/rakis:source-fetch <url|path> [--slug <slug>] [--no-enrich|--force-enrich]`
- **역할**: raw/에 원본만 저장. LLM 분석 금지.
- **알고리즘**:
  1. 유형 감지 + slug 생성
  2. 원본 수집 (WebFetch / repomix / 파일 복사)
  3. `raw/{type}/{slug}/source.md` + `meta.json` 저장
  4. 임계값 체크: repo · PDF · 웹페이지 ≥5000자 → 자동 enrich
  5. NotebookLM 인증 있으면 briefing + study-guide + mindmap 생성 → `notebooklm/`
  6. wiki 쓰지 않음. 끝에 wiki-ingest 안내 출력

### 2. `wiki-ingest` (리디자인)

- **트리거**: `/rakis:wiki-ingest [--full]`
- **역할**: raw의 미처리 소스 → wiki compile
- **알고리즘**:
  1. `raw/**/meta.json` 전수 스캔 → `wiki/sources/{slug}.md` 없는 것만 추림 (증분)
  2. 각 미처리 소스마다:
     - `source.md` + `notebooklm/*` 읽어 `wiki/sources/{slug}.md` 생성
     - `index.md`에서 관련 기존 페이지 후보 탐색
     - 영향받는 `wiki/projects/*` · `wiki/concepts/*` append/생성
  3. `index.md` · `log.md` 갱신
  4. 끝에 `cd "<vault>" && /graphify wiki --update` 안내
- **`--full`**: 전체 재컴파일 (마이그레이션·대규모 재구조화 용)

### 3. `wiki-query` (유지 + v3 스키마)

- **트리거**: `/rakis:wiki-query "<질문>" [--scope project]`
- **알고리즘**: 현행 Step 0 양분기 유지
  - 답변형: `index.md` → `overview.md` → 개별 페이지
  - 탐색형: 프로젝트 컨텍스트 ≤50줄 압축 → graphify query → 3-카테고리
  - `--scope project`: 탐색 범위를 `wiki/projects/{name}.md` + `related:` 이웃으로 제한 (신규)

### 4. `wiki-wrap-up` (유지 + v3 스키마)

- **트리거**: `/rakis:wiki-wrap-up`
- **알고리즘**: 세션 요약 질의 → `log.md` + 해당되면 `wiki/projects/{name}.md` append
- raw 거치지 않음 (섹션 2 예외 규칙)
- 끝에 graphify 증분 업데이트 안내

### 5. `wiki-lint` (유지 + outputs)

- **트리거**: `/rakis:wiki-lint` (주 1회 권장)
- **알고리즘**:
  1. 고아/stale/frontmatter 위반 검사
  2. `outputs/lint-{YYYY-MM-DD}.md` 저장
  3. `wiki/overview.md` 통계 섹션 갱신
  4. `log.md` 한 줄 + graphify 풀 리빌드 안내

### 6. `setup` (유지)

- **트리거**: `/rakis:setup`
- marker 파일 기반 멱등성 (v2와 동일)
- v3에서 v2 구조 감지 시 `migrate-v3` 우선 실행 지시

### 7. `migrate-v3` (신규, 1회성)

- **트리거**: `/rakis:migrate-v3 [--dry-run]`
- 상세는 섹션 5 참조

### graphify 통합 정책 (v2.5.1 결정 승계)

rakis는 graphify를 bash로 직접 호출하지 않음. "언제 graphify를 돌려야 하는지 시점을 안내"까지가 rakis의 역할.

| 스킬 | 안내 문구 |
|------|-----------|
| `wiki-ingest` 완료 | `cd "<vault>" && /graphify wiki --update` |
| `wiki-wrap-up` 완료 | `cd "<vault>" && /graphify wiki --update` |
| `wiki-lint` 완료 | `cd "<vault>" && /graphify wiki` (풀 리빌드) |
| `wiki-query` 탐색형 (CLI 미설치) | "설치 후 `/graphify wiki --update` 실행 권장" |
| `migrate-v3` 완료 | `rm -rf "<vault>/graphify-out/" && cd "<vault>" && /graphify wiki` |

**graphify target = `<vault>/wiki`**. raw/repos의 repomix.txt 같은 대용량 코드 덤프가 그래프에 섞이는 것을 막고, Karpathy 사상과도 일치. `graphify-out/`은 cwd 기준이므로 안내 시 `cd <vault>` 병기.

## 섹션 4: 파이프라인 시나리오

### 시나리오 A: 신규 repo 분석 (v2 source-analyze 대체)

```
$ /rakis:source-fetch https://github.com/plastic-labs/honcho
  → slug: "plastic-labs-honcho"
  → repomix 실행 → raw/repos/plastic-labs-honcho/repomix.txt
  → meta.json 저장 (stars, captured_at, contributor)
  → 임계값 체크: repo → 자동 enrich
  → NotebookLM: briefing.md + study-guide.md + mindmap.md
    → raw/repos/plastic-labs-honcho/notebooklm/
  → "raw 저장 완료. /rakis:wiki-ingest 로 위키에 반영하세요"

$ /rakis:wiki-ingest
  → raw 스캔: plastic-labs-honcho 신규 감지 (1건)
  → source.md + notebooklm/* 읽고 wiki/sources/plastic-labs-honcho.md 생성
  → index.md에서 관련 페이지 탐색: "agent-memory" 키워드 매칭
    → wiki/concepts/agent-memory.md 존재 → related 추가 + 섹션 append
  → index.md 업데이트
  → log.md: ## [2026-04-17] plastic-labs-honcho | ingest — agent memory 인프라
  → "1개 소스 반영. cd <vault> && /graphify wiki --update 권장"
```

### 시나리오 B: 세션 중 배운 것 wrap-up

```
$ /rakis:wiki-wrap-up
  → 대화 스캔: "오늘 뭐 배웠지?"
  → 후보: "SQLAlchemy selectinload vs joinedload 차이"
  → 타겟 결정: wiki/concepts/sqlalchemy-eager-loading.md (기존)
  → Gotchas 섹션에 append
  → log.md: ## [2026-04-17] sqlalchemy-eager-loading | N+1 문제 해결
  → "cd <vault> && /graphify wiki --update 권장"
```

### 시나리오 C: 주간 위키 건강 점검

```
$ /rakis:wiki-lint
  → 고아 페이지: 3건 / stale: 2건 / frontmatter 위반: 1건
  → overview.md 통계 섹션 갱신 (총 페이지, 소스, 커뮤니티, 최근 7일)
  → outputs/lint-2026-04-17.md 저장 (상세 리포트)
  → log.md: ## [2026-04-17] lint | 6건 발견
  → "cd <vault> && /graphify wiki 풀 리빌드 권장"
```

### 탐색형 wiki-query 예시

```
$ /rakis:wiki-query "caveman이랑 read-once가 실제로 같이 쓸 수 있나?"
  → Step 0: "실제로 ~있나" = 답변형
  → Step 1: index.md → caveman-vs-read-once 매칭
  → Step 2: 해당 페이지 읽고 답변
  → graphify 사용 안 함

$ /rakis:wiki-query "agent memory랑 context management가 어떻게 연결되지?"
  → Step 0: "어떻게 연결" = 탐색형
  → Step 1-A-1: 프로젝트 컨텍스트 압축 (≤50줄)
  → Step 1-A-2: graphify query "agent memory AND context management"
  → Step 1-A-3: 3-카테고리 결과
    직접: [honcho, caveman, read-once]
    간접: [harness, langchain agent harness]
    잠재: [obsidian vault operations]
```

## 섹션 5: 마이그레이션 `rakis:migrate-v3`

### 전제
- 1회성 스킬. 완료 후 marker 파일(`.rakis-v3-migrated`)로 재실행 방지.
- `--dry-run` 모드 필수.
- 자동 롤백 없음 (archive-v2 백업 + git 히스토리로 충분).

### 실행 단계

**0. Pre-flight 검증**
- 볼트 경로 탐지 (`OBSIDIAN_VAULT_PATH` → iCloud default → CLAUDE.md 검증)
- marker 존재 확인 → 있으면 중단
- v2 구조 감지: `raw/repos/*/graph-report.md` · `analysis.md` 존재 여부 집계
- 영향 범위 리포트 출력

**1. 백업 권장**
- `git commit` 또는 `cp -r vault vault-backup-v2/` 권장 메시지
- 진행 여부 재확인

**2. raw/ 정리**
```
raw/repos/{repo}/graph-report.md → outputs/archive-v2/repos/{repo}/graph-report.md
raw/repos/{repo}/analysis.md     → outputs/archive-v2/repos/{repo}/analysis.md
```
이동 방식(삭제 아님), 경로 구조 보존. `repomix.txt`는 원본 역할이라 그대로.

**3. frontmatter 일괄 수정**
- 모든 `wiki/**/*.md` · `raw/**/*.md` 스캔
- `confidence:` 제거
- `type:` enum 밖이면 사용자 확인 후 매핑 (`analysis` → `source-summary` 등)
- `created` · `updated` 누락 시 mtime 기반 채움

**4. meta.json 역보완**
- `raw/articles/{slug}.md` (평면 파일) → `raw/articles/{slug}/source.md` + `meta.json` 승격
- frontmatter의 source_url/captured_at 등을 meta.json으로 이관
- 평면 파일 삭제 (dry-run에선 diff만)

**5. 신규 구조 생성**
- `outputs/` 디렉토리 생성
- `Home.md` → `wiki/overview.md` 리네이밍 (기존 내용 보존 + overview 템플릿 섹션 주입)
- 이미 있으면 skip (멱등)

**6. index.md 재생성 (선택적)**
- `--rebuild-index` 플래그 있을 때만
- 전 페이지 frontmatter 스캔 → type별 섹션 정렬

**7. 완료 처리**
- `.rakis-v3-migrated` marker 생성 (`~/.claude/plugins/data/rakis/` 하위)
- `log.md`: `## [YYYY-MM-DD] migrate-v3 | v2 → v3 마이그레이션 완료 (graph-report N, analysis N, frontmatter N)`
- 권장 다음 동작 안내:
  ```
  rm -rf "<vault>/graphify-out/"   # v2 그래프 캐시 삭제
  cd "<vault>" && /graphify wiki    # v3 기준 풀 빌드
  ```

### Dry-run 출력 예시
```
DRY RUN — no files modified

Files to move (archive):
  raw/repos/yamadashy-repomix/graph-report.md → outputs/archive-v2/...
  ... (8건)

Frontmatter updates:
  wiki/sources/foo.md: remove confidence:, map type:analysis → source-summary
  ... (42건)

Structural changes:
  Home.md → wiki/overview.md (existing content preserved)
  create outputs/

Run without --dry-run to apply.
```

## 섹션 6: 테스트 및 릴리즈

### 테스트 3계층

**1. 유닛 테스트** (≈63개, pre-push hook 실행)

| 범주 | 대상 | 개수 |
|------|------|------|
| 스킬 파싱 | 7개 frontmatter | 7 |
| type enum | 6개 값 + 잘못된 값 거부 | 7 |
| frontmatter 스키마 | 필수/선택 필드, confidence 거부 | 8 |
| slug 생성 | URL/repo/한글 정규화 | 6 |
| 임계값 로직 | enrich 자동/수동/강제 | 4 |
| marker 멱등성 | setup·migrate-v3 재실행 방지 | 3 |
| install.sh | 기존 계승 | 28 |

**2. 마이그레이션 golden 테스트**

```
tests/fixtures/
├── vault-v2-sample/
│   ├── raw/repos/foo/{repomix.txt, graph-report.md, analysis.md}
│   ├── wiki/sources/bar.md (confidence: 포함)
│   ├── Home.md
│   └── log.md
└── vault-v3-expected/
    ├── raw/repos/foo/{repomix.txt, meta.json}
    ├── wiki/sources/bar.md (confidence: 제거)
    ├── wiki/overview.md
    ├── outputs/archive-v2/repos/foo/{graph-report.md, analysis.md}
    └── log.md
```

- `vault-v2-sample` 복사 → `migrate-v3` → `vault-v3-expected`와 diff. 차이 있으면 실패.
- `--dry-run`이 파일을 전혀 수정하지 않는지 별도 검증.

**3. 스모크 E2E** (1 시나리오)

```
tests/e2e/smoke.sh
  1. 임시 vault 생성
  2. /rakis:source-fetch tests/fixtures/sample-article.md
  3. /rakis:wiki-ingest
  4. /rakis:wiki-query "sample 주제가 뭐야?"
  5-9. 결과 자산 assertion
```

- NotebookLM stub: `RAKIS_NOTEBOOKLM_MOCK=1` 환경변수
- repomix/graphify: 조건부 스킵 또는 stub

### 릴리즈 체크리스트

**v3.0.0-rc.1**
- [ ] 유닛/golden/스모크 전부 통과
- [ ] CHANGELOG.md v3.0.0 섹션 (breaking changes 명시)
- [ ] README v3 흐름 반영 (source-fetch → wiki-ingest)
- [ ] marketplace.json 버전 bump
- [ ] 개인 vault에 `migrate-v3 --dry-run` 검증
- [ ] 개인 vault 1회 마이그레이션 → wiki-ingest · wiki-query 수동 smoke

**v3.0.0 (GA)**
- [ ] RC 이슈 전부 해결
- [ ] 리포 tag `v3.0.0`
- [ ] `wiki/projects/raki-claude-plugins.md` 업데이트 (Decisions)
- [ ] `log.md` 릴리즈 기록

### Rollout

v2 단절(backward compat 없음). 대신:
1. 릴리즈 노트 최상단에 "⚠️ 기존 사용자는 `/rakis:migrate-v3 --dry-run` 선행 권장"
2. v3 `/rakis:setup` 실행 시 v2 구조 감지하면 "migrate-v3를 먼저 돌리세요" 안내
3. 구 스킬 `/rakis:source-analyze`는 "v3에서 제거됨. `/rakis:source-fetch` + `/rakis:wiki-ingest`로 대체" 안내만 출력 후 종료

## 브레인스토밍 결정 로그

| ID | 질문 | 선택 |
|----|------|------|
| Q1 | source-analyze 재설계 방향 | (B) source-fetch + wiki-ingest 분리 |
| Q2 | wiki-ingest가 raw 어디까지 읽나 | (A) raw만, 증분 |
| Q3 | 관련 페이지 탐색 방식 | (A) index.md 기반 |
| Q4 | wiki-query 분기 유지 | (A) 양분기 유지 |
| Q5 | comment 필드 강제성 | (B) 선택적 |
| Q6 | wiki/projects/ 유지 | (A) 유지 |
| Q7 | NotebookLM enrich 트리거 | (C) 임계값 자동 |
| Q8 | overview.md + outputs/ 도입 | (A) 둘 다 |
| Q9 | frontmatter 표준 | (B) confidence 제거, type enum |
| Q10 | 마이그레이션 전략 | (A) 자동 스크립트 |
| Q11 | backward compat | (A) 완전 단절 |
| Q12 | raw enrichment 구조 | (A) 소스별 서브폴더 + notebooklm/ |
| Q13 | 테스트 전략 | 유닛 + golden + 스모크 E2E |
| 추가 | graphify target | `<vault>/wiki`로 축소 |

## Non-Goals

- v2와의 동시 지원 (co-exist 기간 없음)
- 자동 롤백 (archive-v2 백업으로 충분)
- NotebookLM Q&A 엔진 역할 (v3에서 제거, wiki 자체에 질의)
- graphify를 rakis 스킬이 bash로 자동 호출 (v2.5.1 결정 승계 — 수동 안내)

## Open Questions

현재 없음. writing-plans에서 구현 단계별로 다시 질문 발생 가능.
