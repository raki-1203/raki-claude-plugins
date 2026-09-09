# 판정 레지스터 (verdicts.md) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 도구·접근의 채택/기각/제거 판정을 vault 루트 `verdicts.md` 한 곳에서 읽을 수 있게 하고, 앞으로의 판정이 `wiki-wrap-up` 을 통해 자동으로 쌓이게 한다.

**Architecture:** `verdicts.md` 는 **색인**이다 — 근거 본문은 각 상세 페이지에 그대로 두고 여기엔 한 줄 요약과 링크만 둔다. 쓰기는 `wiki-wrap-up` 하나만 담당하며, 이미 있는 "결정과 이유" 추출에 판정 분기를 얹는다. 초기 백필로 과거 판정 7건을 채운다.

**Tech Stack:** Markdown (Obsidian wikilink), bash 검증 스크립트, `scripts/frontmatter.py` (rakis), `lint.sh` (rakis)

**Spec:** `docs/superpowers/specs/2026-09-09-verdict-register-design.md`

## Global Constraints

- vault 경로는 환경변수 `OBSIDIAN_VAULT_PATH` 로 얻는다. 하드코딩 금지.
- `verdicts.md` 판정값은 정확히 세 가지만 쓴다: `채택` / `기각` / `제거`.
- `verdicts.md` 행 정렬은 **날짜 역순**(최신이 위).
- `상세` 열은 **판정 근거가 서술된 페이지**를 가리킨다. 소스 요약 페이지가 아니다.
- 백필은 **페이지에 근거가 명시된 것만** 넣는다. 날짜나 근거가 불분명하면 넣지 않고 보고한다.
- `verdicts.md` 편집은 vault CLAUDE.md 의 `index.md` 편집 규칙을 따른다 — 쓰기 직전 재읽기, 전체 재작성 금지, 해당 줄만 편집.
- rakis 스킬 파일은 `SKILL.md` ≤500줄을 유지한다.
- 커밋은 사용자가 요청할 때만 한다. 각 Task 의 커밋 스텝은 사용자 승인 후 실행한다.

---

### Task 1: vault 에 `verdicts.md` 신설 + 백필 7건

**Files:**
- Create: `$OBSIDIAN_VAULT_PATH/verdicts.md`
- Modify: `$OBSIDIAN_VAULT_PATH/CLAUDE.md` (Layer 3 코드블록)
- Modify: `$OBSIDIAN_VAULT_PATH/log.md` (최상단 항목 추가)
- Test: `/tmp/verify-verdicts.sh` (일회용 검증 스크립트, 커밋하지 않음)

**Interfaces:**
- Produces: 루트 `verdicts.md` — 5열 마크다운 표(`날짜 | 대상 | 판정 | 한 줄 근거 | 상세`), frontmatter `type: index`. Task 2 의 `wiki-wrap-up` 이 이 표의 헤더 구분선(`|---|---|---|---|---|`) 바로 아래에 행을 삽입한다.

- [ ] **Step 1: 검증 스크립트를 먼저 작성한다**

