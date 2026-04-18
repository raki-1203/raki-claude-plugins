---
name: source-fetch
description: Use when the user wants to add an external source (URL, GitHub repo, PDF, local file) to the Obsidian vault — saves the original to raw/ and optionally enriches with NotebookLM briefing/study-guide/mindmap. Does NOT write to wiki/.
---

# source-fetch — 원본만 raw/에 저장

외부 소스를 `raw/`에 불변 원본으로 저장한다. 어떤 LLM 분석도 하지 않는다. wiki 컴파일은 `/rakis:wiki-ingest`가 담당.

## Vault 경로 탐지

1. 환경변수 `OBSIDIAN_VAULT_PATH` 있으면 사용
2. `~/Library/Mobile Documents/com~apple~CloudDocs/Documents/Vault`
3. Vault `CLAUDE.md`에 "Three-Layer" 또는 "raw/" 언급 검증

## 인자

```
/rakis:source-fetch <url-or-path> [--slug <slug>] [--no-enrich|--force-enrich]
```

## Phase 0: 유형 감지 + slug 생성

| 유형 | 감지 | raw 경로 |
|------|------|---------|
| GitHub repo | `github.com/{owner}/{repo}` | `raw/repos/{owner}-{repo}/` |
| YouTube | `youtube.com`/`youtu.be` | `raw/articles/{slug}/` |
| PDF | `.pdf` | `raw/papers/{slug}/` |
| 웹 URL | `http(s)://` 기타 | `raw/articles/{slug}/` |
| 로컬 파일 | path 존재 | `raw/articles/{slug}/` (복사) |

slug는 `scripts/slug.sh`의 `rakis_slug` 함수로 정규화. `--slug` 인자가 있으면 그대로 사용(정규화 패스).

## Phase 1: 중복 체크 + 재수집(refresh) 정책

- `raw/{type}/{slug}/meta.json` 존재 여부 확인
- 존재 시: "이미 수집됨. 재수집(덮어쓰기) 또는 건너뛰기?" 질문 후 대기

**재수집 선택 시 동작 (정책 A — 단순 덮어쓰기):**
1. `raw/{type}/{slug}/` 내부를 **통째로 덮어씀** (source, notebooklm/ 포함). 별도 archive/ 백업 없음 — 과거 복구는 iCloud/Time Machine에 의존.
2. `meta.json`은 **이전 값을 읽어 이력 필드를 보존**하며 덮어씀 (Phase 2 참조).
3. **wiki는 건드리지 않음**. 필요 시 사용자가 대상 페이지만 삭제하고 증분 재컴파일: `rm "$VAULT/wiki/sources/{slug}.md" && /rakis:wiki-ingest`. (`--full`은 전체 sources를 삭제·재생성하므로 단일 slug 갱신에는 쓰지 말 것.)
4. 마지막 출력 메시지에 한 줄 안내: `"raw 갱신 완료 (refresh #N). 위키 재컴파일: rm \"$VAULT/wiki/sources/{slug}.md\" && /rakis:wiki-ingest"`

## Phase 2: 원본 수집

> **유형별 상세**: `references/fetchers.md` 참조

요약:
- GitHub repo → `npx -y repomix --remote <url> --output raw/repos/{slug}/repomix.txt`
- 웹/YouTube/LinkedIn/X → WebFetch 또는 notebooklm 소스 텍스트로 `raw/articles/{slug}/source.md`
- PDF → 다운로드하여 `raw/papers/{slug}/source.pdf`
- 로컬 파일 → `cp` 후 확장자 유지

`meta.json`은 매번 작성. **재수집인 경우 이전 meta.json에서 `captured_at_first`·`refresh_count`를 읽어 이어씀**:

```json
{
  "type": "repo|article|paper",
  "source_url": "<원본 URL 또는 로컬경로>",
  "captured_at_first": "<최초 수집 ISO 8601 — 재수집 시 유지>",
  "captured_at": "<이번 수집 ISO 8601 — 재수집 시 갱신>",
  "refresh_count": 0,
  "contributor": "raki-1203",
  "slug": "<slug>",
  "size_bytes": 0,
  "source_file": "source.md|source.pdf|repomix.txt"
}
```

**작성 규칙:**
- 신규 수집: `captured_at_first = captured_at = 현재 ISO 8601`, `refresh_count = 0`
- 재수집: 기존 파일에서 `captured_at_first`를 그대로 유지(없으면 이전 `captured_at` 값으로 세팅), `captured_at`을 현재로 갱신, `refresh_count += 1`

## Phase 3: NotebookLM enrich (임계값 자동)

> **임계값·호출 상세**: `references/enrich.md` 참조

요약 규칙:

| 조건 | 기본 동작 | `--no-enrich` | `--force-enrich` |
|------|----------|---------------|------------------|
| repo | enrich | skip | enrich |
| PDF | enrich | skip | enrich |
| 웹/로컬 텍스트 ≥5000자 | enrich | skip | enrich |
| 그 외 (짧은 글/트윗/이미지) | skip | skip | enrich |

enrich 조건 충족 시:
1. `command -v notebooklm` 확인 → 없으면 안내 후 건너뜀 (에러 아님)
2. `notebooklm auth check --test` → 실패 시 건너뜀
3. 노트북 생성 + 원본 업로드
4. `notebooklm notebook mindmap <id> --output raw/{type}/{slug}/notebooklm/mindmap.md`
5. `notebooklm notebook briefing <id> --output raw/{type}/{slug}/notebooklm/briefing.md`
6. `notebooklm notebook study-guide <id> --output raw/{type}/{slug}/notebooklm/study-guide.md`
7. 노트북 삭제 (ID 추적 안 함)

## Phase 4: 출력

- 요약 출력: 경로, 크기, enrich 여부
- **wiki 쓰지 않음**. 마지막 줄:
  > "raw 저장 완료. `/rakis:wiki-ingest` 로 위키에 반영하세요."

## 에러 처리

| 실패 지점 | 대응 |
|-----------|------|
| repomix | `gh clone` 폴백 → 실패 시 에러 |
| WebFetch | 사용자에게 텍스트 직접 입력 요청 |
| notebooklm 인증/업로드 | enrich 건너뛰고 raw만 저장 (에러 아님) |
| slug 정규화 공백 | 사용자에게 `--slug` 요청 |

## references/

| 파일 | 언제 |
|------|------|
| `fetchers.md` | 유형별 fetch 명령 상세 |
| `enrich.md` | NotebookLM 호출 순서·실패 처리 |
