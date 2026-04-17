# migrate-v3 체크리스트

## Pre-flight 체크

1. 볼트 경로 존재 확인
2. `CLAUDE.md` 또는 `wiki/` 디렉토리 존재 → 실제 rakis 볼트 확인
3. 영향 예상:
   - `raw/repos/*/graph-report.md` 개수
   - `raw/repos/*/analysis.md` 개수
   - `confidence:` 라인 개수 (`grep -rc "^confidence:" wiki/`)
   - `Home.md` 존재 여부

## 경계 케이스

| 상황 | 대응 |
|------|------|
| Home.md와 wiki/overview.md가 모두 존재 | wiki/overview.md 우선, Home.md는 그대로 둠 |
| outputs/가 이미 존재 | 내용 건드리지 않고 그대로 둠 |
| raw/repos/*에 meta.json이 있음 | 덮어쓰지 않음 |
| confidence 필드가 중첩 YAML 내부에 있음 | top-level만 제거 (들여쓰기 있는 건 보존) |
| 마이그레이션 도중 실패 | 다음 재실행은 마커 없는 상태로 재개 (이미 이동된 파일은 건너뜀) |

## 디버깅

실패 시 다음 파일 확인:
- `outputs/archive-v2/` — 이동된 legacy 파일
- `log.md` 최상단 — 마이그레이션 기록 한 줄 있는지
- `.rakis-v3-migrated` — 성공 마커

마커가 없는데 실행되면 중단 없이 재시도되므로, 문제 해결 후 다시 호출.
