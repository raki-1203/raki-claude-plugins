# repo-analyze 스킬 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** GitHub repo URL을 입력하면 repomix + NotebookLM으로 자동 분석하여 Obsidian 위키에 저장하는 스킬

**Architecture:** 단일 SKILL.md가 파이프라인을 정의하고, 서브에이전트를 병렬 디스패치하여 속도를 최적화한다. NotebookLM이 핵심 분석 엔진이며, 실패 시 Claude가 fallback. 결과는 wiki-ingest 스킬을 통해 Obsidian에 저장.

**Tech Stack:** repomix (npx), notebooklm-py (CLI), gh CLI, 기존 wiki-ingest 스킬

---

## 파일 구조

| 파일 | 역할 |
|------|------|
| `skills/repo-analyze/SKILL.md` | 메인 스킬 — 트리거, 파이프라인 흐름, 서브에이전트 디스패치, 에러 처리 |
| `skills/repo-analyze/references/common-questions.md` | 모든 repo에 공통으로 던지는 질문 5개 + 질문 생성 가이드 |
| `skills/repo-analyze/references/notebooklm-guide.md` | NotebookLM CLI 사용법, fallback 절차, 에러 처리 상세 |
| `skills/repo-analyze/references/deep-analysis.md` | 확장 분석 가이드 — 추가 질의, 콘텐츠 생성(팟캐스트/슬라이드 등) |

---

### Task 1: 공통 질문 템플릿 작성

**Files:**
- Create: `skills/repo-analyze/references/common-questions.md`

- [ ] **Step 1: 공통 질문 파일 작성**

```markdown
# 공통 질문 템플릿

모든 repo 분석에 기본으로 사용하는 질문 세트. 이 질문들은 NotebookLM에 소스 업로드 후 자동으로 질의된다.

## 공통 질문 (5개)

1. "이 프로젝트가 해결하려는 핵심 문제는 무엇이고, 어떤 사용자/상황을 타겟으로 하는가?"
2. "사용된 기술 스택(언어, 프레임워크, 주요 의존성)을 정리하고, 각 선택의 이유를 추론해줘."
3. "프로젝트 디렉토리 구조를 설명하고, 각 주요 모듈/패키지의 역할과 데이터 흐름을 정리해줘."
4. "이 프로젝트를 처음 사용하려면 어떻게 설치하고 실행하나? 최소한의 시작 가이드를 작성해줘."
5. "이 프로젝트의 핵심 강점과 한계(또는 개선이 필요한 부분)를 각각 3가지씩 분석해줘."

## 맞춤 질문 생성 가이드

Claude(Sonnet)가 repomix 출력을 읽고 repo 특성에 맞는 추가 질문 5~10개를 동적으로 생성한다.

### 질문 생성 원칙

- repo 유형을 먼저 판별: 프레임워크, CLI 도구, 라이브러리, 애플리케이션, 플러그인, 데이터 파이프라인 등
- 해당 유형에서 중요한 관점으로 질문 생성
- "예/아니오"로 끝나는 질문 금지 — 분석적 답변을 유도하는 질문으로

### 유형별 질문 방향 예시

| repo 유형 | 질문 방향 |
|-----------|----------|
| 프레임워크 | 확장 포인트, 플러그인 시스템, 미들웨어 구조, 마이그레이션 전략 |
| CLI 도구 | 명령어 구조, 설정 관리, 파이프라인 연동, 에러 처리 |
| 라이브러리 | API 설계, 타입 안전성, 번들 크기, 트리쉐이킹, 호환성 |
| 애플리케이션 | 아키텍처 패턴, 상태 관리, 인증/인가, 배포 전략 |
| 데이터 파이프라인 | 스케일링, 에러 복구, 모니터링, 데이터 스키마 |
| AI/ML | 모델 구조, 학습 파이프라인, 추론 최적화, 벤치마크 |
```

- [ ] **Step 2: 커밋**

```bash
git add skills/repo-analyze/references/common-questions.md
git commit -m "feat(repo-analyze): add common questions template"
```

---

### Task 2: NotebookLM 가이드 작성

