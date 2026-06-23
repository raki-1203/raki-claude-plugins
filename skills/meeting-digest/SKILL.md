---
name: meeting-digest
description: 회의 녹음 파일을 받아 mlx-whisper로 전사하고 구조화된 회의록(안건/논의/결정/액션/이슈)으로 정리해서 Obsidian vault의 프로젝트별 폴더에 저장. '회의록 정리', '녹음 정리해줘'라고 할 때 사용.
version: 1.2.0
license: MIT
---

# meeting-digest — 회의 녹음 → 구조화된 회의록

오디오 파일(mp3/m4a/wav/mp4 등)을 받아 한국어 전사 후 LLM으로 구조화된 회의록을 만들어 vault에 저장한다.

## 호출

```
/rakis:meeting-digest <audio-path> [--project <name>] [--title "회의명"] [옵션]
```

**필수 인자**
- `<audio-path>`: 오디오/비디오 파일 경로 (mp3, m4a, wav, flac, ogg, mp4, mov 등)

**선택 인자** (생략 시 인터랙티브 질문/자동 추정으로 보완)
- `--project <name>`: 프로젝트명. 생략 시 vault의 기존 프로젝트 목록 보여주고 선택/신규 입력 받음
- `--title "회의명"`: 회의 제목. 생략 시 파일명에서 추정 (의미없으면 사용자에게 확인)
- `--date YYYY-MM-DD`: 회의 날짜. 기본값 = 오디오 파일의 mtime (없으면 오늘)
- `--model <name>`: Whisper 모델. 기본 `large-v3` (Apple MLX). 보통 변경 불필요
- `--attendees "이름1,이름2"`: 참석자 목록 (frontmatter에 기록)

## Vault 경로 검증

`OBSIDIAN_VAULT_PATH` 환경변수가 **반드시** 설정돼야 한다. 없으면:

```
❌ OBSIDIAN_VAULT_PATH 환경변수가 설정되지 않았습니다.

~/.zshrc 또는 ~/.bashrc 에 아래 줄을 추가하세요:
  export OBSIDIAN_VAULT_PATH="$HOME/path/to/your/Vault"
```

이후 vault 경로 존재 + `CLAUDE.md` 에 "Three-Layer" 또는 "raw/" 언급 검증. 실패 시 중단.

## Phase 0: 인자 검증 + 의존성 체크

1. `<audio-path>` 존재 확인. 없으면 에러 후 중단.
2. 의존성 체크 (`command -v mlx_whisper`). 없으면:
   ```
   ❌ mlx_whisper 미설치. /rakis:setup 실행 후 다시 시도하세요.
   ```
   중단.
3. `ffmpeg` 체크. 없으면 경고만 출력하고 진행 (대부분 포맷은 mlx_whisper 내부에서 처리되지만, mp4/mov 등은 ffmpeg 필요할 수 있음).

### Phase 0-A: `--project` 인터랙티브 보완

`--project` 인자가 없으면 vault에서 기존 프로젝트를 스캔해서 보여주고 선택받는다.

```bash
# wiki/projects/*.md 와 raw/meetings/*/ 둘 다 스캔 (합집합)
PROJECTS=$(
  {
    ls "$VAULT/wiki/projects/" 2>/dev/null | sed 's/\.md$//'
    ls "$VAULT/raw/meetings/" 2>/dev/null
  } | sort -u
)
```

출력 예:
```
어느 프로젝트인가요?

기존 프로젝트:
  [1] openclaw
  [2] kgenlm
  [3] viva-republica
  [n] 새 프로젝트 입력
  [c] 취소

선택:
```

- 번호 → 해당 프로젝트로 진행
- `n` → "프로젝트명을 입력하세요:" 받음. 빈 입력이면 재질문
- `c` → 중단
- 기존 프로젝트 0개면 바로 "프로젝트명을 입력하세요:" 한 줄 질문

### Phase 0-B: `--title` 자동 추정

