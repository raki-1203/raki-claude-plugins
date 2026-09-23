# link-follow — 본문 속 참고 링크 추출·분류·수집

SNS 게시물·뉴스레터·블로그 글은 대개 **자기가 알맹이가 아니다.** 알맹이를 가리킬 뿐이다.
게시물만 저장하면 위키에 "무엇을 소개했다"는 사실만 남고 소개된 대상은 안 들어온다.

> 실측 계기: 2026-09-23 `linkedin-soulai-awesome-jev`. 게시물 본문 4,389바이트 중
> 실질 내용은 `github.com/AnotiaWang/awesome-jev`(★306) 한 줄이었다. 게시물만
> 수집한 결과 레포는 미수집으로 남았고, 게시물이 주장한 내용(SDK·연구 자료·가격)을
> 대조할 원본이 raw에 없었다.

## 적용 조건 — 좁게 잡는다

| 조건 | 값 | 이유 |
|------|-----|------|
| 대상 타입 | `article` 만 | repo(`repomix.txt`)·paper(PDF)는 링크가 본질적으로 수백 개다. `awesome-jev`에 이걸 돌리면 인덱싱된 488개 프로젝트가 전부 수집 대상이 된다 |
| 깊이 | **1 고정** | 자식 수집에서는 이 단계를 돌지 않는다. 그래서 순환 탐지 장치가 따로 필요 없다 |
| 추출 범위 | `source.md` 본문 + 이미지 전사 텍스트 | 스크린샷 안에만 있는 URL도 대상이다 |

`--no-follow` 가 있으면 Step 1~4까지만 하고 Step 5(수집)를 건너뛴다. 분류 결과는
그대로 `meta.json`에 남으므로 나중에 사람이 보고 개별 수집할 수 있다.

## Step 1: URL 추출

`source.md`에서 `https?://` 로 시작하는 문자열을 모두 뽑는다. 마크다운 링크
`[텍스트](url)`·꺾쇠 `<url>`·맨 URL 세 형태를 모두 잡되, 끝에 붙은 문장부호
(`.` `,` `)` `>` `"`)는 떼어낸다.

```bash
grep -oE 'https?://[^][:space:])<>"]+' source.md | sed 's/[.,)>"]*$//' | sort -u
```

메타 주석(`<!-- url: ... -->`)에 적힌 원본 URL 자신도 잡히므로 Step 3에서 제외된다.

## Step 2: 단축 링크 해석

`lnkd.in` `bit.ly` `t.co` `buff.ly` `ow.ly` `dub.sh` `han.gl` 등은 **해석 전까지
분류할 수 없다.** 무엇을 가리키는지 모르는 채로 제외하면 알맹이를 놓친다.

```bash
curl -sIL -A "$UA" "$URL" | grep -i '^location:' | tail -1
```

⚠️ **`lnkd.in` 은 두 형태가 다르게 동작한다** (2026-09-23 실측):

| 형태 | HEAD 리다이렉트 | 해석 방법 |
|------|----------------|-----------|
| `lnkd.in/p/{code}` | `301 + Location` 옴 | 위 `curl -sIL` 로 충분 |
| `lnkd.in/{code}` | **안 옴** (Location 헤더 없음) | 인터스티셜 HTML을 GET해서 본문의 대상 URL을 긁는다 |

```bash
# lnkd.in/{code} — 경고 페이지 HTML 안에 대상 URL이 그대로 들어 있다
curl -s -A "$UA" "https://lnkd.in/$CODE" \
  | grep -oE 'https?://[^"<> ]+' | grep -v -e lnkd.in -e linkedin.com -e licdn.com | head -1
```

`UA` 는 일반 브라우저 User-Agent를 쓴다. 기본 curl UA면 막히는 곳이 있다.

해석에 실패하면 `status: "failed"`, `reason: "unresolved-shortlink"` 로 기록하고 넘어간다.

## Step 3: 정규화 + 자기 자신 제외

1. 트래킹 파라미터 제거: `utm_*` `rcm` `trk` `trackingId` `fbclid` `gclid` `ref` `ref_src` `si` `igshid`
2. 프래그먼트(`#...`) 제거, 말미 `/` 통일, 호스트 소문자화, `www.` 제거
3. 국가 서브도메인 통일: `kr.linkedin.com` → `www.linkedin.com`
4. 정규화 결과가 **부모 URL과 같으면 제외** — `reason: "tracking"`
5. 정규화 결과가 **이미 raw에 있으면** (`raw/**/meta.json` 의 `source_url` 을 같은 규칙으로 정규화해 대조) 수집하지 않고 `status: "already-fetched"` + 그 slug 를 기록

## Step 4: 분류

**수집 대상은 "읽을거리 하나"를 가리키는 링크다.** 구독처·계정·랜딩은 대상이 아니다.

