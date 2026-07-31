# enrich — NotebookLM 보조 산출물 생성

## 임계값 판정

```python
def should_enrich(meta, flag):
    if flag == "force":
        return True
    if flag == "no":
        return False
    t = meta["type"]
    if t in ("repo", "paper"):
        return True
    if t == "article" and meta["size_bytes"] >= 5000:
        return True
    return False
```

## 사전 조건

```bash
command -v notebooklm >/dev/null || { echo "notebooklm 미설치 — skip"; exit 0; }
notebooklm auth check --test 2>&1 | grep -q "Authentication is valid" || {
  echo "notebooklm 인증 만료 — skip"; exit 0;
}
```

둘 중 하나라도 실패하면 **에러 아님**, enrich만 건너뛴다.

## 실행 순서

> **CLI 규칙**: `notebooklm-py`는 `notebook` 네임스페이스가 없음. `create/delete/generate/download` 모두 **최상위 명령**. 노트북은 `-n <id>` 옵션 또는 `notebooklm use <id>` 컨텍스트로 지정.

```bash
# 1. 노트북 생성 — JSON 파싱으로 ID 추출
NB_ID=$(notebooklm create "{slug}" --json | jq -r '.notebook.id')

# 2. 소스 업로드 (유형별) — source add 는 파일 경로/URL 자동 감지
#    repo의 경우 1.9MB 초과 시 자동 분할 (notebooklm 2MB 한도 + 마진)
case "$TYPE" in
  repo)
    SRC="raw/repos/{slug}/repomix.txt"
    SIZE=$(stat -f%z "$SRC" 2>/dev/null || stat -c%s "$SRC")
    if [ "$SIZE" -gt 1900000 ]; then
      PREFIX="/tmp/{slug}-part-"
      split -b 1800k -a 2 -d "$SRC" "$PREFIX"
      for p in "$PREFIX"*; do
        # 확장자 없으면 NotebookLM이 "Unknown" 타입으로 인식 → .txt 부여
        mv "$p" "$p.txt"
        notebooklm source add "$p.txt" -n "$NB_ID"
      done
      rm "$PREFIX"*.txt
    else
      notebooklm source add "$SRC" -n "$NB_ID"
    fi
    ;;
  paper)  notebooklm source add "raw/papers/{slug}/source.pdf"  -n "$NB_ID" ;;
  article)
    if [ -n "$URL" ]; then
      notebooklm source add "$URL" -n "$NB_ID"
    else
      notebooklm source add "raw/articles/{slug}/source.md" -n "$NB_ID"
    fi
    ;;
esac

# 3. briefing 생성 + 다운로드 (generate → download 2단계)
#
#    report 산출물은 노트북에 여러 개 존재할 수 있으므로 생성 직후 --latest 로 받는다.

# --hint 로 전달된 도메인 힌트를 주입
APPEND_ARGS=()
if [ -n "${DOMAIN_HINT:-}" ]; then
  APPEND_ARGS=(--append "$DOMAIN_HINT")
fi

notebooklm generate report --format briefing-doc --wait -n "$NB_ID" "${APPEND_ARGS[@]}"
notebooklm download report --latest -n "$NB_ID" "raw/{type}/{slug}/notebooklm/briefing.md" --force

# 4. 노트북 삭제 (ID 추적 안 함)
notebooklm delete -n "$NB_ID" -y
```

> **왜 briefing만 만드는가** (2026-07-31, 실측 기반)
>
> 이전에는 briefing·study-guide·mindmap 3종을 만들었다. vault 실측 결과:
>
> | 산출물 | 생성 | 위키가 인용 | 판정 |
> |--------|-----:|-----------:|------|
> | briefing | 73 | 23 (32%) | **유지** |
> | study-guide | 73 | 21 (29%) | 제거 |
> | mindmap | 73 | 11 (15%) | 제거 |
>
> - **study-guide**: 분량의 35.6%가 퀴즈(18.8%)와 서술형 질문(16.8%)이다. 학습 장치지 위키 콘텐츠가 아니다. 나머지도 26.7%는 briefing과 중복이고, 고유하게 쓸모 있는 건 용어 사전 21.2%뿐이었다.
> - **mindmap**: 어휘의 41%가 briefing에 없어 정보 자체는 중복이 아니다. 그러나 인용률 15%로 워크플로에 읽는 단계가 없었다. 정보가 있어도 소비되지 않으면 비용만 남는다.
> - enrich 유무는 위키 페이지 품질을 가르지 못했다 (평균 3,210자 vs 3,113자). 결정 변수는 소스 밀도와 작성 노력이다. briefing을 남긴 건 "enrich가 품질을 올려서"가 아니라, 대용량 repo(수백만 토큰 repomix)에서 직접 읽어선 못 건질 사실을 뽑아주기 때문이다.

> **언어 설정**: 출력 언어는 `notebooklm language set <code>` 로 계정 전체에 적용됨 (글로벌). `/rakis:setup` 단계 6 참조. 산출 호출마다 `--language` 플래그로 덮어쓰기도 가능.

## 대용량 소스 분할 (자동)

repomix.txt가 2MB 초과 시 notebooklm이 400 에러를 반환한다. 위 "실행 순서 step 2"의 `repo` 분기에서 `stat`으로 사이즈를 확인해 1.9MB 초과 시 자동으로 1.8MB 단위 분할 업로드한다.

**주의 사항**:
- `split` 결과물은 확장자가 없어 NotebookLM이 "Unknown" 타입으로 인식 → 업로드 직전 `.txt`로 rename 필수
- macOS는 `stat -f%z`, Linux는 `stat -c%s` (위 스크립트는 둘 다 fallback 처리)
- 분할 업로드된 part는 노트북 안에서 별도 source로 표시되지만 NotebookLM이 통합 인덱싱한다

## Mock 모드 (CI/테스트용)

`RAKIS_NOTEBOOKLM_MOCK=1` 환경변수가 설정되면 실제 CLI 호출 대신 스텁 파일 생성:

```bash
if [ "${RAKIS_NOTEBOOKLM_MOCK:-0}" = "1" ]; then
  mkdir -p "raw/{type}/{slug}/notebooklm"
  echo "# Mock Briefing for {slug}" > "raw/{type}/{slug}/notebooklm/briefing.md"
  exit 0
fi
```
