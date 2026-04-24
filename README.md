# raki-claude-plugins

Personal Claude Code plugin collection by raki-1203.

## Plugins

### obsidian-wiki

Karpathy-style LLM Wiki management for Obsidian.

Turns your Obsidian vault into an LLM-maintained knowledge base using Andrej Karpathy's 3-layer architecture:

- **`raw/`** — Immutable source material (you add, LLM reads)
- **`wiki/`** — LLM-generated pages (concepts, entities, sources, comparisons)
- **Schema** — CLAUDE.md defines conventions and rules

## 사용 워크플로 (v3)

### 새 소스 수집 → 위키 반영
```
/rakis:source-fetch https://example.com/article
/rakis:wiki-ingest
```

### 질의
```
/rakis:wiki-query "질문"
/rakis:wiki-query "프로젝트 X에서 Y가 뭐야?" --scope project
```

### 세션 마무리
```
/rakis:wiki-wrap-up
```

### 주간 건강 점검
```
/rakis:wiki-lint
```

### v2 사용자 마이그레이션 (1회)
```
/rakis:migrate-v3 --dry-run
/rakis:migrate-v3
```

## 스킬 목록 (v3)

| 스킬 | 역할 |
|------|------|
| `source-fetch` | URL/repo/PDF를 raw/에 저장 |
| `wiki-ingest` | raw → wiki/ 컴파일 |
| `wiki-query` | 위키 질의 (답변형/탐색형) |
| `wiki-wrap-up` | 세션 학습 기록 |
| `wiki-lint` | 위키 건강 점검 |
| `wiki-init` | 빈 볼트 초기화 |
| `migrate-v3` | v2 → v3 마이그레이션 (1회성) |

## 의존성

- `notebooklm-py` (optional, enrich 용)
- `npx` + `repomix` (repo 수집)
- `gh` CLI (private repo 폴백)
- `graphify` CLI (탐색형 query + 주간 풀 리빌드)

#### Commands

| Command | What it does |
|---------|-------------|
| `/rakis:setup` | 의존성 설치 + 글로벌 CLAUDE.md 매핑 |
| `/rakis:help` | 사용법 안내 (`/rakis:help <이름>`으로 상세) |
| `/rakis:wc-cp-graph` | 워크트리 graphify 파일 복사 |

## 빠른 시작

```bash
# 1. 의존성 설치 (머신당 1회)
/rakis:setup

# 2. vault 세팅 (vault당 1회)
/rakis:wiki-init

# 3. 평소 사용
/rakis:source-fetch https://example.com/article   # raw/에 저장
/rakis:wiki-ingest                                 # raw → wiki 컴파일
/rakis:wiki-query "MCP가 뭐였지?"                  # 질의
/rakis:wiki-wrap-up                                # 세션 끝에 학습 저장

# 4. 주 1회
/rakis:wiki-lint                                   # 건강 점검 + 그래프 리빌드

# 자세히
/rakis:help <이름>
```

## Installation

```bash
claude plugin install github:raki-1203/raki-claude-plugins
```

개발 시 clone 후:
```bash
make init
```

## Setup

### 1. 의존성 설치

플러그인 설치 후 한 번만 실행해주세요:

```text
/rakis:setup
```

`source-fetch`, `wiki-query` 등 일부 스킬에 필요한 외부 도구(notebooklm-py, gh, graphify, node)를 점검하고, 누락된 것을 동의 후 설치합니다. Python 툴 관리자 `uv`도 없으면 같이 자동 설치됩니다.

전제조건: macOS, Homebrew. brew가 없으면 setup 시작 시 안내합니다.

### 2. Obsidian Vault 경로 (**필수**)

`OBSIDIAN_VAULT_PATH` 환경변수가 **반드시** 설정돼있어야 합니다. 미설정 시 스킬이 에러 메시지 출력 후 중단됩니다 (v3.5.0 부터 기본값 폴백 제거).

```bash
# ~/.zshrc 또는 ~/.bashrc 에 추가 — 실제 vault 위치로 변경
export OBSIDIAN_VAULT_PATH="$HOME/Nextcloud/Vault"
# 또는: "$HOME/Library/Mobile Documents/com~apple~CloudDocs/Documents/Vault"
# 또는: "$HOME/Documents/Vault"
```

추가 후 `source ~/.zshrc` 또는 새 터미널.

## Vault Structure (v3)

```
Vault/
  CLAUDE.md              — Schema & rules
  index.md               — Master catalog
  log.md                 — Chronological log
  .rakis-v3-migrated     — Migration marker
  raw/                   — Immutable source material
    articles/            — Web clippings
    papers/              — PDFs
    repos/               — Code docs (repomix)
  wiki/                  — LLM-managed pages
    overview.md          — Vault dashboard
    sources/             — Source summaries
    projects/            — Project pages
    concepts/            — Topic pages
    entities/            — People/org pages
    comparisons/         — Analysis pages
  outputs/               — One-shot artifacts (lint reports, archive-v2)
```

## License

MIT
