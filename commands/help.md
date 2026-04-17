---
description: rakis 플러그인의 사용법을 안내합니다 (/rakis:help 또는 /rakis:help <스킬명>)
---

# /rakis:help

당신은 rakis 플러그인의 사용법 안내를 담당합니다. 인자 유무에 따라 다르게 응답.

## 인자 파싱

`$ARGUMENTS`를 확인:
- **비어있음** → 전체 개요 출력 (단계 A)
- **스킬명 1개** → 해당 스킬 상세 출력 (단계 B)
- **알 수 없는 이름** → "알 수 없는 스킬" + 사용 가능한 스킬 목록 제시

인식하는 스킬명:
- `wiki-query`, `wiki-ingest`, `source-fetch`, `migrate-v3`, `wiki-wrap-up`, `wiki-lint`, `wiki-init`
- `setup`, `help`, `wc-cp-graph` (커맨드)

## 단계 A: 전체 개요 출력 (인자 없을 때)

아래 내용을 그대로 출력:

```
# rakis — Obsidian LLM Wiki 관리 플러그인

Karpathy의 LLM Knowledge Base 방법론(3-Layer)으로 Obsidian vault에 지식을 축적·질의하는 플러그인.

## 빠른 시작

1. 의존성 설치 (머신당 1회):
   /rakis:setup

2. vault 세팅 (vault당 1회):
   /wiki-init

3. 평소 사용:
   - "~ 정리된 거 있어?"           → wiki-query (답변형)
   - "이 프로젝트 관련 뭐 있어?"    → wiki-query (탐색형)
   - "~ 분석해줘"                   → source-fetch
   - "이거 저장해줘"                → wiki-ingest
   - /wiki-wrap-up                  → 세션 끝에 학습 저장

4. 주 1회: /wiki-lint
   (건강 점검 + 그래프 리빌드)

## 전체 스킬/커맨드

스킬:
  wiki-query      — 위키 질의 (답변형/탐색형 자동 분기)
  wiki-ingest     — 자료 저장 (코멘트 강제)
  source-fetch    — 소스 수집 (NotebookLM + 코멘트 강제)
  migrate-v3      — v2 → v3 vault 마이그레이션
  wiki-wrap-up    — 세션 학습 저장 (코멘트 자동 생성)
  wiki-lint       — 건강 점검 + 풀 그래프 리빌드
  wiki-init       — vault 초기화 (프로젝트 폴더에서 실행)

커맨드:
  /rakis:setup        — 의존성 설치 + 글로벌 CLAUDE.md 매핑
  /rakis:help         — 이 안내 (/rakis:help <스킬명>으로 상세)
  /rakis:wc-cp-graph  — 워크트리 graphify 파일 복사

## 자세히 보기

/rakis:help <이름>     예: /rakis:help wiki-query
```

## 단계 B: 스킬별 상세 출력 (인자 1개)

### wiki-query

```
# wiki-query — 위키 질의

## 용도
vault에 축적된 지식으로 질문에 답변하거나, 프로젝트 관련 위키 탐색.

## 동작 분기
- 답변형: "X가 뭐야?", "X 쓰는 법?"
  → index.md + 관련 페이지 + graphify query(있으면) → 답변 (인용 포함)
- 탐색형: "이 프로젝트 관련 뭐 있어?", "둘러보고 싶어"
  → 프로젝트 컨텍스트 수집(≤50줄) → graphify query → 관련 페이지 목록

## 사용 예시
"openclaw에 대해 정리된 거 있어?"
"riverpod 어떻게 쓰는 거였지?"
"이 프로젝트 관련해서 뭐 있어?"  (프로젝트 폴더에서)

## 트리거
"~ 정리된 거 있어?", "~ 뭐였지?", "~ 찾아봐"
```

### wiki-ingest

```
# wiki-ingest — 자료 저장

## 용도
URL/파일/텍스트를 Obsidian 3-Layer vault에 저장.
raw/에 원본 보존 + wiki/에 요약 페이지 생성 + 관련 페이지 업데이트.

## 사용법
/wiki-ingest <자료> "왜 저장하는지"

인자 없이 호출하면 코멘트를 질문으로 받음.

## 동작
1. 코멘트 수집 (필수)
2. raw/에 원본 저장 (immutable)
3. wiki/sources/에 요약 페이지 + comment frontmatter
4. 관련 페이지 업데이트 + index.md 갱신
5. log.md 기록
6. graphify <vault> --update (그래프 증분)

## 트리거
"저장해줘", "위키에 넣어줘", "정리해줘"
```

### source-fetch

```
# source-fetch — 소스 수집

## 용도
GitHub repo, 블로그, 논문 PDF, YouTube, LinkedIn 등을 NotebookLM으로 심층 분석하고 Obsidian에 축적.

## 사용법
/source-fetch <URL 또는 파일> "왜 분석하는지"

여러 소스 비교:
/source-fetch URL1 URL2 "왜 비교하는지"

## 동작
Phase 0: 코멘트 수집 + 유형 감지
Phase 1: 중복 체크 (캐시 재사용)
Phase 2~4: NotebookLM 병렬 분석
Phase 5: 결과 통합
Phase 6: raw/ + wiki/ 저장 (comment frontmatter 포함)
Phase 7: graphify <vault> --update

## 확장 분석
"더 깊이", "팟캐스트로", "슬라이드로", "퀴즈" 등 후속 요청 가능.

## 트리거
"분석해줘", "파악", "정리", "비교해줘", "vs"
```