`--title` 인자가 없으면 파일명(확장자 제외)에서 추정한다.

**의미있는 파일명 판별**:
- 길이 ≥ 5
- 영문/한글 글자가 ≥ 3개 (숫자·기호 제외)
- 다음 패턴이면 "의미없음"으로 판단 (대소문자 무시):
  - `recording`, `audio`, `voice`, `note`, `memo`, `meeting`, `untitled`, `new`, `temp`
  - `IMG`, `VID`, `MOV`, `REC`
  - 순수 숫자/날짜 (`20260512`, `0512-1430`)
  - `Zoom_xxx`, `GoogleMeet_xxx`, `Teams_xxx` 등 도구명 prefix

**의미있다면** → 그대로 title로 사용
**의미없다면** → 사용자에게 한 줄 질문:
```
회의 제목을 입력하세요 (파일명 '<원본>'에서 자동 추정 실패):
```
빈 입력 시 파일명을 그대로 쓰고 진행 (사용자가 그래도 진행하겠다는 신호).

## Phase 1: slug + 경로 준비

### 날짜 결정
```bash
if [--date 인자 있음]: 그대로 사용
elif [오디오 파일의 mtime 있음]: YYYY-MM-DD 추출
else: 오늘 날짜
```

### slug 정규화 (한글 보존)
회의 제목이 한글일 가능성이 높으므로 ASCII 강제 변환 X.

규칙:
- `--title` 인자가 있으면 그 값 / 없으면 audio 파일명(확장자 제외)
- 공백·`/`·`\`·`:`·`*`·`?`·`"`·`<`·`>`·`|` → `-`
- 연속 `-` 축약
- 앞뒤 `-` 제거
- 60자 제한
- 결과가 빈 문자열이면 사용자에게 `--title` 직접 입력 요청

### 프로젝트 slug
`--project` 값도 동일한 규칙으로 정규화. 한글 보존.

### 경로 구성
```
RAW_DIR="$VAULT/raw/meetings/$PROJECT/$DATE-$SLUG"
WIKI_PATH="$VAULT/wiki/meetings/$PROJECT/$DATE-$SLUG.md"
```

**중복 체크**: `$WIKI_PATH` 이미 존재 시 사용자에게 질문:
```
이미 존재합니다: wiki/meetings/{project}/{date}-{slug}.md
[o] 덮어쓰기  [s] 다른 slug 사용  [c] 취소
```

`raw/meetings/$PROJECT/` 폴더가 처음 생성되는 경우 → 안내 한 줄 출력 (`✓ 새 프로젝트 폴더 생성: meetings/{project}/`).

## Phase 2: 원본 오디오 raw/에 복사

```bash
mkdir -p "$RAW_DIR"
cp "$AUDIO" "$RAW_DIR/audio.$EXT"
```

`meta.json` 작성:
```json
{
  "project": "<project>",
  "title": "<title or slug>",
  "date": "YYYY-MM-DD",
  "slug": "<slug>",
  "source_file": "audio.<ext>",
  "audio_size_bytes": 0,
  "audio_duration_sec": null,
  "captured_at": "<ISO 8601>",
  "model": "<whisper model>",
  "attendees": ["..."]
}
```

(duration은 ffprobe 사용 가능 시 채우고, 없으면 null)

## Phase 3: 전사 실행

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/meeting-digest/scripts/transcribe.sh" \
  --audio "$RAW_DIR/audio.$EXT" \
  --out-dir "$RAW_DIR" \
  --model "$MODEL" \
  --lang ko
