---
name: source-analyze
description: "다양한 소스(GitHub repo, 블로그, 논문 PDF, YouTube, LinkedIn, X 등)를 자동 분석하여 Obsidian 위키에 지식으로 축적. URL이나 파일과 함께 '분석', '파악', '정리', '알아봐', '분석해줘', '이게 뭐야', '살펴봐', '요약해줘'라고 하면 이 스킬 사용. '/source-analyze URL'로도 직접 호출 가능. 여러 소스를 한번에 비교 분석도 가능('비교해줘', 'vs'). NotebookLM을 핵심 분석 엔진으로 사용하여 요약·리포트·마인드맵을 자동 생성. GitHub repo는 repomix+graphify로 코드 구조까지 분석. 분석 후 '더 깊이', '비교해줘', '팟캐스트로', '슬라이드로' 등 추가 분석도 지원. 이미 분석된 소스는 캐시 재사용."
version: 2.0.0
license: MIT
---

# source-analyze — 범용 소스 분석 + Obsidian 위키 축적

URL, 파일, 텍스트 등 다양한 소스를 NotebookLM을 핵심 엔진으로 분석하고, 결과를 Obsidian 위키에 저장한다.

## 파이프라인 개요

```
소스 입력 → 유형 감지 → 전처리 → 중복 체크 → NotebookLM 분석 → 콘텐츠 생성 → 통합 → Obsidian 저장
```

## 사전 조건 확인

1. `command -v notebooklm` — 없으면 `uv tool install notebooklm-py --with playwright` 안내. 없어도 Claude fallback.
2. `notebooklm auth check --test` — 실패 시 `! notebooklm login` 안내. 거부 시 fallback.
3. `gh auth status` — GitHub repo 분석 시에만 필요
4. `command -v graphify` — GitHub repo 구조 분석 시에만 필요

## Phase 0: 소스 유형 감지 + 전처리

### 소스 유형 자동 감지

입력을 분석하여 유형을 판별하고, 유형별 전처리를 수행한다.

| 유형 | 감지 기준 | NotebookLM 입력 | 전처리 |
|------|----------|----------------|--------|
| **GitHub repo** | `github.com/{owner}/{repo}` | 텍스트 (repomix 변환) | `npx repomix --remote` → 텍스트 파일 |
| **웹 URL** (블로그, 뉴스) | `http(s)://` (GitHub/YouTube 제외) | URL 직접 업로드 | 없음 |
| **YouTube** | `youtube.com/`, `youtu.be/` | YouTube 소스 | 없음 |
| **PDF** | `.pdf` 확장자 또는 MIME | 파일 직접 업로드 | 없음 |
| **이미지** | `.png`, `.jpg`, `.svg` 등 | 텍스트 (변환 필요) | Claude Vision으로 설명 추출 → 텍스트 업로드 |
| **LinkedIn** | `linkedin.com/` | 텍스트 (추출 필요) | WebFetch → 텍스트 추출 → 텍스트 업로드 |
| **X/Twitter** | `x.com/`, `twitter.com/` | 텍스트 (추출 필요) | WebFetch → 텍스트 추출 → 텍스트 업로드 |
| **로컬 텍스트/마크다운** | `.md`, `.txt` | 텍스트 직접 업로드 | 없음 |

### 전처리 상세

> **GitHub repo 전처리**: `references/agent-prompts.md` 참조 (repomix + graphify)
> **대용량 파일 처리**: `references/notebooklm-guide.md`의 "대용량 파일 처리" 참조

**LinkedIn/X 추출**: WebFetch 도구로 URL 콘텐츠를 가져온 뒤, 게시글 본문 + 링크를 텍스트로 정리하여 `notebooklm source add "{텍스트}" --title "{제목}"` 으로 업로드.

**이미지**: Read 도구로 이미지를 읽고 Claude Vision으로 설명을 추출한 뒤 텍스트로 업로드.

### 소스명 생성

| 유형 | 소스명 규칙 | 예시 |
|------|-----------|------|
| GitHub repo | `{owner}-{repo}` | `yamadashy-repomix` |
| 웹 URL | URL에서 도메인+경로 추출 | `langchain-anatomy-agent-harness` |
| YouTube | 영상 제목 kebab-case | `karpathy-llm-wiki-talk` |
| 로컬 파일 | 파일명 (확장자 제외) | `research-paper-2026` |
| LinkedIn/X | 작성자-주제 | `jeongmin-lee-harness-engineering` |

## Phase 1: 중복 체크 + 캐시

1. Obsidian `wiki/sources/{소스명}.md` 존재 확인
2. 분기:
   - **없음** → Phase 2로 진행
   - **있음** → 선택지: 기존 보기 / 재분석 / NotebookLM 추가 질의만

