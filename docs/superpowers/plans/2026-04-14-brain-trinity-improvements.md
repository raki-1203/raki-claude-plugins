# Brain Trinity 영상 기반 rakis 플러그인 개선 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** rakis 플러그인에 (1) graphify 위키 통합, (2) 수집 시 코멘트 강제, (3) `/wiki-init` 스킬, (4) `/rakis:help` 커맨드를 추가해 Karpathy LLM Wiki 방법론을 완성도 있게 반영.

**Architecture:** 스킬 문서(SKILL.md) 기반 플러그인이므로 코드 구현이 아닌 **마크다운 스킬 파일의 절차 수정/추가**가 핵심. 각 스킬이 자기 책임(쓰는 스킬 → 그래프 증분 업데이트, lint → 풀 리빌드, query → 답변/탐색 분기)을 명시적으로 수행하도록 한다. 기존 스킬은 절차 섹션에 신규 단계를 **추가**하는 방식(기존 동작 유지 + 신규 동작 덧붙임).

**Tech Stack:** Markdown (SKILL.md), YAML frontmatter, graphify CLI, Bash (검증/훅), Obsidian vault 파일 시스템.

**참조 스펙:** `docs/superpowers/specs/2026-04-14-brain-trinity-improvements-design.md`

---

## 파일 구조 (전체 변경 지도)

### 신규 파일
- `skills/wiki-init/SKILL.md` — vault 초기화 인터뷰 스킬
- `commands/help.md` — `/rakis:help` 커맨드 (전체/스킬별 사용법)

### 수정 파일
- `skills/wiki-query/SKILL.md` — 답변형/탐색형 분기, graphify query 연동
- `skills/wiki-ingest/SKILL.md` — 코멘트 강제 (Step 0), comment frontmatter, 그래프 증분 업데이트 (Step 6)
- `skills/source-analyze/SKILL.md` — 코멘트 강제 (Phase 0), comment frontmatter, 그래프 증분 업데이트 (Phase 7)
- `skills/wiki-wrap-up/SKILL.md` — 코멘트 자동 생성, comment frontmatter, 그래프 증분 업데이트 (Step 5)
- `skills/wiki-lint/SKILL.md` — 데이터 갭에 comment 추가, 풀 그래프 리빌드 (Step 5)
- `commands/skill-mapping.md` — 신규 스킬/커맨드(`wiki-init`, `/rakis:help`) 매핑 반영
- `README.md` — 전체 사용법 업데이트
- `.claude-plugin/plugin.json` — 버전 bump 2.4.0 → 2.5.0
- `package.json` — 버전 bump 2.4.0 → 2.5.0

---

## 작업 순서 근거

1. **Task 1~2**: frontmatter 스펙 확정 (comment 필드 규약) — 이후 모든 스킬이 이 규약을 참조
2. **Task 3~6**: 기존 스킬에 코멘트 + 그래프 업데이트 로직 추가 (독립적이므로 병렬 구현 가능)
3. **Task 7**: wiki-query 분기 로직 (graphify query 활용 — graph.json 존재 전제)
4. **Task 8**: wiki-lint 풀 리빌드 + 데이터 갭 확장
5. **Task 9**: `/wiki-init` 신규 스킬
6. **Task 10**: `/rakis:help` 커맨드
7. **Task 11**: skill-mapping.md 갱신
8. **Task 12**: README.md 갱신
9. **Task 13**: 버전 bump + 최종 커밋

---

## Task 1: frontmatter `comment` 필드 규약 정의

**목적:** 모든 스킬이 참조할 `comment` frontmatter 필드의 형식과 규칙을 확정. 개별 스킬 수정 전에 먼저 합의한다.

**Files:**
- 변경 없음 (이 task는 규약 문서화 목적 — 다음 task들에서 실제 사용)

**규약:**
- 필드명: `comment`
- 위치: YAML frontmatter (description 바로 다음)
- 값: **1-2 문장, 한국어**, "왜 저장/분석했는지" 목적 기록
- 예시:
  - `comment: "jobdori 분석 중 원류 프레임워크로 등장"`
  - `comment: "프로젝트 X 상태 관리 조사 중 발견, riverpod 비교 대상"`
- 누락 허용: 기존 페이지는 누락 가능 (wiki-lint의 "데이터 갭"에서 탐지)

- [ ] **Step 1: 규약을 디자인 스펙에 확정되어 있는지 재확인**

`docs/superpowers/specs/2026-04-14-brain-trinity-improvements-design.md`를 읽고 "개선 2" 섹션에 아래 내용이 있는지 확인:

```yaml
comment: "프로젝트 X 조사 중 원류로 등장, 기술 참고"
```

이 예시와 "1-2 문장, 한국어" 규약이 명시되어 있는지 확인. 없으면 스펙에 추가.

**확인 결과:** 스펙에 이미 있음. 이 task는 메모리 체크포인트 역할 — 다음 task들이 이 규약을 따르도록 강제.

- [ ] **Step 2: 진행 가능 확인 후 Task 2로**

다음 task부터 실제 스킬 수정 시작.

---

## Task 2: wiki-ingest — 코멘트 강제 + frontmatter comment + 그래프 증분 업데이트

**Files:**
- Modify: `skills/wiki-ingest/SKILL.md`

**변경 요약:**
1. 상단에 "코멘트 입력" Step 0 추가 (절차 시작 전)
2. Step 2의 frontmatter 예시에 `comment` 필드 추가
3. 끝에 Step 6 추가: 그래프 증분 업데이트

- [ ] **Step 1: Step 0 (코멘트 입력) 추가**

`skills/wiki-ingest/SKILL.md`의 "## 절차" 섹션 바로 아래, 기존 "### 1. 원본 저장" 위에 다음 섹션을 삽입:

```markdown
### 0. 코멘트 수집 (Gold In, Gold Out)

"왜 저장하는지" 목적을 반드시 기록한다. 이 코멘트는 wiki/ 페이지 frontmatter의 `comment` 필드로 저장되어 나중에 맥락 파악/역검색에 사용된다.

**입력 방식:**
- 인자로 전달: `/wiki-ingest <자료> "왜 저장하는지"`
- 인자 없으면 질문:
  ```
  왜 이 자료를 저장하시나요? (한 줄, 한국어 권장)
  > _____
  ```
- 사용자가 답할 때까지 대기 (빈 답변 거부)

**형식:**
- 1-2 문장, 한국어
- 예시:
  - `"jobdori 분석 중 원류 프레임워크로 등장"`
  - `"프로젝트 X 상태 관리 조사 중 발견, riverpod 비교 대상"`

수집된 코멘트를 변수로 보관하여 Step 2의 frontmatter 생성과 이후 기존 페이지 업데이트에 사용한다.
```

- [ ] **Step 2: Step 2의 frontmatter 예시에 `comment` 필드 추가**

기존 frontmatter 블록(wiki-ingest/SKILL.md 내 "### 2. 요약 페이지 생성" 섹션)을 다음으로 교체:

```yaml
---
title: Source Title
type: source-summary
sources:
  - "[[raw/articles/source-file]]"
comment: "Step 0에서 수집한 사용자 코멘트 — 왜 저장했는지"
related:
  - "[[관련-위키-페이지]]"
created: YYYY-MM-DD
updated: YYYY-MM-DD
confidence: high | medium | low
description: 한 줄 요약
---
```

그리고 바로 아래 본문에 이 줄 추가:

```markdown
**`comment` 필드**: Step 0에서 수집한 사용자 코멘트를 그대로 기록. 1-2 문장, 한국어. 나중에 wiki-query의 역검색 대상이 된다.
```

- [ ] **Step 3: Step 6 (그래프 증분 업데이트) 추가**

파일 끝 "## 주의사항" 섹션 위에 다음 섹션을 삽입:

```markdown
### 6. 그래프 증분 업데이트

모든 저장 단계가 끝나면 vault 그래프를 증분 업데이트한다.

**조건 체크:**
```bash
command -v graphify
```

- 성공 → 업데이트 실행
- 실패 → 건너뜀 (경고 없이 조용히)

**실행:**
```bash
graphify "${VAULT_PATH}" --update
```

- graph.json이 없으면 graphify가 자동으로 풀 빌드로 전환 (graphify 자체 동작)
- 실행 출력은 요약해서 사용자에게 보고 (예: "그래프: 3개 노드 추가, 5개 엣지 업데이트")
- 실패해도 ingest는 성공으로 간주 (그래프는 다음 wiki-lint에서 복구)

**`${VAULT_PATH}`**: "Vault 경로 탐지" 섹션의 결과 경로.
```

- [ ] **Step 4: 전체 읽고 일관성 확인**

