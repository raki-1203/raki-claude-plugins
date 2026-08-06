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

**설치 여부와 함께 현재 버전도 기록하세요** — 단계 2.5의 업그레이드 전후를 비교해 보고하려면 필요합니다.

```bash
notebooklm --version 2>/dev/null | tail -1
uv tool list 2>/dev/null | grep -E "notebooklm-py|mlx-whisper"
```

| 도구 | 체크 명령 | 설치 명령 |
|------|----------|----------|
| `notebooklm-py` | `command -v notebooklm` | `uv tool install --upgrade --python 3.12 notebooklm-py --with playwright` |
| `node` | `command -v node` | `brew upgrade node 2>/dev/null \|\| brew install node` |
| `gh` | `command -v gh` | `brew upgrade gh 2>/dev/null \|\| brew install gh` |
| `jq` | `command -v jq` | `brew upgrade jq 2>/dev/null \|\| brew install jq` |
| `yq` | `command -v yq` | `brew upgrade yq 2>/dev/null \|\| brew install yq` |
| `mlx-whisper` | `command -v mlx_whisper` | `uv tool install --upgrade mlx-whisper` |
| `ffmpeg` | `command -v ffmpeg` | `brew upgrade ffmpeg 2>/dev/null \|\| brew install ffmpeg` |

> **notebooklm-py의 `--python 3.12` 핀 고정 (제거하지 말 것)**: Python 3.13은 `ssl.create_default_context()`에 `VERIFY_X509_STRICT`를 기본으로 켠다. 사내망(KT 등)이 TLS를 가로채는 환경에서 기업 CA 인증서가 RFC 5280의 SKI/AKI 확장을 갖추지 않은 경우가 많아, 3.13에서는 CA를 신뢰시켜도 `Missing Authority Key Identifier`로 전부 거부된다. 3.12는 이 검사가 없어 정상 동작한다. 사내망 CA 번들 설정은 `source-fetch/references/enrich.md` 참조.
>
> **mlx-whisper**: Apple MLX 기반 Whisper CLI. `meeting-digest` 스킬이 회의 녹음 전사에 사용 (Apple Silicon 네이티브, faster-whisper 대비 ~11배 빠름). 첫 실행 시 large-v3 모델 ~3GB가 HuggingFace에서 자동 다운로드됨.
> **ffmpeg**: 오디오/비디오 포맷 변환. mp4/mov 등 비디오 파일에서 오디오 추출 시 필요.

결과를 다음 형식으로 출력하세요:

```
[필수]
  uv                    ✓
  notebooklm-py         ✓ (v1.2.3 → 최신 확인)
  node                  ✓
  gh                    ✓
  jq                    ✓
  yq                    ✓
  mlx-whisper           ✗   uv tool install --upgrade mlx-whisper
  ffmpeg                ✗   brew install ffmpeg
```

모든 항목이 ✓여도 **단계 2.5는 반드시 실행**하세요. 그 다음 단계 3을 건너뛰고 단계 6으로 갑니다.

## 단계 2.5: uv tool 업그레이드 (항상 실행)

**빠진 게 없어도 실행합니다.** 설치 여부만 보고 넘어가면 도구가 낡은 채로 방치되기 때문입니다.

```bash
uv tool upgrade --all
```

한 줄로 `notebooklm-py`·`mlx-whisper`를 모두 최신으로 올립니다. 이미 최신이면 아무것도 하지 않으므로 재실행이 안전합니다.

업그레이드 후 버전을 다시 읽어 단계 9 요약에 `0.3.4 → 0.7.3` 형태로 표기하세요. 변화가 없으면 버전만 적습니다.

> **brew 패키지(node·gh·jq·yq·ffmpeg)는 대상이 아닙니다.** 매번 `brew upgrade`를 돌리면 setup이 몇 분씩 걸립니다. 이들은 누락됐을 때만 설치하고, 갱신은 사용자의 평소 `brew upgrade`에 맡깁니다.

> **왜 이 단계가 있는가** (2026-07-31 추가): `command -v`는 존재만 확인하고 버전을 보지 않습니다. `notebooklm-py` 0.3.4가 설치돼 있던 환경에서 Google이 NotebookLM 도메인을 옮겼는데, setup은 "✓ 설치됨"으로 통과시켜 4개 마이너 버전(0.3.4 → 0.7.3) 뒤처진 채 인증이 조용히 깨져 있었다. 존재 확인과 최신 확인은 다른 문제다.

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

