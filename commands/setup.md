---
description: rakis 플러그인의 외부 의존성을 점검하고 누락된 도구를 설치합니다
---

# /rakis:setup

당신은 raki-claude-plugins 플러그인의 의존성 셋업을 수행합니다. 다음 절차를 정확히 따라주세요.

## 단계 1: 전제조건 점검

다음을 순서대로 확인하세요.

### brew

```bash
command -v brew
```

- 성공 → 다음 단계로
- 실패 → 사용자에게 다음 메시지를 출력하고 **즉시 중단** (마커 만들지 마세요):
  > brew(Homebrew)가 필요합니다. 다음 명령을 직접 실행한 뒤, `/rakis:setup`을 다시 실행해주세요.
  >
  > ```
  > /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  > ```

### uv

```bash
command -v uv
```

- 성공 → 다음 단계로
- 실패 → 사용자에게 "uv를 자동 설치할까요?"라고 묻고, 동의 시:
  ```bash
  curl -LsSf https://astral.sh/uv/install.sh | sh
  ```
  설치 후 PATH 갱신을 위해 사용자에게 새 셸 또는 `source ~/.zshrc`(또는 동등) 안내. 거부 시 setup 중단 (마커 만들지 마세요).

> **주의**: `uv` 설치 직후에는 현재 세션에서 PATH가 아직 갱신되지 않아 `command -v uv`가 계속 실패할 수 있습니다. 이 경우 사용자에게 "새 터미널을 열고 `/rakis:setup`을 다시 실행해주세요"라고 안내한 뒤 **이 세션에서는 중단**하세요 (마커 만들지 마세요). 같은 세션에서 재설치를 반복하지 마세요.

## 단계 2: 의존성 점검

다음 도구들의 설치 여부를 `command -v`로 확인하세요.

> 점검 결과를 대화가 끝날 때까지 기억해두세요 (예: `missing = [notebooklm-py, gh]`, `installed_already = [uv, node]`). 단계 7의 결과 요약에서 "새로 설치됨" vs "이미 있던 것"을 구분하려면 이 정보가 필요합니다.

| 도구 | 체크 명령 | 설치 명령 |
|------|----------|----------|
| `notebooklm-py` | `command -v notebooklm` | `uv tool install notebooklm-py --with playwright` |
| `node` | `command -v node` | `brew install node` |
| `gh` | `command -v gh` | `brew install gh` |
| `graphify` | `command -v graphify` | `uv tool install graphifyy --python 3.13` |

> **graphify 패키지명 주의**: PyPI 패키지명은 `graphifyy` (오타 아님, y가 두 개), 설치 후 명령어는 `graphify` (y 한 개).

결과를 다음 형식으로 출력하세요:

```
[필수]
  uv               ✓
  notebooklm-py    ✗   uv tool install notebooklm-py --with playwright
  node             ✓
  gh               ✗   brew install gh
  graphify         ✗   uv tool install graphifyy --python 3.13
```

모든 항목이 ✓이면 단계 3을 건너뛰고 단계 6으로 가세요. ("이미 모두 설치되어 있습니다" 출력 + 마커 생성)

## 단계 3: 사용자 선택

빠진 게 있으면 다음과 같이 묻고 답을 기다리세요:

```
필수 N개 누락. 어떻게 진행할까요?
[a] 모두 설치
[c] 항목별 선택
[s] 건너뛰기 (마커는 만듦, 이후 안내 안 함)
```

## 단계 4: 설치 실행

사용자 선택에 따라:
- **[a] 모두 설치**: 빠진 도구를 위 표 순서대로 설치 명령 실행
- **[c] 항목별 선택**: 각 빠진 도구에 대해 하나씩 "설치할까요?" 묻고 동의 항목만 설치
- **[s] 건너뛰기**: 아무것도 설치하지 않고 단계 6으로 (마커는 생성)

각 설치 명령은 Bash 도구로 직접 실행. Claude Code의 권한 prompt가 사용자에게 한 번 더 확인을 받습니다.

설치 중 하나라도 실패하면, **마커를 만들지 말고** 사용자에게 어떤 게 실패했는지 보고한 뒤 종료. 앞서 성공한 도구들은 시스템에 이미 설치된 상태로 유지되므로, 다음 `/rakis:setup` 재실행 시 빠진 것만 다시 시도됩니다 (idempotent).

## 단계 5: 인터랙티브 인증 안내

