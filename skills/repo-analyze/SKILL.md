---
name: repo-analyze
description: "GitHub repo를 자동 분석하여 Obsidian 위키에 지식으로 축적. GitHub URL과 함께 '분석', '파악', '정리', '알아봐', '분석해줘', '이게 뭐야', '살펴봐'라고 하면 이 스킬 사용. '/repo-analyze URL'로도 직접 호출 가능. 여러 URL을 한번에 비교 분석도 가능('비교해줘', 'vs'). repomix로 repo 전체를 문서화하고, NotebookLM을 핵심 분석 엔진으로 사용하여 요약·리포트·마인드맵을 자동 생성. 분석 후 '더 깊이', '비교해줘', '팟캐스트로', '슬라이드로' 등 추가 분석도 지원. 이미 분석된 repo는 캐시 재사용."
version: 1.1.0
license: MIT
---

# repo-analyze — GitHub Repo 자동 분석 + Obsidian 위키 축적

GitHub repo URL을 입력하면 NotebookLM을 핵심 엔진으로 사용하여 자동 분석하고, 결과를 Obsidian 위키에 저장한다.

## 파이프라인 개요

```
URL 입력 → 중복 체크 → repomix (캐시 or 신규) → 병렬 수집 → NotebookLM 분석 → 병렬 생성 → 통합 → Obsidian 저장
```

## 사전 조건 확인

1. URL에서 `{owner}/{repo}` 파싱
2. `command -v notebooklm` — 없으면 `uv tool install notebooklm-py --with playwright` 안내. 없어도 Claude fallback으로 동작.
3. `notebooklm auth check --test` — 실패 시 `! notebooklm login` 안내. 거부 시 fallback.
4. `gh auth status` — 실패 시 커뮤니티 활성도 건너뜀
5. `command -v graphify` — 없으면 `uv tool install graphifyy --python 3.13` 안내. 없어도 동작.

## Phase 0: 중복 체크 + 캐시 재사용

### 단일 소스 모드

1. Obsidian `wiki/sources/{repo}.md` 존재 확인 (mcp__obsidian__read_note)
2. 분기:
   - **없음** → Phase 1로 진행
   - **있음** → 사용자에게 선택지:
     > "이미 분석된 repo입니다. 1) 기존 분석 보기  2) 재분석  3) NotebookLM 추가 질의만"
   - 1 → wiki 페이지 출력
   - 2 → repomix 재생성 + 기존 NotebookLM 노트북 ID 재사용
   - 3 → wiki에서 노트북 ID 추출 → `notebooklm use {id} && notebooklm ask "질문"`

### 멀티 소스 모드

여러 URL이 주어지거나 "비교해줘", "vs" 키워드가 있으면:
1. 각 URL별 중복 체크 — 기존 캐시 재사용
2. 하나의 NotebookLM 노트북에 모든 소스 합침
3. 교차 분석 → `wiki/comparisons/`에 저장

### repomix 캐시 전략

- 첫 분석: `/tmp/repomix-{repo}.txt` → Obsidian `raw/repos/{repo}/repomix.txt`에 보존
- 재분석: 캐시 존재 시 재사용. "재분석" 선택 시만 재생성.

### 대용량 자동 분할

| 크기 | 대응 |
|------|------|
| < 2MB | 그대로 업로드 |
| 2~10MB | `repomix --compress` 재시도 → 여전히 크면 분할 |
| > 10MB | 파일 경계에서 2MB 단위 분할 업로드 |

## Phase 1: repomix 실행

1. Obsidian `raw/repos/{repo}/repomix.txt` 캐시 확인 → 있으면 재사용
2. 없으면: `npx repomix --remote {owner}/{repo} --output /tmp/repomix-{repo}.txt`
3. 대용량 체크 → 필요 시 compress/분할
4. Obsidian에 캐시 보존

fallback: `gh repo clone` 후 로컬에서 repomix

## 오케스트레이션 규칙

- **변수 치환**: `{owner}`, `{repo}`, `{notebook_id}` 등은 디스패치 전에 실제 값으로 치환
- **병렬 디스패치**: "병렬" Phase에서는 하나의 메시지에서 모든 Agent를 동시에 호출 (`run_in_background: true`)
- **순차 의존**: Phase N+1은 Phase N 완료 후 시작

