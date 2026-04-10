# 출력 문서 템플릿

Phase 5에서 모든 에이전트 결과를 통합할 때 사용하는 문서 구조.

## 사용자 출력용 통합 문서

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
{Phase 3 공통 질문 답변을 섹션으로 구조화}

### 이 프로젝트가 해결하는 문제
### 기술 스택과 의존성
### 프로젝트 구조
### 사용법
### 강점과 한계

## 맞춤 분석
{Phase 3 맞춤 질문 답변}

## 리포트
{Agent D 결과 — NotebookLM 미사용 시 "NotebookLM 미사용 — 해당 항목 없음"}

## 마인드맵
{Agent E 결과를 마크다운 계층 목록으로 변환 — NotebookLM 미사용 시 "NotebookLM 미사용 — 해당 항목 없음"}

## 구조적 분석 (graphify)
{Agent G 결과 — graphify 미실행 시 "graphify 미설치 — 해당 항목 없음"}

### God Nodes (핵심 허브)
{GRAPH_REPORT.md에서 추출}

### Surprising Connections
{GRAPH_REPORT.md에서 추출}

### 커뮤니티 구조
{GRAPH_REPORT.md에서 추출}

## NotebookLM
- 노트북 ID: {notebook_id 또는 "미생성"}
- 추가 질의: `notebooklm use {notebook_id} && notebooklm ask "질문"`
```

## 비교 분석용 문서 (멀티 소스 모드)

```markdown
# {repo1} vs {repo2} 비교 분석

## 개요
| 항목 | {repo1} | {repo2} |
|------|---------|---------|
| 한 줄 설명 | | |
| Stars | | |
| 기술 스택 | | |
| 라이선스 | | |

## 공통점

## 차이점

## 각각 적합한 사용 시나리오

## 종합 평가

## NotebookLM
- 노트북 ID: {notebook_id}
- 추가 질의 가능
```

## Obsidian 저장 구조

### 단일 소스

```
raw/repos/{repo명}/
  ├── metadata.md       ← Agent A 결과
  ├── analysis.md       ← Phase 5 통합 문서 전문
  ├── repomix.txt       ← repomix 캐시 (재분석 시 재사용)
  └── graph-report.md   ← graphify 결과 (있을 때만)

wiki/sources/{repo명}.md ← 정제본
```

### 비교 분석 (멀티 소스)

```
wiki/comparisons/{repo1}-vs-{repo2}.md ← 비교 정제본
```

## wiki 페이지 frontmatter 템플릿

```yaml
---
title: {Repo명}
type: source-summary
sources:
  - "[[raw/repos/{repo명}/metadata]]"
  - "[[raw/repos/{repo명}/analysis]]"
related:
  - "[[관련-위키-페이지]]"
created: YYYY-MM-DD
updated: YYYY-MM-DD
confidence: high
description: "한 줄 요약"
---
```
