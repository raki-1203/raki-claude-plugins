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
case "$TYPE" in
  repo)   notebooklm source add "raw/repos/{slug}/repomix.txt" -n "$NB_ID" ;;
  paper)  notebooklm source add "raw/papers/{slug}/source.pdf"  -n "$NB_ID" ;;
  article)
    if [ -n "$URL" ]; then
      notebooklm source add "$URL" -n "$NB_ID"
    else
      notebooklm source add "raw/articles/{slug}/source.md" -n "$NB_ID"
    fi
    ;;
esac

# 3. 산출물 생성 + 다운로드 (generate → download 2단계)
#
#    - mind-map  → JSON 파일 (mindmap.json)
#    - briefing  → report --format briefing-doc → markdown
#    - study-guide → report --format study-guide → markdown
#
#    report 산출물은 노트북에 여러 개 존재할 수 있으므로 생성 직후 --latest 로 받는다.

notebooklm generate mind-map -n "$NB_ID"
notebooklm download mind-map -n "$NB_ID" "raw/{type}/{slug}/notebooklm/mindmap.json" --force

# --hint 로 전달된 도메인 힌트는 briefing/study-guide 에만 적용
# (mind-map CLI는 --append 미지원)
APPEND_ARGS=()
if [ -n "${DOMAIN_HINT:-}" ]; then
  APPEND_ARGS=(--append "$DOMAIN_HINT")
fi

notebooklm generate report --format briefing-doc --wait -n "$NB_ID" "${APPEND_ARGS[@]}"
notebooklm download report --latest -n "$NB_ID" "raw/{type}/{slug}/notebooklm/briefing.md" --force

notebooklm generate report --format study-guide --wait -n "$NB_ID" "${APPEND_ARGS[@]}"
notebooklm download report --latest -n "$NB_ID" "raw/{type}/{slug}/notebooklm/study-guide.md" --force

# 4. 노트북 삭제 (ID 추적 안 함)
notebooklm delete -n "$NB_ID" -y
```

> **언어 설정**: 출력 언어는 `notebooklm language set <code>` 로 계정 전체에 적용됨 (글로벌). `/rakis:setup` 단계 6 참조. 산출 호출마다 `--language` 플래그로 덮어쓰기도 가능.

## 대용량 소스 분할

repomix.txt가 2MB 초과 시 notebooklm이 400 에러. 분할 업로드:

```bash
split -b 1800k -a 2 -d "raw/repos/{slug}/repomix.txt" /tmp/{slug}-part-
for p in /tmp/{slug}-part-*; do
  notebooklm source add "$p" -n "$NB_ID"
done
rm /tmp/{slug}-part-*
```

## Mock 모드 (CI/테스트용)

`RAKIS_NOTEBOOKLM_MOCK=1` 환경변수가 설정되면 실제 CLI 호출 대신 스텁 파일 생성:

```bash
if [ "${RAKIS_NOTEBOOKLM_MOCK:-0}" = "1" ]; then
  mkdir -p "raw/{type}/{slug}/notebooklm"
  echo '{"mock": "mindmap for {slug}"}' > "raw/{type}/{slug}/notebooklm/mindmap.json"
  echo "# Mock Briefing for {slug}" > "raw/{type}/{slug}/notebooklm/briefing.md"
  echo "# Mock Study Guide for {slug}" > "raw/{type}/{slug}/notebooklm/study-guide.md"
  exit 0
fi
```
