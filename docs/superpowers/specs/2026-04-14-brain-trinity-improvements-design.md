# Brain Trinity 영상 기반 rakis 플러그인 3가지 개선

**날짜**: 2026-04-14
**참조**: [[brain-trinity-llm-wiki-obsidian-graphify]] (위키)

## 배경

YouTube "브레인 트리니티" 영상의 Karpathy LLM Wiki 방법론(Claude Code × Obsidian × Graphify)과 rakis 플러그인의 현재 구조를 비교해 3가지 개선 포인트를 도출.

영상은 **vault 중심** 사용 패턴(vault 폴더에서 Claude 실행)인 반면, rakis는 **프로젝트 중심** 사용 패턴(프로젝트 폴더에서 Claude 실행, vault는 외부 경로)이 기본. 본 개선안은 rakis의 정체성인 "프로젝트 중심"을 유지하면서 영상의 방법론을 선택적으로 수용.

## rakis 정체성

```
프로젝트/ ← Claude 실행                   vault/ ← 저장소일 뿐
├── graphify (코드 분석, graphify 자체가    ├── wiki/ (rakis가 관리)
│   post-commit 훅으로 관리 — rakis 영역 밖)├── raw/
└── rakis 스킬 → vault 외부 경로 접근      └── graph.json (rakis가 관리)
```

**경계**: 프로젝트 코드 그래프는 graphify 자체가 관리. rakis는 vault 내 위키 그래프만 책임.

## 3가지 개선 + 1 (help 커맨드)

### 개선 1: Graphify 위키 통합

**원칙**
- graphify는 vault 경로를 대상으로 동작 (영상 방식)
- 위키에 쓰는 스킬이 저장 후 증분 업데이트
- wiki-lint가 주 1회 풀 리빌드로 정합성 보장
- wiki-query가 그래프 활용 (없으면 index.md 방식으로 폴백)

**스킬별 변경**

| 스킬 | 추가 동작 | 명령 |
|------|----------|------|
| `wiki-ingest` | Step 5(log) 이후 Step 6 신규: 그래프 증분 업데이트 | `graphify <vault> --update` |
| `source-analyze` | Phase 6(저장) 이후 Phase 7 신규: 그래프 증분 업데이트 | `graphify <vault> --update` |
| `wiki-wrap-up` | Step 4(실행) 이후 Step 5 신규: 그래프 증분 업데이트 | `graphify <vault> --update` |
| `wiki-lint` | Step 4(수정 적용) 이후 Step 5 신규: 풀 리빌드 | `graphify <vault>` |
| `wiki-query` | 질문 분석 후 내부 분기 (답변형/탐색형) | `graphify query "..."` |

**wiki-query 내부 분기 로직**

```
질문 받음
  ↓
질문 분석: 답변형 vs 탐색형
  ↓
[답변형] "X가 뭐야?", "X 쓰는 법?"
  → index.md 읽기 → 관련 페이지 명확?
     Yes → 페이지 읽어서 답변
     No  → graphify query로 심층 답변 (graph 없으면 기존 방식)
  ↓
[탐색형] "이 프로젝트 관련 뭐 있어?", "둘러보고 싶어"
  → 프로젝트 컨텍스트 압축 수집 (≤50줄):
      - 프로젝트명 (1줄)
      - 기술 스택 (의존성 이름만, 10-20줄)
      - CLAUDE.md 헤더/첫 섹션 (20줄)
      - 최근 10 커밋 메시지 (10줄)
      - wiki/projects/{name}.md의 description만 (3줄)
  → graphify query에 컨텍스트+질문 전달
  → 관련 페이지 목록 출력 (내용은 지연 로딩)
```

**답변형/탐색형 분기 기준 (예시)**
- 탐색형 시그널: "이 프로젝트", "여기에", "지금 작업", "관련해서 뭐", "둘러"
- 나머지: 답변형

**graphify 미설치 시**: `command -v graphify` 체크 실패 → 해당 단계 스킵, 기존 방식으로 진행.

**첫 실행**: vault에 graph.json이 없으면 `--update` 대신 풀 빌드로 자동 전환 (graphify 자체 감지 동작 활용).

