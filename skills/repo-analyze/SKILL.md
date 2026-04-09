---
name: repo-analyze
description: "GitHub repo를 자동 분석하여 Obsidian 위키에 지식으로 축적. GitHub URL과 함께 '분석', '파악', '정리', '알아봐', '분석해줘', '이게 뭐야', '살펴봐'라고 하면 이 스킬 사용. '/repo-analyze URL'로도 직접 호출 가능. repomix로 repo 전체를 문서화하고, NotebookLM을 핵심 분석 엔진으로 사용하여 요약·리포트·마인드맵을 자동 생성. 분석 후 '더 깊이', '비교해줘', '팟캐스트로', '슬라이드로' 등 추가 분석도 지원."
version: 1.0.0
license: MIT
---

# repo-analyze — GitHub Repo 자동 분석 + Obsidian 위키 축적

GitHub repo URL을 입력하면 NotebookLM을 핵심 엔진으로 사용하여 자동 분석하고, 결과를 Obsidian 위키에 저장한다.

## 파이프라인 개요

```
URL 입력 → repomix → 병렬 수집 → NotebookLM 분석 → 병렬 생성 → 통합 → Obsidian 저장
```

## 사전 조건 확인

스킬 실행 시 가장 먼저 확인:

1. URL에서 `{owner}/{repo}` 파싱
2. `command -v notebooklm` — 없으면 `pip install notebooklm` 안내
3. `notebooklm auth check --test` — 실패 시 `! notebooklm login` 안내. 사용자가 거부하면 fallback 모드(Claude 직접 분석)로 전환
4. `gh auth status` — 실패 시 커뮤니티 활성도 수집 건너뜀

## Phase 1: repomix 실행

```bash
npx repomix --remote {owner}/{repo} --output /tmp/repomix-{repo}.txt
```

실패 시 fallback:
```bash
gh repo clone {owner}/{repo} /tmp/{repo} --depth 1
npx repomix /tmp/{repo} --output /tmp/repomix-{repo}.txt
```

## Phase 2: 병렬 정보 수집

3개의 서브에이전트를 동시에 디스패치한다. **반드시 하나의 메시지에서 3개 Agent 호출을 병렬로 보낸다.**

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
3. references/common-questions.md의 공통 질문 5개를 확인한다
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

NotebookLM fallback 모드면 이 Phase는 건너뛴다. 3개의 서브에이전트를 동시에 디스패치.

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
2. notebooklm generate mind-map --wait
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
{Agent D 결과}

## 마인드맵
{Agent E 결과 — JSON을 마크다운 계층 목록으로 변환}

## NotebookLM
- 노트북 ID: {notebook_id}
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
  └── analysis.md    ← Phase 5 통합 문서 전문
```

wiki-ingest 스킬을 호출하여:
1. `wiki/sources/{repo명}.md` 생성 — 분석 정제본
2. `index.md` 갱신
3. `log.md` 기록
4. 관련 기존 wiki 페이지와 `[[위키링크]]` 연결

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