```

산출물:
- `$RAW_DIR/transcript.txt` — 본문
- `$RAW_DIR/transcript.json` — 타임스탬프 포함 segments
- `$RAW_DIR/transcript.srt` — 자막 (필요 시 검토용)

exit code 처리:
- `2` → 의존성 안내 후 중단
- `3` → 오디오 파일 문제
- `4` → 전사 실패 안내 후 raw/ 정리 여부 사용자에게 질문

전사가 길어질 수 있음을 사전 안내:
> ⏳ 전사 중... (Apple Silicon 기준 대략 오디오 길이의 0.1배 내외 소요)

## Phase 4: 구조화된 회의록 생성

`transcript.txt` 를 읽어 다음 구조로 마크다운 생성. **transcript.json의 타임스탬프**를 활용하면 발언 시점 인용 가능.

**읽기 방식 (디테일 누락 방지)**: 전사가 길면(대략 4000단어 / 250줄 초과) 통째로 한 번에 요약하지 말 것. 처음부터 끝까지 순차적으로 읽으며 논의 단위마다 구체 디테일(수치·스펙·조건·발언자·제안)을 메모로 쌓은 뒤, 그 메모를 바탕으로 아래 구조를 채운다. 후반부를 스킵하면 회의 막판의 결정·액션이 통째로 누락되므로 끝까지 읽는다.

### 회의록 본문 형식

````markdown
---
title: "<회의 제목>"
type: meeting
description: "<한 줄 요약 — 회의의 핵심 결정/주제>"
project: <project>
date: YYYY-MM-DD
duration_min: <분 단위, 없으면 생략>
attendees: [<참석자 목록>]
tags: [meeting, <project>]
raw: "raw/meetings/<project>/<date>-<slug>/"
related: []
---

# <회의 제목>

> **프로젝트**: [[projects/<project>]]
> **일자**: YYYY-MM-DD
> **참석**: <attendees joined by comma>

## TL;DR
<3~5줄 핵심 요약. 무엇을 논의했고 무엇이 결정됐는지>

## 안건
- <안건 1>
- <안건 2>

## 주요 논의
### <소주제 1>
<논의 내용. 누가 무슨 입장이었는지 문맥상 파악되면 명시. 고도 요약하지 말고 아래 디테일을 bullet로 풀어쓴다.>
- 구체 수치·스펙·조건: <금액/날짜/수량/기술 스펙/"단 ~인 경우" 같은 단서를 그대로>
- 제안·반대·대안: <누가 무엇을 제안했고 어떤 반대/보류 대안이 나왔는지>
> "발언 인용" — (mm:ss)

### <소주제 2>
...

## 요구사항·스펙
<!-- 이 회의에서 요구사항/스펙/제약이 다뤄졌을 때만 작성. 없으면 섹션 생략. -->
- <항목>: <구체 명세 — 수치·형식·조건을 전사 그대로. 뭉뚱그리지 말 것>
- ...

## 결정사항
- [<결정 1>] — 근거: <왜>
- [<결정 2>] — 근거: <왜>

## 액션 아이템
- [ ] <담당자가 문맥상 명확하면 명시, 아니면 "미정"> · <할 일 — 구체 산출물/범위/조건까지. "정리하기"가 아니라 "X를 Y 형식으로 정리"> · 기한: <있으면>
- [ ] ...

## 미해결 이슈
- <다음 회의로 미뤄진 사항>
- <추가 조사 필요한 부분>

## 원본
- 오디오: `raw/meetings/<project>/<date>-<slug>/audio.<ext>`
- 전사: `raw/meetings/<project>/<date>-<slug>/transcript.txt`
````

### 작성 규칙
0. **frontmatter**: `title`은 회의 제목(본문 H1과 동일), `type`은 항상 `meeting` 고정. vault frontmatter 검증(title/type 필수)을 위해 누락 금지.
1. **사실만 추출**: 전사문에 없는 내용 추가 금지. 추론은 명시("문맥상 ~로 보임").
2. **디테일 보존 우선**: 구체 수치·금액·날짜·수량·기술 스펙·고유명사·조건/예외("단 ~인 경우")는 요약 때문에 떨어뜨리지 말고 전사 그대로 보존한다. "여러 안을 논의함"처럼 뭉개지 말고 어떤 안들이었는지 나열. 짧게 만드는 것보다 빠짐없는 게 우선이다 (TL;DR만 짧게).
3. **부차 논의·맥락**: 메인 주제가 아니어도 결정에 영향 준 배경, 반대 의견, 보류된 대안은 해당 소주제 bullet로 남긴다. "곁가지라 생략"하지 말 것.
4. **액션 아이템**: 발화 문맥에서 "내가 할게요", "그건 X님이" 같은 단서로 담당자 추출. 불명확하면 "미정". 할 일은 구체 산출물/범위/조건까지 적는다.
5. **결정사항**: 합의된 것만. 논의만 되고 결정 안 된 건 "미해결 이슈"로.
6. **TL;DR**: 회의 안 본 사람도 핵심을 알 수 있게.
7. 전사 품질이 낮은 구간(반복/잡음)은 무시. 의미 없는 자동 자막 산출물(예: 같은 단어 반복)은 노이즈로 판단.

### 누락 점검 (작성 후 필수)
회의록 초안을 만든 뒤 transcript를 한 번 더 빠르게 훑어, 전사에 나왔지만 회의록에서 빠진 **구체 수치·요구사항·조건·액션**이 없는지 확인하고 누락분을 채운다. 이 점검을 건너뛰지 않는다.

## Phase 5: vault 저장

1. `mkdir -p "$VAULT/wiki/meetings/$PROJECT"`
2. 회의록을 `$WIKI_PATH`에 저장
3. **프로젝트 페이지 링크 추가** (`wiki/projects/$PROJECT.md` 존재 시):
   - 파일에 `## Meetings` 섹션이 없으면 파일 끝에 추가
   - 있으면 그 섹션 맨 위에 다음 한 줄 추가:
     ```
     - [[meetings/<project>/<date>-<slug>|<date> <title>]]
     ```