### migrate-v3

```
# migrate-v3 — v2 → v3 vault 마이그레이션

## 용도
v2 구조(graph-report.md, analysis.md 등 legacy 파일)를 v3 Karpathy 3-Layer 구조로 변환.

## 사용법
/rakis:migrate-v3 --dry-run   # 영향 확인 (실제 변경 없음)
/rakis:migrate-v3             # 실제 실행

## 동작
1. v2 legacy 파일 탐지
2. dry-run 모드: 영향받는 파일 목록 + 변경 사항 미리보기
3. 실행 모드: raw/ 재구성 + wiki/ 메타데이터 마이그레이션
4. .rakis-v3-migrated 마커 생성

## 트리거
"/rakis:migrate-v3" 명시 실행, "v3 마이그레이션"
```

### wiki-wrap-up

```
# wiki-wrap-up — 세션 마무리 → 위키 저장

## 용도
세션 종료 전 이 세션의 학습/결정/트러블슈팅을 자동 추출해서 vault에 기록.

## 사용법
/wiki-wrap-up

## 동작
1. 세션 회고 (대화 자동 분석)
   - 새 개념, 해결한 문제, 결정, 패턴
   - 각 항목의 "왜"(comment) 자동 추출
2. 사용자 확인 (전체/선택/코멘트 수정/취소)
3. 승인된 항목 wiki/에 저장 (comment 포함)
4. log.md 기록
5. graphify <vault> --update

## 트리거
"/wiki-wrap-up" 명시 실행 권장
```

### wiki-lint

```
# wiki-lint — 위키 건강 점검

## 용도
vault 품질 정기 점검. 주 1회 권장.

## 사용법
/wiki-lint

## 점검 항목
A. 모순 — 다른 페이지가 같은 사실 다르게 기술
B. 오래된 정보 — updated: 30일 이상 (빠르게 변하는 주제)
C. 고아 페이지 — 아무 곳에서도 링크 안 됨
D. 누락 페이지 — [[link]] 있지만 파일 없음
E. 데이터 갭 — frontmatter 누락 (description, sources, related, confidence, comment)

## 동작
1. 전체 스캔
2. 5가지 점검
3. 카테고리별 리포트
4. 사용자 승인 후 수정 실행
5. graphify <vault> 풀 리빌드 (정합성 보장)

## 트리거
"위키 점검해줘", "위키 정리해줘", "린트해줘"
```

### wiki-init

```
# wiki-init — vault 초기화

## 용도
Obsidian vault에 Karpathy 3-Layer 구조를 자동 생성.
프로젝트 폴더에서 실행 (vault는 외부 경로).

## 사용법
/wiki-init

## 동작
1. 기존 상태 체크 (멱등성)
   - 없음/부분/CLAUDE존재/완료 5분기
2. 인터뷰 (6개 질문)
   - vault 경로, 역할, 목적, 자료 형태, 관심 분야, 아웃풋
3. 구조 생성 (raw/ 5 + wiki/ 5 + index.md + log.md)
4. vault CLAUDE.md 생성 (사용자 프로필 + 규칙)
5. 초기 graphify 빌드 (빈 vault는 스킵)
6. 완료 리포트

## 트리거
"/wiki-init" 명시 실행, "위키 초기화"
```

### setup

```
# /rakis:setup — 의존성 설치

## 용도
rakis 플러그인이 필요로 하는 외부 도구를 설치하고, 글로벌 CLAUDE.md에 스킬 매핑을 추가.

## 설치 대상
- uv (Python 도구 매니저, 전제조건)
- notebooklm-py (NotebookLM CLI)
- node, gh, graphify

## 사용법
/rakis:setup

## 동작
1~2. 전제조건 + 의존성 점검
3~4. 사용자 선택 후 설치 실행
5. notebooklm 인증 안내 (첫 설치 시)
6. 글로벌 ~/.claude/CLAUDE.md에 rakis 스킬 매핑 추가 (동의 시)
7~8. 마커 생성 + 결과 요약

## 멱등성
재실행 안전. 이미 설치된 도구는 --upgrade 실행.
```

### help

```
# /rakis:help — 사용법 안내

## 용도
rakis 전체 또는 특정 스킬/커맨드의 사용법 출력.

## 사용법
/rakis:help            — 전체 개요
/rakis:help <이름>     — 특정 스킬/커맨드 상세
```

### wc-cp-graph

```
# /rakis:wc-cp-graph — 워크트리 헬퍼

## 용도
메인 워크트리의 graphify 산출물(GRAPH_REPORT.md, CLAUDE.md, .claude/settings.json)을 현재 워크트리로 복사.

## 사용법
/rakis:wc-cp-graph

## 동작
메인 워크트리에서 다음을 현재 경로로 복사:
- graphify-out/GRAPH_REPORT.md
- CLAUDE.md (있으면)
- .claude/settings.json (있으면)
```

## 알 수 없는 이름일 때

```
알 수 없는 이름: <입력>

사용 가능한 스킬:
  wiki-query, wiki-ingest, source-fetch, migrate-v3, wiki-wrap-up, wiki-lint, wiki-init

사용 가능한 커맨드:
  setup, help, wc-cp-graph

/rakis:help <이름> 형식으로 호출하세요.
```

## 주의사항

- 각 스킬 상세는 하드코딩된 블록을 그대로 출력 (동적 생성 금지 — 일관성 유지)
- 스킬 파일이 수정되면 이 help도 같이 갱신해야 함
