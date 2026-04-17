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

## 초기 구조 (v3)

**폴더 생성:**

```bash
mkdir -p "$VAULT_PATH"/{raw/articles,raw/repos,raw/papers,wiki/sources,wiki/projects,wiki/concepts,wiki/entities,wiki/comparisons,outputs}
```

**각 하위 폴더에 .gitkeep 생성 (outputs 제외):**

```bash
touch "${VAULT_PATH}/raw/articles/.gitkeep"
touch "${VAULT_PATH}/raw/repos/.gitkeep"
touch "${VAULT_PATH}/raw/papers/.gitkeep"
touch "${VAULT_PATH}/wiki/concepts/.gitkeep"
touch "${VAULT_PATH}/wiki/entities/.gitkeep"
touch "${VAULT_PATH}/wiki/sources/.gitkeep"
touch "${VAULT_PATH}/wiki/comparisons/.gitkeep"
touch "${VAULT_PATH}/wiki/projects/.gitkeep"
touch "${VAULT_PATH}/.rakis-v3-migrated"
```

**overview.md 템플릿 생성 (없을 때만):**

```bash
[ -f "${VAULT_PATH}/wiki/overview.md" ] || cat > "${VAULT_PATH}/wiki/overview.md" <<'EOF'
---
title: "Vault Overview"
type: index
sources: []
related: []
created: $(date +%Y-%m-%d)
updated: $(date +%Y-%m-%d)
description: "볼트 대시보드"
---

# Vault Overview

## 주제 요약

(자료 수집 후 wiki-lint가 자동 갱신)

## 통계

(wiki-lint가 자동 갱신)

## 최근 활동

(wiki-lint가 자동 갱신)
EOF
```

**index.md 템플릿 생성 (없을 때만):**

```bash
[ -f "${VAULT_PATH}/index.md" ] || cat > "${VAULT_PATH}/index.md" <<'EOF'
# Wiki Index

LLM이 관리하는 마스터 카탈로그. 새 페이지 생성 시 반드시 업데이트.

## Sources

(비어있음 — 첫 자료 수집 시 자동 생성)

## Projects

(비어있음)

## Concepts

(비어있음)

## Entities

(비어있음)

## Comparisons

(비어있음)
EOF
```

**log.md 템플릿 생성 (없을 때만):**

```bash
[ -f "${VAULT_PATH}/log.md" ] || cat > "${VAULT_PATH}/log.md" <<'EOF'
# Log

시간순 기록. Claude가 자동으로 추가.

EOF
```

### 4. vault CLAUDE.md 생성

인터뷰 결과를 반영한 CLAUDE.md를 vault 루트에 생성. **기존 CLAUDE.md가 있으면 Step 1에서 백업 합의 후** `.bak`로 이동하고 재생성.

```bash
cat > "${VAULT_PATH}/CLAUDE.md" <<EOF
# Vault Schema (v3)

이 vault는 Karpathy LLM Wiki 방법론(3-Layer)으로 관리된다. rakis 플러그인 스킬을 통해 수집·질의·점검이 이루어진다.

## User Profile
- 역할: ${USER_ROLE}
- 목적: ${USER_PURPOSE}
- 관심 분야: ${USER_INTERESTS}

## Input
주로 수집하는 자료: ${USER_SOURCES}

## Output
선호 아웃풋: ${USER_OUTPUT_PREF}

## 3-Layer 구조

### raw/ (Immutable)
- 한 번 저장하면 절대 수정하지 않음
- 원본 그대로 보존 (웹 클리핑, PDF, repomix 등)
- 하위: articles/, repos/, papers/

### wiki/ (LLM 관리)
- 모든 페이지는 YAML frontmatter 필수
- 필수 필드: title, type, sources, related, created, updated, description
- type enum: source-summary | project | concept | entity | comparison | index
- 링크는 \`[[wiki-link]]\` 형식 (상대 링크)
- 태그: #concept, #entity, #tool, #person

### outputs/ (일회성 산출물)
- wiki-lint, graph-report 등 LLM 산출물
- 날짜 파일명 고정: {YYYY-MM-DD}-{tool}.{ext}

## 페이지 타입별 폴더

| type | 폴더 |
|------|------|
| source-summary | wiki/sources/ |
| project | wiki/projects/ |
| concept | wiki/concepts/ |
| entity | wiki/entities/ |
| comparison | wiki/comparisons/ |
| index | wiki/ (overview.md) |

## index.md와 log.md
- index.md: 섹션별(sources/projects/concepts/entities/comparisons) 마스터 카탈로그
- log.md: 시간순 기록. wiki-wrap-up이 자동 추가. raw 거치지 않음.

## 예외 규칙 (v3)
- wrap-up은 raw를 거치지 않고 wiki·log에 직접 쓴다. log.md가 출처 역할.

## 언어 규칙
- 기술 용어는 영어 그대로
- 설명/서술은 한국어
EOF
```

### 5. 초기 graphify 빌드 안내

graphify는 Claude Code 스킬이므로 `/graphify <VAULT_PATH>` 형태로 사용자가 직접 invoke해야 한다. bash 실행 불가.

**빈 vault 체크:**
```bash
find "${VAULT_PATH}/wiki" -name '*.md' -not -name '.gitkeep' | head -1
```

**안내 분기:**
- 빈 vault → Step 6 리포트에서 "첫 자료 수집 후 `/graphify` 실행하세요"
- 페이지 있음 + graphify 설치됨 (`command -v graphify` 성공) → Step 6 리포트에서 "`/graphify \"${VAULT_PATH}\"` 실행 권장"
- graphify 미설치 → Step 6 리포트에서 "`/rakis:setup`으로 graphify 설치 후 `/graphify` 실행"

### 6. 완료 리포트

```
✅ wiki-init 완료

vault: ${VAULT_PATH}
생성된 구조: 5 raw/ + 5 wiki/ 하위폴더
CLAUDE.md: 생성됨 (사용자 프로필 + 규칙)

다음 단계:
  1. 환경변수 설정 (선택):
     export OBSIDIAN_VAULT_PATH="${VAULT_PATH}"
  2. 첫 자료 수집:
     /source-analyze <URL> "왜 분석하는지"
  3. 그래프 빌드 (자료가 쌓인 후):
     /graphify "${VAULT_PATH}"
  4. 질의:
     "~ 정리된 거 있어?"
```

## 주의사항

- 이 스킬은 프로젝트 폴더에서 실행한다 (vault 폴더에서 실행하는 것은 지원 범위 밖)
- 기존 vault에 덮어쓰기 하지 않음 — 상태 체크 후 보완/재설정/스킵 분기
- CLAUDE.md 백업 시 `.bak` 확장자 사용 (타임스탬프 없음 — 단순히 이전 것만 보존)
- graphify 의존성은 `/rakis:setup`이 설치 담당. wiki-init은 건너뛸 뿐 설치하지 않음.