## 단계 6: NotebookLM 출력 언어 확인

`notebooklm`이 설치되어 있을 때만 실행. 미설치면 이 단계 전체 건너뜀.

```bash
command -v notebooklm >/dev/null || { echo "notebooklm 미설치 — 언어 설정 건너뜀"; }
```

설치되어 있으면 인증 상태 먼저 확인:

```bash
notebooklm auth check --test 2>&1 | grep -q "Authentication is valid"
```

- **실패** → 다음 안내만 출력하고 이 단계 종료 (마커 생성에는 영향 없음):
  > notebooklm 인증이 필요합니다. `! notebooklm login` 실행 후 `/rakis:setup`을 다시 돌리면 언어 설정까지 완료됩니다.

- **성공** → 현재 언어 확인:

```bash
notebooklm language get
```

출력 파싱:
- `Language: ko` 포함 → "NotebookLM 출력 언어: ko (한국어) ✓" 출력 후 통과
- 그 외 (`not set`, `en`, 기타) → 사용자에게 다음과 같이 묻고 대기:

```
NotebookLM 출력 언어가 현재 '<감지된 값>' 입니다.
mindmap/briefing/study-guide가 이 언어로 생성됩니다.

[y] 한국어(ko)로 설정
[o] 다른 언어 코드 직접 입력
[n] 그대로 두기 (건너뛰기)
```

- **[y]** → `notebooklm language set ko` 실행 후 결과 한 줄 출력
- **[o]** → 언어 코드 받아서 `notebooklm language set <code>` 실행. 실패 시 `notebooklm language list`로 유효 코드 확인 안내
- **[n]** → 건너뛰기

> **주의**: `language`는 NotebookLM 계정의 GLOBAL 설정이라 모든 노트북에 적용됨. 여기서 한 번 `ko`로 맞춰두면 이후 source-fetch enrich 산출물이 한국어로 생성됨.

## 단계 6.5: 화자 분리(diarization) venv — 선택

`meeting-digest`의 화자 분리(누가 말했는지 라벨링)에 쓰이는 격리 venv. **선택 사항**이며
senko(Apple 네이티브 CoreML)를 쓴다. HF 토큰·약관 동의 불필요. **사용자에게 물어본 뒤** 진행.

먼저 이미 있는지 확인:

```bash
DIA_VENV="$HOME/.local/share/rakis/diarize-venv"
[ -x "$DIA_VENV/bin/python" ] && "$DIA_VENV/bin/python" -c "import senko" 2>/dev/null \
  && echo "화자 분리 venv 준비됨 ✓" || echo "화자 분리 venv 없음"
```

- **이미 준비됨** → "화자 분리: 준비됨 ✓" 출력하고 단계 7로
- **없으면** → 사용자에게 묻고 대기:

```
회의록 화자 분리(누가 말했는지)를 설정할까요?
  - 격리 venv 생성 + senko 설치 (Apple 네이티브 CoreML, 모델 ~수십 MB)
  - HF 토큰·약관 동의 불필요
설정 안 해도 회의록은 정상 생성됩니다(화자 라벨만 없음).

[y] 설정  [n] 건너뛰기
```

- **[n]** → 건너뛰기 (마커 생성에 영향 없음)
- **[y]** → 아래 실행:

```bash
DIA_VENV="$HOME/.local/share/rakis/diarize-venv"
uv venv --python 3.13 "$DIA_VENV"
uv pip install --python "$DIA_VENV/bin/python" senko
"$DIA_VENV/bin/python" -c "import senko; print('senko OK')"
```

설치 성공 후 안내:

> 화자 분리 준비 완료. 이후 `/rakis:meeting-digest`가 자동으로 화자 분리를 수행합니다.
> (첫 실행 시 senko 모델 ~수십 MB 다운로드, 이후 캐시)

> **주의**: Python 3.13으로 격리하는 이유 — mlx_whisper 시스템 환경(3.14)과 분리해 충돌 방지.
> Mac에서 senko는 CoreML로 동작하므로 torch/PyTorch·HF 토큰이 필요 없다.

## 단계 7: 글로벌 CLAUDE.md에 스킬 매핑 추가