| 판정 | reason | 예 |
|------|--------|-----|
| ✅ 수집 | — | `github.com/{owner}/{repo}`, `*.pdf`, `arxiv.org/abs/*`, 경로가 있는 기사·블로그 글, `youtube.com/watch?v=*`, `youtu.be/*`, 문서 사이트의 개별 페이지 |
| ❌ 제외 | `subscription-channel` | `t.me/*`, `discord.gg/*`, `open.kakao.com/*`, `youtube.com/@handle`·`/channel/*`(영상 아닌 채널홈), `linkedin.com/in/*`, `x.com/{user}`(게시물 경로 없음), `instagram.com/{user}`(`/p/` 없음), `patreon.com/*`, `buymeacoffee.com/*` |
| ❌ 제외 | `landing-page` | 경로가 없는 루트 도메인 (`https://example.com/`, `https://example.com`) |
| ❌ 제외 | `platform-internal` | 원본과 같은 호스트의 프로필·해시태그·다른 게시물·도움말 (`linkedin.com/feed/hashtag/*`, `linkedin.com/help/*`) |
| ❌ 제외 | `asset` | 이미지·CSS·JS·폰트 CDN (`*.licdn.com`, `*.cdninstagram.com`, `*.jpg` `*.png` `*.css` `*.js`) |

**경계가 애매하면 수집한다.** 잘못 수집한 raw는 폴더 하나 지우면 끝이지만,
잘못 제외한 링크는 아무도 눈치채지 못한다.

단, **한 부모당 수집 대상 8개를 넘으면** 거기서 멈추고 나머지는
`status: "skipped"`, `reason: "fanout-limit"` 으로 기록한 뒤 사용자에게 알린다.
링크 목록 글(주간 뉴스레터 등)이 통째로 빨려 들어오는 것을 막는 안전장치다.

## Step 5: 수집 실행

대상마다 **Phase 0~3을 다시 실행한다.** 자식은 부모와 무관한 독립 소스다:

- 자기 유형에 따라 `raw/repos/` · `raw/papers/` · `raw/articles/` 중 제자리로 간다
- 자기 slug 를 갖는다 (`rakis_slug`)
- 자기 `meta.json` 을 갖는다 → `wiki-ingest` 가 전수 스캔으로 알아서 집어간다
- enrich 임계값도 자기 타입 기준으로 적용된다 (repo면 briefing 생성)

부모의 `--no-enrich` / `--force-enrich` / `--hint` 는 자식에게도 그대로 전달한다.
`--slug` 는 부모에게만 적용된다.

**자식 수집 실패는 부모를 실패시키지 않는다.** `status: "failed"` + `reason` 에
실패 사유를 적고 다음 링크로 넘어간다. Phase 1의 중복 질문도 자식에게는 묻지 않는다
— 이미 Step 3에서 `already-fetched` 로 걸러졌기 때문이다.

## Step 6: meta.json 기록

부모 `meta.json` 에 `references` 배열을 추가한다. **수집한 것뿐 아니라 제외한 것도
전부 남긴다** — 나중에 "이 링크는 왜 안 들어왔나"를 되물을 수 있어야 한다.

```json
"references": [
  {
    "url": "https://github.com/AnotiaWang/awesome-jev",
    "slug": "anotiawang-awesome-jev",
    "status": "fetched"
  },
  {
    "url": "https://t.me/aiinnovationstudio",
    "status": "skipped",
    "reason": "subscription-channel"
  }
]
```

- `url` 은 **해석·정규화를 마친 실제 URL**. 본문에 적힌 단축 URL이 아니다
- `slug` 는 `status` 가 `fetched` · `already-fetched` 일 때만 넣는다
- `status`: `fetched` | `already-fetched` | `skipped` | `failed`
- `reason`: `skipped` · `failed` 일 때 필수

자식 `meta.json` 에는 역방향 링크를 넣는다:

```json
"referenced_by": ["linkedin-soulai-awesome-jev"]
```

이미 존재하는 자식(`already-fetched`)이면 배열에 부모 slug 를 **추가**한다
(중복 제거). 여러 게시물이 같은 레포를 가리키는 경우가 흔하다.

## 실패 처리 요약

| 실패 지점 | 대응 |
|-----------|------|
| 단축 링크 해석 불가 | `failed` / `unresolved-shortlink` — 원본 단축 URL을 그대로 기록 |
| 자식 fetch 실패 (404·차단·repomix 실패) | `failed` / 실패 사유 — 부모 수집은 정상 완료 처리 |
| 수집 대상 8개 초과 | 초과분 `skipped` / `fanout-limit` — 출력에서 사용자에게 알림 |
| 자식 enrich 실패 | 기존 정책대로 enrich만 건너뜀 (에러 아님) |
