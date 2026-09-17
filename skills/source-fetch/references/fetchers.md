# fetchers — 유형별 원본 수집 상세

## GitHub repo

```bash
mkdir -p "raw/repos/{slug}"
npx -y repomix --remote "{url}" --output "raw/repos/{slug}/repomix.txt"
```

repomix 실패 시 (예: 프라이빗 repo, 토큰 이슈):

```bash
gh repo clone "{owner}/{repo}" /tmp/repo-{slug}
cd /tmp/repo-{slug} && npx -y repomix --output "$VAULT/raw/repos/{slug}/repomix.txt"
rm -rf /tmp/repo-{slug}
```

`meta.json`에 `stars`, `language`, `license` 추가 가능:
```bash
gh api "repos/{owner}/{repo}" --jq '{stars: .stargazers_count, language: .language, license: .license.spdx_id}'
```

## 웹 페이지 (일반 URL)

WebFetch 도구 사용:
```
WebFetch(url="{url}", prompt="Extract main content as plain text. Preserve headings and code blocks.")
```

결과를 `raw/articles/{slug}/source.md`에 저장. 상단에 메타 주석:
```markdown
<!-- url: {url} -->
<!-- captured_at: {ISO8601} -->

{본문}
```

## 첨부 이미지 확인 (SNS·랜딩페이지 필수)

WebFetch는 텍스트만 추출한다 — 수익 인증 스크린샷, 헤드라인 배너, 계정 캡처 등 **이미지에만 있는 정보**(수치, 증거, 주장과의 모순)를 놓친다. SNS 게시물(Threads/X/Facebook/Instagram)이나 마케팅 랜딩페이지를 수집할 때는:

1. WebFetch 결과에서 이미지 존재 신호를 확인한다 — alt 텍스트, 캐러셀 인디케이터("1/2" 등), 명백히 비어 보이는 짧은 본문(리드폼뿐인 페이지는 실제로 이미지에 오퍼 내용이 있을 가능성이 높음).
2. 이미지가 있으면 Chrome 브라우저 자동화(`mcp__claude-in-chrome__*`)로 실제 페이지를 열어 스크린샷을 찍는다.
3. 스크린샷을 `raw/{type}/{slug}/images/`에 실제 파일로 저장하고, `source.md`에 이미지 경로(`![설명](images/...)`)와 이미지 안 텍스트·수치를 옮겨 적는다.
4. **`N/M` 배지를 캐러셀로 단정하지 않는다.** 아래 "Threads self-thread" 섹션을 먼저 확인할 것. 캐러셀이 맞고 2번째 이후에 자동화로 접근이 안 되면 "미확보"라고 `source.md` 주석에 솔직히 기록하고 넘어가되, 최소 1번째 이미지는 반드시 확인한다.
5. 텍스트만으로 "콘텐츠 없음"이라 판단하지 않는다 — 이미지 확인 전까지는 판단을 보류한다.

## Threads self-thread (`N/M` 배지)

**`1/11` 같은 배지는 이미지 캐러셀이 아닐 때가 많다.** 작성자가 연달아 올린 **N개의 독립 게시물(self-thread)** 위치 표시인 경우가 흔하다. 각 게시물은 자기 고유 shortcode를 가지므로 **스와이프·방향키·`img_index`로 넘길 대상이 존재하지 않는다** — 이걸 캐러셀로 착각하면 넘기는 방법을 찾느라 시간을 통째로 날린다.

**판별**: 게시물 API로 확인한다.

```bash
curl -s "https://www.threads.com/api/v1/media/{media_pk}/info/" \
  -H "X-IG-App-ID: 238260118697367" -H "X-ASBD-ID: 129477"
```

- `carousel_media` 있음 → 진짜 미디어 캐러셀
- `media_type: 1` + `text_post_app_info.self_thread_info.self_thread_length: N` → **self-thread**

**수집 절차 (self-thread)**:

1. permalink(`/@{user}/post/{shortcode}`)로 **직접 navigate하면 피드로 리다이렉트된다.** 리다이렉트된 피드에서 해당 게시물의 링크를 클릭해야 permalink 뷰로 들어간다:
   ```js
   document.querySelector('a[href*="/post/{shortcode}"]').click()
   ```