글로벌 CLAUDE.md(`~/.claude/CLAUDE.md`)에 rakis 스킬 매핑이 이미 있는지 확인:

```bash
grep -q "rakis:wiki-query" ~/.claude/CLAUDE.md 2>/dev/null
```

- **이미 있으면** → "글로벌 CLAUDE.md에 스킬 매핑이 이미 있습니다." 출력하고 다음 단계로
- **없으면** → 사용자에게 다음과 같이 묻기:

> 글로벌 CLAUDE.md에 rakis 스킬 매핑을 추가할까요?
> 추가하면 모든 프로젝트에서 위키 검색, 소스 분석 등이 자연스럽게 작동합니다.
> [y] 추가 / [n] 건너뛰기

**[y] 동의 시**, `commands/skill-mapping.md` 파일의 `---` 구분선 아래 내용(`## Obsidian LLM Wiki` 이하 전체)을 읽어서 `~/.claude/CLAUDE.md`에 추가한다. 파일에 이미 `## Obsidian LLM Wiki` 섹션이 있으면 그 섹션을 교체하고, 없으면 파일 끝에 추가.

> **참조**: 추가할 내용의 원본은 이 명령과 같은 디렉토리의 `skill-mapping.md`에 있다. 인라인으로 하드코딩하지 말고 해당 파일을 읽어서 사용할 것.

**[n] 거부 시** → 건너뛰기 (마커 생성에 영향 없음).

## 단계 8: 마커 생성

모든 필수 단계가 완료되었거나 사용자가 [s] 건너뛰기를 선택한 경우:

```bash
mkdir -p "${CLAUDE_PLUGIN_DATA}"
touch "${CLAUDE_PLUGIN_DATA}/.setup-done"
```

## 단계 9: 결과 요약

다음 형식으로 사용자에게 요약 출력:

```
=== rakis:setup 완료 ===

새로 설치됨:
  ✓ gh

업그레이드됨:
  ↑ notebooklm-py   0.3.4 → 0.7.3

이미 최신:
  ✓ uv
  ✓ mlx-whisper     0.4.3
  ✓ node

다음에 할 일:
  ! notebooklm login
```

`업그레이드됨` 항목이 있으면 **버전이 올라간 도구는 동작이 바뀌었을 수 있다**고 한 줄 덧붙이세요 — 특히 `notebooklm-py`는 CLI 출력 형식이 마이너 버전 사이에 바뀐 전례가 있습니다(0.7.3에서 `create` 출력에 `Tip:` 줄 추가).

빠진 항목이 있다면 별도 표시. 마커 생성 여부도 명시. NotebookLM 언어 설정 결과도 포함 (예: `NotebookLM 언어: ko ✓` 또는 `NotebookLM 언어: 건너뜀 (인증 필요)`).

## 단계 10: v2 구조 감지 (Vault 이동 전 체크)

Vault 경로가 탐지되면, v2 잔재 확인:

```bash
LEGACY_COUNT=$(find "$VAULT/raw" -maxdepth 3 \( -name "graph-report.md" -o -name "analysis.md" \) -type f 2>/dev/null | wc -l | tr -d ' ')
HAS_MARKER=$( [ -f "$VAULT/.rakis-v3-migrated" ] && echo 1 || echo 0 )

if [ "$LEGACY_COUNT" -gt 0 ] && [ "$HAS_MARKER" = "0" ]; then
  cat <<EOS
⚠️  v2 구조가 감지되었습니다 (legacy 파일 $LEGACY_COUNT개).

v3 스킬을 사용하기 전에 먼저 마이그레이션을 실행하세요:

  /rakis:migrate-v3 --dry-run   # 영향 확인
  /rakis:migrate-v3             # 실제 실행

이 단계 없이 v3 스킬을 돌리면 wiki/와 raw/가 불일치 상태가 됩니다.
EOS
  exit 1
fi
```

## Idempotent 보장

`/rakis:setup`은 언제 다시 실행해도 안전합니다:
- 마커가 있어도 점검을 다시 수행. 모두 ✓이면 "이미 setup 완료" 출력 후 즉시 종료.
- 일부만 설치된 부분 상태 → 단계 2부터 다시 실행. 빠진 게 있으면 단계 3의 `[a]/[c]/[s]` 프롬프트가 다시 출현하고, 사용자 선택에 따라 빠진 것만 설치합니다.
