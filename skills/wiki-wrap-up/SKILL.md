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

**추가 추출: 각 항목의 "왜" (코멘트)**

각 항목에 대해 세션 대화 맥락에서 **왜 이것이 저장 가치가 있는지** 한 줄로 자동 추출한다. 이것은 나중에 frontmatter의 `comment` 필드로 저장된다.

예시:
- OpenClaw: `"jobdori 분석 중 원류 프레임워크로 등장, 별도 페이지 필요"`
- iCloud vault 경로: `"vault 접근 시도 중 iCloud 경로 특이성 발견"`
- OMC 제거 결정: `"실제 사용 안 함 확인, CLAUDE.md 간소화 목적"`

추출 기준:
- 세션에서 해당 주제가 **언제/왜 등장했는지**
- 작업의 어떤 문맥에서 유용했는지
- 사용자가 명시적으로 언급하지 않았어도 대화 흐름에서 유추 가능

### 2. 필터링

다음은 **저장하지 않는다:**
- 코드 변경 내용 (git에 있음)
- 이미 위키에 있는 내용 (`index.md` 확인)
- 프로젝트 특화 설정 (CLAUDE.md에 있음)
- 이 세션에서만 유효한 임시 정보

### 3. 사용자 확인

추출 결과를 보여주고 승인을 받는다. 각 항목에 자동 생성된 comment도 함께 표시:

```
## 이 세션에서 위키에 저장할 내용

### 새로운 개념 (N건)
- **OpenClaw**: 오픈소스 AI 에이전트 프레임워크
  comment: "jobdori 분석 중 원류 프레임워크로 등장"
  → wiki/concepts/에 저장

- **clawhip**: Claude Code ↔ OpenClaw 이벤트 브릿지
  comment: "OpenClaw 알림 구조 조사 중 발견"
  → wiki/concepts/에 저장

### 트러블슈팅 (N건)
- **iCloud vault 경로**: ~/Library/Mobile Documents/...
  comment: "vault 접근 시 iCloud 경로 특이성"
  → 기존 페이지에 추가

### 결정 기록 (N건)
- **OMC 제거**: 실제로 안 쓰고 있어서 CLAUDE.md에서 삭제
  comment: "실사용 검증 후 CLAUDE.md 간소화"
  → log.md에 기록

저장할까요?
[전체] 그대로 저장
[선택] 항목별 선택
[수정] 코멘트 수정 후 저장
[취소] 저장하지 않음
```

**[수정] 선택 시**: 각 항목에 대해 "이 코멘트로 할까요? (Enter = 그대로, 수정할 내용 입력)" 순차 질문. 사용자 입력을 해당 항목의 comment로 대체.

### 4. 위키 저장 실행

승인된 항목에 대해:

1. **새 개념/엔티티** → `wiki/concepts/` 또는 `wiki/entities/`에 새 페이지 생성
   - YAML frontmatter 포함 (title, type, sources, `comment`, related, created, updated, confidence, description)
   - `comment`: Step 1에서 자동 추출된 값 또는 Step 3에서 사용자가 수정한 값
2. **기존 페이지 보강** → 해당 페이지의 내용 업데이트, `updated:` 갱신
   - 기존 페이지에 `comment` 필드가 없으면 자동 추가 (이 세션에서 추출된 값으로)
   - 이미 `comment`가 있으면 덮어쓰지 않고 기존 값 유지
3. **트러블슈팅/패턴** → 관련 개념 페이지에 섹션 추가, 또는 새 페이지 생성
4. **결정 기록** → `log.md`에 추가
5. **`index.md` 갱신** — 새 페이지가 있으면 적절한 섹션에 추가

### 5. 그래프 증분 업데이트

Step 4의 저장이 끝나면 vault 그래프를 증분 업데이트한다.

**조건 체크:**
```bash
command -v graphify
```

- 성공 → 업데이트 실행
- 실패 → 건너뜀 (경고 없이 조용히)

**실행:**
```bash
graphify "${VAULT_PATH}" --update
```

- graph.json 없으면 graphify가 풀 빌드로 자동 전환
- graphify 명령의 stdout을 한 줄로 요약해서 Step 6 완료 보고에 포함
- 실패해도 wrap-up 자체는 성공 (그래프는 다음 lint에서 복구)

**`${VAULT_PATH}`**: "## Vault 경로" 섹션의 경로 (또는 `OBSIDIAN_VAULT_PATH` 환경변수).

### 6. 완료 보고

```
## Wiki Wrap-up 완료

- 새 페이지: 2건 (openclaw.md, clawhip.md)
- 업데이트: 1건 (claude-code.md)
- 로그 기록: 1건
- 그래프: 증분 업데이트 완료 (자세한 건 graphify 출력 참조)

다음 세션에서 "~에 대해 정리된 거 있어?"로 찾을 수 있습니다.
```

## 주의사항

- 사용자 승인 없이 저장하지 않음
- 과도하게 많이 저장하지 않음 — 세션당 핵심 3-5건이 적정
- 이미 위키에 있는 내용은 중복 생성하지 않고 업데이트
- `raw/`에는 저장하지 않음 (wrap-up은 가공된 지식이므로 wiki/에 직접)
