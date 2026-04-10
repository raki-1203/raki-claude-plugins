# Agent 프롬프트 상세

Phase 2~4에서 디스패치하는 서브에이전트의 프롬프트 템플릿. SKILL.md의 파이프라인 흐름에서 참조.

## Phase 2: 병렬 정보 수집

> **병렬 디스패치**: 아래 4개 Agent를 하나의 메시지에서 동시에 호출한다.

### Agent A: 커뮤니티 활성도 [Haiku]

```
Agent(
  model: "haiku",
  description: "GitHub 커뮤니티 활성도 수집",
  prompt: "Bash 도구를 사용하여 다음 GitHub repo의 커뮤니티 활성도를 수집하라: {owner}/{repo}

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
  prompt: "Bash 도구를 사용하여 NotebookLM에 새 노트북을 생성하고 소스를 업로드하라. notebooklm은 로컬에 설치된 CLI 도구다.

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
  prompt: "Bash 도구를 사용하여 graphify CLI로 repo의 구조적 분석을 수행하라.

1. gh repo clone {owner}/{repo} /tmp/{repo}-graphify --depth 1
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
  prompt: "Bash 도구를 사용하여 NotebookLM 노트북에 질문을 순차적으로 던지고 답변을 수집하라. notebooklm은 로컬에 설치된 CLI 도구다.

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

NotebookLM fallback 모드면 이 Phase는 건너뛴다.

> **병렬 디스패치**: 아래 3개 Agent를 하나의 메시지에서 동시에 호출한다.

### Agent D: 리포트 생성 [Haiku]

```
Agent(
  model: "haiku",
  description: "NotebookLM 리포트 생성",
  prompt: "Bash 도구를 사용하여 NotebookLM에서 study-guide 리포트를 생성하고 다운로드하라.
1. notebooklm use {notebook_id}
2. notebooklm generate report --format study-guide --wait
3. notebooklm download report /tmp/{repo}-report.md
4. Read 도구로 /tmp/{repo}-report.md 읽어서 내용 반환"
)
```

### Agent E: 마인드맵 생성 [Haiku]

```
Agent(
  model: "haiku",
  description: "NotebookLM 마인드맵 생성",
  prompt: "Bash 도구를 사용하여 NotebookLM에서 마인드맵을 생성하고 다운로드하라.
1. notebooklm use {notebook_id}
2. notebooklm generate mind-map
3. notebooklm download mind-map /tmp/{repo}-mindmap.json
4. Read 도구로 /tmp/{repo}-mindmap.json 읽어서 내용 반환"
)
```

### Agent F: 노트북 요약 수집 [Haiku]

```
Agent(
  model: "haiku",
  description: "NotebookLM 노트북 요약 수집",
  prompt: "Bash 도구를 사용하여 NotebookLM 노트북의 AI 생성 요약을 수집하라.
1. notebooklm use {notebook_id}
2. notebooklm summary
반환: 노트북 AI 요약 전문."
)
```