---

### 개선 2: 수집 시 코멘트 강제 (Gold In, Gold Out)

**원칙**: "왜 저장/분석하는지" 목적을 기록해서 나중에 맥락 파악 가능하게 함.

**스킬별 적용**

| 스킬 | 코멘트 받는 방식 |
|------|-----------------|
| `source-analyze` | 인자 OR Phase 0 직후 질문 |
| `wiki-ingest` | 인자 OR Step 1 직후 질문 |
| `wiki-wrap-up` | 세션 맥락에서 자동 생성 (Step 3 사용자 확인 시 수정 가능) |

**입력 방식**

```
# 인자 전달
/source-analyze https://... "왜 분석하는지"
/wiki-ingest <자료> "왜 저장하는지"

# 인자 없으면 질문
/source-analyze https://...
  → "왜 이 소스를 분석하시나요? (한 줄)"
```

**frontmatter 확장**

모든 `wiki/*` 페이지에 `comment` 필드 추가:

```yaml
---
title: ...
type: source-summary
sources:
  - "[[raw/articles/...]]"
comment: "프로젝트 X 조사 중 원류로 등장, 기술 참고"   # 신규
related: [...]
created: 2026-04-14
updated: 2026-04-14
confidence: high
description: ...
---
```

**wiki-wrap-up 자동 생성**

세션 대화 맥락에서 각 저장 항목의 "왜"를 추출해 `comment`에 자동 기록. Step 3 사용자 확인 화면에서 함께 표시하고 사용자가 수정 가능:

```
## 이 세션의 wiki 저장

### 새 개념 (2)
- **OpenClaw**: comment: "jobdori 분석 중 원류 프레임워크로 등장"
- **clawhip**: comment: "OpenClaw 알림 구조 조사 중 발견"

모두 저장 / 선택 / 코멘트 수정 / 취소?
```

**wiki-query 활용**: 질의 시 `comment` 필드도 매칭 대상 포함 → "왜 저장했는지"로도 역검색 가능.

**기존 페이지 호환성**: 이미 만들어진 페이지는 `comment` 없음 → `wiki-lint`의 "데이터 갭" 카테고리에 탐지, 보완 제안.

---

### 개선 3: `/wiki-init` 스킬 (신규)

**목적**: 새 사용자가 rakis를 처음 사용할 때 인터뷰 기반으로 vault 구조와 CLAUDE.md를 자동 생성.

**실행 위치**: 프로젝트 폴더 (rakis는 프로젝트 중심 — vault 중심 사용은 범위 밖).

**흐름**

```
/wiki-init
  ↓
[1] vault 경로 상태 체크
    - 완전히 비어있음  → 전체 생성 + 인터뷰
    - 일부 폴더만 있음 → "기존 구조 감지. 부족한 부분만 보완할까요?"
    - CLAUDE.md 존재   → "이미 초기화됨. 재설정? (기존 파일 .bak 백업)"
    - 완전히 세팅됨    → "이미 완료. 변경 없음"
  ↓
[2] 인터뷰 (질문은 하나씩)
  ↓
[3] vault 구조 생성
  ↓
[4] vault CLAUDE.md 생성
  ↓
[5] 초기 graphify 빌드 (빈 vault면 스킵)
  ↓
[6] 완료 리포트
```

**인터뷰 항목**

| 순서 | 질문 | 사용처 |
|------|------|-------|
| 1 | vault 경로 (기본: iCloud Obsidian) | 설정 저장 |
| 2 | 역할 (예: 백엔드 개발자) | CLAUDE.md schema |
| 3 | 목적 (예: 기술 조사 축적) | CLAUDE.md schema |
| 4 | 주로 저장할 자료 (블로그/논문/repo/영상 등 복수 선택) | CLAUDE.md schema |
| 5 | 관심 분야/기술 스택 | CLAUDE.md schema |
| 6 | 선호 아웃풋 (한국어 요약 등) | CLAUDE.md schema |

**생성될 vault 구조**

