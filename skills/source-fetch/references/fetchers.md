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
4. 캐러셀 2번째 이후 이미지처럼 자동화로 접근이 안 되면 "미확보"라고 `source.md` 주석에 솔직히 기록하고 넘어가되, 최소 1번째 이미지는 반드시 확인한다.
5. 텍스트만으로 "콘텐츠 없음"이라 판단하지 않는다 — 이미지 확인 전까지는 판단을 보류한다.

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

첨부 이미지가 있으면 위 "첨부 이미지 확인" 섹션대로 반드시 확인한다 — 특히 Threads/Facebook은 수익 인증 스크린샷류가 본문 텍스트 없이 이미지로만 첨부되는 경우가 흔하다.

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