수정된 `skills/wiki-ingest/SKILL.md`를 처음부터 끝까지 읽어서:
- Step 0 → 1 → 2 → ... → 6 순서가 자연스러운지
- `comment` 필드가 frontmatter에 포함되는지
- Step 6의 VAULT_PATH 참조가 맞는지
- "## 주의사항"에 "모든 wiki 페이지에 YAML frontmatter **필수**" 항목이 여전히 있는지 (comment 필드도 필수임을 암시)

문제 있으면 수정.

- [ ] **Step 5: 커밋**

```bash
git add skills/wiki-ingest/SKILL.md
git commit -m "feat(wiki-ingest): 코멘트 강제 + frontmatter comment 필드 + 그래프 증분 업데이트

- Step 0 추가: 자료 저장 전 '왜 저장하는지' 코멘트 수집 (인자 또는 질문)
- frontmatter에 comment 필드 추가 (한국어 1-2문장)
- Step 6 추가: graphify <vault> --update 로 vault 그래프 증분 업데이트
- graphify 미설치 시 Step 6 건너뜀 (경고 없이)"
```

---

## Task 3: source-analyze — 코멘트 강제 + frontmatter comment + 그래프 증분 업데이트

**Files:**
- Modify: `skills/source-analyze/SKILL.md`
- Modify: `skills/source-analyze/references/output-template.md` (frontmatter 템플릿 보유 시)

**변경 요약:**
1. "## Phase 0" 섹션 맨 처음에 "코멘트 수집" 단계 추가
2. "## Phase 6" 저장 시 frontmatter에 `comment` 필드 포함
3. "## Phase 7" 신규 추가: 그래프 증분 업데이트

- [ ] **Step 1: Phase 0 맨 앞에 코멘트 수집 단계 추가**

`skills/source-analyze/SKILL.md`의 "## Phase 0: 소스 유형 감지 + 전처리" 섹션 바로 아래, 기존 "### 소스 유형 자동 감지" 위에 다음을 삽입:

```markdown
### 코멘트 수집 (Gold In, Gold Out) — 유형 감지 전

"왜 분석하는지" 목적을 반드시 기록한다. 이 코멘트는 wiki/sources/ 페이지 frontmatter의 `comment` 필드로 저장되어 나중에 맥락 파악/역검색에 사용된다.

**입력 방식:**
- 인자로 전달: `/source-analyze https://... "왜 분석하는지"`
- 인자 없으면 질문:
  ```
  왜 이 소스를 분석하시나요? (한 줄, 한국어 권장)
  > _____
  ```
- 사용자가 답할 때까지 대기 (빈 답변 거부)

**멀티 소스 모드:**
여러 소스가 주어지거나 "비교해줘" 키워드가 있으면 코멘트도 공통 하나만 받는다:
  ```
  이 소스들을 왜 비교/분석하시나요?
  ```

**형식:**
- 1-2 문장, 한국어
- 예시:
  - `"jobdori 분석 중 원류 프레임워크로 등장"`
  - `"langchain agent harness 시리즈와 비교하려고"`

수집된 코멘트는 Phase 6의 frontmatter 생성에 사용된다.
```

- [ ] **Step 2: Phase 6 저장 시 frontmatter에 comment 필드 포함**

`skills/source-analyze/SKILL.md`의 "## Phase 6: Obsidian 저장" 섹션 바로 아래, 기존 테이블 위에 다음을 삽입:

```markdown
**frontmatter 필수 필드:**
모든 wiki/ 페이지(sources/, comparisons/) frontmatter에 다음 필드를 포함한다:

```yaml
---
title: ...
type: source-summary | comparison
sources:
  - "[[raw/...]]"
comment: "Phase 0에서 수집한 사용자 코멘트 — 왜 분석했는지"
related:
  - [...]
created: YYYY-MM-DD
updated: YYYY-MM-DD
confidence: high | medium | low
description: ...
---
```

**`comment` 필드**: Phase 0에서 수집한 사용자 코멘트를 그대로 기록. 멀티 소스 모드에서는 공통 코멘트 하나를 모든 페이지에 동일하게 기록한다.
```

- [ ] **Step 3: Phase 7 (그래프 증분 업데이트) 추가**

`skills/source-analyze/SKILL.md`의 "## 확장 분석 (사용자 요청 시)" 섹션 바로 위에 다음을 삽입:

```markdown
## Phase 7: 그래프 증분 업데이트

Phase 6 저장이 끝나면 vault 그래프를 증분 업데이트한다.

**조건 체크:**
```bash
command -v graphify
```

- 성공 → 업데이트 실행
- 실패 → 건너뜀 (경고 없이 조용히)

**실행:**
```bash
graphify "${VAULT_PATH}" --update
```

- graph.json이 없으면 graphify가 자동으로 풀 빌드로 전환
- 실행 출력을 요약해서 사용자에게 보고
- 실패해도 분석은 성공으로 간주

`${VAULT_PATH}`: "Vault 경로 탐지" 또는 `OBSIDIAN_VAULT_PATH` 환경변수로 결정된 경로.
```

- [ ] **Step 4: references/output-template.md 확인 및 업데이트**

`skills/source-analyze/references/output-template.md`가 존재하면 읽기. 이 파일에 frontmatter 템플릿이 포함되어 있다면 그 템플릿에도 `comment` 필드를 추가:

```bash
ls skills/source-analyze/references/output-template.md 2>/dev/null
```

파일 존재 시 내용을 Read → `comment:` 라인이 있는지 확인 → 없으면 frontmatter 템플릿의 `sources:` 다음 줄에 추가. 파일이 없으면 이 step 건너뜀.

- [ ] **Step 5: 전체 읽고 일관성 확인**

수정된 `skills/source-analyze/SKILL.md`를 읽어:
- 코멘트 수집이 Phase 0 맨 앞에 있는지
- Phase 6의 frontmatter에 comment 필드가 있는지
- Phase 7이 "확장 분석" 위에 있는지
- 번호가 Phase 0 → 1 → 2 → 3 → 4 → 5 → 6 → 7 순인지

문제 있으면 수정.

- [ ] **Step 6: 커밋**

```bash
git add skills/source-analyze/SKILL.md
git add skills/source-analyze/references/output-template.md 2>/dev/null || true
git commit -m "feat(source-analyze): 코멘트 강제 + frontmatter comment 필드 + 그래프 증분 업데이트

- Phase 0 맨 앞에 코멘트 수집 단계 추가 (인자 또는 질문)
- Phase 6 저장 시 frontmatter에 comment 필드 포함
- Phase 7 신규: graphify <vault> --update 로 vault 그래프 증분 업데이트
- 멀티 소스 모드에서는 공통 코멘트 하나 적용"
```

---

## Task 4: wiki-wrap-up — 코멘트 자동 생성 + frontmatter comment + 그래프 증분 업데이트

**Files:**
- Modify: `skills/wiki-wrap-up/SKILL.md`

**변경 요약:**
1. Step 1 회고 시 각 항목의 "왜 저장하는지" 자동 추출
2. Step 3 사용자 확인 화면에 자동 생성된 comment 표시 + 수정 가능
3. Step 4 저장 시 frontmatter에 comment 포함
4. Step 5 신규: 그래프 증분 업데이트

- [ ] **Step 1: Step 1 (세션 회고)에 "왜" 추출 명시**

`skills/wiki-wrap-up/SKILL.md`의 "### 1. 세션 회고 (자동)" 섹션의 기존 A~D 항목 아래에 다음 문단 추가:

```markdown
**추가 추출: 각 항목의 "왜" (코멘트)**

각 항목에 대해 세션 대화 맥락에서 **왜 이것이 저장 가치가 있는지** 한 줄로 자동 추출한다. 이것은 나중에 frontmatter의 `comment` 필드로 저장된다.

예시:
- OpenClaw: `"jobdori 분석 중 원류 프레임워크로 등장, 별도 페이지 필요"`
- iCloud vault 경로: `"vault 접근 시도 중 iCloud 경로 특이성 발견"`
- OMC 제거 결정: `"실제 사용 안 함 확인, CLAUDE.md 간소화 목적"`

추출 기준:
- 세션에서 해당 주제가 **언제/왜 등장했는지**
- 작업의 어떤 문맥에서 유용했는지
- 사용자가 명시적으로 언급하지 않았어도 대화 흐름에서 유추 가능
```

- [ ] **Step 2: Step 3 (사용자 확인)에 자동 생성 코멘트 표시 + 수정 옵션**

기존 Step 3의 확인 화면 예시 블록을 다음으로 교체:

````markdown
### 3. 사용자 확인

추출 결과를 보여주고 승인을 받는다. 각 항목에 자동 생성된 comment도 함께 표시:

```
## 이 세션에서 위키에 저장할 내용

### 새로운 개념 (N건)
- **OpenClaw**: 오픈소스 AI 에이전트 프레임워크
  comment: "jobdori 분석 중 원류 프레임워크로 등장"
  → wiki/concepts/에 저장

