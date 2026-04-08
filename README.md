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
| `wiki-ingest` | "저장해줘", "위키에 넣어줘" | Save source to raw/, create/update wiki pages |
| `wiki-query` | "~에 대해 정리된 거 있어?" | Search wiki via index.md, answer with citations |
| `wiki-lint` | "위키 점검해줘" | Health check: contradictions, orphans, gaps |
| `wiki-wrap-up` | 세션 종료 시 | Session-end knowledge capture |

## Installation

```bash
claude plugin install github:raki-1203/raki-claude-plugins
```

## Setup

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