## Phase 2~4: Agent 디스패치

> **상세 프롬프트**: `references/agent-prompts.md`를 읽고 해당 Phase의 Agent 프롬프트를 사용한다.

### Phase 2: 병렬 정보 수집 (4개 Agent 동시)

| Agent | 모델 | 역할 |
|-------|------|------|
| A | Haiku | gh CLI로 커뮤니티 활성도 수집 |
| B | Sonnet | repomix 읽고 repo 분석 + 맞춤 질문 생성 |
| C | Haiku | NotebookLM 노트북 생성 + 소스 업로드 |
| G | Sonnet | graphify 구조 분석 (설치 시에만) |

### Phase 3: NotebookLM 자동 질의 (순차)

- Agent B의 질문 세트 + Agent C의 노트북 ID → Sonnet 에이전트가 순차 질의
- **fallback**: NotebookLM 불가 시 Claude가 repomix 파일을 직접 분석

### Phase 4: 병렬 콘텐츠 생성 (3개 Agent 동시)

| Agent | 모델 | 역할 |
|-------|------|------|
| D | Haiku | NotebookLM study-guide 리포트 생성 |
| E | Haiku | NotebookLM 마인드맵 생성 |
| F | Haiku | NotebookLM 노트북 요약 수집 |

NotebookLM fallback 모드면 건너뜀 → Phase 5에서 "해당 항목 없음" 표기.

## Phase 5: 결과 통합

> **출력 문서 구조**: `references/output-template.md`를 읽고 템플릿에 맞춰 통합한다.

모든 에이전트 결과를 구조화된 분석 문서로 통합하여 **사용자에게 핵심 내용을 정리해서 출력**한다.

## Phase 6: Obsidian 저장

> **저장 구조 상세**: `references/output-template.md`의 "Obsidian 저장 구조" 섹션 참조.

wiki-ingest의 절차를 따라 직접 실행:
1. `raw/repos/{repo명}/`에 metadata.md, analysis.md, repomix.txt 캐시 저장
2. `wiki/sources/{repo명}.md` 생성 (YAML frontmatter 필수)
3. `index.md` 갱신, `log.md` 기록
4. 관련 기존 wiki 페이지와 `[[위키링크]]` 연결

## 확장 분석 (사용자 요청 시)

> **상세 가이드**: `references/deep-analysis.md`를 읽고 해당 기능을 실행한다.

| 키워드 | 기능 |
|--------|------|
| "더 깊이", "코드 품질" | 추가 질의 (코드 품질 5개 + 아키텍처 4개) |
| "비교해줘" | NotebookLM 리서치 + 비교 질의 |
| "팟캐스트로", "오디오로" | 오디오 생성 |
| "슬라이드로", "PPT로" | 슬라이드 생성 |
| "인포그래픽" | 인포그래픽 생성 |
| "퀴즈", "플래시카드" | 학습 자료 생성 |

## 에러 처리 요약

| 실패 지점 | 대응 |
|-----------|------|
| repomix 실패 | gh clone 후 로컬에서 재시도 |
| NotebookLM 인증 없음 | 로그인 안내 → 거부 시 Claude fallback |
| NotebookLM 업로드 실패 | 2회 재시도 → 실패 시 Claude fallback |
| NotebookLM 질의/생성 실패 | 해당 항목 건너뛰고 진행 |
| gh CLI 실패 | 커뮤니티 활성도 "수집 실패" 표기 |
| graphify 미설치/실패 | 구조적 분석 건너뜀 |

## references/ 구조

| 파일 | 언제 읽나 |
|------|----------|
| `agent-prompts.md` | Phase 2~4 에이전트 디스패치 시 |
| `output-template.md` | Phase 5 결과 통합 + Phase 6 저장 시 |
| `common-questions.md` | Agent B가 질문 생성할 때 참고용 |
| `notebooklm-guide.md` | NotebookLM CLI 상세 사용법 필요 시 |
| `deep-analysis.md` | "더 깊이" 등 확장 분석 요청 시 |