- **clawhip**: Claude Code ↔ OpenClaw 이벤트 브릿지
  comment: "OpenClaw 알림 구조 조사 중 발견"
  → wiki/concepts/에 저장

### 트러블슈팅 (N건)
- **iCloud vault 경로**: ~/Library/Mobile Documents/...
  comment: "vault 접근 시 iCloud 경로 특이성"
  → 기존 페이지에 추가

### 결정 기록 (N건)
- **OMC 제거**: 실제로 안 쓰고 있어서 CLAUDE.md에서 삭제
  comment: "실사용 검증 후 CLAUDE.md 간소화"
  → log.md에 기록

저장할까요?
[전체] 그대로 저장
[선택] 항목별 선택
[수정] 코멘트 수정 후 저장
[취소] 저장하지 않음
```

**[수정] 선택 시**: 각 항목에 대해 "이 코멘트로 할까요? (Enter = 그대로, 수정할 내용 입력)" 순차 질문. 사용자 입력을 해당 항목의 comment로 대체.
````

- [ ] **Step 3: Step 4 (저장 실행)에 frontmatter comment 포함 명시**

기존 Step 4의 1번(새 개념/엔티티) 항목을 다음으로 교체:

```markdown
1. **새 개념/엔티티** → `wiki/concepts/` 또는 `wiki/entities/`에 새 페이지 생성
   - YAML frontmatter 포함 (title, type, sources, `comment`, related, created, updated, confidence, description)
   - `comment`: Step 1에서 자동 추출된 값 또는 Step 3에서 사용자가 수정한 값
```

2번(기존 페이지 보강) 항목에는 다음 줄 추가:

```markdown
2. **기존 페이지 보강** → 해당 페이지의 내용 업데이트, `updated:` 갱신
   - 기존 페이지에 `comment` 필드가 없으면 자동 추가 (이 세션에서 추출된 값으로)
   - 이미 `comment`가 있으면 덮어쓰지 않고 기존 값 유지
```

- [ ] **Step 4: Step 5 (그래프 증분 업데이트) 추가**

기존 "### 5. 완료 보고" 섹션 **바로 위**에 새 Step 5를 삽입하고, 완료 보고를 Step 6으로 번호 변경:

```markdown
### 5. 그래프 증분 업데이트

Step 4의 저장이 끝나면 vault 그래프를 증분 업데이트한다.

**조건 체크:**
```bash
command -v graphify
```

- 성공 → 업데이트 실행
- 실패 → 건너뜀 (경고 없이)

**실행:**
```bash
graphify "${VAULT_PATH}" --update
```

- graph.json 없으면 graphify가 풀 빌드로 자동 전환
- 실행 결과를 Step 6 완료 보고에 요약 포함
- 실패해도 wrap-up 자체는 성공 (그래프는 다음 lint에서 복구)

### 6. 완료 보고
```

그리고 완료 보고 예시 블록에 "그래프" 라인 추가:

```
## Wiki Wrap-up 완료

- 새 페이지: 2건 (openclaw.md, clawhip.md)
- 업데이트: 1건 (claude-code.md)
- 로그 기록: 1건
- 그래프: 증분 업데이트 완료 (3개 노드 추가)

다음 세션에서 "~에 대해 정리된 거 있어?"로 찾을 수 있습니다.
```

- [ ] **Step 5: 전체 읽고 일관성 확인**

수정된 `skills/wiki-wrap-up/SKILL.md`를 읽어:
- Step 번호: 1 → 2 → 3 → 4 → 5 → 6 순서 맞는지
- 각 Step에서 comment 관련 로직이 연결되는지 (추출 → 확인 → 저장)
- Step 5의 VAULT_PATH 참조 방식이 기존 "## Vault 경로" 섹션과 일치하는지

문제 있으면 수정.

- [ ] **Step 6: 커밋**

```bash
git add skills/wiki-wrap-up/SKILL.md
git commit -m "feat(wiki-wrap-up): 코멘트 자동 생성 + frontmatter comment + 그래프 증분 업데이트

- Step 1 회고 시 각 항목의 '왜 저장 가치가 있는지' 자동 추출
- Step 3 확인 화면에 자동 생성 코멘트 표시 + 수정 옵션 추가
- Step 4 저장 시 frontmatter에 comment 필드 포함
- Step 5 신규: graphify <vault> --update 로 그래프 증분 업데이트
- 완료 보고에 그래프 업데이트 결과 포함"
```

---

## Task 5: wiki-query — 답변형/탐색형 분기 + graphify query 연동

**Files:**
- Modify: `skills/wiki-query/SKILL.md`

**변경 요약:**
1. Step 1 위에 "Step 0: 질문 분석 (답변형/탐색형 분기)" 추가
2. 탐색형 처리 절차 추가 (프로젝트 컨텍스트 수집 + graphify query)
3. 답변형 처리에 graphify query 폴백 통합
4. comment 필드를 검색 대상에 포함 명시

- [ ] **Step 1: Step 0 (질문 분석 분기) 추가**

`skills/wiki-query/SKILL.md`의 "## 절차" 바로 아래, 기존 "### 1. index.md 읽기" 위에 다음을 삽입:

```markdown
### 0. 질문 분석 — 답변형 vs 탐색형

질문을 분석해서 처리 경로를 결정한다.

**탐색형 시그널 (하나라도 포함되면 탐색형):**
- "이 프로젝트", "여기에", "지금 작업"
- "관련해서 뭐 있어", "관련된 것들"
- "둘러", "뭐가 있", "훑어"
- 질문이 없이 `/wiki-query`만 호출된 경우

**답변형:**
- 위 시그널 없음
- 명시적 질문: "X가 뭐야?", "X 쓰는 법?", "X vs Y"

분기:
- **답변형** → Step 1 (index.md 읽기)로 진행
- **탐색형** → Step 1-A (프로젝트 컨텍스트 수집)로 분기
```

- [ ] **Step 2: 탐색형 전용 섹션 1-A 추가**

기존 "### 1. index.md 읽기" 바로 위에 다음 섹션을 삽입:

```markdown
### 1-A. 탐색형 처리 (프로젝트 컨텍스트 기반 관련 페이지 찾기)

**이 단계는 Step 0에서 탐색형으로 분기된 경우에만 실행.** 답변형이면 Step 1로.

#### 1-A-1. 프로젝트 컨텍스트 압축 수집 (≤50줄)

현재 작업 디렉토리에서 다음을 수집하되 **압축**한다 (각 항목 최대 크기 준수):

| 항목 | 수집 방식 | 최대 크기 |
|------|----------|----------|
| 프로젝트명 | 작업 디렉토리 basename 또는 package.json의 `name` | 1줄 |
| 기술 스택 | `package.json` / `pyproject.toml` / `Cargo.toml` 의 의존성 이름만 (버전 제외) | 20줄 |
| CLAUDE.md 요약 | CLAUDE.md가 있으면 헤더 + 첫 섹션만, 또는 300자 이내 요약 | 20줄 |
| 최근 커밋 | `git log --oneline -10` (git repo인 경우만) | 10줄 |
| 프로젝트 위키 페이지 | `wiki/projects/{프로젝트명}.md`가 있으면 frontmatter의 description만 | 3줄 |

**합계 ≤ 50줄 준수.** 넘으면 가장 긴 항목부터 추가 압축.

없는 항목은 건너뜀 (예: git repo 아니면 커밋 수집 생략).

#### 1-A-2. graphify query 실행

```bash
command -v graphify
```

- 성공 → graphify query 실행
- 실패 → 폴백 (index.md 전체 스캔 + 프로젝트 컨텍스트로 필터링)

**실행:**
```bash
graphify query "프로젝트 컨텍스트:\n${CONTEXT}\n\n위 프로젝트와 관련된 위키 페이지를 찾아주세요. 직접 관련, 간접 관련, 잠재 유용으로 분류해주세요."
```

여기서 `${CONTEXT}`는 1-A-1에서 수집한 압축 컨텍스트. vault 경로는 graphify가 현재 vault의 graph.json을 참조하도록 환경변수로 전달하거나 vault 디렉토리에서 실행.

**vault 경로 전달 방법:**
```bash
cd "${VAULT_PATH}" && graphify query "..."
```

#### 1-A-3. 결과 프레젠테이션 (지연 로딩)

graphify query 결과를 **페이지 목록만** 출력. 내용은 읽지 않음:

```
[프로젝트: <프로젝트명>]
[기술 스택: <스택 요약>]

관련 위키 페이지:

직접 관련 (N):
  - [[page-a]] — 한 줄 설명
  - [[page-b]] — 한 줄 설명

간접 관련 (N):
  - [[page-c]] — 한 줄 설명

잠재 유용 (N):
  - [[page-d]] — 한 줄 설명

다음 동작?
  > 전체 읽어줘 / N번만 자세히 / 이대로 끝내
```

