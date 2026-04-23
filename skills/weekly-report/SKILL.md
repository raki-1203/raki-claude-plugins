---
name: weekly-report
description: "주간 업무 보고서 초안을 자동 생성. 목요일 회의 전 '/rakis:weekly-report' 또는 '주간보고 만들어줘'라고 할 때 사용. CWD 아래 모든 git 레포에서 지난 7일간 본인 커밋/PR/이슈를 수집·요약해 마크다운으로 출력한다."
version: 1.0.0
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

### 4. 요약 생성 (Task 6에서 채움)

### 5. 마크다운 조립 (Task 7에서 채움)

### 6. 출력 + 저장 (Task 7에서 채움)
