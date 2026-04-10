---
name: project-graph
description: "현재 프로젝트에 graphify 지식 그래프를 셋업하고 유지보수. '그래프 셋업', '프로젝트 그래프', '구조 분석', 'graphify 설정', 'graphify 설치', '코드 구조 파악해줘', '아키텍처 분석' 등 요청 시 사용. 셋업 후 git hooks로 커밋마다 자동 갱신. '/project-graph'로 직접 호출 가능. 이미 graphify-out/이 있으면 갱신·질의 모드로 동작."
version: 1.0.0
license: MIT
---

# project-graph — 프로젝트 지식 그래프 셋업 + 유지보수

현재 작업 프로젝트에 graphify 지식 그래프를 구축하여, Claude Code가 프로젝트 구조를 항상 최신 상태로 파악할 수 있게 한다.

## 사전 조건 확인

1. `command -v graphify` — 없으면 안내:
   > "graphify가 필요합니다. `! uv tool install graphifyy --python 3.13` 을 실행해주세요."
2. 현재 디렉토리가 프로젝트 루트인지 확인 (`.git/` 또는 주요 설정 파일 존재)

## 모드 분기

`graphify-out/` 디렉토리 존재 여부로 모드를 결정:

### A. 초기 셋업 (graphify-out/ 없음)

1. **그래프 빌드**
   ```bash
   graphify
   ```
   - graphify-out/graph.json, GRAPH_REPORT.md, interactive HTML 등 생성
   - 완료 후 결과 요약을 사용자에게 출력 (노드 수, 엣지 수, 커뮤니티 수, 갓노드 상위 5개)

2. **Git Hooks 설치**
   ```bash
   graphify hook install
   ```
   - post-commit: 커밋할 때마다 변경된 코드 파일의 AST를 재파싱하여 graph.json 자동 갱신
   - post-checkout: 브랜치 전환 시 해당 브랜치 상태로 그래프 재빌드
   - 사용자에게 안내: "이제 커밋할 때마다 graph.json이 자동으로 갱신됩니다."

3. **Claude Code 통합 (선택)**
   ```bash
   graphify claude install
   ```
   - CLAUDE.md에 graphify 섹션 추가
   - PreToolUse 훅 등록 → Glob/Grep 호출 전에 GRAPH_REPORT.md를 컨텍스트에 자동 주입
   - 사용자에게 확인 후 실행 (CLAUDE.md를 수정하므로)

4. **사용자에게 안내**
   > "셋업 완료! 다음과 같이 활용할 수 있습니다:
   > - 커밋할 때마다 자동 갱신 (git hooks)
   > - `graphify query "질문"` — 그래프 기반 질의
   > - `graphify --update` — 문서/이미지 변경 시 수동 갱신
   > - `graphify --watch` — 백그라운드 실시간 감시 (터미널 필요)"

### B. 갱신 모드 (graphify-out/ 있음)

사용자 요청에 따라 분기:

| 요청 | 실행 |
|------|------|
| "그래프 업데이트", "갱신" | `graphify --update` (변경분만 재추출) |
| "구조 분석", "아키텍처 보여줘" | GRAPH_REPORT.md를 Read로 읽어서 요약 출력 |
| "X가 뭐야?", "X 어디서 쓰여?" | `graphify query "질문"` 실행 |
| "X에서 Y까지 경로" | `graphify query "X to Y" --dfs` 실행 |
| "전체 리빌드" | `graphify` (전체 재빌드) |
| "훅 상태 확인" | `graphify hook status` |

### C. 질의 모드

graphify-out/graph.json이 있으면 바로 질의 가능:

```bash
graphify query "이 프로젝트에서 가장 핵심적인 모듈은?" --budget 3000
```

- `--budget`: 토큰 예산 (기본 2000)
- `--dfs`: 깊이 우선 탐색 (경로 추적에 유리)

질의 결과를 사용자에게 보여주고, 필요하면 추가 질의를 이어간다.

## graphify 출력물 구조

```
graphify-out/
├── graph.json          ← 지식 그래프 (노드, 엣지, 커뮤니티)
├── GRAPH_REPORT.md     ← 분석 리포트 (갓노드, 서프라이징 연결)
├── graph.html          ← 인터랙티브 시각화
├── stats.json          ← 토큰 절감 통계
└── cache/              ← SHA256 캐시 (증분 업데이트용)
```

## .gitignore 권장

graphify-out/은 프로젝트에 커밋하지 않는 것을 권장 (로컬 분석 결과):
```
graphify-out/
```

단, GRAPH_REPORT.md를 팀과 공유하고 싶으면 별도로 커밋 가능.

## Obsidian 연동 (선택)

프로젝트 그래프 분석 결과를 Obsidian 위키에도 저장하고 싶으면:
1. GRAPH_REPORT.md를 `raw/repos/{프로젝트명}/graph-report.md`에 복사
2. wiki-ingest 절차를 따라 wiki/sources/{프로젝트명}.md 갱신

## 에러 처리

| 실패 지점 | 대응 |
|-----------|------|
| graphify 미설치 | uv tool install 안내 |
| graphify 실행 실패 | 에러 메시지 출력, 원인 안내 |
| git hooks 설치 실패 | .git/ 디렉토리 존재 확인, 수동 설치 안내 |
| graph.json 손상 | `graphify` 전체 리빌드 안내 |
| Claude Code 통합 거부 | 통합 없이도 query 명령으로 사용 가능 안내 |
