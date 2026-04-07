---
name: wiki-query
description: "Obsidian LLM Wiki에서 질문에 답변. 사용자가 이전에 조사/저장한 내용에 대해 질문하거나, '~에 대해 정리된 거 있어?', '~ 뭐였지?', '~ 찾아봐'라고 할 때 사용. index.md 기반 탐색 후 위키 인용으로 응답한다."
version: 1.0.0
license: MIT
---

# wiki-query — Obsidian LLM Wiki 질문 답변

위키에 축적된 지식을 기반으로 질문에 답변한다. RAG 대신 **컴파일된 지식**을 활용.

## Vault 경로 탐지

아래 순서로 Vault 경로를 결정:
1. 환경변수 `OBSIDIAN_VAULT_PATH`가 있으면 사용
2. `~/Library/Mobile Documents/com~apple~CloudDocs/Documents/Vault` (iCloud)

## 절차

### 1. index.md 읽기

`index.md`를 **반드시 먼저** 읽어 관련 페이지를 파악한다.
이것이 위키의 검색 엔진 역할을 한다.

### 2. 관련 페이지 탐색

index에서 찾은 관련 페이지들을 읽고 정보 수집.
필요하면 각 페이지의 `related:` 링크를 따라 추가 페이지도 탐색.

탐색 우선순위:
1. `wiki/concepts/` — 주제별 정리
2. `wiki/entities/` — 사람/조직 정보
3. `wiki/comparisons/` — 비교 분석
4. `wiki/sources/` — 원본 요약

### 3. 답변 합성

- 위키 페이지를 `[[wiki-link]]` 형태로 인용하며 답변
- 여러 페이지의 정보를 종합할 때 출처를 명시
- `confidence`가 low인 정보는 불확실하다고 표시
- `updated:` 날짜가 오래된 정보는 "최신 정보가 아닐 수 있음" 표시

### 4. 새 페이지 생성 (선택적)

답변이 충분히 가치 있고 기존에 없는 내용이면:
- 적절한 `wiki/` 하위 폴더에 새 페이지 생성
- YAML frontmatter 포함 (type, sources, related, created, updated, confidence, description)
- `index.md` 갱신
- `log.md` 기록

## 응답 형식

```markdown
## 답변

[위키 기반 답변 내용]

**참조한 위키 페이지:**
- [[page-1]] — 관련 내용 요약
- [[page-2]] — 관련 내용 요약
```

## 위키에 없는 경우

위키에 없는 내용은 **명확히** 알려준다:

```
위키에 아직 관련 내용이 없습니다.
조사해서 위키에 추가할까요?
```

사용자가 동의하면 → wiki-ingest 절차로 전환.

## 주의사항

- 위키 정보가 오래되었을 수 있으므로 `updated:` 날짜 항상 확인
- 위키에 없는 내용을 있는 것처럼 답변하지 말 것
- 웹 검색이 필요하면 사용자에게 ingest 제안
- 답변 시 반드시 출처 페이지를 인용
