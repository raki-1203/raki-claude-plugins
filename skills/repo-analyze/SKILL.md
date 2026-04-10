---
name: repo-analyze
description: "GitHub repo를 자동 분석하여 Obsidian 위키에 지식으로 축적. GitHub URL과 함께 '분석', '파악', '정리', '알아봐', '분석해줘', '이게 뭐야', '살펴봐'라고 하면 이 스킬 사용. '/repo-analyze URL'로도 직접 호출 가능. 여러 URL을 한번에 비교 분석도 가능('비교해줘', 'vs'). repomix로 repo 전체를 문서화하고, NotebookLM을 핵심 분석 엔진으로 사용하여 요약·리포트·마인드맵을 자동 생성. 분석 후 '더 깊이', '비교해줘', '팟캐스트로', '슬라이드로' 등 추가 분석도 지원. 이미 분석된 repo는 캐시 재사용."
version: 1.0.0
license: MIT
---

# repo-analyze — GitHub Repo 자동 분석 + Obsidian 위키 축적

GitHub repo URL을 입력하면 NotebookLM을 핵심 엔진으로 사용하여 자동 분석하고, 결과를 Obsidian 위키에 저장한다.

## 파이프라인 개요

```
URL 입력 → 중복 체크 → repomix (캐시 or 신규) → 병렬 수집 → NotebookLM 분석 → 병렬 생성 → 통합 → Obsidian 저장
```

## Phase 0: 중복 체크 + 캐시 재사용

스킬 실행 시 가장 먼저 기존 분석 여부를 확인한다.

### 단일 소스 모드

1. URL에서 `{owner}/{repo}` 파싱
2. Obsidian `wiki/sources/{repo}.md` 존재 확인 (mcp__obsidian__read_note)
3. 분기:
   - **없음** → 전체 파이프라인 실행
   - **있음** → 사용자에게 선택지 제시:
     > "이미 분석된 repo입니다 ({updated} 기준). 어떻게 할까요?
     > 1) 기존 분석 보기
     > 2) 재분석 (최신 코드 반영)
     > 3) 기존 NotebookLM 노트북에 추가 질의만"
   - 1 선택 → wiki 페이지 읽어서 출력
   - 2 선택 → repomix 재생성 + 기존 NotebookLM 노트북 ID 재사용 (새로 만들지 않음)
   - 3 선택 → wiki에서 노트북 ID 추출 → `notebooklm use {id} && notebooklm ask "질문"`

### 멀티 소스 모드

여러 URL이 주어지거나 "비교해줘", "vs" 키워드가 있으면 멀티 소스 모드로 진입.

1. 각 URL별 중복 체크:
   - 이미 분석됨 → Obsidian `raw/repos/{repo}/repomix.txt` 캐시 재사용
   - 새 소스 → repomix 실행
2. 하나의 NotebookLM 노트북에 모든 소스 합침:
   ```bash
   notebooklm create "비교 분석: {repo1} vs {repo2}"
   notebooklm source add /path/to/repomix-{repo1}.txt
   notebooklm source add /path/to/repomix-{repo2}.txt
   ```
3. 교차 분석 질의 → 비교 문서 생성
4. Obsidian `wiki/comparisons/{repo1}-vs-{repo2}.md`에 저장

### repomix 캐시 전략

repomix 출력을 Obsidian에 보존하여 재사용:
- 첫 분석 시: `/tmp/repomix-{repo}.txt` → Obsidian `raw/repos/{repo}/repomix.txt`에 복사
- 재분석 시: 캐시 존재하면 재사용 (repomix 실행 건너뜀). 사용자가 "재분석" 선택 시만 재생성.

### 대용량 파일 자동 분할

repomix 출력이 클 때 NotebookLM 업로드 실패를 방지:

1. 파일 크기 확인
2. 분기:
   - **< 2MB** → 그대로 업로드
   - **2~10MB** → `repomix --compress` 옵션으로 재생성 시도 → 여전히 크면 분할
   - **> 10MB** → 파일을 2MB 단위로 분할하여 여러 소스로 업로드
3. 분할 시 파일 경계(파일별 구분선)에서 나눔 — 파일 중간에서 자르지 않음

## 사전 조건 확인

스킬 실행 시 가장 먼저 확인:

1. URL에서 `{owner}/{repo}` 파싱
2. `command -v notebooklm` — 없으면 `pip install notebooklm-py` 안내 (PyPI 패키지명: `notebooklm-py`, CLI 명령어: `notebooklm`)
3. `notebooklm auth check --test` — 실패 시 `! notebooklm login` 안내. 사용자가 거부하면 fallback 모드(Claude 직접 분석)로 전환. **NotebookLM 연동은 선택적** — fallback(Claude 직접 분석)으로도 핵심 기능은 동작한다.
4. `gh auth status` — 실패 시 커뮤니티 활성도 수집 건너뜀
5. `command -v graphify` — 없으면 `uv tool install graphifyy --python 3.13` 안내. 없어도 파이프라인은 NotebookLM만으로 동작.

## Phase 1: repomix 실행

캐시 확인 → 없으면 실행:

1. Obsidian `raw/repos/{repo}/repomix.txt` 존재 확인
   - 있고 재분석 아님 → 캐시를 `/tmp/repomix-{repo}.txt`에 복사하여 재사용
   - 없거나 재분석 → repomix 실행:
     ```bash
     npx repomix --remote {owner}/{repo} --output /tmp/repomix-{repo}.txt
     ```
2. 대용량 체크: 파일 크기 > 2MB면 `--compress` 재시도 또는 분할 준비
3. 실행 후 Obsidian `raw/repos/{repo}/repomix.txt`에 캐시 보존

실패 시 fallback:
```bash
gh repo clone {owner}/{repo} /tmp/{repo} --depth 1
npx repomix /tmp/{repo} --output /tmp/repomix-{repo}.txt
```

## 오케스트레이션 규칙

- **변수 치환**: Agent 프롬프트의 `{owner}`, `{repo}`, `{notebook_id}` 등은 템플릿 플레이스홀더다. 디스패치 전에 실제 값으로 치환하여 프롬프트 문자열을 구성한 뒤 Agent를 호출한다.
- **병렬 디스패치**: "병렬" 표기된 Phase에서는 반드시 **하나의 메시지에서 모든 Agent 호출을 동시에 보낸다** (`run_in_background: true`).
- **순차 의존**: Phase N+1은 Phase N의 모든 Agent가 결과를 반환한 후에 시작한다.

## Phase 2: 병렬 정보 수집

> **병렬 디스패치**: 아래 4개 Agent를 하나의 메시지에서 동시에 호출한다 (Agent A, B, C + Agent G).

### Agent A: 커뮤니티 활성도 [Haiku]

```
Agent(
  model: "haiku",
  description: "GitHub 커뮤니티 활성도 수집",
  prompt: "다음 GitHub repo의 커뮤니티 활성도를 수집하라: {owner}/{repo}

실행할 명령어:
1. gh repo view {owner}/{repo} --json stargazerCount,forkCount,issues,updatedAt,pushedAt,createdAt,description,licenseInfo
2. gh api repos/{owner}/{repo}/commits --jq '.[0:5] | .[] | {date: .commit.author.date, message: .commit.message | split(\"\\n\")[0]}'

결과를 아래 형식으로 정리하여 반환:
- 설명: ...
- Stars: ...
- Forks: ...
- 오픈 이슈: ...
- 생성일: ...
- 최근 푸시: ...
- 라이선스: ...
- 최근 커밋 5개: (날짜 + 메시지)"
)
```

### Agent B: repo 분석 + 질문 생성 [Sonnet]

```
Agent(
  model: "sonnet",
  description: "repo 분석 및 맞춤 질문 생성",
  prompt: "다음 파일을 읽고 이 repo의 특성을 분석한 뒤, NotebookLM에 던질 맞춤 질문을 생성하라.

파일: /tmp/repomix-{repo}.txt

절차:
1. 파일을 Read 도구로 읽는다 (대용량이면 처음 3000줄 + 마지막 500줄)
2. repo 유형을 판별한다 (프레임워크, CLI, 라이브러리, 앱, 플러그인, 데이터 파이프라인, AI/ML 등)
3. 공통 질문 5개를 사용한다:
   - '이 프로젝트가 해결하려는 핵심 문제는 무엇이고, 어떤 사용자/상황을 타겟으로 하는가?'
   - '사용된 기술 스택(언어, 프레임워크, 주요 의존성)을 정리하고, 각 선택의 이유를 추론해줘.'
   - '프로젝트 디렉토리 구조를 설명하고, 각 주요 모듈/패키지의 역할과 데이터 흐름을 정리해줘.'
   - '이 프로젝트를 처음 사용하려면 어떻게 설치하고 실행하나? 최소한의 시작 가이드를 작성해줘.'
   - '이 프로젝트의 핵심 강점과 한계를 각각 3가지씩 분석해줘.'
4. repo 유형과 특성에 맞는 맞춤 질문 5~10개를 생성한다

반환 형식:
---
repo_type: {판별된 유형}
summary: {repo 한 줄 요약}
tech_stack: {주요 기술 스택}
questions:
  common:
    - 질문1 ~ 질문5
  custom:
    - 맞춤질문1 ~ 맞춤질문N
---"
)
```

