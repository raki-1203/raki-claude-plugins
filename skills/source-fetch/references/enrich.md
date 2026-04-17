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

```bash
NB_ID=$(notebooklm notebook create --title "{slug}" --format id)

# 업로드 (유형별)
case "$TYPE" in
  repo)   notebooklm source add --file "raw/repos/{slug}/repomix.txt" "$NB_ID" ;;
  paper)  notebooklm source add --file "raw/papers/{slug}/source.pdf" "$NB_ID" ;;
  article)
    if [ -n "$URL" ]; then
      notebooklm source add --url "$URL" "$NB_ID"
    else
      notebooklm source add --file "raw/articles/{slug}/source.md" "$NB_ID"
    fi
    ;;
esac

# 생성 대기 (notebooklm --wait 플래그 사용)
notebooklm notebook mindmap "$NB_ID" --wait --output "raw/{type}/{slug}/notebooklm/mindmap.md"
notebooklm notebook briefing "$NB_ID" --wait --output "raw/{type}/{slug}/notebooklm/briefing.md"
notebooklm notebook study-guide "$NB_ID" --wait --output "raw/{type}/{slug}/notebooklm/study-guide.md"

# 노트북 삭제 (ID 추적 안 함)
notebooklm notebook delete "$NB_ID" --yes
```

## 대용량 소스 분할

repomix.txt가 2MB 초과 시 notebooklm이 400 에러. 분할 업로드:

```bash
split -b 1800k -a 2 -d "raw/repos/{slug}/repomix.txt" /tmp/{slug}-part-
for p in /tmp/{slug}-part-*; do
  notebooklm source add --file "$p" "$NB_ID"
done
rm /tmp/{slug}-part-*
```

## Mock 모드 (CI/테스트용)

`RAKIS_NOTEBOOKLM_MOCK=1` 환경변수가 설정되면 실제 CLI 호출 대신 스텁 파일 생성:

```bash
if [ "${RAKIS_NOTEBOOKLM_MOCK:-0}" = "1" ]; then
  mkdir -p "raw/{type}/{slug}/notebooklm"
  echo "# Mock Mindmap for {slug}" > "raw/{type}/{slug}/notebooklm/mindmap.md"
  echo "# Mock Briefing for {slug}" > "raw/{type}/{slug}/notebooklm/briefing.md"
  echo "# Mock Study Guide for {slug}" > "raw/{type}/{slug}/notebooklm/study-guide.md"
  exit 0
fi
```