**사용자 후속 입력에 따라:**
- "전체 읽어줘" → 모든 페이지 Read → 답변형 Step 3로 진행
- "N번만" → 해당 페이지만 Read → 해당 페이지 중심으로 답변
- "끝내" → 여기서 종료
```

- [ ] **Step 3: 답변형 Step 2에 graphify query 폴백 추가**

기존 "### 2. 관련 페이지 탐색" 섹션 맨 아래에 다음 문단 추가:

```markdown
**index.md 기반 탐색이 불충분할 때 (graphify query 폴백):**

다음 조건 중 하나면 graphify query로 심층 탐색:
- index.md에서 관련 페이지를 1개 미만 찾음
- 질문이 복잡한 관계성을 요구 ("A와 B의 관계", "C에 영향을 준 요인들")

```bash
command -v graphify && [ -f "${VAULT_PATH}/graph.json" ]
```

둘 다 성공 시:
```bash
cd "${VAULT_PATH}" && graphify query "질문 내용"
```

graphify query 결과를 Step 3의 답변 합성에 추가 자료로 활용.

graph.json이 없으면 건너뛰되, 응답 끝에 한 줄 안내 추가: "`/wiki-lint` 실행 후 재질의하면 그래프 기반 심층 답변 가능."
```

- [ ] **Step 4: comment 필드를 검색 대상에 포함 명시**

기존 "### 2. 관련 페이지 탐색" 섹션 시작부에 다음 문단 추가:

```markdown
**검색 대상 필드:**
- 페이지 본문
- frontmatter의 `description`
- frontmatter의 `comment` (신규) — "왜 저장했는지"로 역검색 가능

사용자가 "X 조사하면서 본 거 있어?" 같은 맥락 질의를 하면 `comment` 필드를 우선 매칭.
```

- [ ] **Step 5: 전체 읽고 일관성 확인**

수정된 `skills/wiki-query/SKILL.md`를 읽어:
- Step 0 분기 로직이 명확한지
- Step 1-A의 하위 단계 번호(1-A-1, 1-A-2, 1-A-3)가 일관된지
- 답변형/탐색형 모두 Step 3(답변 합성)으로 수렴하는 구조인지 (또는 탐색형은 별도 프레젠테이션으로 끝나는지)
- comment 필드 활용이 Step 2에 명시되어 있는지

문제 있으면 수정.

- [ ] **Step 6: 커밋**

```bash
git add skills/wiki-query/SKILL.md
git commit -m "feat(wiki-query): 답변형/탐색형 분기 + graphify query 연동 + comment 검색

- Step 0 신규: 질문 분석해서 답변형/탐색형 분기
- Step 1-A 신규: 탐색형은 프로젝트 컨텍스트 압축 수집(≤50줄) → graphify query
- 답변형 Step 2에 graphify query 폴백 추가 (graph.json 있을 때)
- frontmatter comment 필드를 검색 대상에 포함 (역검색 지원)
- graphify 미설치/graph 없음 시 기존 index.md 방식으로 폴백"
```

---

## Task 6: wiki-lint — 풀 그래프 리빌드 + 데이터 갭에 comment 포함

**Files:**
- Modify: `skills/wiki-lint/SKILL.md`

**변경 요약:**
1. 데이터 갭(E) 항목에 `comment` 누락 추가
2. Step 5 신규: 풀 그래프 리빌드

- [ ] **Step 1: 데이터 갭(E)에 comment 누락 추가**

`skills/wiki-lint/SKILL.md`의 "#### E. 데이터 갭 (Gaps)" 섹션을 다음으로 교체:

```markdown
#### E. 데이터 갭 (Gaps)
frontmatter가 불완전한 페이지:
- `description` 누락
- `sources` 비어있음
- `related` 비어있음
- `confidence` 누락
- `comment` 누락 (기존 페이지 마이그레이션 대상)
→ 보완 제안.

**comment 누락 특별 처리:**
기존에 생성된 페이지는 대부분 `comment` 필드가 없다. wiki-lint는 이를 데이터 갭으로 탐지하되, **자동으로 채우지 않고** 사용자에게 다음과 같이 물어본다:

```
⚪ comment 누락 페이지 N건. 어떻게 할까요?

[a] 페이지별로 대화형 입력 받기
[b] 일괄 "migrated - 코멘트 없이 생성된 초기 페이지" 로 채우기
[s] 건너뛰기 (다음 lint에서 다시 물음)
```
```

- [ ] **Step 2: Step 5 (풀 그래프 리빌드) 추가**

기존 "## 주의사항" 섹션 바로 위에 다음 섹션을 삽입:

```markdown
### 5. 그래프 풀 리빌드

Step 4 수정이 모두 끝나면 vault 그래프를 **풀 리빌드**한다. lint는 주 1회 수행되므로 정합성 보장을 위해 증분이 아닌 풀 빌드.

**조건 체크:**
```bash
command -v graphify
```

- 성공 → 풀 빌드 실행
- 실패 → 건너뜀 + 사용자에게 1회 안내: "graphify 미설치로 그래프 리빌드 건너뜀. `/rakis:setup` 실행 권장."

**실행:**
```bash
graphify "${VAULT_PATH}"
```

(--update 플래그 없음 = 풀 빌드)

**실행 결과 보고:**
Step 4의 "수정 실행 보고" 끝에 그래프 리빌드 결과 요약 추가:

```
## 위키 린트 완료 (YYYY-MM-DD)

수정: N건
  - 모순 해결: N
  - 링크 보강: N
  - comment 보완: N

그래프 리빌드: 완료 (노드 N개, 엣지 N개)
```

**실패 처리:**
- graphify 실행 실패 시 lint 자체는 성공으로 처리
- 실패 메시지만 보고: "그래프 리빌드 실패 — 다음 lint에서 재시도"
```

- [ ] **Step 3: 전체 읽고 일관성 확인**

수정된 `skills/wiki-lint/SKILL.md`를 읽어:
- 데이터 갭에 comment가 포함되어 있는지
- Step 5가 Step 4(수정 실행) 다음에 배치되었는지
- 보고서 형식에 그래프 리빌드 결과가 포함되는지
- 주 1회 권장 주기와 풀 빌드 선택이 일관되는지

문제 있으면 수정.

- [ ] **Step 4: 커밋**

```bash
git add skills/wiki-lint/SKILL.md
git commit -m "feat(wiki-lint): 풀 그래프 리빌드 + 데이터 갭에 comment 누락 포함

- 데이터 갭(E) 항목에 comment 누락 탐지 추가 (기존 페이지 마이그레이션)
- comment 누락 처리 3-way 옵션: 대화형/일괄/건너뛰기
- Step 5 신규: graphify <vault> 풀 리빌드 (주 1회 정합성 보장)
- graphify 미설치 시 건너뜀 + 1회 안내"
```

---

## Task 7: `/wiki-init` 신규 스킬

**Files:**
- Create: `skills/wiki-init/SKILL.md`

**변경 요약:** 인터뷰 기반 vault 초기화 스킬 신규 생성.

- [ ] **Step 1: `skills/wiki-init/SKILL.md` 파일 생성**

다음 내용으로 파일을 생성:

````markdown
---
name: wiki-init
description: "Obsidian LLM Wiki vault 초기 세팅. '/wiki-init' 실행 또는 '위키 초기화'라고 할 때 사용. 인터뷰로 vault 경로/사용자 프로필을 수집하고 Karpathy 3-Layer 구조(raw/, wiki/, index.md, log.md, CLAUDE.md)를 자동 생성한다. 멱등성 보장 — 기존 구조는 보완만."
version: 1.0.0
license: MIT
---

# wiki-init — Obsidian LLM Wiki vault 초기화

프로젝트 폴더에서 실행하여 외부 vault 경로에 Karpathy 3-Layer 구조를 원격 생성한다. rakis는 프로젝트 중심 사용 패턴이므로 Claude 실행 위치는 프로젝트, vault는 저장소.

## 절차

### 1. 기존 상태 체크 (멱등성)

아래 순서로 vault 경로를 탐지:
1. 환경변수 `OBSIDIAN_VAULT_PATH`
2. 사용자가 직접 입력 (Step 2의 인터뷰에서 받음)

**이미 경로가 결정되어 있으면 바로 상태 체크로 진행.** 없으면 Step 2로.

```bash
# 상태 체크 결정 트리
[ -d "${VAULT_PATH}" ] || echo "not_exists"
[ -f "${VAULT_PATH}/CLAUDE.md" ] && echo "claude_md_exists"
[ -d "${VAULT_PATH}/wiki" ] && echo "wiki_exists"
[ -d "${VAULT_PATH}/raw" ] && echo "raw_exists"
```

**분기:**

| 상태 | 분기 |
|------|------|
| 경로 없음 | Step 2(인터뷰)부터 전체 실행 |
| 경로 있음 + 폴더 전부 없음 | Step 3(구조 생성)으로 |
| 경로 있음 + 일부 폴더만 있음 | "기존 구조 감지됨. 부족한 부분만 보완할까요? (y/n)" → y면 Step 3 부분 실행 |
| CLAUDE.md 이미 있음 | "이미 초기화됨. 재설정? (기존 CLAUDE.md는 .bak 백업) (y/n)" → y면 Step 2부터 |
| 완전히 세팅됨 + CLAUDE.md 있음 | "이미 완료. 변경 없음" 출력 후 Step 6(완료 리포트)으로 직행 |

### 2. 인터뷰 (질문은 하나씩, 순서대로)

각 질문은 **한 번에 하나씩** 보여주고 답을 받는다. 사용자가 빈 답을 주면 기본값을 사용하거나 재질문.

**질문 1: vault 경로**

```
vault 경로를 입력하세요.
기본값 (iCloud Obsidian): ~/Library/Mobile Documents/com~apple~CloudDocs/Documents/Vault
Enter = 기본값 사용
> _____
```

입력이 있으면 `~` 확장, 절대 경로로 변환하여 `VAULT_PATH` 변수에 저장.

**질문 2: 역할**

```
당신의 역할/직무는 무엇인가요? (예: 백엔드 개발자, 데이터 엔지니어, AI 연구자)
> _____
```

빈 답이면 재질문. 결과를 `USER_ROLE` 변수에 저장.

**질문 3: 목적**

```
이 vault를 어떤 목적으로 사용하시나요? (예: 기술 조사 축적, 프로젝트 지식 관리, 논문 정리)
> _____
```

결과를 `USER_PURPOSE` 변수에 저장.

**질문 4: 자료 형태 (복수 선택)**

```
주로 어떤 자료를 저장하실 건가요? (복수 선택, 쉼표 구분)
[1] 블로그 글 / 웹 아티클
[2] 논문 / PDF
[3] GitHub 저장소
[4] YouTube 영상
[5] 강의 자료 / 슬라이드
[6] 기타 (자유 기술)