### Agent C: NotebookLM 노트북 생성 [Haiku]

```
Agent(
  model: "haiku",
  description: "NotebookLM 노트북 생성",
  prompt: "NotebookLM에 새 노트북을 생성하고 소스를 업로드하라.

실행할 명령어:
1. notebooklm create \"{owner}/{repo} 분석\"
   - 출력에서 노트북 ID를 파싱
2. notebooklm use {notebook_id}
3. notebooklm source add /tmp/repomix-{repo}.txt
4. notebooklm source add \"https://github.com/{owner}/{repo}\"

반환: 노트북 ID와 소스 업로드 결과.
업로드 실패 시 에러 메시지를 그대로 반환하라."
)
```

### Agent G: graphify 구조 분석 [Sonnet]

> graphify가 설치되어 있을 때만 실행. 미설치 시 건너뜀.

```
Agent(
  model: "sonnet",
  description: "graphify 구조적 분석",
  prompt: "graphify CLI를 사용하여 repo의 구조적 분석을 수행하라.

Bash 도구로 실행:
1. cd /tmp/{repo} (repomix가 클론한 경로) 또는 gh repo clone {owner}/{repo} /tmp/{repo}-graphify --depth 1
2. cd /tmp/{repo}-graphify && graphify

graphify가 생성하는 파일들:
- graphify-out/graph.json — 지식 그래프
- graphify-out/GRAPH_REPORT.md — 갓노드, 서프라이징 연결, 커뮤니티 분석

3. GRAPH_REPORT.md 내용을 Read로 읽어서 전문 반환
4. graph.json에서 주요 통계 반환 (노드 수, 엣지 수, 커뮤니티 수)

반환: GRAPH_REPORT.md 전문 + graph.json 통계 요약"
)
```

## Phase 3: NotebookLM 자동 질의 [Sonnet]

Agent B의 질문 세트와 Agent C의 노트북 ID를 사용한다.

```
Agent(
  model: "sonnet",
  description: "NotebookLM 자동 질의 및 답변 수집",
  prompt: "NotebookLM 노트북에 질문을 순차적으로 던지고 답변을 수집하라.

노트북 ID: {Agent C 결과}
질문 세트: {Agent B 결과의 questions}

절차:
1. notebooklm use {notebook_id}
2. 각 질문에 대해: notebooklm ask \"질문\" → 답변 수집
3. 완료 후 대화 이력 저장: notebooklm history --save

반환: 질문-답변 쌍의 전체 목록.
에러 시: 해당 질문만 건너뛰고 계속 진행."
)
```

**fallback** (NotebookLM 불가 시):

```
Agent(
  model: "sonnet",
  description: "Claude 직접 분석 (NotebookLM fallback)",
  prompt: "/tmp/repomix-{repo}.txt 파일을 읽고 아래 질문들에 답변하라.
질문 세트: {Agent B 결과의 questions}
각 질문에 대해 repomix 출력 기반으로 상세히 답변.
앞에 '(Claude 직접 분석 — NotebookLM 미사용)' 표기."
)
```

## Phase 4: 병렬 콘텐츠 생성

NotebookLM fallback 모드면 이 Phase는 건너뛴다 (Phase 5에서 해당 섹션을 "NotebookLM 미사용 — 해당 항목 없음"으로 표기).

> **병렬 디스패치**: 아래 3개 Agent를 하나의 메시지에서 동시에 호출한다.

### Agent D: 리포트 생성 [Haiku]

```
Agent(
  model: "haiku",
  description: "NotebookLM 리포트 생성",
  prompt: "NotebookLM에서 study-guide 리포트를 생성하고 다운로드하라.
1. notebooklm use {notebook_id}
2. notebooklm generate report --format study-guide --wait
3. notebooklm download report /tmp/{repo}-report.md
반환: 리포트 내용 요약 (200자)."
)
```

### Agent E: 마인드맵 생성 [Haiku]

```
Agent(
  model: "haiku",
  description: "NotebookLM 마인드맵 생성",
  prompt: "NotebookLM에서 마인드맵을 생성하고 다운로드하라.
1. notebooklm use {notebook_id}
2. notebooklm generate mind-map
3. notebooklm download mind-map /tmp/{repo}-mindmap.json
반환: 마인드맵 JSON 내용."
)
```

