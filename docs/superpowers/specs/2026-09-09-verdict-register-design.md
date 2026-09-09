# 판정 레지스터 (verdicts.md) 설계

- **작성일**: 2026-09-09
- **상태**: 설계 승인 대기
- **영향 범위**: rakis `wiki-wrap-up` 스킬 1개 + vault 루트 파일 1개 신설
- **출처**: [[wikiskill-skill-evolution]] (arXiv:2608.27454) 의 `skill-impact.md` 대조

## 배경

WikiSkill 논문은 에이전트 스킬 진화 과정에서 **거절된 제안의 diff·검증 점수·판정 결과를 `skill-impact.md` 한 파일에 모은다.** 다음 반복의 스킬 제안자는 이 파일을 먼저 읽고 "이미 시도했고 실패한" 방향을 반복하지 않는다. 스킬 계층에서 지워진 실패한 시도가 위키 계층에는 감사 추적으로 남는 구조다.

이 vault(rakis 3-Layer)에는 대응하는 자리가 없다. 기각 판정은 개별 페이지에 흩어져 있다:

- graphify 제거(2026-07-31) → `wiki/projects/raki-claude-plugins.md` Decisions
- study-guide·mindmap 제거(2026-07-31) → 같은 페이지 다른 절
- Codex 프록시 제거(2026-09-01) → `wiki/concepts/claude-code-codex-proxy.md`
- graft 채택(2026-09-07) → `wiki/projects/claude-code-context-tuning.md`
- 24시간 녹화 도입 안 함 → `wiki/projects/raki-claude-plugins.md` 미구현 갭

`log.md`는 245개 항목의 시간순 사건 나열이라 판정 이력이 아니다. 결과적으로 **"이거 이미 검토했나?"에 답하려면 페이지를 하나씩 뒤져야 한다.**

한편 판정을 **추출하는** 메커니즘은 이미 있다 — `wiki-wrap-up` 절차 1-C("결정과 이유")가 세션마다 그것을 뽑는다. 없는 것은 추출이 아니라 **모이는 자리**다.

## 목표

도구·접근의 채택/기각 판정을 한자리에서 읽을 수 있게 한다. 재검토 시점에 "이미 판단이 내려졌는가, 근거가 무엇이었는가"를 한 번의 읽기로 확인한다.

**비목표** — 아래는 이 설계가 하지 않는다:

- 모든 설계 결정의 기록 (프로젝트 페이지 Decisions 섹션이 이미 한다)
- 판정 근거의 보관 (근거 본문은 지금 있는 자리에 그대로 둔다)
- 자동 게이팅·롤백 (rakis에는 검증 점수에 해당하는 지표가 없다)

## 설계

### 1. 파일: 루트 `verdicts.md`

`index.md`·`log.md` 옆에 둔다. vault CLAUDE.md가 Layer 3를 "Root Files — Navigation & Logs"로 정의하며, 판정 색인이 정확히 그 성격이다. `wiki/` 안에 두면 소스도 개념도 엔티티도 아닌 것이 섞인다.

```markdown
---
title: Verdicts
type: index
sources: []
related: []
created: 2026-09-09
updated: YYYY-MM-DD
description: "도구·접근 채택/기각 판정 색인 — 근거 본문은 각 상세 페이지에"
---

# Verdicts

> 도구·접근을 **채택했거나 기각한** 판정만 모은다. 근거 본문은 여기 없다 — `상세` 링크를 따라간다.
> 재검토 전에 먼저 읽는다: 이미 판단이 내려졌는가, 무엇이 근거였는가.

| 날짜 | 대상 | 판정 | 한 줄 근거 | 상세 |
|---|---|---|---|---|
| 2026-09-07 | graft | 채택 | SWE-bench 54→66%, 후보 중 유일한 실측치 | [[projects/claude-code-context-tuning]] |
| 2026-07-31 | graphify | 제거 | 노드↑ → 오탐 표면↑, 쿼리 경로에 없어 3주 stale | [[projects/raki-claude-plugins]] |
```

**판정 3값**

| 값 | 의미 |
|---|---|
| `채택` | 도입해서 쓰고 있다 |
| `기각` | 검토했으나 도입하지 않았다 (써보지 않고 내린 판단) |
| `제거` | 도입했다가 뺐다 (써보고 내린 판단) |