예: 1,2,3 또는 "주로 블로그랑 논문"
> _____
```

결과를 `USER_SOURCES` 변수에 저장 (자연어 그대로 보관).

**질문 5: 관심 분야**

```
주요 관심 분야/기술 스택은? (자유 기술, 쉼표 구분 권장)
예: Flutter, AI Agent, RAG, LangChain
> _____
```

결과를 `USER_INTERESTS` 변수에 저장.

**질문 6: 선호 아웃풋**

```
위키에서 선호하는 아웃풋 형태는? (예: 한국어 요약, 영문 원문 유지, 비교표 위주, 초보자용 설명)
> _____
```

결과를 `USER_OUTPUT_PREF` 변수에 저장.

### 3. 구조 생성

**폴더 생성:**

```bash
mkdir -p "${VAULT_PATH}/raw/articles"
mkdir -p "${VAULT_PATH}/raw/papers"
mkdir -p "${VAULT_PATH}/raw/repos"
mkdir -p "${VAULT_PATH}/raw/data"
mkdir -p "${VAULT_PATH}/raw/images"
mkdir -p "${VAULT_PATH}/wiki/concepts"
mkdir -p "${VAULT_PATH}/wiki/entities"
mkdir -p "${VAULT_PATH}/wiki/sources"
mkdir -p "${VAULT_PATH}/wiki/comparisons"
mkdir -p "${VAULT_PATH}/wiki/projects"
```

**각 하위 폴더에 .gitkeep 생성:**

```bash
touch "${VAULT_PATH}/raw/articles/.gitkeep"
touch "${VAULT_PATH}/raw/papers/.gitkeep"
touch "${VAULT_PATH}/raw/repos/.gitkeep"
touch "${VAULT_PATH}/raw/data/.gitkeep"
touch "${VAULT_PATH}/raw/images/.gitkeep"
touch "${VAULT_PATH}/wiki/concepts/.gitkeep"
touch "${VAULT_PATH}/wiki/entities/.gitkeep"
touch "${VAULT_PATH}/wiki/sources/.gitkeep"
touch "${VAULT_PATH}/wiki/comparisons/.gitkeep"
touch "${VAULT_PATH}/wiki/projects/.gitkeep"
```

**index.md 템플릿 생성 (없을 때만):**

```bash
[ -f "${VAULT_PATH}/index.md" ] || cat > "${VAULT_PATH}/index.md" <<'EOF'
# Wiki Index

LLM이 관리하는 마스터 카탈로그. 새 페이지 생성 시 반드시 업데이트.

## Concepts

(비어있음 — 첫 자료 수집 시 자동 생성)

## Entities

(비어있음)

## Sources

(비어있음)

## Comparisons

(비어있음)

## Projects

(비어있음)
EOF
```

**log.md 템플릿 생성 (없을 때만):**

```bash
[ -f "${VAULT_PATH}/log.md" ] || cat > "${VAULT_PATH}/log.md" <<'EOF'
# Wiki Log

시간순 기록. 자료 수집/분석/린트 이력.

EOF
```

### 4. vault CLAUDE.md 생성

인터뷰 결과를 반영한 CLAUDE.md를 vault 루트에 생성. **기존 CLAUDE.md가 있으면 Step 1에서 백업 합의 후** `.bak`로 이동하고 재생성.

```bash
cat > "${VAULT_PATH}/CLAUDE.md" <<EOF
# Vault Schema

이 vault는 Karpathy LLM Wiki 방법론(3-Layer)으로 관리된다. rakis 플러그인 스킬을 통해 수집·질의·점검이 이루어진다.

## User Profile
- 역할: ${USER_ROLE}
- 목적: ${USER_PURPOSE}
- 관심 분야: ${USER_INTERESTS}

## Input
주로 수집하는 자료: ${USER_SOURCES}

## Output
선호 아웃풋: ${USER_OUTPUT_PREF}

## Rules

### raw/ (Immutable)
- 한 번 저장하면 절대 수정하지 않음
- 원본 그대로 보존 (웹 클리핑, PDF, repomix 등)

### wiki/ (LLM 관리)
- 모든 페이지는 YAML frontmatter 필수
- 필수 필드: title, type, sources, comment, related, created, updated, confidence, description
- \`comment\`: 수집 시 입력한 "왜 저장/분석했는지" (1-2문장 한국어)
- 링크는 \`[[wiki-link]]\` 형식 (상대 링크)
- 태그: #concept, #entity, #tool, #person

### index.md
- 새 페이지 생성 시 반드시 해당 섹션에 추가
- 형식: \`- [[page-name]] — 한 줄 설명\`

### log.md
- 주요 작업 이력 기록
- 형식: \`## [YYYY-MM-DD] page-name | 작업 설명\`

## 페이지 타입별 폴더

| type | 폴더 |
|------|------|
| concept | wiki/concepts/ |
| entity | wiki/entities/ |
| source-summary | wiki/sources/ |
| comparison | wiki/comparisons/ |
| project | wiki/projects/ |

## 언어 규칙
- 기술 용어는 영어 그대로
- 설명/서술은 한국어
EOF
```

### 5. 초기 graphify 빌드

```bash
command -v graphify
```

- 성공 + vault에 페이지가 1개 이상 → 풀 빌드 실행
- 성공 + vault가 비어있음 → 건너뜀, "첫 wiki-ingest 후 자동 빌드됩니다" 안내
- 실패 → 건너뜀, "graphify 미설치. /rakis:setup 권장" 안내

**빈 vault 체크:**
```bash
find "${VAULT_PATH}/wiki" -name '*.md' -not -name '.gitkeep' | head -1
```

출력이 있으면 페이지 존재 → 빌드.

**실행:**
```bash
cd "${VAULT_PATH}" && graphify "${VAULT_PATH}"
```

### 6. 완료 리포트

```
✅ wiki-init 완료

vault: ${VAULT_PATH}
생성된 구조: 5 raw/ + 5 wiki/ 하위폴더
CLAUDE.md: 생성됨 (사용자 프로필 + 규칙)
graphify 초기 빌드: <완료 | 스킵 (빈 vault) | 스킵 (미설치)>

다음 단계:
  1. 환경변수 설정 (선택):
     export OBSIDIAN_VAULT_PATH="${VAULT_PATH}"
  2. 첫 자료 수집:
     /source-analyze <URL> "왜 분석하는지"
  3. 질의:
     "~ 정리된 거 있어?"
```

## 주의사항

