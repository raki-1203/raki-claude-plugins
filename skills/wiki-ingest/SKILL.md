---
name: wiki-ingest
description: "Obsidian LLM Wiki에 새 자료를 수집(Ingest). 사용자가 URL, 글, PDF, 정보를 '저장해줘', '위키에 넣어줘', '정리해줘'라고 하거나, 조사/리서치 결과를 기록할 때 사용. raw/에 원본 저장 후 wiki/ 페이지를 자동 생성·갱신한다."
version: 1.0.0
license: MIT
---

# wiki-ingest — Obsidian LLM Wiki 자료 수집

Karpathy의 LLM Knowledge Base 방법론 기반. 새 자료를 3-Layer Vault에 수집한다.

## Vault 경로 탐지

아래 순서로 Vault 경로를 결정:
1. 환경변수 `OBSIDIAN_VAULT_PATH`가 있으면 사용
2. `~/Library/Mobile Documents/com~apple~CloudDocs/Documents/Vault` (iCloud)
3. Vault 내 `CLAUDE.md`에 "Three-Layer" 또는 "raw/" 언급이 있는지 확인하여 검증

## 절차

### 1. 원본 저장 (raw/) — Immutable

소스 유형에 따라 적절한 하위 폴더에 저장. **한 번 저장하면 절대 수정하지 않는다.**

| 유형 | 폴더 | 방법 |
|------|------|------|
| URL/웹 글 | `raw/articles/` | WebFetch로 내용 가져와 마크다운으로 저장 |
| PDF | `raw/papers/` | 파일 복사 또는 요약 저장 |
| 코드/레포 | `raw/repos/` | README, 핵심 코드 발췌 |
| 데이터 | `raw/data/` | CSV, JSON 등 |
| 이미지 | `raw/images/` | 스크린샷, 다이어그램 |
| 기타 | `raw/assets/` | 다운로드 첨부파일 |

파일명: `kebab-case.md` (날짜 접두사 선택적: `2026-04-07-title.md`)

### 2. 요약 페이지 생성 (wiki/sources/)

모든 wiki 페이지는 반드시 YAML frontmatter를 포함:

```yaml
---
title: Source Title
type: source-summary
sources:
  - "[[raw/articles/source-file]]"
related:
  - "[[관련-위키-페이지]]"
created: YYYY-MM-DD
updated: YYYY-MM-DD
confidence: high | medium | low
description: 한 줄 요약
---
```

핵심 내용을 구조화하여 요약. 원문 인용은 `>` 블록쿼트 사용.

### 3. 기존 위키 페이지 업데이트

1. `index.md`를 읽어 관련 기존 페이지 파악
2. 관련 페이지의 내용 보강, `related:` 링크 추가, `updated:` 갱신
3. 새 개념이 발견되면 → `wiki/concepts/`에 새 페이지
4. 새 사람/조직이 발견되면 → `wiki/entities/`에 새 페이지
5. 비교 분석이 필요하면 → `wiki/comparisons/`에 새 페이지

**하나의 source가 10-15개 기존 페이지에 영향을 줄 수 있다.**

### 4. index.md 갱신

새로 생성된 모든 페이지를 적절한 섹션(Concepts/Entities/Sources/Comparisons)에 추가.
형식: `- [[page-name]] — 한 줄 설명`

### 5. log.md 기록

맨 아래에 추가:
```
## [YYYY-MM-DD] page-name | 작업 설명
```

## 페이지 유형별 폴더

| type | 폴더 | 예시 |
|------|------|------|
| concept | `wiki/concepts/` | openclaw.md, mcp-server.md |
| entity | `wiki/entities/` | anthropic.md, heo-yechan.md |
| source-summary | `wiki/sources/` | karpathy-llm-wiki-gist.md |
| comparison | `wiki/comparisons/` | openclaw-vs-claude-channels.md |

## 링킹 규칙

- Obsidian 스타일 `[[wiki-link]]` 사용
- wiki/ 내에서는 상대 링크: `[[openclaw]]` (전체 경로 아님)
- 태그: `#concept`, `#entity`, `#tool`, `#person`

## 언어 규칙

- 기술 용어: 영어 그대로
- 설명/서술: 한국어

## 주의사항

- `raw/` 파일은 생성 후 **절대 수정하지 않음** (immutable)
- 모든 wiki 페이지에 YAML frontmatter **필수**
- frontmatter의 `description`은 dataview 쿼리에 사용되므로 반드시 작성
- 이미 존재하는 페이지를 중복 생성하지 말 것 — index.md를 먼저 확인
