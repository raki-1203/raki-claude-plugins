# rakis 플러그인 setup 시스템 — 디자인

## 배경

raki-claude-plugins 의 `source-analyze`, `project-graph` 등 일부 스킬은 외부 도구(notebooklm-py, gh, graphify, node 등)에 의존한다. 새 맥에 플러그인을 처음 설치했을 때 이 의존성이 자동으로 갖춰지지 않아, 사용자가 SKILL.md를 읽으며 하나씩 깔아야 한다. 일부가 누락된 채로 source-analyze가 실행되면 fallback 동작으로 떨어져 결과 품질이 떨어질 수 있다.

## 목표

1. 새 맥에 플러그인을 설치하면 첫 세션에 자동으로 "setup 필요" 안내가 한 번 뜬다.
2. `/rakis-setup` 명령 한 번으로 플러그인 전체 외부 의존성을 점검하고, 사용자 동의 후 자동 설치한다.
3. setup이 끝나면 다시 안내하지 않는다.
4. Idempotent — 언제든 다시 실행해도 안전.

## Non-goals

- `notebooklm login` 같은 인터랙티브 인증의 자동화 — 안내만 한다.
- `brew` 자체의 자동 설치 — 안내만 하고 setup 중단.
- 비-macOS(Linux/Windows) 환경 지원 — v1은 macOS만 가정.
- 버전 변경에 따른 재안내 — v2 후보.
- **PPT/PPTX, DOCX 파일 처리 — source-analyze에서 기능 자체를 제거한다** (시스템 python3 의존이 깨지기 쉽고, 사용 빈도가 낮음. 필요해지면 v2에서 ephemeral 실행으로 재도입).

## 아키텍처

### 신규 파일

```
raki-claude-plugins/
├── hooks/
│   └── hooks.json               ← SessionStart hook 정의 (신규)
└── commands/
    └── rakis-setup.md           ← /rakis-setup 명령 (Claude에게 지시문, 신규)
```

### 수정 파일

- `README.md` — Setup 섹션 추가
- `skills/source-analyze/SKILL.md` — PPT/PPTX, DOCX 처리 관련 모든 부분 제거 (소스 유형 표, 변환 코드 블록, 에러 처리, description)

> `scripts/check-deps.sh` 같은 별도 스크립트는 만들지 않는다. 의존성 점검은 `commands/rakis-setup.md` 안에서 Claude가 직접 `command -v` 호출로 처리한다 (단순성, 재사용 필요성 없음).

### 컴포넌트 1: SessionStart Hook