```
<vault-path>/
├── raw/
│   ├── articles/   .gitkeep
│   ├── papers/     .gitkeep
│   ├── repos/      .gitkeep
│   ├── data/       .gitkeep
│   └── images/     .gitkeep
├── wiki/
│   ├── concepts/   .gitkeep
│   ├── entities/   .gitkeep
│   ├── sources/    .gitkeep
│   ├── comparisons/ .gitkeep
│   └── projects/   .gitkeep
├── index.md        (빈 템플릿)
├── log.md          (빈 템플릿)
└── CLAUDE.md       (인터뷰 기반 schema)
```

**vault CLAUDE.md 템플릿** (인터뷰 결과 반영, 스킬 매핑은 없음)

```markdown
# Vault Schema

## User Profile
- 역할: {답변 2}
- 목적: {답변 3}
- 관심 분야: {답변 5}

## Input
주로 수집하는 자료: {답변 4}

## Output
선호 아웃풋: {답변 6}

## Rules
- raw/ 파일은 immutable (한번 저장 후 수정 금지)
- 모든 wiki 페이지는 YAML frontmatter 필수
- 수집 시 comment 필드 필수 (왜 저장/분석했는지)
- 링크는 [[wiki-link]] 형식
```

**`/rakis:setup`과의 경계**

| 스킬 | 레벨 | 역할 |
|------|------|------|
| `/rakis:setup` | 머신 | 의존성 설치 (graphify, notebooklm 등) + 글로벌 `~/.claude/CLAUDE.md`에 rakis 스킬 매핑 |
| `/wiki-init` | vault | vault 구조 + vault CLAUDE.md 생성 + 사용자 프로필 |

순서: `/rakis:setup` 먼저 → `/wiki-init`으로 vault 세팅.

---

### 개선 4 (보너스): `/rakis:help` 커맨드

**목적**: 사용자가 rakis의 전체 스킬/커맨드 사용법을 쉽게 발견할 수 있도록.

**사용법**

```
/rakis:help            # 전체 개요 + 빠른 시작
/rakis:help <스킬명>   # 특정 스킬의 사용법 + 예시
```

**`/rakis:help` 출력 (개요)**

```
# rakis — Obsidian LLM Wiki 관리 플러그인

## 빠른 시작
1. /rakis:setup           # 의존성 설치 (머신당 1회)
2. /wiki-init             # vault 세팅 (vault당 1회)
3. 평소 사용:
   - "~ 정리된 거 있어?"   → wiki-query
   - "~ 분석해줘"           → source-analyze
   - "이거 저장해줘"        → wiki-ingest
   - /wiki-wrap-up          → 세션 끝에 학습 저장
4. 주 1회: /wiki-lint     # 건강 점검 + 그래프 리빌드

## 전체 스킬
- wiki-query      위키 질의 (답변형/탐색형 자동 분기)
- wiki-ingest     자료 저장 (코멘트 강제)
- source-analyze  소스 심층 분석 (코멘트 강제)
- wiki-wrap-up    세션 학습 저장 (코멘트 자동)
- wiki-lint       건강 점검 + 풀 그래프 리빌드
- wiki-init       vault 초기화 (신규)

## 자세히 보기
/rakis:help <스킬명>
```

**`/rakis:help wiki-query` 출력 예시**

```
# wiki-query — 위키 질의

## 용도
vault에 축적된 지식으로 질문에 답변하거나, 프로젝트 관련 위키 탐색.

## 사용법
- 답변형: "MCP 서버가 뭐였지?"
- 탐색형: "이 프로젝트 관련 뭐 있어?" (프로젝트 폴더에서)

## 동작
- 답변형 → index.md + graph 탐색 → 답변 (인용 포함)
- 탐색형 → 프로젝트 컨텍스트 수집 → graph 탐색 → 관련 페이지 목록

## 예시
"openclaw에 대해 정리된 거 있어?"
"riverpod 어떻게 쓰는 거였지?"
"이 프로젝트 관련해서 뭐 있어?"
```

---

## 최종 구성

### 스킬/커맨드 전체 목록