### 멀티 소스 모드

여러 소스가 주어지거나 "비교해줘", "vs" 키워드가 있으면:
1. 각 소스별 유형 감지 + 전처리 + 중복 체크
2. 하나의 NotebookLM 노트북에 모든 소스 합침
3. 교차 분석 → `wiki/comparisons/`에 저장

### 캐시 전략

| 유형 | 캐시 위치 | 재사용 |
|------|----------|--------|
| GitHub repo | `raw/repos/{repo}/repomix.txt` | repomix 재실행 건너뜀 |
| 웹 URL | NotebookLM 노트북 ID (wiki 페이지에 기록) | 노트북 재사용 |
| 로컬 파일 | 없음 (원본이 로컬에 있으므로) | — |

### 대용량 자동 분할

> **상세 절차**: `references/notebooklm-guide.md`의 "대용량 파일 처리" 참조.

repomix 등 대용량 텍스트는 2MB 기준 분할 업로드. 원본 재업로드 금지.

## Phase 2: 병렬 정보 수집

> **상세 프롬프트**: `references/agent-prompts.md` 참조.

소스 유형에 따라 실행할 Agent가 다르다:

| Agent | 모델 | GitHub repo | 웹/문서/기타 |
|-------|------|------------|-------------|
| A: 커뮤니티 활성도 | Haiku | ✅ gh CLI | ❌ 건너뜀 |
| B: 소스 분석 + 질문 생성 | Sonnet | repomix 읽기 | WebFetch/파일 읽기 |
| C: NotebookLM 노트북 생성 | Haiku | ✅ | ✅ |
| G: graphify 구조 분석 | Sonnet | ✅ (설치 시) | ❌ 건너뜀 |

**Agent B의 동작 차이**:
- GitHub repo → repomix 파일을 읽고 코드 기반 질문 생성
- 웹/문서 → WebFetch 또는 Read로 내용을 읽고 주제 기반 질문 생성
- 공통 질문 5개는 소스 유형에 맞게 조정 (`references/common-questions.md` 참조)

## Phase 3~4: NotebookLM 분석 + 콘텐츠 생성

> **상세 프롬프트**: `references/agent-prompts.md` 참조.

Phase 3: Sonnet이 NotebookLM에 질문 순차 질의 (fallback: Claude 직접 분석)
Phase 4: Haiku 3개가 리포트/마인드맵/요약 병렬 생성

## Phase 5: 결과 통합

> **출력 템플릿**: `references/output-template.md` 참조.

사용자에게 **핵심 내용을 정리해서 출력**한다. GitHub repo는 구조적 분석 포함, 웹/문서는 내용 분석 중심.

## Phase 6: Obsidian 저장

> **저장 구조**: `references/output-template.md` 참조.

| 유형 | raw/ 저장 | wiki/ 저장 |
|------|----------|-----------|
| GitHub repo | `raw/repos/{repo}/` (metadata, analysis, repomix 캐시) | `wiki/sources/{repo}.md` |
| 웹/문서/기타 | `raw/articles/{소스명}.md` (원문 또는 추출 텍스트) | `wiki/sources/{소스명}.md` |
| 비교 분석 | — | `wiki/comparisons/{A}-vs-{B}.md` |

## 확장 분석 (사용자 요청 시)

> **상세 가이드**: `references/deep-analysis.md` 참조.

| 키워드 | 기능 |
|--------|------|
| "더 깊이", "코드 품질" | 추가 질의 |
| "비교해줘" | NotebookLM 리서치 + 비교 |
| "팟캐스트로", "오디오로" | 오디오 생성 |
| "슬라이드로", "PPT로" | 슬라이드 생성 |
| "인포그래픽" | 인포그래픽 생성 |
| "퀴즈", "플래시카드" | 학습 자료 생성 |

## 에러 처리 요약

| 실패 지점 | 대응 |
|-----------|------|
| repomix 실패 | gh clone 후 재시도 |
| NotebookLM 인증 없음 | 로그인 안내 → Claude fallback |
| NotebookLM 업로드 실패 | 분할 시도 → 실패 시 Claude fallback |
| WebFetch 실패 | 사용자에게 텍스트 직접 입력 요청 |
| graphify 미설치 | 구조적 분석 건너뜀 |

## references/ 구조

| 파일 | 언제 읽나 |
|------|----------|
| `agent-prompts.md` | Phase 2~4 에이전트 디스패치 시 |
| `output-template.md` | Phase 5 결과 통합 + Phase 6 저장 시 |
| `common-questions.md` | Agent B가 질문 생성할 때 |
| `notebooklm-guide.md` | NotebookLM CLI 상세 필요 시 |
| `deep-analysis.md` | 확장 분석 요청 시 |