이번 setup에서 `notebooklm-py`가 새로 설치되었다면, 마지막에 다음 메시지를 출력:

> notebooklm 인증이 필요합니다. 다음 명령을 직접 실행해주세요 (브라우저에서 Google 로그인이 열립니다):
>
> ```
> ! notebooklm login
> ```

(자동 실행 금지 — 인터랙티브 브라우저 로그인이라 자동화 불가)

## 단계 6: 글로벌 CLAUDE.md에 스킬 매핑 추가

글로벌 CLAUDE.md(`~/.claude/CLAUDE.md`)에 rakis 스킬 매핑이 이미 있는지 확인:

```bash
grep -q "rakis:wiki-query" ~/.claude/CLAUDE.md 2>/dev/null
```

- **이미 있으면** → "글로벌 CLAUDE.md에 스킬 매핑이 이미 있습니다." 출력하고 다음 단계로
- **없으면** → 사용자에게 다음과 같이 묻기:

> 글로벌 CLAUDE.md에 rakis 스킬 매핑을 추가할까요?
> 추가하면 모든 프로젝트에서 위키 검색, 소스 분석 등이 자연스럽게 작동합니다.
> [y] 추가 / [n] 건너뛰기

**[y] 동의 시**, `~/.claude/CLAUDE.md`를 Read 도구로 읽은 뒤 Edit 도구로 다음 섹션을 추가한다. 파일에 이미 `## Obsidian LLM Wiki` 섹션이 있으면 그 섹션을 교체하고, 없으면 파일 끝에 추가:

```markdown
## Obsidian LLM Wiki

- **플러그인**: `rakis@raki-claude-plugins`
- **Vault 경로**: `~/Library/Mobile Documents/com~apple~CloudDocs/Documents/Vault`
- **구조**: Karpathy 3-Layer (raw/ → wiki/ → schema)

### 스킬 사용 (필수)

위키 관련 작업은 항상 rakis 플러그인 스킬을 사용한다. 직접 파일 조작은 스킬이 로드되지 않은 환경에서만.

| 상황 | 스킬 |
|------|------|
| 이전에 조사/저장한 내용 검색·질문 | `rakis:wiki-query` |
| URL·파일·repo 분석 | `rakis:source-analyze` |
| 새 지식을 위키에 저장 | `rakis:wiki-ingest` |
| 세션 마무리 시 학습 기록 | `rakis:wiki-wrap-up` |
| 위키 건강 점검 (주 1회) | `rakis:wiki-lint` |
| 프로젝트 코드 구조 분석 | `rakis:project-graph` |
| 플러그인 의존성 설치 (최초 1회) | `rakis:setup` |

### Wrap-up → Wiki 규칙
작업 완료 시 (커밋, PR, 큰 태스크 마무리) 다음을 확인:
- 이 세션에서 **새로 알게 된 것** (도구, 패턴, 트러블슈팅)이 있는가?
- 위키에 아직 없는 내용인가?

해당되면 사용자에게 제안: "위키에 저장할까요? — {한 줄 요약}"
승인 시 wiki-ingest 스킬로 저장.
```

**[n] 거부 시** → 건너뛰기 (마커 생성에 영향 없음).

## 단계 7: 마커 생성

모든 필수 단계가 완료되었거나 사용자가 [s] 건너뛰기를 선택한 경우:

```bash
mkdir -p "${CLAUDE_PLUGIN_DATA}"
touch "${CLAUDE_PLUGIN_DATA}/.setup-done"
```

## 단계 8: 결과 요약

다음 형식으로 사용자에게 요약 출력:

```
=== rakis:setup 완료 ===

새로 설치됨:
  ✓ notebooklm-py
  ✓ gh
  ✓ graphify

이미 있던 것:
  ✓ uv
  ✓ node

다음에 할 일:
  ! notebooklm login
```

빠진 항목이 있다면 별도 표시. 마커 생성 여부도 명시.

## Idempotent 보장

`/rakis:setup`은 언제 다시 실행해도 안전합니다:
- 마커가 있어도 점검을 다시 수행. 모두 ✓이면 "이미 setup 완료" 출력 후 즉시 종료.
- 일부만 설치된 부분 상태 → 단계 2부터 다시 실행. 빠진 게 있으면 단계 3의 `[a]/[c]/[s]` 프롬프트가 다시 출현하고, 사용자 선택에 따라 빠진 것만 설치합니다.