위치: `hooks/hooks.json`

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          {
            "type": "command",
            "command": "test -f \"${CLAUDE_PLUGIN_DATA}/.setup-done\" || echo '[rakis] 처음 사용이시네요. /rakis-setup 을 먼저 실행해주세요.'",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

- `matcher: "startup"` — 세션 시작 시점에 발화
- `${CLAUDE_PLUGIN_DATA}/.setup-done` 마커 파일이 없으면 한 줄 안내를 stdout에 출력 → Claude context로 주입됨
- 마커 있으면 조용 (`test -f ... || echo`로 분기)
- 실제 의존성 점검은 hook이 아니라 `/rakis-setup`의 책임 (hook은 항상 가볍게 유지)

### 컴포넌트 2: `/rakis-setup` 명령

위치: `commands/rakis-setup.md`

이 파일은 Claude에게 다음 절차를 수행하라는 지시문이다:

#### 단계 1: 전제조건 점검

- `command -v brew` 실패 → 안내 후 setup 중단:
  > brew가 필요합니다. 다음을 실행한 뒤 `/rakis-setup`을 다시 실행해주세요.
  > ```
  > /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  > ```
- `command -v uv` 실패 → 사용자 동의 후 자동 설치:
  ```
  curl -LsSf https://astral.sh/uv/install.sh | sh
  ```

#### 단계 2: 의존성 점검 표 출력

```
[필수]
  uv               ✓
  notebooklm-py    ✗   uv tool install notebooklm-py --with playwright
  node             ✓
  gh               ✗   brew install gh

[선택]
  graphify         ✗   uv tool install graphifyy --python 3.13
                       (project-graph 스킬 + source-analyze 코드 분석용)
```

#### 단계 3: 사용자 선택

빠진 게 있으면:
```
필수 N개, 선택 M개 누락. 어떻게 진행할까요?
[a] 필수만 설치
[b] 전체 설치 (필수 + 선택)
[c] 항목별 선택
[s] 건너뛰기 (마커는 만듦, 더 안내 안 함)
```

#### 단계 4: 설치 실행

선택에 따라 명령을 순차 실행. 각 명령은 Claude Code의 권한 prompt를 통해 사용자가 한 번 더 확인하므로, 자동 설치라 해도 사용자 통제권은 유지된다.

#### 단계 5: 인터랙티브 인증 안내

`notebooklm-py`가 새로 설치된 경우, 마지막에:
> notebooklm 인증이 필요합니다. 다음 명령을 직접 실행해주세요 (브라우저에서 Google 로그인):
> ```
> ! notebooklm login
> ```

#### 단계 6: 마커 생성

모든 필수 단계가 완료(설치 성공 또는 사용자가 [s] 선택)되면:
```bash
mkdir -p "${CLAUDE_PLUGIN_DATA}"
touch "${CLAUDE_PLUGIN_DATA}/.setup-done"
```

#### 단계 7: 결과 요약 출력

무엇이 새로 설치됐는지 / 무엇이 빠졌는지 / 사용자가 다음에 할 일(예: notebooklm login)을 표 또는 목록으로 정리.

## 의존성 매핑 (확정)

| 도구 | 분류 | 체크 방법 | 설치 명령 | 비고 |
|------|------|----------|----------|------|
| `brew` | 전제조건 | `command -v brew` | (수동 — 안내만) | 없으면 setup 중단 |
| `uv` | 전제조건 | `command -v uv` | `curl -LsSf https://astral.sh/uv/install.sh \| sh` | 동의 후 자동 설치 |
| `node`/`npm` | 필수 | `command -v npm` | `brew install node` | repomix가 npx로 실행하기 위해 필요 |
| `notebooklm-py` | 필수 | `command -v notebooklm` | `uv tool install notebooklm-py --with playwright` | source-analyze 핵심 엔진. playwright 브라우저는 함께 설치됨 |
| `gh` | 필수 | `command -v gh` | `brew install gh` | GitHub repo 분석용 |
| `graphify` | 선택 | `command -v graphify` | `uv tool install graphifyy --python 3.13` | PyPI 패키지명은 `graphifyy` (오타 아님), 명령어는 `graphify`. project-graph 스킬과 source-analyze 코드 분석 양쪽에서 사용 |

### 특수 항목

- **`playwright` 브라우저**: `notebooklm-py`를 `--with playwright`로 설치할 때 함께 설치되므로 별도 점검 항목 없음.
- **`notebooklm login`**: 인터랙티브(브라우저 Google 로그인). 자동화 불가, 안내만.
- **`repomix`**: `npx`로 즉석 실행. 사전 설치 불필요.

## 흐름 다이어그램

```
새 맥에 플러그인 설치
       ↓
첫 Claude Code 세션
       ↓
SessionStart hook 발화
       ↓
${CLAUDE_PLUGIN_DATA}/.setup-done 존재?
       ↓ No
"[rakis] /rakis-setup 을 먼저 실행해주세요" 안내 출력
       ↓
사용자가 /rakis-setup 실행
       ↓
brew 존재?  ── No ──→ 안내 후 중단 (마커 X)
       ↓ Yes
uv 존재?  ── No ──→ 동의 후 설치
       ↓ Yes
의존성 점검 → 표 출력
       ↓
빠진 거 있나?  ── No ──→ "이미 setup 완료" 출력 + 마커 생성
       ↓ Yes
사용자 선택 (a/b/c/s)
       ↓
설치 명령 순차 실행 (각각 권한 prompt)
       ↓
모든 필수 설치 성공?  ── No ──→ 실패 항목 표시, 마커 X
       ↓ Yes
notebooklm 새로 설치됐나?  ── Yes ──→ ! notebooklm login 안내
       ↓
마커 파일 생성
       ↓
결과 요약 출력
       ↓
다음 세션부터는 hook이 조용
```

## 에러 처리 / 엣지 케이스

| 상황 | 대응 |
|------|------|
| `brew` 없음 | 안내 후 setup 중단. 마커 안 만듦 |
| `uv` 설치 실패 | 에러 메시지 출력, setup 중단. 마커 안 만듦 |
| 개별 도구 설치 실패 | 어떤 게 실패했는지 표시. 마커 안 만듦 (다음에 다시 시도하도록) |
| 사용자가 [s] 건너뛰기 선택 | 마커 만듦 (안내 끄기). source-analyze는 fallback 동작 |
| 사용자가 권한 prompt 거부 | "거부됨, 마커 안 만듦. 나중에 다시 /rakis-setup 실행" |
| 이미 마커 있는 상태에서 재실행 | 조용히 점검만 → 모두 ✓이면 "이미 setup 완료" 출력 후 종료. 빠진 게 있으면 정상 설치 흐름 |
| 일부 도구만 설치된 부분 상태 | `/rakis-setup` 재실행이면 자연스럽게 빠진 것만 다시 시도 (idempotent) |

## source-analyze SKILL.md 변경

PPT/PPTX, DOCX 처리 기능을 완전히 제거한다.

| 위치 | 변경 내용 |
|------|----------|
| `description` (라인 3) | "PPT, 문서" 같은 표현 제거. 지원 소스 목록을 GitHub repo / 블로그 / 논문 PDF / YouTube / LinkedIn / X 정도로 정리 |
| Phase 0 "소스 유형 자동 감지" 표 (라인 33~42) | `PPT/PPTX`, `DOCX` 행 삭제 |
| "전처리 상세" 섹션 (라인 49~76) | `PPT/PPTX 변환` 코드 블록과 `DOCX 변환` 코드 블록 삭제 |
| "에러 처리 요약" 표 (라인 182) | "PPT/DOCX 변환 실패" 행 삭제 |

이미지, LinkedIn/X, 로컬 텍스트/마크다운 등 나머지 소스 유형 처리는 그대로 유지된다 (외부 도구 의존이 없거나 있어도 setup 대상에 포함됨).

## README 변경

`README.md`에 Setup 섹션 추가 (Installation 섹션 바로 아래):

```markdown
## Setup

플러그인 설치 후 한 번만 실행해주세요:

\`\`\`
/rakis-setup
\`\`\`

`source-analyze`, `project-graph` 등 일부 스킬에 필요한 외부 도구(notebooklm-py, gh, graphify 등)를 점검하고, 누락된 것을 동의 후 설치합니다.

전제조건: macOS, Homebrew. brew가 없으면 setup 시작 시 안내합니다.
```

## 테스트 계획

플러그인 기능이라 단위 테스트가 어렵고, 다양한 환경 시나리오를 직접 돌려서 확인하는 방식으로 검증한다.

| 시나리오 | 기대 동작 |
|---------|----------|
| 의존성이 모두 있는 환경 → `/rakis-setup` 실행 | "이미 모두 설치되어 있습니다" 출력 + 마커 생성 |
| 일부 빠진 환경 → `/rakis-setup` → [a] 필수만 | 필수만 설치, 선택 항목 skip, 마커 생성 |
| 일부 빠진 환경 → `/rakis-setup` → [b] 전체 | 모두 설치, 마커 생성 |
| 일부 빠진 환경 → `/rakis-setup` → [c] 항목별 | 사용자가 선택한 것만 설치 |
| 일부 빠진 환경 → `/rakis-setup` → [s] 건너뛰기 | 아무것도 설치 안 함, 마커는 생성 |
| brew 없는 환경 → `/rakis-setup` | 안내 후 중단, 마커 X |
| 첫 세션 (마커 없음) | hook이 안내 메시지 출력 |
| 두 번째 세션 (마커 있음) | hook 조용 |
| 이미 마커 있는 상태에서 `/rakis-setup` 재실행 | 점검만 수행, 빠진 게 없으면 즉시 종료 |

## v2 후보 (지금은 하지 않음)

- `plugin.json` 버전 추적 → 새 의존성 추가 시 자동 재안내
- Linux / Windows 지원
- `--recheck` / `--yes` 옵션 (비대화형 모드)
- PPT/DOCX 처리 재도입 (필요해진다면) — `uv run --with python-pptx python3 -c "..."` 형식의 ephemeral 실행으로
- 의존성 매트릭스를 `commands/rakis-setup.md` 본문에서 분리해 별도 manifest 파일로 관리