```bash
cat > /tmp/verify-verdicts.sh <<'EOF'
#!/bin/bash
# verdicts.md 계약 검증. 통과 시 exit 0.
set -uo pipefail
V="$OBSIDIAN_VAULT_PATH"
F="$V/verdicts.md"
P="$HOME/.claude/plugins/cache/raki-claude-plugins/rakis/3.15.0"
fail=0

[ -f "$F" ] || { echo "FAIL: verdicts.md 없음"; exit 1; }

# 1) frontmatter 유효
uv run --quiet python3 "$P/scripts/frontmatter.py" validate "$F" >/dev/null 2>&1 \
  || { echo "FAIL: frontmatter 검증 실패"; fail=1; }

# 2) 표 본문 행 7개 이상, 판정값은 3값만
rows=$(grep -c '^| 2026-' "$F")
[ "$rows" -ge 7 ] || { echo "FAIL: 표 행 $rows 개 (7 이상 기대)"; fail=1; }
bad=$(awk -F'|' '/^\| 2026-/ {gsub(/ /,"",$4); if ($4!="채택" && $4!="기각" && $4!="제거") print $4}' "$F")
[ -z "$bad" ] || { echo "FAIL: 허용되지 않은 판정값: $bad"; fail=1; }

# 3) 날짜 역순 정렬
dates=$(awk -F'|' '/^\| 2026-/ {gsub(/ /,"",$2); print $2}' "$F")
[ "$dates" = "$(echo "$dates" | sort -r)" ] || { echo "FAIL: 날짜 역순 아님"; fail=1; }

# 4) 상세 열의 모든 wikilink 타깃 존재
cd "$V"
missing=$(awk -F'|' '/^\| 2026-/ {print $6}' "$F" \
  | grep -o '\[\[[^]]*\]\]' | tr -d '[]' \
  | while read -r t; do
      base="${t##*/}"
      find wiki -name "$base.md" -print -quit | grep -q . || echo "$t"
    done)
[ -z "$missing" ] || { echo "FAIL: 깨진 상세 링크: $missing"; fail=1; }

[ $fail -eq 0 ] && echo "PASS: verdicts.md 계약 전부 통과 ($rows 행)"
exit $fail
EOF
chmod +x /tmp/verify-verdicts.sh
```

- [ ] **Step 2: 검증 스크립트를 실행해 실패를 확인한다**

Run: `/tmp/verify-verdicts.sh`
Expected: FAIL — `FAIL: verdicts.md 없음`, exit 1

- [ ] **Step 3: `verdicts.md` 를 백필 7행과 함께 작성한다**

파일 전체를 아래 내용으로 생성한다. 판정 근거는 전부 상세 페이지 본문에서 확인된 것이다.

```markdown
---
title: Verdicts
type: index
sources: []
related: []
created: 2026-09-09
updated: 2026-09-09
description: "도구·접근 채택/기각/제거 판정 색인 — 근거 본문은 각 상세 페이지에"
---

# Verdicts

> 도구·접근을 **채택했거나 기각·제거한** 판정만 모은다. 근거 본문은 여기 없다 — `상세` 링크를 따라간다.
> 재검토 전에 먼저 읽는다: 이미 판단이 내려졌는가, 무엇이 근거였는가.
>
> **판정 3값** — `채택`: 도입해서 쓰고 있다 · `기각`: 검토했으나 도입하지 않았다(써보지 않고 내린 판단) · `제거`: 도입했다가 뺐다(써보고 내린 판단).
> "검토 중"·"미도입"은 판정이 아니므로 올리지 않는다.
>
> **편집 규칙** — 이 파일은 여러 기기가 Nextcloud로 동기화하며 건드린다. 쓰기 직전에 다시 읽고, 해당 줄만 편집한다. 전체 재작성 금지. (`index.md` 2026-08-14 사고 참조)

| 날짜 | 대상 | 판정 | 한 줄 근거 | 상세 |
|---|---|---|---|---|
| 2026-09-07 | graft | 채택 | SWE-bench Verified 54%→66%, 후보 중 유일하게 표준 벤치마크 수치를 낸 도구. Tier 1만 로컬 전용 설치 | [[projects/claude-code-context-tuning]] |
| 2026-09-01 | Codex 프록시 (cli-proxy-api) | 제거 | 구축 4일 만에 `502 anthropic upstream request failed` 의 원인으로 드러남. 상시 기동이 전제라던 것이 곧 SPOF | [[concepts/claude-code-codex-proxy]] |
| 2026-08-24 | eli5 — 공식판 대신 보강판 | 채택 | 공식 `SKILL.md` 는 321바이트·두 문장이라 근거 표기와 검증 장치가 없다. 조사·`file:line` 근거·이단계 검증을 얹은 자체판 채택 | [[projects/raki-claude-plugins]] |
| 2026-07-31 | graphify | 제거 | 한국어 위키 질의에서 `index.md` 텍스트 매칭보다 나빴다. 노드↑ → 라벨 부분문자열 오탐 표면↑ 구조라 최신화할수록 악화, 3주간 호출 0회 | [[projects/raki-claude-plugins]] |
| 2026-07-31 | NotebookLM study-guide | 제거 | 위키 인용률 29%, 분량의 35.6%가 퀴즈(18.8%)와 서술형 질문(16.8%) — 학습 장치지 위키 콘텐츠가 아니다 | [[projects/raki-claude-plugins]] |
| 2026-07-31 | NotebookLM mindmap | 제거 | 위키 인용률 15%. 어휘의 41%가 briefing에 없어 정보 자체는 고유하나, 워크플로에 읽는 단계가 없었다 | [[projects/raki-claude-plugins]] |
| 2026-07-31 | 24시간 오디오·화면 녹화 (Omi·Screenpipe) | 기각 | 장비·저장·프라이버시 비용 대비 실익이 "회고 계층" 하나로 좁혀 보인다 | [[projects/raki-claude-plugins]] |
```

