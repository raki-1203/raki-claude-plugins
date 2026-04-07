---
name: wiki-wrap-up
description: "세션 마무리 시 학습/발견을 Obsidian Wiki에 저장. 세션 끝내기 전 '/wiki-wrap-up' 실행. 이 세션에서 새로 알게 된 것, 해결한 문제, 발견한 패턴을 추출하여 위키에 기록한다."
argument-hint: "[주제 힌트 (선택)]
allowed-tools: [Read, Write, Edit, Glob, Grep, Bash, WebFetch, Agent]
---

# wiki-wrap-up — 세션 마무리 → Wiki 저장

세션 종료 전에 실행. 이 세션에서 배운 것을 Obsidian LLM Wiki에 기록한다.

## Vault 경로

`~/Library/Mobile Documents/com~apple~CloudDocs/Documents/Vault`

## 절차

### 1. 세션 회고 (자동)

이 세션의 대화를 돌아보며 다음을 추출한다:

**A. 새로 알게 된 것** (도구, 서비스, 라이브러리, 개념)
- 예: "OpenClaw은 LLM 오케스트레이션 프레임워크다"
- 예: "MCPVault는 Obsidian 안 켜도 vault 접근 가능"

**B. 해결한 문제와 방법** (트러블슈팅, 워크어라운드)
- 예: "iCloud vault 경로는 ~/Library/Mobile Documents/com~apple~CloudDocs/"
- 예: "PDF 텍스트 추출 안 되면 pdftoppm으로 이미지 변환 후 읽기"

**C. 결정과 이유** (아키텍처, 설계, 도구 선택)
- 예: "OMC 제거 — 실제로 안 쓰고 있어서"
- 예: "MCPVault 선택 — Obsidian 안 켜도 동작해서"

**D. 발견한 패턴/규칙**
- 예: "CLAUDE.md는 50줄 이하가 효과적"
- 예: "SDD + TDD 조합이 가장 강력"

### 2. 필터링

다음은 **저장하지 않는다:**
- 코드 변경 내용 (git에 있음)
- 이미 위키에 있는 내용 (`index.md` 확인)
- 프로젝트 특화 설정 (CLAUDE.md에 있음)
- 이 세션에서만 유효한 임시 정보

### 3. 사용자 확인

추출 결과를 보여주고 승인을 받는다:

```
## 이 세션에서 위키에 저장할 내용

### 새로운 개념 (N건)
- **OpenClaw**: 오픈소스 AI 에이전트 프레임워크 → wiki/concepts/에 저장
- **clawhip**: Claude Code ↔ OpenClaw 이벤트 브릿지 → wiki/concepts/에 저장

### 트러블슈팅 (N건)
- **iCloud vault 경로**: ~/Library/Mobile Documents/... → 기존 페이지에 추가

### 결정 기록 (N건)
- **OMC 제거**: 실제로 안 쓰고 있어서 CLAUDE.md에서 삭제 → log.md에 기록

저장할까요? (전체/선택/취소)
```

### 4. 위키 저장 실행

승인된 항목에 대해:

1. **새 개념/엔티티** → `wiki/concepts/` 또는 `wiki/entities/`에 새 페이지 생성
   - YAML frontmatter 포함 (title, type, sources, related, created, updated, confidence, description)
2. **기존 페이지 보강** → 해당 페이지의 내용 업데이트, `updated:` 갱신
3. **트러블슈팅/패턴** → 관련 개념 페이지에 섹션 추가, 또는 새 페이지 생성
4. **결정 기록** → `log.md`에 추가
5. **`index.md` 갱신** — 새 페이지가 있으면 적절한 섹션에 추가

### 5. 완료 보고

```
## Wiki Wrap-up 완료

- 새 페이지: 2건 (openclaw.md, clawhip.md)
- 업데이트: 1건 (claude-code.md)
- 로그 기록: 1건

다음 세션에서 "~에 대해 정리된 거 있어?"로 찾을 수 있습니다.
```

## 주의사항

- 사용자 승인 없이 저장하지 않음
- 과도하게 많이 저장하지 않음 — 세션당 핵심 3-5건이 적정
- 이미 위키에 있는 내용은 중복 생성하지 않고 업데이트
- `raw/`에는 저장하지 않음 (wrap-up은 가공된 지식이므로 wiki/에 직접)
