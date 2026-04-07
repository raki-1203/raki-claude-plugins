---
name: wiki-lint
description: "Obsidian LLM Wiki 건강 점검. '위키 점검해줘', '위키 정리해줘', '린트해줘'라고 할 때 사용. 모순, 고아 페이지, 누락 개념, 오래된 정보를 식별하고 수정을 제안한다. 주 1회 실행 권장."
version: 1.0.0
license: MIT
---

# wiki-lint — Obsidian LLM Wiki 건강 점검

위키의 품질과 일관성을 유지하기 위한 정기 점검. 주 1회 실행 권장.

## Vault 경로 탐지

아래 순서로 Vault 경로를 결정:
1. 환경변수 `OBSIDIAN_VAULT_PATH`가 있으면 사용
2. `~/Library/Mobile Documents/com~apple~CloudDocs/Documents/Vault` (iCloud)

## 절차

### 1. 전체 스캔

wiki/ 하위 모든 .md 파일을 읽음:
- `wiki/concepts/`
- `wiki/entities/`
- `wiki/sources/`
- `wiki/comparisons/`
- `projects/` (레거시 폴더, 존재하는 경우)
- `index.md`, `log.md`

### 2. 5가지 점검 항목

#### A. 모순 (Contradictions)
서로 다른 페이지에서 같은 사실을 다르게 기술하는 경우.
→ 어느 쪽이 맞는지 판단하고 수정 제안.
→ 최신 source를 가진 쪽을 우선.

#### B. 오래된 정보 (Stale)
`updated:` 날짜가 30일 이상 된 페이지 중 빠르게 변하는 주제.
(도구 버전, API, 가격 등은 빠르게 변함)
→ 재확인 또는 업데이트 필요 표시.

#### C. 고아 페이지 (Orphans)
다른 페이지에서 `[[링크]]`로 참조되지 않는 페이지.
→ 관련 페이지에 링크 추가하거나 삭제 제안.

#### D. 누락 페이지 (Missing)
`[[wiki-link]]`로 언급되지만 실제 파일이 없는 개념.
→ 페이지 생성 제안 (제목 + 한 줄 설명).

#### E. 데이터 갭 (Gaps)
frontmatter가 불완전한 페이지:
- `description` 누락
- `sources` 비어있음
- `related` 비어있음
- `confidence` 누락
→ 보완 제안.

### 3. 보고서 작성

점검 결과를 카테고리별로 정리하여 사용자에게 보고:

```markdown
## 위키 린트 결과 (YYYY-MM-DD)

**총 페이지: N개**

### 🔴 모순 (N건)
- [[page-a]] vs [[page-b]]: 설명

### 🟡 오래된 정보 (N건)
- [[page]]: 마지막 업데이트 YYYY-MM-DD, 주제 특성상 재확인 필요

### 🟠 고아 페이지 (N건)
- [[page]]: 어디서도 참조되지 않음

### 🔵 누락 페이지 (N건)
- [[missing-page]]: [[page-a]]에서 언급됨

### ⚪ 데이터 갭 (N건)
- [[page]]: description 누락

### ✅ 건강한 페이지 (N개)
```

### 4. 수정 실행

**반드시 사용자 승인 후 실행:**
- 모순/오래된 정보 수정
- 누락 페이지 생성
- 링크 보강
- frontmatter 보완
- `index.md` 갱신
- `log.md`에 린트 실행 기록: `## [YYYY-MM-DD] lint | 위키 린트 N건 수정`

## 주의사항

- 수정은 보고 후 **사용자 승인을 받고** 실행
- 삭제보다는 업데이트 우선
- 대량 변경 시 카테고리별로 나눠서 진행
- index.md도 점검 대상 — 실제 파일과 index 항목이 일치하는지 확인
