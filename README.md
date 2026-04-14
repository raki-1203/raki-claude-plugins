# raki-claude-plugins

Personal Claude Code plugin collection by raki-1203.

## Plugins

### obsidian-wiki

Karpathy-style LLM Wiki management for Obsidian.

Turns your Obsidian vault into an LLM-maintained knowledge base using Andrej Karpathy's 3-layer architecture:

- **`raw/`** — Immutable source material (you add, LLM reads)
- **`wiki/`** — LLM-generated pages (concepts, entities, sources, comparisons)
- **Schema** — CLAUDE.md defines conventions and rules

#### Skills

| Skill | Trigger | What it does |
|-------|---------|-------------|
| `wiki-query` | "~에 대해 정리된 거 있어?", "이 프로젝트 관련 뭐 있어?" | 답변형/탐색형 자동 분기. graphify query 연동 |
| `wiki-ingest` | "저장해줘", "정리해줘" | 자료 수집. 코멘트 강제 + 그래프 증분 업데이트 |
| `source-analyze` | "분석해줘", "비교해줘" | NotebookLM 기반 심층 분석 + 코멘트 강제 |
| `wiki-wrap-up` | `/wiki-wrap-up` | 세션 학습 자동 추출 + 코멘트 자동 생성 |
| `wiki-lint` | "위키 점검해줘", 주 1회 | 건강 점검 + graphify 풀 리빌드 |
| `wiki-init` | `/wiki-init`, "위키 초기화" | vault 인터뷰 기반 초기 세팅 |

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
/wiki-init

# 3. 평소 사용
"MCP가 뭐였지?"                    # wiki-query 트리거
"https://... 분석해줘"              # source-analyze 트리거
/wiki-wrap-up                       # 세션 끝에 학습 저장

# 4. 주 1회
/wiki-lint                          # 건강 점검 + 그래프 리빌드

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

`source-analyze`, `wiki-query` 등 일부 스킬에 필요한 외부 도구(notebooklm-py, gh, graphify, node)를 점검하고, 누락된 것을 동의 후 설치합니다. Python 툴 관리자 `uv`도 없으면 같이 자동 설치됩니다.

전제조건: macOS, Homebrew. brew가 없으면 setup 시작 시 안내합니다.

### 2. Obsidian Vault 경로

Set your vault path as an environment variable:

```bash
export OBSIDIAN_VAULT_PATH="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Documents/Vault"
```

Or the plugin will auto-detect the default iCloud path.

## Vault Structure

```
Vault/
  CLAUDE.md          — Schema & rules
  index.md           — Master catalog (LLM search engine)
  log.md             — Chronological operation log
  Home.md            — Obsidian dashboard
  raw/
    articles/        — Web clippings
    papers/          — PDFs
    repos/           — Code docs
    data/            — Datasets
    images/          — Visuals
    assets/          — Attachments
  wiki/
    concepts/        — Topic pages
    entities/        — People/org pages
    sources/         — Source summaries
    comparisons/     — Analysis pages
```

## License

MIT