- 이 스킬은 프로젝트 폴더에서 실행한다 (vault 폴더에서 실행하는 것은 지원 범위 밖)
- 기존 vault에 덮어쓰기 하지 않음 — 상태 체크 후 보완/재설정/스킵 분기
- CLAUDE.md 백업 시 `.bak` 확장자 사용 (타임스탬프 없음 — 단순히 이전 것만 보존)
- graphify 의존성은 `/rakis:setup`이 설치 담당. wiki-init은 건너뛸 뿐 설치하지 않음.
````

- [ ] **Step 2: 생성된 파일 검증**

```bash
ls skills/wiki-init/SKILL.md && head -10 skills/wiki-init/SKILL.md
```

- frontmatter가 올바른지 (name, description, version)
- description이 트리거 키워드를 포함하는지 ("위키 초기화", "/wiki-init")

- [ ] **Step 3: 전체 읽고 일관성 확인**

`skills/wiki-init/SKILL.md`를 처음부터 끝까지 읽어:
- Step 1~6이 번호 순서대로 진행되는지
- VAULT_PATH 등 변수 참조가 일관되는지
- 멱등성 분기 5가지 케이스가 Step 1에 다 있는지
- Step 4의 CLAUDE.md 템플릿에 인터뷰 결과 변수가 전부 포함되는지

문제 있으면 수정.

- [ ] **Step 4: 커밋**

```bash
git add skills/wiki-init/SKILL.md
git commit -m "feat(wiki-init): 신규 스킬 — vault 인터뷰 기반 원격 초기화

- 인터뷰: vault 경로, 역할, 목적, 자료 형태, 관심 분야, 아웃풋 (6개)
- 구조 생성: raw/ 5개 + wiki/ 5개 하위폴더 + index.md + log.md
- vault CLAUDE.md 자동 생성 (사용자 프로필 + 규칙)
- 멱등성 5분기: 없음/부분/CLAUDE존재/완료/빈폴더
- 초기 graphify 빌드 (빈 vault는 스킵)"
```

---

## Task 8: `/rakis:help` 커맨드 신규 생성

**Files:**
- Create: `commands/help.md`

**변경 요약:** 전체/스킬별 사용법을 출력하는 커맨드.

- [ ] **Step 1: `commands/help.md` 파일 생성**

다음 내용으로 파일을 생성:

````markdown
---
description: rakis 플러그인의 사용법을 안내합니다 (/rakis:help 또는 /rakis:help <스킬명>)
---

# /rakis:help

당신은 rakis 플러그인의 사용법 안내를 담당합니다. 인자 유무에 따라 다르게 응답.

## 인자 파싱

`$ARGUMENTS`를 확인:
- **비어있음** → 전체 개요 출력 (단계 A)
- **스킬명 1개** → 해당 스킬 상세 출력 (단계 B)
- **알 수 없는 이름** → "알 수 없는 스킬" + 사용 가능한 스킬 목록 제시

인식하는 스킬명:
- `wiki-query`, `wiki-ingest`, `source-analyze`, `wiki-wrap-up`, `wiki-lint`, `wiki-init`
- `setup`, `help`, `wc-cp-graph` (커맨드)

## 단계 A: 전체 개요 출력 (인자 없을 때)

아래 내용을 그대로 출력:

```
# rakis — Obsidian LLM Wiki 관리 플러그인

Karpathy의 LLM Knowledge Base 방법론(3-Layer)으로 Obsidian vault에 지식을 축적·질의하는 플러그인.

## 빠른 시작

1. 의존성 설치 (머신당 1회):
   /rakis:setup

2. vault 세팅 (vault당 1회):
   /wiki-init

3. 평소 사용:
   - "~ 정리된 거 있어?"           → wiki-query (답변형)
   - "이 프로젝트 관련 뭐 있어?"    → wiki-query (탐색형)
   - "~ 분석해줘"                   → source-analyze
   - "이거 저장해줘"                → wiki-ingest
   - /wiki-wrap-up                  → 세션 끝에 학습 저장

4. 주 1회: /wiki-lint
   (건강 점검 + 그래프 리빌드)

## 전체 스킬/커맨드

스킬:
  wiki-query      — 위키 질의 (답변형/탐색형 자동 분기)
  wiki-ingest     — 자료 저장 (코멘트 강제)
  source-analyze  — 소스 심층 분석 (NotebookLM + 코멘트 강제)
  wiki-wrap-up    — 세션 학습 저장 (코멘트 자동 생성)
  wiki-lint       — 건강 점검 + 풀 그래프 리빌드
  wiki-init       — vault 초기화 (프로젝트 폴더에서 실행)

커맨드:
  /rakis:setup        — 의존성 설치 + 글로벌 CLAUDE.md 매핑
  /rakis:help         — 이 안내 (/rakis:help <스킬명>으로 상세)
  /rakis:wc-cp-graph  — 워크트리 graphify 파일 복사

## 자세히 보기

/rakis:help <이름>     예: /rakis:help wiki-query
```

## 단계 B: 스킬별 상세 출력 (인자 1개)

### wiki-query

```
# wiki-query — 위키 질의

## 용도
vault에 축적된 지식으로 질문에 답변하거나, 프로젝트 관련 위키 탐색.

## 동작 분기
- 답변형: "X가 뭐야?", "X 쓰는 법?"
  → index.md + 관련 페이지 + graphify query(있으면) → 답변 (인용 포함)
- 탐색형: "이 프로젝트 관련 뭐 있어?", "둘러보고 싶어"
  → 프로젝트 컨텍스트 수집(≤50줄) → graphify query → 관련 페이지 목록

## 사용 예시
"openclaw에 대해 정리된 거 있어?"
"riverpod 어떻게 쓰는 거였지?"
"이 프로젝트 관련해서 뭐 있어?"  (프로젝트 폴더에서)

## 트리거
"~ 정리된 거 있어?", "~ 뭐였지?", "~ 찾아봐"
```

### wiki-ingest

```
# wiki-ingest — 자료 저장

## 용도
URL/파일/텍스트를 Obsidian 3-Layer vault에 저장.
raw/에 원본 보존 + wiki/에 요약 페이지 생성 + 관련 페이지 업데이트.

## 사용법
/wiki-ingest <자료> "왜 저장하는지"

인자 없이 호출하면 코멘트를 질문으로 받음.

## 동작
1. 코멘트 수집 (필수)
2. raw/에 원본 저장 (immutable)
3. wiki/sources/에 요약 페이지 + comment frontmatter
4. 관련 페이지 업데이트 + index.md 갱신
5. log.md 기록
6. graphify <vault> --update (그래프 증분)

## 트리거
"저장해줘", "위키에 넣어줘", "정리해줘"
```

### source-analyze

```
# source-analyze — 소스 심층 분석

## 용도
GitHub repo, 블로그, 논문 PDF, YouTube, LinkedIn 등을 NotebookLM으로 심층 분석하고 Obsidian에 축적.

## 사용법
/source-analyze <URL 또는 파일> "왜 분석하는지"

여러 소스 비교:
/source-analyze URL1 URL2 "왜 비교하는지"

## 동작
Phase 0: 코멘트 수집 + 유형 감지
Phase 1: 중복 체크 (캐시 재사용)
Phase 2~4: NotebookLM 병렬 분석
Phase 5: 결과 통합
Phase 6: raw/ + wiki/ 저장 (comment frontmatter 포함)
Phase 7: graphify <vault> --update

## 확장 분석
"더 깊이", "팟캐스트로", "슬라이드로", "퀴즈" 등 후속 요청 가능.

## 트리거
"분석해줘", "파악", "정리", "비교해줘", "vs"
```

### wiki-wrap-up

```
# wiki-wrap-up — 세션 마무리 → 위키 저장

## 용도
세션 종료 전 이 세션의 학습/결정/트러블슈팅을 자동 추출해서 vault에 기록.

## 사용법
/wiki-wrap-up

## 동작
1. 세션 회고 (대화 자동 분석)
   - 새 개념, 해결한 문제, 결정, 패턴
   - 각 항목의 "왜"(comment) 자동 추출
2. 사용자 확인 (전체/선택/코멘트 수정/취소)
3. 승인된 항목 wiki/에 저장 (comment 포함)
4. log.md 기록
5. graphify <vault> --update

## 트리거
"/wiki-wrap-up" 명시 실행 권장
```

### wiki-lint

```
# wiki-lint — 위키 건강 점검

## 용도
vault 품질 정기 점검. 주 1회 권장.

## 사용법
/wiki-lint

## 점검 항목
A. 모순 — 다른 페이지가 같은 사실 다르게 기술
B. 오래된 정보 — updated: 30일 이상 (빠르게 변하는 주제)
C. 고아 페이지 — 아무 곳에서도 링크 안 됨
D. 누락 페이지 — [[link]] 있지만 파일 없음
E. 데이터 갭 — frontmatter 누락 (description, sources, related, confidence, comment)

## 동작
1. 전체 스캔
2. 5가지 점검
3. 카테고리별 리포트
4. 사용자 승인 후 수정 실행
5. graphify <vault> 풀 리빌드 (정합성 보장)

## 트리거
"위키 점검해줘", "위키 정리해줘", "린트해줘"
```