**Files:**
- Create: `skills/repo-analyze/references/notebooklm-guide.md`

- [ ] **Step 1: NotebookLM 가이드 파일 작성**

```markdown
# NotebookLM 연동 가이드

notebooklm-py CLI를 사용하여 NotebookLM과 프로그래밍 방식으로 연동한다.

## 사전 조건 확인

스킬 실행 시 가장 먼저 notebooklm-py 설치 여부와 인증 상태를 확인한다.

### 설치 확인

```bash
command -v notebooklm || pip install notebooklm
```

### 인증 확인

```bash
notebooklm auth check --test
```

실패 시 사용자에게 안내:
> "NotebookLM 인증이 필요합니다. `! notebooklm login` 을 실행하여 Google 계정으로 로그인해주세요."

인증이 불가능한 환경이면 fallback(Claude 직접 분석)으로 전환한다.

## 노트북 생성

```bash
notebooklm create "{owner}/{repo} 분석"
```

출력에서 노트북 ID를 파싱하여 이후 단계에 전달한다.

## 소스 업로드

repomix 출력 파일을 소스로 추가:

```bash
notebooklm use {notebook_id}
notebooklm source add "/tmp/repomix-{repo}.txt"
```

GitHub repo URL도 추가 소스로 등록:

```bash
notebooklm source add "https://github.com/{owner}/{repo}"
```

### 파일 크기 제한

- 20MB 초과 시 업로드가 타임아웃될 수 있음
- 대안 1: repomix의 `--compress` 옵션 사용
- 대안 2: 파일을 분할하여 여러 소스로 업로드
- 대안 3: fallback으로 전환

## 질의

노트북을 활성화한 상태에서 질문:

```bash
notebooklm use {notebook_id}
notebooklm ask "질문 내용"
```

답변은 stdout으로 출력된다. 각 질문의 답변을 수집하여 분석 문서에 포함한다.

## 콘텐츠 생성

### 리포트

```bash
notebooklm generate report --format study-guide --wait
notebooklm download report ./report.md
```

### 마인드맵

```bash
notebooklm generate mind-map --wait
notebooklm download mind-map ./mindmap.json
```

### 오디오 (팟캐스트)

```bash
notebooklm generate audio "이 프로젝트의 핵심을 설명해줘" --format deep-dive --length default --wait
notebooklm download audio ./podcast.mp3
```

### 슬라이드

```bash
notebooklm generate slide-deck --format detailed --wait
notebooklm download slide-deck ./slides.pptx --format pptx
```

### 인포그래픽

```bash
notebooklm generate infographic --orientation landscape --wait
notebooklm download infographic ./infographic.png
```

## 대화 이력 저장

```bash
notebooklm history --save
```

## Fallback: Claude 직접 분석

NotebookLM 연동 실패 시 Claude가 직접 분석한다.

### 전환 조건

다음 중 하나라도 해당하면 fallback으로 전환:
1. `notebooklm auth check --test` 실패 + 사용자가 로그인 거부
2. 소스 업로드 2회 연속 실패
3. 노트북 생성 실패

### fallback 절차

1. repomix 출력 파일을 Read 도구로 직접 읽기
2. 공통 질문 + 맞춤 질문에 대해 Claude가 직접 답변 생성
3. 리포트/마인드맵 생성은 건너뜀 (NotebookLM 전용 기능)
4. 결과 문서에 "NotebookLM 미사용 — Claude 직접 분석" 표기
5. NotebookLM 노트북 ID 항목은 "미생성" 표기
```

- [ ] **Step 2: 커밋**

```bash
git add skills/repo-analyze/references/notebooklm-guide.md
git commit -m "feat(repo-analyze): add NotebookLM integration guide"
```

---

### Task 3: 확장 분석 가이드 작성

**Files:**
- Create: `skills/repo-analyze/references/deep-analysis.md`

- [ ] **Step 1: 확장 분석 가이드 파일 작성**