- [ ] **Step 4: 검증 스크립트를 실행해 통과를 확인한다**

Run: `/tmp/verify-verdicts.sh`
Expected: PASS — `PASS: verdicts.md 계약 전부 통과 (7 행)`

실패하면 출력이 지목한 항목만 고친다. 링크가 깨졌다면 상세 페이지의 실제 파일명을 `find "$OBSIDIAN_VAULT_PATH/wiki" -name '<basename>.md'` 로 확인한다.

- [ ] **Step 5: vault `CLAUDE.md` Layer 3 코드블록에 한 줄 추가한다**

`### Layer 3: Root Files — Navigation & Logs` 아래 코드블록을 다음으로 교체한다. **해당 블록만 편집한다.**

```
index.md         — master catalog of all pages
log.md           — append-only chronological record
verdicts.md      — tool/approach adoption verdicts (rationale lives in the linked page)
wiki/overview.md — Obsidian home dashboard (dataview). v3 이전엔 루트 Home.md
```

- [ ] **Step 6: `log.md` 최상단에 기록 한 줄을 삽입한다**

기존 최상단 항목 **바로 앞**에 삽입한다. `log.md` 전체를 다시 쓰지 않는다.

```markdown
## [2026-09-09] verdicts | 신설 — 도구·접근 판정 색인 루트 파일. 과거 판정 7건 백필 (WikiSkill skill-impact.md 대응물)
```

- [ ] **Step 7: 백필에서 제외한 항목을 사용자에게 보고한다**

아래를 그대로 보고한다. 이것들은 **판별 기준에 미달**해 넣지 않은 것이지 누락이 아니다.

```
백필 제외 (판별 기준 미달):
- caveman / caveman-compress / boucle·read-once / context-mode / shunt
  → 상태가 "미도입"·"검토 중"이다. 채택/기각/제거 중 하나로 떨어지지 않아 제외.
- source-analyze 스킬 제거 (rakis v3.0)
  → 제거는 확실하나 페이지에 정확한 날짜가 없다. CHANGELOG 확인 후 추가할지 판단 필요.
```

- [ ] **Step 8: 커밋 (사용자 승인 후)**

vault 는 git 저장소가 아니므로 커밋 대상이 아니다. Nextcloud 동기화만 확인한다:

```bash
ls -la "$OBSIDIAN_VAULT_PATH/verdicts.md"
```

---

### Task 2: `wiki-wrap-up` 이 판정을 `verdicts.md` 에 기록하게 한다

**Files:**
- Modify: `skills/wiki-wrap-up/SKILL.md` (4곳)
- Modify: `CHANGELOG.md`
- Test: `./lint.sh`

**Interfaces:**
- Consumes: Task 1 이 만든 `verdicts.md` 의 표 구조 — 5열(`날짜 | 대상 | 판정 | 한 줄 근거 | 상세`), 헤더 구분선 바로 아래가 최신 행 자리.
- Produces: 없음 (스킬 문서 변경으로 종료)

- [ ] **Step 1: 현재 상태를 확인한다 (실패 확인에 해당)**

Run:
```bash
grep -c "verdicts" skills/wiki-wrap-up/SKILL.md
```
Expected: `0` — 아직 어디에도 언급이 없다.

- [ ] **Step 2: 절차 1-C 에 판정 분기를 추가한다**

