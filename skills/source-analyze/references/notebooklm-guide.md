# NotebookLM 연동 가이드

notebooklm-py CLI를 사용하여 NotebookLM과 프로그래밍 방식으로 연동한다.

## 사전 조건 확인

스킬 실행 시 가장 먼저 notebooklm-py 설치 여부와 인증 상태를 확인한다.

### 설치 확인

```bash
command -v notebooklm || pip install notebooklm-py
```

### 인증 확인

```bash
notebooklm auth check --test
```

실패 시 사용자에게 안내:
> "NotebookLM 인증이 필요합니다. `! notebooklm login` 을 실행하여 Google 계정으로 로그인해주세요."

인증이 불가능한 환경이면 fallback(Claude 직접 분석)으로 전환한다.

## 노트북 생성

```bash
notebooklm create "{owner}/{repo} 분석"
```

출력에서 노트북 ID를 파싱하여 이후 단계에 전달한다.

## 소스 업로드

repomix 출력 파일을 소스로 추가:

```bash
notebooklm use {notebook_id}
notebooklm source add "/tmp/repomix-{repo}.txt"
```

GitHub repo URL도 추가 소스로 등록:

```bash
notebooklm source add "https://github.com/{owner}/{repo}"
```

### 대용량 파일 처리 (필수)

repomix 출력이 클 때 업로드 실패를 방지하는 단계적 대응:

**1단계: 크기 확인**
```bash
wc -c /tmp/repomix-{repo}.txt
```

**2단계: 크기별 대응**

| 크기 | 대응 |
|------|------|
| < 2MB | 그대로 업로드 |
| 2~10MB | compress 시도 → 여전히 > 2MB면 분할 |
| > 10MB | 바로 분할 |

**3단계: compress 시도**
```bash
npx repomix --remote {owner}/{repo} --compress --output /tmp/repomix-{repo}-compressed.txt
```

**4단계: 파일 분할 업로드** (compress 후에도 > 2MB일 때)

repomix 출력은 파일마다 `====` 구분선이 있다. **반드시 이 구분선을 경계로 분할**해야 한다. `split -b` 같은 바이트 기준 분할은 UTF-8 멀티바이트 문자 중간이나 repomix 토큰 중간에서 잘려 업로드 시 400 Bad Request를 유발한다(특히 한글·중국어 등 비ASCII 포함 repo).

**권장: `====` 구분선 기준 Python 분할 (primary)**

```bash
uv run python3 - <<'PY' /tmp/repomix-{repo}.txt /tmp/repomix-{repo}-part-
import pathlib, sys

src = pathlib.Path(sys.argv[1])
prefix = sys.argv[2]
ext = src.suffix or ".txt"          # .txt (repomix 기본) 또는 .xml
limit = 1_900_000                    # ~1.85MB (2MB 경계 여유)

parts, buf, size = [], [], 0
for line in src.read_text(encoding="utf-8").splitlines(keepends=True):
    # 새 파일 경계이고 현재 파트가 충분히 크면 flush
    if line.startswith("====") and size > limit and buf:
        parts.append("".join(buf))
        buf, size = [], 0
    buf.append(line)
    size += len(line.encode("utf-8"))
if buf:
    parts.append("".join(buf))

for i, part in enumerate(parts):
    out = pathlib.Path(f"{prefix}{i+1:02d}-of-{len(parts):02d}{ext}")
    out.write_text(part, encoding="utf-8")
    print(out)
PY
```

생성 예: `/tmp/repomix-{repo}-part-01-of-05.txt` ~ `-05-of-05.txt`

**각 파트 업로드**:
```bash
for f in /tmp/repomix-{repo}-part-*.txt; do
  notebooklm source add "$f" --title "{repo} $(basename "$f" .txt)"
done
```

**fallback (Python 실행 환경이 없을 때만)**:
```bash
# split -b 는 UTF-8 중간 잘림 위험. 비ASCII 포함 repo에는 쓰지 말 것.
SRC=/tmp/repomix-{repo}.txt
EXT="${SRC##*.}"
split -b 1900k "$SRC" "/tmp/repomix-{repo}-part-" --additional-suffix=".$EXT"
```

**주의**:
- **분할 파트 확장자는 원본(repomix 출력) 확장자를 그대로 유지.** 확장자가 없거나 바뀌면 NotebookLM이 MIME 판별에 실패해 400 Bad Request로 거절한다 (2026-04-14 실발생).
- **`====` 기준 분할이 primary, 바이트 기준 split은 fallback.** 바이트 분할은 UTF-8 멀티바이트 경계를 깰 수 있다.
- 경계값 2MB는 근접하면 거절될 수 있어 1900k(약 1.85MB)로 여유를 둔다.
- 원본 파일을 그대로 재업로드하는 것은 금지 — 더 큰 파일을 올리면 의미 없음.
- 분할 실패 시에만 Claude fallback으로 전환.

## 질의

노트북을 활성화한 상태에서 질문:

```bash
notebooklm use {notebook_id}
notebooklm ask "질문 내용"
```

답변은 stdout으로 출력된다. 각 질문의 답변을 수집하여 분석 문서에 포함한다.

## 콘텐츠 생성

### 리포트

```bash
notebooklm generate report --format study-guide --wait
notebooklm download report ./report.md
```

### 마인드맵

```bash
notebooklm generate mind-map
notebooklm download mind-map ./mindmap.json
```

### 오디오 (팟캐스트)

```bash
notebooklm generate audio "이 프로젝트의 핵심을 설명해줘" --format deep-dive --length default --wait
notebooklm download audio ./podcast.mp3
```

### 슬라이드

```bash
notebooklm generate slide-deck --format detailed --wait
notebooklm download slide-deck ./slides.pptx --format pptx
```

### 인포그래픽

```bash
notebooklm generate infographic --orientation landscape --wait
notebooklm download infographic ./infographic.png
```

## 리서치 (웹 검색)

```bash
notebooklm source add-research "{검색 주제}" --mode deep --import-all
```

- `--mode fast`: 빠른 검색 (기본)
- `--mode deep`: 깊은 검색
- `--import-all`: 발견된 소스를 자동으로 노트북에 추가

유사 프로젝트 비교 등에 활용.

## 대화 이력 저장

```bash
notebooklm history --save
```

## Fallback: Claude 직접 분석

NotebookLM 연동 실패 시 Claude가 직접 분석한다.

### 전환 조건

다음 중 하나라도 해당하면 fallback으로 전환:
1. `notebooklm auth check --test` 실패 + 사용자가 로그인 거부
2. 소스 업로드 2회 연속 실패
3. 노트북 생성 실패

### fallback 절차

1. repomix 출력 파일을 Read 도구로 직접 읽기
2. 공통 질문 + 맞춤 질문에 대해 Claude가 직접 답변 생성
3. 리포트/마인드맵 생성은 건너뜀 (NotebookLM 전용 기능)
4. 결과 문서에 "NotebookLM 미사용 — Claude 직접 분석" 표기
5. NotebookLM 노트북 ID 항목은 "미생성" 표기