2. permalink 뷰에서는 **2~N번 게시물이 답글(reply) 영역에 전부 렌더된다.** `get_page_text` 한 번이면 본문 전문을 얻는다. 프로필 `/media` 탭 무한스크롤로 찾아 헤맬 필요가 없다.
3. 작성자가 본문에 붙인 접두사(`1/`, `2/` …)와 UI 배지 번호는 **하나씩 어긋날 수 있다.** 둘 다 기록할 것.
4. 인용(quote) 카드가 섞여 있으면 self-thread 구성원과 구분해 적는다.

**이미지 원본 받기**:

`javascript_tool`로 `img.src`를 읽으면 `[BLOCKED: Cookie/query string data]`로 막힌다 (Meta CDN 서명 토큰 보호 — 우회하지 말 것). 대신 `read_network_requests`를 쓴다:

1. 페이지 로드 **전에** `read_network_requests`를 한 번 호출해 추적을 시작시킨다 (호출 시점부터 기록된다)
2. 페이지를 열고 끝까지 스크롤해 이미지를 전부 로드시킨다
3. `read_network_requests(urlPattern: ".jpg")` → 서명된 CDN 원본 URL이 그대로 나온다
4. `curl -sL -A "<브라우저 UA>"`로 받는다. 스크린샷보다 해상도가 높다 (실측 1844x1022 vs 뷰포트 캡처 1093x1092)

**어느 게시물의 이미지인지 매핑**: URL의 `ig_cache_key` 파라미터가 media pk의 base64다.

```bash
python3 -c "import base64,sys; print(base64.b64decode(sys.argv[1]+'==').decode())" "Mzk4NzM2MDQxOTMyMDY4NDYyNA"
# → 3987360419320684624
```

pk는 시간순(snowflake)이라 **정렬하면 게시물 순서와 일치한다.** `video_first_frame_thumbnail` 태그가 붙은 건 영상 게시물의 썸네일이다 (영상 자체는 별도).

> 실측: 2026-09-17 `@choi.openai/post/DdV8yzpD-BQ` (self_thread_length=11). 캐러셀로 착각해 스와이프·방향키·`/embed`·`img_index`·프로필 미디어 탭 등 12가지를 시도해 전부 실패했고, 답글 영역을 여는 것으로 한 번에 해결됐다.

## YouTube

notebooklm-py가 YouTube URL을 직접 소스로 받음. `source.md`에는 자리표시자만:
```markdown
<!-- url: {url} -->
<!-- type: youtube -->
<!-- captured_at: {ISO8601} -->

(원본은 NotebookLM이 처리. 이 파일은 포인터 역할.)
```

enrich 시 notebooklm에 URL 직접 업로드. YouTube는 enrich 임계값 무관하게 enrich 시도(자막 없으면 skip).

## PDF

```bash
curl -L -o "raw/papers/{slug}/source.pdf" "{url}"
```

크기 검증: 0바이트면 실패로 간주.

## LinkedIn / X (Twitter) / Threads / Facebook

WebFetch 후 본문 텍스트만 추출:
```
WebFetch(url="{url}", prompt="Extract the post body text and author name. No UI chrome.")
```

`source.md`에 저장 형식:
```markdown
<!-- url: {url} -->
<!-- platform: linkedin|x|threads|facebook -->
<!-- captured_at: {ISO8601} -->

**Author:** {author}

{본문}
```

첨부 이미지가 있으면 위 "첨부 이미지 확인" 섹션대로 반드시 확인한다. **Threads에서 `N/M` 배지를 봤다면 "Threads self-thread" 섹션을 먼저 읽을 것** — 캐러셀이 아니라 독립 게시물 N개인 경우가 흔하다 — 특히 Threads/Facebook은 수익 인증 스크린샷류가 본문 텍스트 없이 이미지로만 첨부되는 경우가 흔하다.

## 이미지

로컬 복사 + Vision 설명:
```
Read(file_path="{path}")
```

설명을 텍스트로 작성하여 `source.md`에 저장. 원본 이미지도 같은 폴더에 복사.

## 로컬 파일

```bash
cp "{path}" "raw/articles/{slug}/source.{ext}"
```

확장자는 원본 유지(`.md`, `.txt`, `.pdf` 등).