```markdown
# 확장 분석 가이드

기본 분석 완료 후 사용자가 추가 요청 시 실행하는 확장 기능들.

## 트리거 키워드

| 사용자 표현 | 실행할 기능 |
|------------|-----------|
| "더 깊이 분석해줘", "코드 품질 봐줘" | 추가 질의 |
| "유사 프로젝트 비교해줘" | NotebookLM 리서치 + 비교 질의 |
| "팟캐스트로 만들어줘", "오디오로" | 오디오 생성 |
| "슬라이드로 정리해줘", "PPT로" | 슬라이드 생성 |
| "인포그래픽", "시각화해줘" | 인포그래픽 생성 |
| "퀴즈 만들어줘" | 퀴즈 생성 |
| "플래시카드" | 플래시카드 생성 |

## 추가 질의

기본 분석에서 다루지 않은 깊은 주제를 NotebookLM에 질의한다.

### 코드 품질 분석 질문

1. "테스트 코드가 있는가? 있다면 어떤 테스트 프레임워크를 쓰고, 커버리지는 어느 수준인가?"
2. "타입 시스템을 활용하고 있는가? (TypeScript, 타입 힌트 등)"
3. "에러 처리 패턴은 어떤가? 일관성이 있는가?"
4. "코드 스타일 — 린팅, 포매팅 설정이 있는가?"
5. "의존성 관리 — 오래된 의존성, 보안 취약점이 우려되는 패키지가 있는가?"

### 아키텍처 심화 질문

1. "핵심 디자인 패턴은 무엇이고, 왜 그 패턴을 선택했는가?"
2. "확장 포인트는 어디인가? 플러그인이나 커스텀 모듈을 추가하려면 어떻게 하는가?"
3. "성능 병목이 될 수 있는 부분은 어디인가?"
4. "보안 관점에서 주의할 부분은?"

## 유사 프로젝트 비교

NotebookLM의 리서치 기능을 활용:

```bash
notebooklm source add-research "{프로젝트 주제} alternatives comparison" --mode deep --import-all
notebooklm ask "이 프로젝트와 유사한 대안들을 비교 분석해줘. 각각의 장단점, 적합한 사용 시나리오를 정리해줘."
```

비교 결과는 Obsidian의 `wiki/comparisons/` 폴더에 저장.

## 콘텐츠 생성

NotebookLM CLI로 다양한 형식의 콘텐츠를 생성한다. 상세 CLI 명령어는 `notebooklm-guide.md` 참조.

### 생성 후 Obsidian 저장

생성된 콘텐츠는 Vault에 저장:

| 콘텐츠 | 저장 경로 |
|--------|----------|
| 오디오 (MP3) | `raw/repos/{repo명}/podcast.mp3` |
| 슬라이드 (PPTX) | `raw/repos/{repo명}/slides.pptx` |
| 인포그래픽 (PNG) | `raw/repos/{repo명}/infographic.png` |
| 마인드맵 (JSON) | `raw/repos/{repo명}/mindmap.json` |

wiki 페이지에는 해당 파일로의 링크를 추가한다.
```

- [ ] **Step 2: 커밋**

```bash
git add skills/repo-analyze/references/deep-analysis.md
git commit -m "feat(repo-analyze): add deep analysis guide"
```

---

### Task 4: 메인 SKILL.md 작성

**Files:**
- Create: `skills/repo-analyze/SKILL.md`

- [ ] **Step 1: SKILL.md 작성**

이 파일이 스킬의 핵심이다. 트리거 description, 파이프라인 흐름, 서브에이전트 디스패치 지침, 에러 처리를 포함한다.

