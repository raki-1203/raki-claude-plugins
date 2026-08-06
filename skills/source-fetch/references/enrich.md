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

# 사내망 TLS 가로채기 대응 — 번들이 있으면 이 스킬 실행 중에만 사용 (셸 전역 설정 아님)
[ -f "$HOME/.config/rakis/corp-ca-bundle.pem" ] && \
  export SSL_CERT_FILE="$HOME/.config/rakis/corp-ca-bundle.pem"

notebooklm auth check --test 2>&1 | grep -q "Authentication is valid" || {
  echo "notebooklm 인증 만료 — skip"; exit 0;
}
```

둘 중 하나라도 실패하면 **에러 아님**, enrich만 건너뛴다.

### 사내망(TLS 가로채기) 환경 설정 — 1회

KT 등 사내망은 TLS를 가로챈다. 리프 인증서 발급자가 `CN=Kt Corporate Forward Trust CA ECDSA`(subject는 `*.google.com`)면 이 경우다. `curl`은 macOS 키체인을 보므로 통과하지만 Python은 certifi 번들만 봐서 죽는다.

**두 가지가 모두 필요하다** — 하나만으로는 안 된다:

1. **CA 번들** — certifi + 사내 루트 CA를 합친 파일:
   ```bash
   mkdir -p ~/.config/rakis
   OUT=~/.config/rakis/corp-ca-bundle.pem
   cat "$(uv tool dir)/notebooklm-py/lib/python3.12/site-packages/certifi/cacert.pem" > "$OUT"
   for cn in "Kt Corporate Root CA" "Kt Corporate Forward Trust CA" "Kt Corporate Forward Trust CA ECDSA"; do
     security find-certificate -a -c "$cn" -p /Library/Keychains/System.keychain >> "$OUT"
   done
   ```
2. **Python 3.12로 설치** — `uv tool install --python 3.12 notebooklm-py --with playwright`

**왜 번들만으로는 부족한가**: Python 3.13은 `ssl.create_default_context()`에 `VERIFY_X509_STRICT`를 기본으로 켠다. 사내 CA 인증서에 RFC 5280이 CA에 요구하는 SKI/AKI 확장이 없으면, CA를 신뢰시켜도 `Missing Authority Key Identifier`로 거부된다. 실측(5개 Google 호스트 × strict on/off): **strict ON은 전부 실패, OFF는 전부 통과**. Python 3.12는 이 검사가 없다.

> `uv` 자체도 같은 MITM에 막힌다(`invalid peer certificate: UnknownIssuer`). 설치 시 `--system-certs`를 붙인다.

> 개인망에서는 이 설정이 무해하다 — 번들은 certifi를 그대로 포함하고, 사내 CA는 이미 macOS가 신뢰하는 것들이다. `SSL_CERT_FILE`은 이 스킬 실행 중에만 export되므로 다른 Python 작업의 신뢰 설정은 건드리지 않는다.

## 실행 순서

> **CLI 규칙**: `notebooklm-py`는 `notebook` 네임스페이스가 없음. `create/delete/generate/download` 모두 **최상위 명령**. 노트북은 `-n <id>` 옵션 또는 `notebooklm use <id>` 컨텍스트로 지정.

> ⚠️ **`source add` 다음에 반드시 `source wait`** (2026-08-06, 실측 확인)
>
> `source add`는 업로드만 하고 **처리 완료를 기다리지 않는다**. 이 상태(`status: preparing`)에서 `generate report`를 부르면 서버가 CREATE_ARTIFACT를 받고 **null을 반환**해 `Error: Report generation is unavailable`로 죽는다.
>
> **`generate --wait`로는 해결되지 않는다** — `--wait`는 *생성* 완료를 기다리지 *소스 처리*를 기다리지 않는다. 이름 때문에 착각하기 쉽다.
>
> 실측 A/B (동일 4.5MB PDF, 같은 노트북):
>
> | 시점 | 소스 status | `generate report` |
> |------|------------|-------------------|
> | `source add` 직후 | `preparing` | ❌ Report generation is unavailable |
> | `source wait` 후 | `ready` | ✅ Briefing Document ready |
>
> 대기 비용은 **2.6초**였다. 에러 문구가 "unavailable"이라 기능 차단·계정 게이팅·API 변경으로 오해하기 쉽지만, 실제로는 순수한 **경쟁 상태**다. `source wait --help`도 "Spawn this in a subagent after `source add` returns"라고 이 단계를 전제한다.

```bash
# 1. 노트북 생성 — JSON 파싱으로 ID 추출
NB_ID=$(notebooklm create "{slug}" --json | jq -r '.notebook.id')

# 2. 소스 업로드 (유형별) — source add 는 파일 경로/URL 자동 감지
#    repo의 경우 1.9MB 초과 시 자동 분할 (notebooklm 2MB 한도 + 마진)
#    업로드한 source id를 모아둔다 — step 2.5에서 처리 완료를 기다려야 한다
SRC_IDS=()
add_source() {  # 인자: source add 에 넘길 대상 (파일 경로 또는 URL)
  SRC_IDS+=("$(notebooklm source add "$1" -n "$NB_ID" --json | jq -r '.source.id')")
}

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
        add_source "$p.txt"
      done
      rm "$PREFIX"*.txt
    else
      add_source "$SRC"
    fi
    ;;
  paper)  add_source "raw/papers/{slug}/source.pdf" ;;
  article)
    if [ -n "$URL" ]; then
      add_source "$URL"
    else
      add_source "raw/articles/{slug}/source.md"
    fi
    ;;
esac

# 2.5 소스 처리 완료 대기 — 생략하면 generate 가 반드시 실패한다 (아래 경고 참조)
for sid in "${SRC_IDS[@]}"; do
  notebooklm source wait "$sid" -n "$NB_ID" --timeout 300 || {
    echo "소스 처리 실패/타임아웃: $sid — enrich 건너뜀"
    notebooklm delete -n "$NB_ID" -y
    exit 0
  }
done

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
