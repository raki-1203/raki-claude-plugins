---
name: weekly-report
description: "주간 업무 보고서 초안을 자동 생성. 목요일 회의 전 '/rakis:weekly-report' 또는 '주간보고 만들어줘'라고 할 때 사용. CWD 아래 모든 git 레포에서 지난 7일간 본인 커밋/PR/이슈를 수집·요약해 마크다운으로 출력한다."
version: 1.1.0
license: MIT
---

# weekly-report — 주간 업무 보고서 생성

CWD 아래 git 레포들에서 지난 7일간의 본인 활동을 수집하여 주간 보고서 초안(마크다운)을 만들고, 터미널에 출력 + 파일로 저장한다.

## 인자 (선택)

```
/rakis:weekly-report [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--force]
```

- `--since`, `--until`: 기본값은 각각 7일 전, 오늘. 필요시 재정의
- `--force`: 같은 주 리포트 파일이 있어도 덮어쓰기 (기본은 `-2`, `-3` 서픽스로 저장)

## 절차

### 1. 인자 파싱

`$ARGUMENTS`에서 `--since`, `--until`, `--force`를 파싱. 없으면 기본값 사용.

### 2. 수집 스크립트 실행

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/weekly-report/scripts/collect_weekly.sh" \
  [--since $SINCE] [--until $UNTIL] \
  --root "$PWD"
```

- stdout을 JSON으로 캡처
- exit 2 (의존성 누락) → `/rakis:setup` 실행 안내 후 중단
- exit 3 (CWD에 레포 없음) → 사용자에게 "workspace 루트에서 실행하세요" 안내 후 중단

### 3. 활동 판정

- `.repos`가 빈 배열이면 → "이번 주 기록된 활동이 없습니다" 메시지 + 파일 저장 없이 중단

### 4. 요약 생성

JSON `.repos` 배열을 순회하며 레포별로 아래를 수행:

#### 4-A. 이번주 성과 bullet 생성 (압축 요약)

입력: `.commits`, `.prs_done`, `.issues_closed`

규칙:
1. **주제 그룹핑 우선**: PR 제목·scope·영역을 보고 의미 단위로 묶는다. 같은 주제 PR들은 하나의 bullet으로 합친다.
   - 출력 형식: `- {주제 요약} — #N1 #N2 #N3`
   - 예: `- showcase 썸네일·iframe·runtime 정합성 안정화 (Azure 404, F5 cross-leak 등) — #454 #455 #460`
2. **중복 커밋 제거**: PR에 속한 커밋은 별도 bullet 만들지 않음 (커밋 subject가 PR title의 부분 집합이면 드롭)
3. **직접 커밋(PR 없음)**: 아래는 드롭하고, 남으면 주제별로 묶어 bullet 1~2개 추가:
    - `wip`, `WIP`, `fix typo`, `lint`, `chore: format`, `style:`로 시작, `Merge branch` 등 의미 없는 메시지
    - subject 10자 미만
4. **close된 PR**: "[close]" 접두사로 구분
5. **이슈 해결**: `issues_closed` → 개수가 적으면 개별 bullet, 많으면 "이슈 N건 해결 — #N1 #N2 #N3" 한 줄로

bullet이 하나도 안 나오면 "_(활동 기록 없음)_" 표기.

목표: 20개 PR이어도 5~8 bullet로 수렴. 회의에서 한눈에 스캔 가능해야 함.

#### 4-B. 진행중 항목 + 다음주 계획 + 이번주 일정

세 개 하위 섹션으로 나눠 출력한다.

**진행중 항목** (open PR/이슈 자동 수집)

입력: `.prs_open`, `.issues_open`

- `prs_open` 각 PR → `- {제목} (#번호) — 목표: ____` (`draft: true`면 제목 앞에 `[초안] `)
- `issues_open` 각 이슈 → `- [이슈] {제목} (#번호) — 목표: ____`
- 하나도 없으면 섹션 통째로 생략

**다음주 계획** (직접 작성 — 빈 체크박스 3개)

```
- [ ]
- [ ]
- [ ]
```

사용자가 open 항목 외에 추가할 계획을 채우는 공간. 비어 있어도 항상 출력.

**이번주 일정** (출장·외근·회의 등, 직접 작성)

```
- (예: 04-25 광화문 KT — 협력사 미팅)
```

안내용 예시 한 줄. 사용자가 채울 내용 없으면 그 줄째로 지움.

### 5. 마크다운 조립

출력 형식:

````markdown
# 주간 업무 기록 - {week_number} ({since} ~ {until})

## {repo.name}

**이번주 성과**
- ...

**진행중 항목**
- ... — 목표: ____

**다음주 계획**
- [ ]
- [ ]
- [ ]

**이번주 일정**
- (예: 04-25 광화문 KT — 협력사 미팅)

## {repo.name}
...

---
_스킵된 레포: {comma-joined list with reason}_
````

규칙:
- 활동 있는 레포만 섹션으로 포함 (수집 스크립트에서 이미 필터링됨)
- `진행중 항목`은 open PR/이슈가 0개면 섹션 통째로 생략
- `다음주 계획`과 `이번주 일정`은 항상 출력 (사용자가 수동 채움)
- `skipped_repos`가 비어있지 않으면 마지막 `---` 아래 한 줄로 표기
- 비어있으면 마지막 `---` 라인 생략

### 6. 터미널 출력 + 파일 저장

- 마크다운 전체를 터미널에 출력 (사용자가 복붙할 수 있도록)
- 저장 경로: `$HOME/workspace/weekly-reports/{week_number}.md`
  - 디렉토리 없으면 `mkdir -p`
  - 파일 존재 + `--force` 없음 → `{week_number}-2.md`, `{week_number}-3.md`... 로 증분 저장
  - `--force` 있음 → 그대로 덮어쓰기
- 저장 후 절대경로를 마지막 한 줄에 출력:
  > 저장 완료: /Users/raki-1203/workspace/weekly-reports/2026-W17.md
