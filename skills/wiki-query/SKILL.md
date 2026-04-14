---
name: wiki-query
description: "Obsidian LLM Wiki에서 질문에 답변. 사용자가 이전에 조사/저장한 내용에 대해 질문하거나, '~에 대해 정리된 거 있어?', '~ 뭐였지?', '~ 찾아봐'라고 할 때 사용. index.md 기반 탐색 후 위키 인용으로 응답한다."
version: 1.0.0
license: MIT
---

# wiki-query — Obsidian LLM Wiki 질문 답변

위키에 축적된 지식을 기반으로 질문에 답변한다. RAG 대신 **컴파일된 지식**을 활용.

## Vault 경로 탐지

아래 순서로 Vault 경로를 결정:
1. 환경변수 `OBSIDIAN_VAULT_PATH`가 있으면 사용
2. `~/Library/Mobile Documents/com~apple~CloudDocs/Documents/Vault` (iCloud)

## 절차

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

### 1-A. 탐색형 처리 (프로젝트 컨텍스트 기반 관련 페이지 찾기)

**이 단계는 Step 0에서 탐색형으로 분기된 경우에만 실행.** 답변형이면 Step 1로.

#### 1-A-1. 프로젝트 컨텍스트 압축 수집 (≤50줄)

현재 작업 디렉토리에서 다음을 수집하되 **압축**한다 (각 항목 최대 크기 준수):

| 항목 | 수집 방식 | 최대 크기 |
|------|----------|----------|
| 프로젝트명 | 작업 디렉토리 basename 또는 package.json의 `name` | 1줄 |
| 기술 스택 | `package.json` / `pyproject.toml` / `Cargo.toml` 의 의존성 이름만 (버전 제외) | 20줄 |
| CLAUDE.md 요약 | CLAUDE.md가 있으면 헤더 + 첫 섹션만 (전체 300자 초과 시 300자로 절단) | 20줄 |
| 최근 커밋 | `git log --oneline -10` (git repo인 경우만) | 10줄 |
| 프로젝트 위키 페이지 | `wiki/projects/{프로젝트명}.md`가 있으면 frontmatter의 description만 | 3줄 |

**합계 ≤ 50줄 준수.** 넘으면 가장 긴 항목부터 추가 압축.

없는 항목은 건너뜀 (예: git repo 아니면 커밋 수집 생략).

#### 1-A-2. graphify query 실행

**조건 체크:**
```bash
command -v graphify && [ -f "${VAULT_PATH}/graph.json" ]
```

- 둘 다 성공 → graphify query 실행
- 실패 → 폴백: index.md를 전체 읽고 프로젝트 컨텍스트로 필터링하여 관련 페이지 목록 생성. 1-A-3의 동일한 3-카테고리 포맷(직접/간접/잠재)으로 출력하되, 분류 근거는 컨텍스트 매칭도에 기반.

**실행:**
```bash
cd "${VAULT_PATH}" && graphify query "프로젝트 컨텍스트:
${CONTEXT}

위 프로젝트와 관련된 위키 페이지를 찾아주세요. 직접 관련, 간접 관련, 잠재 유용으로 분류해주세요."
```

여기서 `${CONTEXT}`는 1-A-1에서 수집한 압축 컨텍스트.

**`${VAULT_PATH}`**: "## Vault 경로 탐지" 섹션의 결과 경로.

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
- "전체 읽어줘" → 모든 페이지 Read → Step 3 답변 합성으로 진행
- "N번만" → 해당 페이지만 Read → 해당 페이지 중심으로 답변
- "끝내" → 여기서 종료

### 1. index.md 읽기

`index.md`를 **반드시 먼저** 읽어 관련 페이지를 파악한다.
이것이 위키의 검색 엔진 역할을 한다.

### 2. 관련 페이지 탐색

**검색 대상 필드:**
- 페이지 본문
- frontmatter의 `description`
- frontmatter의 `comment` (신규) — "왜 저장했는지"로 역검색 가능

사용자가 "X 조사하면서 본 거 있어?" 같은 맥락 질의를 하면 `comment` 필드를 우선 매칭.

index에서 찾은 관련 페이지들을 읽고 정보 수집.
필요하면 각 페이지의 `related:` 링크를 따라 추가 페이지도 탐색.

탐색 우선순위:
1. `wiki/concepts/` — 주제별 정리
2. `wiki/entities/` — 사람/조직 정보
3. `wiki/comparisons/` — 비교 분석
4. `wiki/sources/` — 원본 요약

**index.md 기반 탐색이 불충분할 때 (graphify query 폴백):**

다음 조건 중 하나면 graphify query로 심층 탐색:
- index.md에서 관련 페이지를 1개 미만 찾음
- 질문이 복잡한 관계성을 요구 ("A와 B의 관계", "C에 영향을 준 요인들")

**조건 체크:**
```bash
command -v graphify && [ -f "${VAULT_PATH}/graph.json" ]
```

둘 다 성공 시:
```bash
cd "${VAULT_PATH}" && graphify query "질문 내용"
```

graphify query 결과를 Step 3의 답변 합성에 추가 자료로 활용.

graph.json이 없으면 건너뛰되, 응답 끝에 한 줄 안내 추가: "`/wiki-lint` 실행 후 재질의하면 그래프 기반 심층 답변 가능."

**`${VAULT_PATH}`**: "## Vault 경로 탐지" 섹션의 결과 경로.

### 3. 답변 합성

- 위키 페이지를 `[[wiki-link]]` 형태로 인용하며 답변
- 여러 페이지의 정보를 종합할 때 출처를 명시
- `confidence`가 low인 정보는 불확실하다고 표시
- `updated:` 날짜가 오래된 정보는 "최신 정보가 아닐 수 있음" 표시

### 4. 새 페이지 생성 (선택적)

답변이 충분히 가치 있고 기존에 없는 내용이면:
- 적절한 `wiki/` 하위 폴더에 새 페이지 생성
- YAML frontmatter 포함 (type, sources, related, created, updated, confidence, description)
- `index.md` 갱신
- `log.md` 기록

## 응답 형식

```markdown
## 답변

[위키 기반 답변 내용]

**참조한 위키 페이지:**
- [[page-1]] — 관련 내용 요약
- [[page-2]] — 관련 내용 요약
```

## 위키에 없는 경우

위키에 없는 내용은 **명확히** 알려준다:

```
위키에 아직 관련 내용이 없습니다.
조사해서 위키에 추가할까요?
```

사용자가 동의하면 → wiki-ingest 절차로 전환.

## 주의사항

- 위키 정보가 오래되었을 수 있으므로 `updated:` 날짜 항상 확인
- 위키에 없는 내용을 있는 것처럼 답변하지 말 것
- 웹 검색이 필요하면 사용자에게 ingest 제안
- 답변 시 반드시 출처 페이지를 인용
