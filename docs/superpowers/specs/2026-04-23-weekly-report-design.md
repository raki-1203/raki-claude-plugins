# Weekly Report Skill 디자인

**Date**: 2026-04-23
**Status**: Spec (Pre-implementation)
**Target**: `rakis` 플러그인에 추가

## 목적

매주 목요일 회의 전, 워크스페이스 아래의 모든 레포에서 지난 7일간 본인이 한 작업을 자동으로 수집·요약하여 주간 업무 보고서 초안을 생성한다.

- **이번주 성과** bullet 자동 생성 (git commit + merged/closed PR + closed issue 기반)
- **다음주 계획 후보** bullet 자동 생성 (open PR + open assigned issue 나열)
- 사용자는 생성된 초안을 공유 보고서에 복붙하여 완성

## 범위

### 포함
- CWD 직계 서브디렉토리 중 `.git`이 있는 레포 전수 스캔
- 활동(커밋/PR/이슈)이 있는 레포만 리포트에 포함
- 로컬 `git log --all` 기반 커밋 수집 (실험 브랜치 포함)
- `gh` CLI 기반 PR/이슈 수집, 다중 계정 자동 처리
- 마크다운 출력 + 파일 저장 (`~/workspace/weekly-reports/YYYY-W##.md`)

### 제외
- 팀 전원 활동 수집 (본인 담당분만)
- 레포 → 프로젝트 표시명 매핑 (레포명 그대로 사용)
- 레포가 CWD 밖에 있는 경우 (명시적 `--root` override만 지원)
- 자동화 테스트 스위트 (수동 검증만)

## 아키텍처

```
사용자: /rakis:weekly-report [--since YYYY-MM-DD] [--until YYYY-MM-DD]
   ↓
SKILL.md 로딩
   ↓
[1] scripts/collect_weekly.sh 실행
    - CWD의 직계 git 레포 순회
    - 레포별 git log / gh pr / gh issue 수집
    - 활동 없는 레포 드롭, 접근 불가 레포는 skipped_repos에 사유 기록
    - JSON을 stdout으로 출력
   ↓
[2] Claude가 JSON 읽음
    - 레포별 섹션 생성
    - 이번주 성과: LLM이 의미 단위로 그룹핑 (노이즈 커밋 자동 드롭)
    - 다음주 계획 후보: open PR/이슈 그대로 나열
   ↓
[3] 마크다운 조립 → 터미널 출력 + 파일 저장
```

**핵심 설계 원칙**: 수집(결정적, bash 스크립트)과 요약(판단, LLM) 분리.

## 컴포넌트 구조

```
rakis/
└── skills/
    └── weekly-report/
        ├── SKILL.md
        └── scripts/
            └── collect_weekly.sh
```

스킬 전용 스크립트는 스킬 폴더 내부에 둔다 (superpowers brainstorming 스킬이 따르는 패턴).

### SKILL.md 역할

- `$ARGUMENTS` 파싱 (`--since`, `--until`, 없으면 기본값)
- `./scripts/collect_weekly.sh` 실행, JSON 파싱
- LLM 요약/그룹핑 수행
- 마크다운 조립, 터미널 출력, 파일 저장
- 저장 경로를 마지막에 사용자에게 안내

### collect_weekly.sh 역할

- 인자: `--since YYYY-MM-DD`, `--until YYYY-MM-DD`, `--root <dir>` (기본값: CWD)
- 출력: 아래 JSON 스키마
- 의존성: `git`, `gh`, `jq`, `yq`

## JSON 스키마

```json
{
  "since": "2026-04-16",
  "until": "2026-04-23",
  "week_number": "2026-W17",
  "repos": [
    {
      "name": "kt-innovation-hub-2",
      "remote": "git@github.com:axd-arena/kt-innovation-hub-2.git",
      "owner": "axd-arena",
      "me": "hr.son@kt.com",
      "commits": [
        {
          "sha": "abc1234",
          "subject": "인덱싱 파이프라인 구현",
          "date": "2026-04-20",
          "branch": "main"
        }
      ],
      "prs_done": [
        {
          "number": 42,
          "title": "...",
          "body": "...",
          "state": "merged",
          "merged_at": "2026-04-21T..."
        }
      ],
      "prs_open": [
        {"number": 45, "title": "...", "draft": false}
      ],
      "issues_closed": [{"number": 10, "title": "..."}],
      "issues_open": [{"number": 11, "title": "..."}]
    }
  ],
  "skipped_repos": [
    {"name": "edu_ai", "reason": "gh access denied (account mismatch)"}
  ]
}
```

## 주요 동작 규칙

### R1. 작성자 필터

각 레포마다 `git config user.email`을 읽어 본인 커밋 판별. `~/.gitconfig`의 `includeIf "gitdir:..KT/"` 설정 덕분에 디렉토리별로 올바른 이메일이 자동 반영된다 (개인 레포: `jfhdzzang@gmail.com`, 회사 레포: `hr.son@kt.com`).

### R2. 커밋 범위

- `git log --all --no-merges --author=<me_email> --since=<since> --until=<until>`
- `--all`로 로컬 실험 브랜치까지 포함 (`--remotes` 제한은 걸지 않음)
- 머지 커밋은 제외

### R3. PR-커밋 중복 제거

PR 객체의 commit sha 리스트와 커밋 리스트를 비교하여, PR로 이미 대표되는 커밋은 중복 bullet으로 만들지 않는다. PR이 없는 직접 커밋만 따로 bullet화.

### R4. 이번주 성과 요약 (LLM 지시)

