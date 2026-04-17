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

## LinkedIn / X (Twitter)

WebFetch 후 본문 텍스트만 추출:
```
WebFetch(url="{url}", prompt="Extract the post body text and author name. No UI chrome.")
```

`source.md`에 저장 형식:
```markdown
<!-- url: {url} -->
<!-- platform: linkedin|x -->
<!-- captured_at: {ISO8601} -->

**Author:** {author}

{본문}
```

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
