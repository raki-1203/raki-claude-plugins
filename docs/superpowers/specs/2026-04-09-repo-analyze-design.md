# repo-analyze 스킬 설계

## 개요

GitHub repo URL을 입력하면 자동으로 전체 분석하여 Obsidian 위키에 지식으로 축적하는 스킬.
NotebookLM을 핵심 분석 엔진으로 사용하고, 실패 시 Claude가 fallback으로 분석한다.

## 동기

- 수많은 GitHub repo/라이브러리가 공유되지만 하나하나 깊이 파악할 시간이 없음
- 자동 분석 → Obsidian 위키 축적으로 지식 베이스를 점진적으로 구축
- 기존 rakis 플러그인의 wiki-ingest와 자연스럽게 연결

## 사용 시나리오

- 새로운 라이브러리/프레임워크 평가
- 오픈소스 아키텍처 깊이 학습
- 경쟁/유사 프로젝트 비교 분석

## 트리거

- GitHub URL + 키워드: "분석", "파악", "정리", "알아봐", "분석해줘"
- 직접 호출: `/repo-analyze {URL}`

## 의존성

| 도구 | 용도 | 설치 |
|------|------|------|
| `repomix` | repo → 단일 문서 변환 | `npx repomix` (설치 불필요) |
| `notebooklm-py` | NotebookLM 프로그래밍 접근 | `pip install notebooklm` |
| `gh` CLI | 커뮤니티 활성도 조회 | 사전 설치 필요 |
| `wiki-ingest` 스킬 | Obsidian 저장 | 기존 rakis 플러그인 |

### 사전 조건

- `notebooklm login` 으로 Google 인증 완료 상태
- `gh auth status` 로 GitHub 인증 완료 상태

## 실행 흐름

### 전체 파이프라인

```
GitHub URL 입력
    |
[1] repomix 실행 (Bash)
    |
[2] 병렬 ---+--- Agent A: gh CLI 커뮤니티 활성도 수집      [Haiku]
            +--- Agent B: repo 분석 + 맞춤 질문 생성        [Sonnet]
            +--- Agent C: NotebookLM 노트북 생성            [Haiku]
    |
[3] NotebookLM 소스 업로드 + 자동 질의                     [Sonnet]
    |
[4] 병렬 ---+--- Agent D: NotebookLM 리포트 생성           [Haiku]
            +--- Agent E: NotebookLM 마인드맵 생성          [Haiku]
            +--- Agent F: NotebookLM 질의 답변 수집         [Haiku]
    |
[5] 결과 통합 + 문서 구조화                                [Sonnet]
    |
[6] Obsidian 저장 (wiki-ingest 호출)                      [Haiku]
    |
--- 사용자 추가 요청 시 ---
    |
[7] 확장 분석
    +--- 추가 질의 (코드 품질, 유사 프로젝트, 적용 포인트)
    +--- 인포그래픽 / 슬라이드 생성
    +--- 오디오 요약 (팟캐스트)
    +--- 결과를 Obsidian에 추가 저장
```

### 단계별 상세

#### [1] repomix 실행

```bash
npx repomix --remote {owner/repo} --output /tmp/repomix-{repo}.txt
```

- Bash로 직접 실행 (모델 불필요)
- 출력 파일을 이후 단계에서 참조

#### [2] 병렬 실행 — 정보 수집

**Agent A: 커뮤니티 활성도 [Haiku]**
- `gh repo view {owner/repo} --json stargazerCount,forkCount,issues,updatedAt,pushedAt,createdAt`
- `gh api repos/{owner/repo}/commits --jq '.[0:5]'` 로 최근 커밋 확인
- 결과를 구조화된 텍스트로 반환

**Agent B: repo 분석 + 질문 생성 [Sonnet]**
- repomix 출력을 읽고 repo 특성 파악
- 공통 질문 5개 + 맞춤 질문 5~10개 생성
- 공통 질문: 핵심 문제, 기술 스택, 프로젝트 구조, 사용법, 강점/한계
- 맞춤 질문: repo 유형(프레임워크, CLI, 라이브러리 등)에 따라 동적 생성

**Agent C: NotebookLM 노트북 생성 [Haiku]**
- `notebooklm create "{repo명} 분석"`
- 노트북 ID를 반환

#### [3] NotebookLM 소스 업로드 + 자동 질의 [Sonnet]

- repomix 출력을 NotebookLM에 소스로 업로드
  - 파일 크기가 20MB 초과 시 분할 업로드 또는 요약본 업로드
- README가 별도로 있으면 URL 소스로도 추가
- Agent B가 생성한 질문 세트를 순차적으로 질의
- 각 답변을 수집