`**C. 결정과 이유** (아키텍처, 설계, 도구 선택)` 블록의 예시 두 줄 바로 아래에 삽입한다.

```markdown
**C 중에서도 판정(verdict)인 것을 따로 표시한다**

C 항목이 아래 셋을 **모두** 만족하면 `verdicts.md` 후보다:

1. 대상이 **도구·라이브러리·플러그인·접근법** 중 하나로 이름을 붙일 수 있다
2. 결과가 `채택` / `기각` / `제거` 중 하나로 떨어진다 — "검토 중"·"미도입"은 판정이 아니다
3. 근거가 되는 상세 서술이 위키 어딘가에 있다 (없으면 그 페이지를 먼저 만들거나 보강한다)

후보로 뽑을 때 다섯 값을 함께 추출한다: **날짜 · 대상 · 판정 · 한 줄 근거 · 상세 링크**.
`한 줄 근거`는 항목만 읽고 상세를 열지 말지 판단할 수 있어야 한다 — `"성능 문제"` 는 실패다.
`상세 링크`는 도구가 무엇인지 설명한 소스 페이지가 아니라 **왜 그렇게 판정했는지가 적힌 페이지**를 가리킨다.

셋 중 하나라도 어긋나면 `log.md` 에만 기록한다. 애매하면 올리지 않는다 — 레지스터가 커질수록 "이미 검토했나"에 답하는 속도가 떨어진다.
```

- [ ] **Step 3: 절차 3 확인 화면의 "결정 기록" 블록을 갱신한다**

기존:
```
### 결정 기록 (N건)
- **OMC 제거**: 실제로 안 쓰고 있어서 CLAUDE.md에서 삭제
  comment: "실사용 검증 후 CLAUDE.md 간소화"
  → log.md에 기록
```

교체:
```
### 결정 기록 (N건)
- **OMC 제거**: 실제로 안 쓰고 있어서 CLAUDE.md에서 삭제
  comment: "실사용 검증 후 CLAUDE.md 간소화"
  → log.md에 기록

### 판정 기록 (N건)
- **graft 채택** (2026-09-07)
  한 줄 근거: "SWE-bench Verified 54%→66%, 후보 중 유일한 표준 벤치마크 수치"
  상세: [[projects/claude-code-context-tuning]]
  → verdicts.md + log.md에 기록
```

- [ ] **Step 4: 절차 4-4 저장 실행에 `verdicts.md` 쓰기를 추가한다**

기존 `4. **결정 기록** → \`log.md\`에 추가` 를 다음으로 교체한다.

```markdown
4. **결정 기록** → `log.md`에 추가
5. **판정 기록** → `log.md` + **루트 `verdicts.md`** 에 추가
   - **쓰기 직전에 `verdicts.md` 를 다시 읽는다.** 세션 앞부분에서 읽어둔 내용을 근거로 쓰지 않는다 — 그 사이 다른 기기가 갱신했을 수 있다
   - 표 헤더 구분선(`|---|---|---|---|---|`) **바로 아래**에 새 행을 삽입한다 (날짜 역순 유지)
   - `| YYYY-MM-DD | 대상 | 채택\|기각\|제거 | 한 줄 근거 | [[상세페이지]] |`
   - **전체 재작성 금지** — 해당 줄만 편집한다. 파일을 통째로 생성해 덮어쓰면 그 사이 추가된 판정이 조용히 사라진다
   - `updated:` 를 오늘 날짜로 갱신한다
```

이어지는 기존 5·6번 항목의 번호를 6·7로 밀어 쓴다.

- [ ] **Step 5: 절차 5 완료 보고에 판정 건수를 추가한다**

기존 보고 블록의 `- 로그 기록: 1건` 아래에 한 줄 추가:

```
- 판정 기록: 1건 (verdicts.md)
```

- [ ] **Step 6: 변경이 4곳 모두 들어갔는지 확인한다**

Run:
```bash
grep -c "verdicts" skills/wiki-wrap-up/SKILL.md
```
Expected: `4` 이상 (1-C 분기, 확인 화면, 저장 실행, 완료 보고)