```markdown
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
2. gh api repos/{owner}/{repo}/commits --jq '.[0:5] | .[] | {date: .commit.author.date, message: .commit.message | split(\"\n\")[0]}'

결과를 아래 형식으로 정리하여 반환:
- 설명: ...
- Stars: ...
- Forks: ...
- 오픈 이슈: ...
- 생성일: ...
- 최근 푸시: ...
- 라이선스: ...
- 최근 커밋 5개: (날짜 + 메시지)
"
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
3. references/common-questions.md를 읽고 공통 질문 5개를 확인한다
4. repo 유형과 특성에 맞는 맞춤 질문 5~10개를 생성한다

반환 형식:
---
repo_type: {판별된 유형}
summary: {repo 한 줄 요약}
tech_stack: {주요 기술 스택}
questions:
  common:
    - 질문1
    - 질문2
    - 질문3
    - 질문4
    - 질문5
  custom:
    - 맞춤질문1
    - 맞춤질문2
    ...
---
"
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
업로드 실패 시 에러 메시지를 그대로 반환하라.
"
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
2. 각 질문에 대해:
   - notebooklm ask \"질문\"
   - 답변을 수집
3. 모든 질의 완료 후 대화 이력 저장:
   - notebooklm history --save

반환: 질문-답변 쌍의 전체 목록.

에러 시: 특정 질문 실패 시 해당 질문만 건너뛰고 계속 진행. 실패한 질문 목록을 별도로 반환.
"
)
```

**fallback**: Agent C가 실패했거나 NotebookLM 연동이 불가능한 경우:

```
Agent(
  model: "sonnet",
  description: "Claude 직접 분석 (NotebookLM fallback)",
  prompt: "/tmp/repomix-{repo}.txt 파일을 읽고 아래 질문들에 답변하라.

질문 세트: {Agent B 결과의 questions}

각 질문에 대해 repomix 출력 기반으로 상세히 답변. 코드 예시를 포함하여 구체적으로.

반환: 질문-답변 쌍의 전체 목록.
앞에 '(Claude 직접 분석 — NotebookLM 미사용)' 표기.
"
)
```

## Phase 4: 병렬 콘텐츠 생성

3개의 서브에이전트를 동시에 디스패치한다. NotebookLM fallback 모드면 이 Phase는 건너뛴다.

### Agent D: 리포트 생성 [Haiku]

```
Agent(
  model: "haiku",
  description: "NotebookLM 리포트 생성",
  prompt: "NotebookLM에서 study-guide 리포트를 생성하고 다운로드하라.

1. notebooklm use {notebook_id}
2. notebooklm generate report --format study-guide --wait
3. notebooklm download report /tmp/{repo}-report.md

반환: 리포트 파일 경로와 내용 요약 (200자).
생성 실패 시 에러 메시지 반환.
"
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

반환: 마인드맵 JSON 내용.
생성 실패 시 에러 메시지 반환.
"
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

반환: 노트북 AI 요약 전문.
"
)
```

## Phase 5: 결과 통합 [Sonnet]

모든 에이전트 결과를 하나의 구조화된 문서로 통합한다. 이 단계는 메인 스킬이 직접 수행하거나 Sonnet 서브에이전트에 위임한다.

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
{Phase 3 질의 답변 — 공통 질문 5개에 대한 답변을 섹션으로 구조화}

### 이 프로젝트가 해결하는 문제
### 기술 스택과 의존성
### 프로젝트 구조
### 사용법
### 강점과 한계

## 맞춤 분석
{Phase 3 질의 답변 — 맞춤 질문에 대한 답변}

## 리포트
{Agent D 결과 — study-guide 요약 또는 전문}

## 마인드맵
{Agent E 결과 — JSON을 마크다운 계층 목록으로 변환}

## NotebookLM
- 노트북 ID: {notebook_id}
- 노트북에서 추가 질의 가능: `notebooklm use {notebook_id} && notebooklm ask "질문"`
```

사용자에게 이 문서를 출력한다.

## Phase 6: Obsidian 저장

wiki-ingest 스킬의 절차를 따른다. Vault 경로 탐지 → raw/ 저장 → wiki/ 정제.

### Vault 경로

```
1. 환경변수 OBSIDIAN_VAULT_PATH
2. ~/Library/Mobile Documents/com~apple~CloudDocs/Documents/Vault
```

### 저장 구조

```
raw/repos/{repo명}/
  ├── metadata.md    ← Agent A 결과 (README, 커뮤니티 활성도)
  └── analysis.md    ← Phase 5 통합 문서 전문
```

### wiki 페이지 생성

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
```

- [ ] **Step 2: 커밋**

```bash
git add skills/repo-analyze/SKILL.md
git commit -m "feat(repo-analyze): add main SKILL.md with pipeline flow"
```