| 이름 | 종류 | 상태 | 역할 |
|------|------|------|------|
| `/rakis:setup` | 커맨드 | 기존 | 의존성 설치 + 글로벌 CLAUDE.md 매핑 |
| `/rakis:help` | 커맨드 | **신규** | 사용법 안내 |
| `/rakis:wc-cp-graph` | 커맨드 | 기존 | 워크트리 헬퍼 |
| `/wiki-init` | 스킬 | **신규** | vault 초기화 + 프로필 |
| `wiki-query` | 스킬 | 수정 | 답변형/탐색형 분기 + graph 활용 |
| `wiki-ingest` | 스킬 | 수정 | 코멘트 강제 + 그래프 증분 업데이트 |
| `source-analyze` | 스킬 | 수정 | 코멘트 강제 + 그래프 증분 업데이트 |
| `wiki-wrap-up` | 스킬 | 수정 | 코멘트 자동 + 그래프 증분 업데이트 |
| `wiki-lint` | 스킬 | 수정 | 데이터 갭에 comment 포함 + 풀 그래프 리빌드 |

### 전체 사용 흐름

```
[초기 1회]
  /rakis:setup   → 의존성 + 글로벌 스킬 매핑
  /wiki-init     → vault 원격 세팅

[일상 작업]
  질의 → wiki-query ("~가 뭐야" / "~관련 뭐 있어")
  분석 → source-analyze <URL> "왜 분석"
  저장 → wiki-ingest <자료> "왜 저장"
  마무리 → /wiki-wrap-up (코멘트 자동)

[주 1회]
  /wiki-lint → 건강 점검 + 풀 그래프 리빌드

[필요 시]
  /rakis:help, /rakis:help <스킬명>
```

## 변경 파일 목록 (예상)

### 수정
- `skills/wiki-query/SKILL.md` — 답변형/탐색형 분기 + graphify query 연동
- `skills/wiki-ingest/SKILL.md` — 코멘트 강제 + 증분 그래프 업데이트
- `skills/source-analyze/SKILL.md` — 코멘트 강제 + 증분 그래프 업데이트
- `skills/wiki-wrap-up/SKILL.md` — 코멘트 자동 생성 + 증분 그래프 업데이트
- `skills/wiki-lint/SKILL.md` — 데이터 갭에 comment 필드 추가 + 풀 그래프 리빌드
- `commands/skill-mapping.md` — 새 스킬/커맨드 매핑 반영
- `README.md` — 전체 사용법 업데이트
- `.claude-plugin/plugin.json` + `package.json` — 버전 bump (2.5.0)

### 신규
- `skills/wiki-init/SKILL.md` — 신규 스킬
- `commands/help.md` — 신규 커맨드 (`/rakis:help`)

## 비범위 (Out of Scope)

- **프로젝트 코드 그래프 관리**: graphify 자체가 post-commit 훅으로 처리하는 영역. rakis는 건드리지 않음. 사용자가 원하면 `graphify hook install`을 프로젝트에서 직접 실행.
- **vault 중심 사용 패턴**: vault 폴더에서 직접 Claude 실행하고 싶은 사용자는 rakis 범위 밖. 영상의 "Synthesis 문서 생성" 같은 vault 중심 기능은 추가하지 않음.
- **기존 위키 페이지 일괄 마이그레이션**: comment 필드가 없는 기존 페이지는 `wiki-lint`가 데이터 갭으로 탐지해서 보완을 제안. 일괄 자동 채움은 하지 않음 (사용자 승인 필요).

## 검증 기준

- 각 스킬 수정 후 SKILL.md를 읽고 기존 동작이 깨지지 않는지 확인
- `/wiki-init`: 새 vault 경로에서 실행 → 구조 생성 확인, 기존 구조 위에서 실행 → 멱등성 확인
- graphify 미설치 환경에서도 모든 스킬이 정상 동작 (graphify 단계만 스킵)
- `/rakis:help`: 각 스킬에 대해 출력이 있는지, 설명이 실제 동작과 일치하는지

## 참고

- [[brain-trinity-llm-wiki-obsidian-graphify]] — 원본 영상 분석 및 3가지 개선 포인트 도출
- [[llm-wiki]] — Karpathy LLM Wiki 방법론
- [[graphify]] — graphify 도구 상세 (일반 지식 그래프용 포함)