Run:
```bash
wc -l skills/wiki-wrap-up/SKILL.md
```
Expected: 500 미만

- [ ] **Step 7: lint 를 실행한다**

Run: `./lint.sh`
Expected: `✅ PASS: 65` / `❌ FAIL: 0` — Task 1 이전과 동일해야 한다. 줄어들면 스킬 메타(name/description/라인수/references 일관성)가 깨진 것이다.

- [ ] **Step 8: CHANGELOG 항목을 추가한다**

`## [Unreleased]` 아래(없으면 신설) 에 추가:

```markdown
### Added
- `wiki-wrap-up`: 도구·접근 판정을 vault 루트 `verdicts.md` 색인에 기록. 판별 3조건(이름 붙는 대상 / 채택·기각·제거로 떨어짐 / 근거 페이지 존재)을 만족할 때만 올린다. 근거 본문은 상세 페이지에 그대로 두고 색인에는 한 줄과 링크만 둔다. 근거: WikiSkill(arXiv:2608.27454) `skill-impact.md` 대조 — `docs/superpowers/specs/2026-09-09-verdict-register-design.md`
```

- [ ] **Step 9: 커밋 (사용자 승인 후)**

```bash
git add skills/wiki-wrap-up/SKILL.md CHANGELOG.md docs/superpowers/specs/2026-09-09-verdict-register-design.md docs/superpowers/plans/2026-09-09-verdict-register.md
git commit -m "feat: wiki-wrap-up이 도구 판정을 verdicts.md 색인에 기록"
```

> pre-push 훅이 `feat:` 커밋을 보고 버전을 자동 bump 한다. 첫 푸시는 차단되고 재푸시가 필요하다 — 설계된 동작이다.

---

## Self-Review

**1. Spec coverage**

| 스펙 절 | 구현 위치 |
|---|---|
| §1 파일: 루트 `verdicts.md`, 판정 3값, 날짜 역순, 한 줄 근거 기준, 상세 링크 대상 | Task 1 Step 3 (파일 본문 + 헤더 주석), Step 1 검증 2·3·4 |
| §2 단일 소스 원칙 + `index.md` 편집 규칙 | Task 1 Step 3(헤더에 명시), Task 2 Step 4(쓰기 절차에 강제) |
| §3 쓰기: `wiki-wrap-up` 4곳 + 판별 3조건 | Task 2 Step 2~5 |
| §4 초기 백필 + 추출 규칙 | Task 1 Step 3(7행), Step 7(제외 항목 보고) |
| §5 vault CLAUDE.md 갱신 | Task 1 Step 5 |
| 테스트/검증 표 5항목 | lint → Task 2 Step 7 · frontmatter/링크/판정값/정렬 → Task 1 Step 1 스크립트 · 백필 정확도 → Step 3 본문이 상세 페이지 인용 · 회귀(실사용 1회) → 이 계획 이후 다음 세션 |

`wiki-lint` 누락 탐지는 스펙이 명시적으로 범위 밖으로 뺐으므로 태스크 없음이 맞다.

**2. Placeholder scan** — "TBD"·"적절히 처리"·"위와 유사" 없음. 백필 7행은 실제 값이 전부 적혀 있고, 스킬 변경 4곳은 삽입할 문구 전문이 들어 있다.

**3. Type consistency** — 표 열 이름(`날짜 | 대상 | 판정 | 한 줄 근거 | 상세`)이 Task 1 Step 3, Task 2 Step 3·4, 검증 스크립트의 awk 필드 번호($2 날짜, $4 판정, $6 상세)에서 일치한다. 판정값 3개(`채택`/`기각`/`제거`)가 검증 스크립트·파일 헤더·스킬 판별 조건에서 동일하다.

**한 가지 남는 위험**: 검증 스크립트가 rakis 캐시 경로 `3.15.0` 을 하드코딩한다. 플러그인이 업데이트되면 깨진다 — 일회용 스크립트(`/tmp`, 커밋 안 함)라 수용하되, 실행 시 경로가 없으면 `ls ~/.claude/plugins/cache/raki-claude-plugins/rakis/` 로 실제 버전을 확인해 바꾼다.