### wiki-init

```
# wiki-init — vault 초기화

## 용도
Obsidian vault에 Karpathy 3-Layer 구조를 자동 생성.
프로젝트 폴더에서 실행 (vault는 외부 경로).

## 사용법
/wiki-init

## 동작
1. 기존 상태 체크 (멱등성)
   - 없음/부분/CLAUDE존재/완료 5분기
2. 인터뷰 (6개 질문)
   - vault 경로, 역할, 목적, 자료 형태, 관심 분야, 아웃풋
3. 구조 생성 (raw/ 5 + wiki/ 5 + index.md + log.md)
4. vault CLAUDE.md 생성 (사용자 프로필 + 규칙)
5. 초기 graphify 빌드 (빈 vault는 스킵)
6. 완료 리포트

## 트리거
"/wiki-init" 명시 실행, "위키 초기화"
```

### setup

```
# /rakis:setup — 의존성 설치

## 용도
rakis 플러그인이 필요로 하는 외부 도구를 설치하고, 글로벌 CLAUDE.md에 스킬 매핑을 추가.

## 설치 대상
- uv (Python 도구 매니저, 전제조건)
- notebooklm-py (NotebookLM CLI)
- node, gh, graphify

## 사용법
/rakis:setup

## 동작
1~2. 전제조건 + 의존성 점검
3~4. 사용자 선택 후 설치 실행
5. notebooklm 인증 안내 (첫 설치 시)
6. 글로벌 ~/.claude/CLAUDE.md에 rakis 스킬 매핑 추가 (동의 시)
7~8. 마커 생성 + 결과 요약

## 멱등성
재실행 안전. 이미 설치된 도구는 --upgrade 실행.
```

### help

```
# /rakis:help — 사용법 안내

## 용도
rakis 전체 또는 특정 스킬/커맨드의 사용법 출력.

## 사용법
/rakis:help            — 전체 개요
/rakis:help <이름>     — 특정 스킬/커맨드 상세
```

### wc-cp-graph

```
# /rakis:wc-cp-graph — 워크트리 헬퍼

## 용도
메인 워크트리의 graphify 산출물(GRAPH_REPORT.md, CLAUDE.md, .claude/settings.json)을 현재 워크트리로 복사.

## 사용법
/rakis:wc-cp-graph

## 동작
메인 워크트리에서 다음을 현재 경로로 복사:
- graphify-out/GRAPH_REPORT.md
- CLAUDE.md (있으면)
- .claude/settings.json (있으면)
```

## 알 수 없는 이름일 때

```
알 수 없는 이름: <입력>

사용 가능한 스킬:
  wiki-query, wiki-ingest, source-analyze, wiki-wrap-up, wiki-lint, wiki-init

사용 가능한 커맨드:
  setup, help, wc-cp-graph

/rakis:help <이름> 형식으로 호출하세요.
```

## 주의사항

- 각 스킬 상세는 하드코딩된 블록을 그대로 출력 (동적 생성 금지 — 일관성 유지)
- 스킬 파일이 수정되면 이 help도 같이 갱신해야 함
````

- [ ] **Step 2: 생성된 파일 검증**

```bash
ls commands/help.md && head -5 commands/help.md
```

frontmatter에 description이 있는지, 인자 처리 분기가 명확한지 확인.

- [ ] **Step 3: 각 스킬 상세 블록 검증**

파일을 읽고 각 스킬별 상세가 실제 스킬 동작과 일치하는지 확인:
- wiki-query: 답변형/탐색형 분기 언급
- wiki-ingest: 코멘트 필수 + Step 6 graphify 언급
- source-analyze: Phase 0 코멘트 + Phase 7 graphify 언급
- wiki-wrap-up: 코멘트 자동 + Step 5 graphify 언급
- wiki-lint: 데이터 갭에 comment + Step 5 풀 리빌드 언급
- wiki-init: 6 질문 인터뷰 + 5분기 멱등성 언급

불일치 있으면 수정.

- [ ] **Step 4: 커밋**

```bash
git add commands/help.md
git commit -m "feat(help): /rakis:help 커맨드 신규 — 전체/스킬별 사용법 안내

- 인자 없음: 빠른 시작 + 전체 스킬/커맨드 목록
- 인자 <이름>: 해당 스킬/커맨드 상세 (용도/동작/트리거/예시)
- 알 수 없는 이름: 사용 가능 목록 제시
- 9개 스킬/커맨드 상세 블록 포함"
```

---

## Task 9: skill-mapping.md 갱신 (신규 스킬/커맨드 반영)

**Files:**
- Modify: `commands/skill-mapping.md`

**변경 요약:** 신규 스킬(`wiki-init`)과 커맨드(`/rakis:help`)를 매핑 테이블에 추가.

- [ ] **Step 1: 매핑 테이블에 항목 추가**

`commands/skill-mapping.md`의 "### 스킬 사용 (필수)" 표에 다음 행을 **순서대로** 추가:

기존 "플러그인 의존성 설치 (최초 1회) | `rakis:setup`" 행 **위에** 다음 행 삽입:

```markdown
| vault 초기 세팅 (vault당 1회) | `rakis:wiki-init` |
| 플러그인 사용법 안내 | `/rakis:help` |
```

최종 표 예상 형태:

```markdown
| 상황 | 스킬 |
|------|------|
| 이전에 조사/저장한 내용 검색·질문 | `rakis:wiki-query` |
| URL·파일·repo 분석 | `rakis:source-analyze` |
| 새 지식을 위키에 저장 | `rakis:wiki-ingest` |
| 세션 마무리 시 학습 기록 | `rakis:wiki-wrap-up` |
| 위키 건강 점검 (주 1회) | `rakis:wiki-lint` |
| 프로젝트 코드 구조 분석 | `/graphify` (graphify 자체 스킬, setup에서 자동 설치) |
| vault 초기 세팅 (vault당 1회) | `rakis:wiki-init` |
| 플러그인 사용법 안내 | `/rakis:help` |
| 플러그인 의존성 설치 (최초 1회) | `rakis:setup` |
```

- [ ] **Step 2: 검증**

수정된 파일을 읽고 표의 행 개수가 9개인지, 각 스킬명/커맨드 표기가 일관된지 확인.

- [ ] **Step 3: 커밋**

```bash
git add commands/skill-mapping.md
git commit -m "chore(skill-mapping): wiki-init, /rakis:help 매핑 추가"
```

---

## Task 10: README.md 갱신

**Files:**
- Modify: `README.md`

**변경 요약:** 신규 스킬/커맨드와 변경된 동작을 README에 반영.

- [ ] **Step 1: 현재 README 확인**

```bash
cat README.md
```

현재 섹션 구조 파악. 일반적으로 다음 섹션이 있을 것: 소개, 설치, 사용법, 스킬 목록.

- [ ] **Step 2: 스킬 목록 섹션 업데이트**

스킬 목록 섹션을 찾아서 (보통 "## 스킬" 또는 "## Skills" 또는 "## 기능"), 목록에 `wiki-init` 추가하고 각 스킬의 한 줄 설명을 최신화:

다음 블록으로 교체 (섹션 제목은 기존 것 유지):

```markdown
## 스킬

| 스킬 | 트리거 | 요약 |
|------|--------|------|
| `wiki-query` | "~ 정리된 거 있어?", "~ 뭐였지?" | 답변형/탐색형 자동 분기. graphify query 연동 |
| `wiki-ingest` | "저장해줘", "정리해줘" | 자료 수집. 코멘트 강제 + 그래프 증분 업데이트 |
| `source-analyze` | "분석해줘", "비교해줘" | NotebookLM 기반 심층 분석 + 코멘트 강제 |
| `wiki-wrap-up` | `/wiki-wrap-up` | 세션 학습 자동 추출 + 코멘트 자동 생성 |
| `wiki-lint` | "위키 점검해줘", 주 1회 | 건강 점검 + graphify 풀 리빌드 |
| `wiki-init` | `/wiki-init`, "위키 초기화" | vault 인터뷰 기반 초기 세팅 |

## 커맨드

| 커맨드 | 요약 |
|--------|------|
| `/rakis:setup` | 의존성 설치 + 글로벌 CLAUDE.md 매핑 |
| `/rakis:help` | 사용법 안내 (전체 또는 `<이름>`) |
| `/rakis:wc-cp-graph` | 워크트리 graphify 파일 복사 |
```

- [ ] **Step 3: 빠른 시작 섹션 추가/업데이트**