`기각`과 `제거`를 합치지 않는 이유: 재검토 시 "안 써보고 내린 판단"은 뒤집힐 여지가 크고 "써보고 내린 판단"은 그렇지 않다. 둘을 섞으면 그 차이가 사라진다.

**정렬**: 날짜 역순(최신 위). 재검토는 최근 판정부터 본다.

**`상세` 링크의 대상**: 소스 요약 페이지가 아니라 **판정 근거가 서술된 페이지**를 가리킨다. graft라면 `[[sources/trailhq-graft]]`(도구가 무엇인지)가 아니라 `[[projects/claude-code-context-tuning]]`(왜 채택했는지)이다.

**한 줄 근거의 기준**: `description` 규칙과 같다 — 항목만 읽고 상세 페이지를 열지 말지 판단할 수 있어야 한다. `"성능 문제"`는 실패, `"노드↑ → 오탐 표면↑, 쿼리 경로에 없어 3주 stale"`은 성공.

### 2. 단일 소스 원칙

이 파일에는 **근거 본문이 없다.** 한 줄 요약과 링크뿐이며, 상세는 지금 있는 자리에서 움직이지 않는다. 근거를 여기로 옮기면 프로젝트 맥락에서 결정이 떨어져 나가고, 복제하면 두 곳이 어긋났을 때 어느 쪽이 맞는지 알 수 없게 된다.

**vault CLAUDE.md의 `index.md` 편집 규칙을 그대로 적용한다** — 이 파일도 여러 기기가 Nextcloud로 동기화하며 건드리는 단일 파일이라 같은 사고에 취약하다:

- 쓰기 직전에 반드시 다시 읽는다 (세션 앞부분에서 읽어둔 내용을 근거로 쓰지 않는다)
- 전체 재작성 금지 — 행 추가·수정은 해당 줄만 편집한다
- 사라진 항목이 있으면 덮어쓰기를 의심한다

### 3. 쓰기: `wiki-wrap-up` 만

판정은 특정 스킬이 아니라 대화 중에 나온다. `wiki-wrap-up`은 이미 세션 전체를 회고하므로, 어느 스킬을 돌던 중이었든 그 시점에 잡힌다. `wiki-ingest`에도 넣으면 같은 판단을 두 번 적는 중복 로직이 된다.

**변경 지점 4곳** (`skills/wiki-wrap-up/SKILL.md`):

| 절차 | 변경 |
|---|---|
| 1-C 결정과 이유 | 추출된 결정 중 **도구·접근의 채택/기각**인 것을 판정 후보로 분류. 대상 이름·판정값·한 줄 근거·상세 링크를 함께 뽑는다 |
| 3 사용자 확인 | "결정 기록" 블록에 판정 후보를 `→ verdicts.md + log.md` 로 표시 (일반 결정은 `→ log.md` 그대로) |
| 4-4 위키 저장 실행 | 승인된 판정을 `verdicts.md` 표 최상단 행으로 삽입. §2 편집 규칙 준수 |
| 5 완료 보고 | 판정 기록 건수 한 줄 추가 |

**판정 후보 판별 기준** — 아래를 모두 만족할 때만 `verdicts.md`에 올린다:

1. 대상이 **도구·라이브러리·플러그인·접근법** 중 하나로 이름을 붙일 수 있다
2. 결과가 채택 / 기각 / 제거 중 하나로 떨어진다
3. 근거가 되는 상세 서술이 위키 어딘가에 있다 (없으면 그 페이지를 먼저 만들거나 보강한다)

세 조건 중 하나라도 어긋나면 `log.md`에만 기록한다. 판별이 애매하면 올리지 않는다 — 레지스터가 커질수록 "이미 검토했나"에 답하는 속도가 떨어진다.

### 4. 초기 백필

빈 레지스터는 쓸모가 없다. 아래 페이지에서 판정을 추출해 초기 행을 채운다:

- `wiki/projects/raki-claude-plugins.md` — graphify 제거, study-guide·mindmap 제거, source-analyze 제거, eli5 보강판 채택, 24시간 녹화 도입 안 함
- `wiki/projects/claude-code-context-tuning.md` — graft 채택, caveman·read-once·shunt 등 미도입 후보
- `wiki/concepts/claude-code-codex-proxy.md` — 프록시 제거
- `wiki/concepts/agent-token-reduction-axes.md` — 축별 도구 판정
- `wiki/sources/graphify.md` · `wiki/comparisons/repomix-vs-graphify-vs-gstack.md` — graphify 제거 판정 근거
- 그 밖에 `제거 판정` · `도입 안 함` · `에서 폐기` 표현이 있는 페이지 (2026-09-09 실측 11건)

**추출 규칙**: 페이지에 근거가 명시된 것만 넣는다. 날짜·근거가 불분명하면 넣지 않고 별도로 보고한다 — 레지스터에 추측이 섞이면 "판정을 확인하는 자리"라는 성격 자체가 무너진다.

예상 규모 10~15건.

### 5. vault CLAUDE.md 갱신

Layer 3 코드블록에 한 줄 추가한다. 기존 3줄이 정렬된 영어 설명 형식이므로 그에 맞춘다:

```
index.md         — master catalog of all pages
log.md           — append-only chronological record
verdicts.md      — tool/approach adoption verdicts (rationale lives in the linked page)
wiki/overview.md — Obsidian home dashboard (dataview). v3 이전엔 루트 Home.md
```

## 테스트 / 검증

| 항목 | 방법 | 기준 |
|---|---|---|
| 스킬 구조 | `./lint.sh` | 65/65 PASS 유지 (스킬 메타·라인수·references 일관성) |
| frontmatter | `scripts/frontmatter.py validate verdicts.md` | exit 0 |
| 링크 무결성 | `상세` 열의 모든 `[[...]]` 타깃 존재 확인 | 깨진 링크 0 |
| 백필 정확도 | 각 행의 근거를 상세 페이지 본문과 대조 | 페이지에 없는 주장 0건 |
| 회귀 | `wiki-wrap-up` 을 실제 세션에서 1회 실행 | 판정 후보가 3 확인 단계에 표시되고, 승인 시 행이 추가된다 |

`test.sh`는 NotebookLM 네트워크 계약 테스트라 이 변경과 무관하다 — pre-push 훅이 실행하는 것으로 충분하다.

## 변경 파일

**rakis 레포**

- `skills/wiki-wrap-up/SKILL.md` — 변경 지점 4곳
- `docs/superpowers/specs/2026-09-09-verdict-register-design.md` — 이 문서
- `CHANGELOG.md` · 버전 bump — pre-push 훅이 `feat:` 커밋에서 자동 처리

**vault**

- `verdicts.md` — 신규 (백필 포함)
- `CLAUDE.md` — Layer 3 목록 한 줄
- `log.md` — 신설 기록 한 줄

## 근거와 한계

**WikiSkill에서 가져온 것**: 판정 이력을 한자리에 모으는 것, 거절된 시도를 지우지 않는 것, 색인 한 줄이 "열지 말지"를 판단하게 하는 것.

**가져오지 않은 것과 이유**:

| 논문 요소 | 미채택 사유 |
|---|---|
| 게이팅·롤백 | rakis에는 검증 점수에 해당하는 자동 지표가 없다. 지표 없이 게이트만 흉내 내면 형식만 남는다 |
| 패턴 페이지 10~30줄 제한 | WikiSkill의 `patterns/`는 "실패 유형 + 우회책" 단위라 짧은 게 맞지만, rakis `concepts/`는 도메인 정리라 성격이 다르다 |
| 제안 diff 전문 보관 | `skill-impact.md`는 에이전트가 자동 생성하므로 분량이 문제되지 않는다. 사람이 관리하는 파일에서는 색인이 길어지면 읽히지 않는다 |

**남는 한계**: 판정을 올릴지 말지는 사람(또는 wrap-up 시점의 판단)에 달려 있어, 누락이 조용히 발생할 수 있다. WikiSkill은 하니스가 게이팅 결과를 **프로그램적으로** 덧붙여 이 문제가 없다. 누락 탐지를 `wiki-lint`에 넣는 것은 이번 범위에서 제외했다 — 레지스터가 실제로 쓰이는지 먼저 확인한 뒤 판단한다.