- Merged/closed PR → 제목 기반 bullet 1개씩
- PR에 속하지 않은 직접 커밋 → 의미 단위로 묶어 1~2개 bullet (많으면 생략)
- `wip`, `fix typo`, `lint`, `chore: format`, `merge branch` 같은 노이즈 커밋은 LLM 판단으로 드롭
- Closed issue → "이슈 #N 해결: 제목" 형태

### R5. 다음주 계획 후보

- Open PR → "[진행중] PR #N 제목" (draft면 "[초안]")
- Open assigned issue → "[이슈] #N 제목"
- 요약하지 않고 그대로 나열 (사용자가 확정할 수 있도록)

### R6. gh 다중 계정 자동 처리

레포 owner를 보고 토큰 우선순위를 정한다. 실패 시 반대 토큰으로 fallback:

```bash
# 두 토큰을 미리 로드
KT_TOKEN=$(gh auth token --user hr-son_ktopen)
PERSONAL_TOKEN=$(gh auth token --user raki-1203)

# owner 기반 우선순위 결정
case $OWNER in
  raki-1203|heegene-msft|kimcy)
    PRIMARY=$PERSONAL_TOKEN; SECONDARY=$KT_TOKEN ;;
  *)
    PRIMARY=$KT_TOKEN; SECONDARY=$PERSONAL_TOKEN ;;
esac

# 우선 토큰으로 시도 → 실패 시 반대로 재시도
GH_TOKEN=$PRIMARY gh pr list -R $OWNER/$REPO ... \
  || GH_TOKEN=$SECONDARY gh pr list -R $OWNER/$REPO ... \
  || record_skipped "$REPO" "both accounts denied"
```

개인 레포는 처음부터 개인 토큰으로, 회사 레포는 회사 토큰으로 가서 대부분 1회 호출로 끝난다. 활성 계정 상태는 건드리지 않는다.

협업 계정(`heegene-msft`, `kimcy`)처럼 개인 토큰이어야 하는 owner 패턴이 추가되면 `case` 분기만 수정하면 된다. MVP 범위에서는 현재 사용자의 레포 리스트(workspace/kt 하 13개)만 정상 동작하면 충분.

### R7. 기간 기본값

- `--since` 없으면: `date -v-7d +%Y-%m-%d` (macOS)
- `--until` 없으면: `date +%Y-%m-%d`
- 주차: `date +%G-W%V` (ISO week, 예 `2026-W17`)

### R8. 덮어쓰기 정책

같은 주에 여러 번 실행 시:
- 기존 `2026-W17.md`가 있으면 → `2026-W17-2.md`, `2026-W17-3.md` ... 로 저장
- `--force` 플래그로 덮어쓰기 허용

## 출력 포맷 예시

```markdown
# 주간 업무 기록 - 2026-W17 (2026-04-17 ~ 2026-04-23)

## kt-innovation-hub-2

**이번주 성과**
- 인덱싱 파이프라인 구현 (#42)
- 마스터/서브에이전트 기본 클래스 설계 (#38)
- 데모 UI 디버그 모드 추가 (a1b2c3)

**다음주 계획 후보**
- [진행중] 챗봇-에이전트 인터페이스 (#45)
- [이슈] 툴 서버 연동 테스트 (#52)

## azure_native_architecture

**이번주 성과**
- Retriever 평가 메트릭 추가 (#12)

**다음주 계획 후보**
- [초안] 하이브리드 검색 파이프라인 (#15)

---
_스킵된 레포: edu_ai (gh 접근 권한 없음)_
```

## 에러 처리

| 케이스 | 처리 |
|--------|------|
| `gh`, `jq`, `yq` 중 누락 | 명확한 에러 + `brew install` 안내. `/rakis:setup` 재실행 권유 |
| gh 인증 실패 (양쪽 계정 모두) | 해당 레포를 `skipped_repos`에 기록하고 계속 진행 |
| 전체 레포가 skip됨 | "gh 계정 점검 필요" 경고 + 커밋 데이터만으로라도 리포트 생성 |
| CWD 아래 git 레포 0개 | "이 위치엔 레포가 없습니다. workspace 루트에서 실행하세요" 에러 |
| CWD 자체가 git 레포 | 그 레포 하나만 처리 (focus mode) |
| 본인 활동 0건 | "이번 주 기록된 활동이 없습니다" 메시지, 파일 저장 skip |
| 출력 파일 이미 존재 | `-2`, `-3` 서픽스로 새 파일 저장 (`--force`로 override) |

## 의존성

`rakis` 플러그인의 `/rakis:setup`에 다음 항목을 추가한다:

| 도구 | 체크 | 설치 |
|------|------|------|
| `jq` | `command -v jq` | `brew install jq` |
| `yq` | `command -v yq` | `brew install yq` |

`gh`, `git`은 기존 setup 또는 기본 환경에 이미 있음.

## 테스트 전략

- **자동화 없음** (계정/레포 상태 의존적이라 mock 비용이 이득 대비 큼)
- **수동 검증**:
  1. `bash collect_weekly.sh --root ~/workspace/kt` 돌려서 JSON 파싱 가능 여부 확인
  2. 활성 계정 미접근 레포가 `skipped_repos`에 들어가는지 확인
  3. 2026-04-23 실사용 → 결과 마크다운의 복붙 품질 확인
- 프롬프트 튜닝은 실사용 결과를 보고 SKILL.md에서 조정

## 향후 확장 (YAGNI로 지금은 제외)

- Obsidian 볼트 통합 (wiki/weekly-reports/)
- 표 형태 출력 옵션
- 팀 전원 리포트 모드 (`--all`)
- 레포 → 프로젝트 표시명 매핑

## Open Questions

없음 (브레인스토밍에서 모두 해소).