**fallback**: NotebookLM 연결 실패 시 → Claude(Sonnet)가 repomix 출력을 직접 분석하여 동일한 질문에 답변

#### [4] 병렬 실행 — 콘텐츠 생성

**Agent D: 리포트 생성 [Haiku]**
- `notebooklm generate report --format study-guide --wait`
- 완료 후 마크다운으로 다운로드

**Agent E: 마인드맵 생성 [Haiku]**
- `notebooklm generate mind-map --wait`
- JSON으로 다운로드

**Agent F: 질의 답변 수집 [Haiku]**
- 3단계에서 수집한 답변을 구조화
- 대화 이력을 노트로 저장: `notebooklm history --save`

#### [5] 결과 통합 [Sonnet]

모든 결과를 하나의 구조화된 분석 문서로 통합:

```markdown
# {repo명} 분석

## 한 줄 요약
{NotebookLM 요약 기반}

## 커뮤니티 활성도
| 항목 | 값 |
|------|-----|
| Stars | {n} |
| Forks | {n} |
| 최근 커밋 | {date} |
| 오픈 이슈 | {n} |

## 핵심 분석
### 이 프로젝트가 해결하는 문제
### 기술 스택과 의존성
### 프로젝트 구조
### 사용법
### 강점과 한계

## 맞춤 분석
{repo 특성에 따른 질문-답변들}

## 마인드맵
{JSON → 마크다운 변환 또는 링크}

## NotebookLM
- 노트북 ID: {id}
- 추가 질의 가능
```

#### [6] Obsidian 저장 [Haiku]

wiki-ingest 스킬 호출하여 저장:

```
raw/repos/{repo명}/
  ├── metadata.md    ← README, 구조, 커뮤니티 활성도
  └── analysis.md    ← NotebookLM/Claude 분석 원문

wiki/ → wiki-ingest가 정제본 생성
```

#### [7] 확장 분석 (사용자 요청 시)

사용자가 추가로 요청할 수 있는 것:
- "코드 품질 더 분석해줘" → NotebookLM에 추가 질의
- "유사 프로젝트와 비교해줘" → NotebookLM 리서치 기능 활용
- "팟캐스트로 만들어줘" → `notebooklm generate audio --format deep-dive --wait`
- "슬라이드로 정리해줘" → `notebooklm generate slide-deck --wait`
- "인포그래픽 만들어줘" → `notebooklm generate infographic --wait`

결과는 Obsidian에 추가 저장.

## 모델 배분 전략

| 모델 | 역할 | 해당 단계 |
|------|------|----------|
| **Sonnet** | 분석, 판단, 종합 | 2-B, 3, 5 |
| **Haiku** | CLI 실행, 파일 I/O, 대기 | 2-A, 2-C, 4-D, 4-E, 4-F, 6 |

- Agent 도구의 `model` 파라미터로 지정
- 사용자 플랜에서 해당 모델을 사용할 수 없으면 현재 모델로 fallback

## 예상 소요 시간

| 구간 | 순차 | 병렬 |
|------|------|------|
| repomix | ~1분 | ~1분 |
| 정보 수집 (2단계) | ~3분 | ~1분 |
| 업로드 + 질의 (3단계) | ~3분 | ~3분 |
| 콘텐츠 생성 (4단계) | ~5분 | ~2분 |
| 통합 + 저장 (5-6단계) | ~2분 | ~2분 |
| **전체** | **~14분** | **~9분** |

## 파일 구조

```
skills/repo-analyze/
├── SKILL.md                    ← 메인 스킬 (파이프라인 흐름 + 트리거)
└── references/
    ├── common-questions.md     ← 공통 질문 템플릿 (사용자 커스텀 가능)
    ├── deep-analysis.md        ← 깊은 분석/확장 분석 가이드
    └── notebooklm-guide.md     ← NotebookLM CLI 사용법 + fallback 절차
```

## 에러 처리

| 실패 지점 | fallback |
|-----------|----------|
| repomix 실패 | `gh api`로 파일 트리 직접 수집 |
| NotebookLM 인증 만료 | 사용자에게 `notebooklm login` 안내 |
| NotebookLM 소스 업로드 실패 | 파일 분할 시도 → 실패 시 Claude 직접 분석 |
| NotebookLM 콘텐츠 생성 실패 | 해당 항목 건너뛰고 나머지 진행, 보고서에 누락 명시 |
| gh CLI 실패 | 커뮤니티 활성도 항목 "수집 실패" 표기 |

## 확장 가능성

- 여러 repo 비교 분석 (NotebookLM 하나의 노트북에 여러 소스)
- 주기적 재분석 (repo 업데이트 감지)
- 분석 결과 기반 추천 ("이 repo가 마음에 들면 이것도 볼만합니다")