---

### Task 5: 통합 테스트 — 실제 repo로 드라이런

**Files:**
- 없음 (기존 파일로 테스트)

- [ ] **Step 1: 의존성 확인**

```bash
npx repomix --version
notebooklm --version
gh auth status
```

각 도구가 설치되어 있고 인증이 되어있는지 확인. 없는 도구가 있으면 설치 안내.

- [ ] **Step 2: repomix 테스트**

작은 repo로 repomix가 정상 동작하는지 확인:

```bash
npx repomix --remote revfactory/harness --output /tmp/repomix-harness.txt
wc -l /tmp/repomix-harness.txt
```

Expected: 파일이 생성되고, 줄 수가 0보다 큼.

- [ ] **Step 3: NotebookLM 연동 테스트**

```bash
notebooklm auth check --test
notebooklm create "harness 테스트"
notebooklm source add /tmp/repomix-harness.txt
notebooklm ask "이 프로젝트가 뭔지 한 줄로 설명해줘"
```

Expected: 노트북 생성, 소스 업로드, 질의 응답 모두 성공.

- [ ] **Step 4: 전체 파이프라인 드라이런**

스킬을 트리거하여 전체 흐름 테스트:

```
"https://github.com/revfactory/harness 분석해줘"
```

Expected: 빠른 요약 출력 + Obsidian에 저장 완료.

- [ ] **Step 5: 결과 확인**

```bash
ls -la "${OBSIDIAN_VAULT_PATH:-$HOME/Library/Mobile Documents/com~apple~CloudDocs/Documents/Vault}/raw/repos/harness/"
cat "${OBSIDIAN_VAULT_PATH:-$HOME/Library/Mobile Documents/com~apple~CloudDocs/Documents/Vault}/wiki/sources/harness.md" | head -30
```

Expected: metadata.md, analysis.md 존재. wiki 페이지에 frontmatter + 분석 내용.

- [ ] **Step 6: 문제 수정 및 최종 커밋**

드라이런에서 발견된 문제를 수정하고 커밋:

```bash
git add -A skills/repo-analyze/
git commit -m "fix(repo-analyze): address issues from dry run test"
```

---

### Task 6: SKILL.md 트리거 검증

**Files:**
- 없음 (검증만 수행)

- [ ] **Step 1: should-trigger 테스트**

다음 표현들이 스킬을 트리거하는지 확인:

1. "https://github.com/revfactory/harness 분석해줘"
2. "이 repo 좀 파악해줘 https://github.com/teng-lin/notebooklm-py"
3. "https://github.com/yamadashy/repomix 이게 뭐야?"
4. "/repo-analyze https://github.com/anthropics/claude-code"
5. "github.com/vercel/next.js 정리해줘"
6. "https://github.com/facebook/react 알아봐"
7. "이 레포 살펴봐 https://github.com/sveltejs/svelte"
8. "https://github.com/denoland/deno 분석"

- [ ] **Step 2: should-NOT-trigger 테스트**

다음 표현에서는 트리거되지 않아야 함:

1. "GitHub 계정 설정 방법 알려줘"  (GitHub 관련이지만 repo 분석 아님)
2. "이 코드 리뷰해줘" (분석이지만 GitHub URL 없음)
3. "npm install repomix 해줘" (repomix 언급이지만 repo 분석 요청 아님)
4. "위키에서 harness 찾아줘" (wiki-query가 처리해야 함)
5. "https://docs.google.com/document/d/xxx 정리해줘" (URL이지만 GitHub 아님)
6. "git log 보여줘" (git 관련이지만 외부 repo 분석 아님)
7. "이 프로젝트 구조 설명해줘" (현재 프로젝트 질문, 외부 repo 아님)
8. "GitHub Actions 설정해줘" (GitHub 관련이지만 repo 분석 아님)

- [ ] **Step 3: description 수정 (필요시)**

트리거 테스트 결과에 따라 SKILL.md의 description을 조정. 수정했으면 커밋:

```bash
git add skills/repo-analyze/SKILL.md
git commit -m "fix(repo-analyze): refine trigger description"
```