### Agent F: 노트북 요약 수집 [Haiku]

```
Agent(
  model: "haiku",
  description: "NotebookLM 노트북 요약 수집",
  prompt: "NotebookLM 노트북의 AI 생성 요약을 수집하라.
1. notebooklm use {notebook_id}
2. notebooklm summary
반환: 노트북 AI 요약 전문."
)
```

## Phase 5: 결과 통합 [Sonnet]

모든 에이전트 결과를 하나의 구조화된 문서로 통합한다.

### 출력 문서 구조

```markdown
# {repo명} 분석

## 한 줄 요약
{Agent F의 NotebookLM 요약 또는 Agent B의 summary}

## 커뮤니티 활성도
| 항목 | 값 |
|------|-----|
| Stars | {Agent A} |
| Forks | {Agent A} |
| 최근 커밋 | {Agent A} |
| 오픈 이슈 | {Agent A} |
| 라이선스 | {Agent A} |

## 핵심 분석
{Phase 3 공통 질문 답변을 섹션으로 구조화}

### 이 프로젝트가 해결하는 문제
### 기술 스택과 의존성
### 프로젝트 구조
### 사용법
### 강점과 한계

## 맞춤 분석
{Phase 3 맞춤 질문 답변}

## 리포트
{Agent D 결과 — NotebookLM 미사용 시 "NotebookLM 미사용 — 해당 항목 없음"}

## 마인드맵
{Agent E 결과를 마크다운 계층 목록으로 변환 — NotebookLM 미사용 시 "NotebookLM 미사용 — 해당 항목 없음"}

## 구조적 분석 (graphify)
{Agent G 결과 — graphify 미실행 시 "graphify 미설치 — 해당 항목 없음"}

### God Nodes (핵심 허브)
{GRAPH_REPORT.md에서 추출}

### Surprising Connections
{GRAPH_REPORT.md에서 추출}

### 커뮤니티 구조
{GRAPH_REPORT.md에서 추출}

## NotebookLM
- 노트북 ID: {notebook_id 또는 "미생성"}
- 추가 질의: `notebooklm use {notebook_id} && notebooklm ask "질문"`
```

사용자에게 이 문서를 출력한다.

## Phase 6: Obsidian 저장

Vault 경로 탐지:
1. 환경변수 `OBSIDIAN_VAULT_PATH`
2. `~/Library/Mobile Documents/com~apple~CloudDocs/Documents/Vault`

### 저장 구조

```
raw/repos/{repo명}/
  ├── metadata.md    ← Agent A 결과 (커뮤니티 활성도)
  ├── analysis.md    ← Phase 5 통합 문서 전문
  └── graph-report.md  ← graphify GRAPH_REPORT.md (있을 때만)
```

wiki-ingest의 절차를 따라 직접 실행한다 (스킬 정의: `skills/wiki-ingest/SKILL.md` 참조):
1. `raw/repos/{repo명}/` 에 metadata.md, analysis.md 저장 (immutable)
2. `wiki/sources/{repo명}.md` 생성 — 분석 정제본 (YAML frontmatter 필수)
3. `index.md` 갱신 — 새 페이지 링크 추가
4. `log.md` 기록 — `## [YYYY-MM-DD] {repo명} | repo 분석 저장`
5. 관련 기존 wiki 페이지와 `[[위키링크]]` 연결

## 확장 분석 (사용자 요청 시)

기본 분석 완료 후 사용자가 추가 요청하면 `references/deep-analysis.md`를 읽고 해당 기능을 실행한다.

지원 키워드: "더 깊이", "코드 품질", "비교", "팟캐스트", "슬라이드", "인포그래픽", "퀴즈", "플래시카드"

## 에러 처리 요약

| 실패 지점 | 대응 |
|-----------|------|
| repomix 실패 | gh clone 후 로컬에서 repomix 재시도 |
| NotebookLM 인증 없음 | 사용자에게 로그인 안내 → 거부 시 Claude fallback |
| NotebookLM 업로드 실패 | 2회 재시도 → 실패 시 Claude fallback |
| NotebookLM 질의 실패 | 해당 질문 건너뛰고 진행 |
| NotebookLM 콘텐츠 생성 실패 | 해당 항목 건너뛰고 보고서에 누락 명시 |
| gh CLI 실패 | 커뮤니티 활성도 "수집 실패" 표기 |
| graphify 미설치/실패 | 구조적 분석 건너뛰고 나머지 진행, 보고서에 "graphify 미실행" 표기 |