README에 "빠른 시작" 또는 "Quick Start" 섹션이 있으면 갱신, 없으면 "## 스킬" 섹션 위에 추가:

```markdown
## 빠른 시작

```bash
# 1. 의존성 설치 (머신당 1회)
/rakis:setup

# 2. vault 세팅 (vault당 1회)
/wiki-init

# 3. 평소 사용
"MCP가 뭐였지?"                    # wiki-query 트리거
"https://... 분석해줘"              # source-analyze 트리거
/wiki-wrap-up                       # 세션 끝에 학습 저장

# 4. 주 1회
/wiki-lint                          # 건강 점검 + 그래프 리빌드

# 자세히
/rakis:help <이름>
```
```

- [ ] **Step 4: 요구사항 섹션 업데이트**

"요구사항" 또는 "의존성" 섹션에 graphify 추가 (이미 있으면 스킵):

```markdown
## 요구사항

- Homebrew (macOS)
- uv (Python 도구 매니저)
- Node.js (repomix 실행용)
- graphify (지식 그래프) — `/rakis:setup`이 자동 설치
- notebooklm-py (NotebookLM CLI) — `/rakis:setup`이 자동 설치
- gh (GitHub CLI)
```

- [ ] **Step 5: 전체 읽고 일관성 확인**

README를 처음부터 끝까지 읽어:
- 스킬 수가 6개인지
- 커맨드 수가 3개인지
- 빠른 시작이 setup → init → 사용 순서인지
- 기존 내용과 충돌이 없는지

문제 있으면 수정.

- [ ] **Step 6: 커밋**

```bash
git add README.md
git commit -m "docs(readme): wiki-init, /rakis:help 반영 및 스킬별 변경 사항 업데이트"
```

---

## Task 11: 버전 bump 2.4.0 → 2.5.0

**Files:**
- Modify: `.claude-plugin/plugin.json`
- Modify: `package.json`

**변경 요약:** SemVer minor bump. 신규 기능 추가 (wiki-init, /rakis:help, graphify 통합, 코멘트 강제).

- [ ] **Step 1: plugin.json 버전 변경**

`/Users/raki-1203/workspace/raki-claude-plugins/.claude-plugin/plugin.json`의 `"version": "2.4.0"`을 `"version": "2.5.0"`으로 변경.

- [ ] **Step 2: package.json 버전 변경**

`package.json`의 `"version": "2.4.0"`을 `"version": "2.5.0"`으로 변경.

- [ ] **Step 3: 변경 확인**

```bash
grep '"version"' .claude-plugin/plugin.json package.json
```

둘 다 `"version": "2.5.0"` 인지 확인.

- [ ] **Step 4: 커밋**

**주의:** 프로젝트에 pre-push hook으로 자동 버전 bump가 있음 (최근 커밋 `07988a5`). 수동 bump 후 별도로 push하면 훅이 다시 bump 시도할 수 있음. 이 커밋은 본 plan의 모든 변경을 마무리하는 의미이므로, 훅과 충돌하지 않도록 수동으로 명시.

```bash
git add .claude-plugin/plugin.json package.json
git commit -m "chore: bump version to 2.5.0

브레인 트리니티 영상 기반 3+1 개선:
- graphify 위키 통합 (쓰는 스킬 증분, lint 풀 리빌드, query 연동)
- 수집 시 코멘트 강제 (source-analyze, wiki-ingest, wiki-wrap-up)
- /wiki-init 신규 스킬 (vault 인터뷰 기반 초기화)
- /rakis:help 신규 커맨드 (사용법 안내)"
```

- [ ] **Step 5: 최종 검증**

```bash
git log --oneline -15
```

이 plan의 커밋들이 순서대로 있는지 확인:
1. `feat(wiki-ingest): ...`
2. `feat(source-analyze): ...`
3. `feat(wiki-wrap-up): ...`
4. `feat(wiki-query): ...`
5. `feat(wiki-lint): ...`
6. `feat(wiki-init): ...`
7. `feat(help): ...`
8. `chore(skill-mapping): ...`
9. `docs(readme): ...`
10. `chore: bump version to 2.5.0`

그 위에 design 커밋 `a481342 docs: brain-trinity 영상 기반...`.

모든 커밋이 있으면 plan 완료.

---

## Task 12: 최종 검증

**Files:** 변경 없음

**변경 요약:** 구현 전체가 스펙을 만족하는지 수동 검증.

- [ ] **Step 1: 스펙 재확인**

`docs/superpowers/specs/2026-04-14-brain-trinity-improvements-design.md`를 읽고 아래 체크리스트 수행:

- [ ] 개선 1 (graphify 통합): wiki-ingest, source-analyze, wiki-wrap-up, wiki-lint, wiki-query에 각각 graphify 관련 섹션이 있는가?
- [ ] 개선 2 (코멘트 강제): source-analyze, wiki-ingest는 입력 필수. wiki-wrap-up은 자동 생성. comment frontmatter가 3개 스킬 모두에 명시되어 있는가?
- [ ] 개선 3 (wiki-init): skills/wiki-init/SKILL.md가 존재하고 6개 인터뷰 질문 + 5분기 멱등성이 있는가?
- [ ] 보너스 (/rakis:help): commands/help.md가 존재하고 9개 스킬/커맨드 상세 블록이 있는가?
- [ ] 비범위: 프로젝트 코드 그래프 관리 관련 코드가 추가되지 않았는가? (변경 파일 범위가 스펙과 일치)

- [ ] **Step 2: graphify 미설치 시 동작 수동 확인**

모든 스킬이 `command -v graphify` 체크 후 미설치 시 해당 단계를 건너뛰는 분기가 있는지 확인:
- `grep -l "command -v graphify" skills/*/SKILL.md`
- 결과에 wiki-ingest, source-analyze, wiki-wrap-up, wiki-lint, wiki-query, wiki-init이 모두 나와야 함 (최소 graphify 언급)

- [ ] **Step 3: 트리거 일관성 확인**

`grep -h "description:" skills/*/SKILL.md` 로 각 스킬의 description을 확인. 한국어 트리거 키워드가 포함되어 있어야 함.

- [ ] **Step 4: 완료 보고**

사용자에게 완료 리포트:

```
✅ Brain Trinity 영상 기반 rakis 개선 완료

커밋: 10건
신규 파일: 2 (wiki-init/SKILL.md, help.md)
수정 파일: 7 (wiki-query, wiki-ingest, source-analyze, wiki-wrap-up, wiki-lint, skill-mapping, README)
버전: 2.4.0 → 2.5.0

테스트 방법:
  1. /rakis:setup (의존성 확인)
  2. /wiki-init (새 vault 경로로 인터뷰)
  3. 기존 vault에서 /wiki-init 재실행 (멱등성 확인)
  4. /rakis:help, /rakis:help wiki-query (상세 확인)
  5. 아무 자료로 source-analyze 실행 (코멘트 질문 확인)
  6. /wiki-lint 실행 (풀 그래프 리빌드 확인)
```

---

## Self-Review (계획 작성자 체크)

### 1. 스펙 커버리지

| 스펙 요구사항 | 구현 Task |
|-------------|----------|
| graphify 위키 통합 — wiki-ingest/source-analyze/wrap-up 증분 | Task 2, 3, 4 |
| graphify 위키 통합 — wiki-lint 풀 리빌드 | Task 6 |
| graphify 위키 통합 — wiki-query 답변/탐색 분기 | Task 5 |
| 코멘트 강제 — source-analyze 인자/질문 | Task 3 |
| 코멘트 강제 — wiki-ingest 인자/질문 | Task 2 |
| 코멘트 강제 — wrap-up 자동 생성 | Task 4 |
| frontmatter comment 필드 | Task 2, 3, 4 |
| 기존 페이지 호환 — lint 데이터 갭 | Task 6 |
| /wiki-init 신규 | Task 7 |
| /rakis:help 신규 | Task 8 |
| skill-mapping 갱신 | Task 9 |
| README 갱신 | Task 10 |
| 버전 bump | Task 11 |

**모든 스펙 요구사항이 task에 대응됨.**

### 2. 플레이스홀더 스캔

- "TBD", "TODO", "implement later" 없음
- 모든 스텝에 구체적인 파일 경로/명령어/코드 블록 있음
- "Similar to Task N" 없음 (각 task가 자기 완결적)

### 3. 타입/명칭 일관성

- `VAULT_PATH` 변수명이 wiki-ingest/source-analyze/wiki-wrap-up/wiki-lint/wiki-init/wiki-query 전체에서 동일
- `comment` frontmatter 필드명이 5개 스킬에서 동일
- `graphify <vault> --update` (증분) vs `graphify <vault>` (풀) 구분 일관
- `Step 0` (코멘트 수집)은 ingest/source-analyze에서 공통 명칭

### 4. 결론

플랜 적절. 실행 가능.