4. `log.md`에 한 줄 추가 (파일 끝):
   ```
   ## [YYYY-MM-DD] <project> | 회의록: <title>
   ```
5. `index.md` 의 회의록 섹션이 있으면 카운트 갱신. 없으면 생성하지 않음 (lint 단계에서 처리).

## Phase 6: 결과 출력

```
=== 회의록 생성 완료 ===

프로젝트: <project>
회의명:   <title>
일자:     <date>

원본 (raw):
  raw/meetings/<project>/<date>-<slug>/
    ├ audio.<ext>     (<size>)
    ├ transcript.txt  (<word count> 단어)
    ├ transcript.json
    └ transcript.srt

회의록 (wiki):
  wiki/meetings/<project>/<date>-<slug>.md

프로젝트 페이지 업데이트: <wiki/projects/<project>.md 에 링크 추가 / 페이지 없음>
```

마지막 한 줄로 vault 절대 경로의 회의록 파일 출력 (Obsidian에서 바로 열 수 있도록):
> 열기: `$VAULT/wiki/meetings/<project>/<date>-<slug>.md`

## 에러 처리 요약

| 실패 지점 | 대응 |
|-----------|------|
| `OBSIDIAN_VAULT_PATH` 미설정 | 안내 후 중단 |
| `--project` 누락 | 사용 예시 출력 후 중단 |
| 오디오 파일 없음 | 경로 확인 요청 |
| mlx_whisper 미설치 | `/rakis:setup` 안내 |
| 전사 실패 (exit 4) | raw/ 보존 여부 사용자에게 묻고 중단 |
| slug 빈 결과 | `--title` 명시 요청 |
| 중복 wiki 파일 | overwrite/rename/cancel 질문 |

## 트리거

- `/rakis:meeting-digest <파일> --project <name>` 명시 실행
- "이 회의 녹음 정리해줘"
- "{프로젝트} 회의록 만들어줘"
- 사용자가 오디오 파일 경로를 던지며 "정리해줘"라고 할 때 → `--project` 가 명시 안 됐으면 사용자에게 프로젝트명 질문 후 실행
