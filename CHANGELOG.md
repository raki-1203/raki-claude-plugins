# Changelog

## [3.12.0] — 2026-07-31

### Removed

- **graphify 의존성 전면 제거.** 실측 결과 위키 질의에서 index.md 폴백보다 나빴다.
  - 검증 방법: vault 전체(231 파일 / 162,677 단어)를 풀 리빌드해 1,430 노드·2,464 엣지·85 커뮤니티의 최신 그래프를 만든 뒤 동일 질의로 비교했다. "그래프가 오래돼서 그렇다"는 가설을 먼저 배제했다.
  - **실패 원인 ①** 시작 노드 선택이 라벨 부분문자열 매칭이라, 한국어 일반명사(`자동화`, `파이프라인`)가 무관 도메인의 긴 서술형 노드에 먼저 걸린다. "쿠팡파트너스 쇼츠 파이프라인" 질의가 `shopping-shorts` 페이지를 두고 국민카드 회의록만 반환했다.
  - **실패 원인 ②** BFS depth-3이 50~100 노드로 퍼진 뒤 같은 naive 점수로 정렬돼, 실제 관련 노드가 고차수 허브에 밀린다. 시작 노드가 정확했던 질의("Nextcloud 동기화 데이터 손실")조차 상위 출력에 해당 페이지가 하나도 없었다.
  - 노드가 늘수록 ①의 오탐 표면이 넓어지므로, **그래프를 최신화할수록 결과가 나빠지는** 구조였다.
  - 부수 효과: vault에서 빌드 산출물 500개(7.2MB)가 사라져 Nextcloud 동기화 대상이 줄었다.
- **`/rakis:wc-cp-graph`** — 워크트리 간 graphify 산출물 복사 전용 커맨드. 대상이 사라져 삭제.

### Fixed

- **`/rakis:setup`이 설치된 도구를 절대 업그레이드하지 않던 문제.** 문서는 "재실행하면 `--upgrade`로 최신화된다"고 했지만, 로직은 "모든 항목 ✓이면 단계 3을 건너뛰고 단계 6으로"였다. `command -v`가 통과하는 한 설치 명령이 한 번도 실행되지 않는다.
  - 실제 피해: `notebooklm-py` 0.3.4가 4개 마이너 버전 뒤처진 채 방치됐고, 그 사이 Google이 NotebookLM 도메인을 옮기면서 인증이 조용히 깨졌다. 0.3.4는 `notebooklm.google.com`을 호출하고 `notebook.google.com` 쿠키를 필터에서 제외해, 리다이렉트 후 OSID가 없어 로그인 페이지로 튕긴다. 재로그인·프로필 초기화로는 절대 해결되지 않는다.
  - 조치: **단계 2.5 신설** — 빠진 게 없어도 `uv tool upgrade --all`을 항상 실행. brew 패키지는 매번 돌리면 setup이 몇 분씩 걸려 제외(누락 시에만 설치). 단계 2에서 현재 버전을 기록해 단계 9 요약에 `0.3.4 → 0.7.3` 형태로 표기.
- **`test.sh`가 노트북을 고아로 남기던 문제.** UUID 추출 `grep -oE`에 `head -1`이 없어, notebooklm-py 0.7.3이 `create` 출력에 추가한 `Tip: ... run 'notebooklm use <id>'` 줄까지 잡아 `NB_ID`에 개행이 섞였다. 그 값으로 `notebooklm use`를 부르면 실패 → `set -e`가 스크립트를 죽여 정리 단계가 실행되지 않는다. 2026-04-21자 잔해까지 확인됨.

### Changed

- `wiki-query`: 폴백이던 index.md 경로를 기본 경로로 승격. 탐색형(1-A-2)은 프로젝트 컨텍스트와 index.md `description`을 대조해 직접/간접/잠재 3분류하고, `related:`를 **한 단계만** 따라간다(허브 경유 오염 방지). 관계성 질문은 양쪽 `related:`의 교집합을 쓰고, 교집합이 비면 연결을 지어내지 말고 "위키상 직접 연결 없음"으로 답한다. 보완 수단은 본문 grep.
- `wiki-ingest`·`wiki-wrap-up`·`wiki-lint`·`wiki-init`: 각 스킬 말미의 그래프 빌드/업데이트 안내 단계 삭제.
- `migrate-v3`: v3 풀 빌드 단계 삭제. 레거시 `graphify-out/` 정리 안내만 남김.
- `/rakis:setup`: 의존성 목록에서 graphify 제거.
- `test.sh`: `test_graphify()` 및 `./test.sh graphify` 타깃 삭제.

## [3.11.0] — 2026-07-21

### Changed

- **`source-fetch`가 SNS·랜딩페이지 첨부 이미지를 확인하도록 함**. WebFetch는 텍스트만 추출해 수익 인증 스크린샷·헤드라인 배너·계정 캡처 등 이미지 전용 정보(수치, 증거와 주장의 모순)를 놓치는 문제가 있었다.
  - `references/fetchers.md`: "첨부 이미지 확인(SNS·랜딩페이지 필수)" 섹션 추가 — 이미지 존재 신호 확인 → Chrome 브라우저 자동화로 스크린샷 → `raw/{slug}/images/`에 저장 → `source.md`에 반영하는 절차 명시. 텍스트만으로 "콘텐츠 없음" 판단 금지.
  - "LinkedIn / X (Twitter)" 섹션을 "LinkedIn / X (Twitter) / Threads / Facebook"으로 확장, `platform` 메타에 `threads`·`facebook` 추가.
  - `SKILL.md` Phase 2 요약에 이미지 확인 필수 문구 추가.

## [3.10.0] — 2026-07-13

### Changed

- **`meeting-digest` 화자 분리 엔진을 pyannote.audio(PyTorch) → senko(Apple 네이티브 CoreML)로 교체**. HF 토큰·gated 모델 약관 동의가 사라져 활성화 장벽 제거, torch(~2GB) 대신 CoreML로 경량화, M3 기준 1시간 오디오 ~7.7초로 대폭 빠름.
  - `scripts/diarize.py`: `senko.Diarizer(device='auto')` 사용으로 재작성. merge 로직(`assign_speakers`/`relabel`/`to_speaker_text`)은 그대로 유지 — senko `merged_segments`(`SPEAKER_01` 문자열)를 시간 겹침으로 `transcript.json` 세그먼트에 배정. ffmpeg는 16kHz mono **16-bit** wav로 변환(senko 입력 규격). torch/soundfile 의존성 제거. HF 토큰 로직(exit 5)·`--num-speakers`·`--hf-token` 인자 제거(senko는 화자 수 자동 추정).
  - `scripts/diarize.sh`: `PYTORCH_ENABLE_MPS_FALLBACK` 제거(torch 미사용).
  - `SKILL.md`(1.3.0 → 1.4.0): Phase 3.5 실행 조건에서 HF 토큰 요건 삭제(venv 존재만 확인). `--speakers` 옵션 제거. exit 5 처리 삭제.
  - `/rakis:setup` 단계 6.5: `uv venv --python 3.13` + `uv pip install senko`로 변경, HF 토큰/gated 약관 안내 삭제.

## [3.9.0] — 2026-07-13

### Added

- **`meeting-digest` 화자 분리(diarization) 추가** — 회의록에 "누가 말했는지" 실제 화자 라벨을 붙임 (기존엔 문맥 추측만 가능).
  - `scripts/diarize.py`: pyannote.audio 4.x(`pyannote/speaker-diarization-community-1`)로 화자 구간 추출 → `transcript.json` 세그먼트와 시간 겹침으로 라벨 배정 → `transcript.speakers.{txt,json}` 생성. `--self-check`로 배정 로직 단위검증.
  - `scripts/diarize.sh`: 격리 venv(`~/.local/share/rakis/diarize-venv`) 호출 wrapper. venv 없음 → exit 2, 토큰 없음 → exit 5.
  - 격리 venv(Python 3.12)에 pyannote 설치 — 시스템 mlx_whisper(3.14) 환경과 분리. torchcodec/ffmpeg 버전 불일치는 ffmpeg CLI→soundfile waveform 직접 로드로 우회(pyannote 공식 권장 경로).
  - `SKILL.md`(1.2.0 → 1.3.0): Phase 3.5 화자 분리 단계. venv+HF 토큰 있으면 **자동 실행**, 없으면 조용히 건너뜀(회의록은 정상 생성). `--speakers N`(화자 수 힌트)·`--no-diarize` 옵션. Phase 4는 `transcript.speakers.txt` 우선 사용.
  - `/rakis:setup` 단계 6.5: 화자 분리 venv 설정(선택, opt-in) + HF 토큰/gated 모델 약관 동의 안내.

## [3.7.0] — 2026-06-09

### Changed

- **`meeting-digest` 전사 엔진을 `faster-whisper`(whisper-ctranslate2) → `mlx-whisper`(Apple MLX)로 교체**. M4 Pro 실측에서 동일 large-v3 가중치 기준 ~11.5배 빠름(180s 클립: 177.5s → 15.5s, RTF 0.99 → 0.086), RAM도 더 적고 품질 동급.
  - `transcribe.sh`: `mlx_whisper` 호출로 재작성. short name(large-v3, medium…) → `mlx-community` HF repo 자동 매핑. `--output-name transcript`로 `transcript.{txt,json,srt}` 직접 생성. `--compute-type` 인자는 하위호환용으로 받되 무시.
- **`/rakis:setup` 의존성 `whisper-ctranslate2` → `mlx-whisper`** (`command -v mlx_whisper`, `uv tool install --upgrade mlx-whisper`).
- **`/rakis:help`, `SKILL.md` 문구를 mlx-whisper 기준으로 갱신** (SKILL version 1.0.0 → 1.1.0).
- **회의록 frontmatter에 `title`/`type: meeting` 추가** (Phase 4 형식 + 작성 규칙). vault frontmatter 검증(title/type 필수) 통과.

## [3.6.0] — 2026-05-12

### Added

- **`meeting-digest` 스킬 추가**: 회의 녹음 파일을 받아 faster-whisper(`whisper-ctranslate2`)로 한국어 전사 후 LLM이 구조화된 회의록(안건/주요 논의/결정사항/액션 아이템/미해결 이슈)으로 정리해 Obsidian vault에 저장.
  - 호출: `/rakis:meeting-digest <audio> --project <name> [--title ...] [--date ...] [--model large-v3|medium] [--attendees ...]`
  - 저장 구조 (프로젝트별):
    - `raw/meetings/{project}/{date}-{slug}/audio.{ext}` (원본 immutable)
    - `raw/meetings/{project}/{date}-{slug}/transcript.{txt,json,srt}` (전사)
    - `wiki/meetings/{project}/{date}-{slug}.md` (구조화 회의록)
  - `wiki/projects/{project}.md` 가 있으면 "## Meetings" 섹션에 회의록 링크 자동 추가
  - `transcribe.sh` 래퍼 스크립트로 whisper-ctranslate2 호출 (compute_type=int8, Apple Silicon 친화)
- **`/rakis:setup` 의존성에 `whisper-ctranslate2`, `ffmpeg` 추가**. 첫 실행 시 large-v3 모델 ~3GB 다운로드됨을 안내.
- **`/rakis:help` 에 meeting-digest 상세 블록 추가**.

## [3.5.2] — 2026-05-06

### Fixed

- `source-fetch` enrich 단계에서 대용량 repo(repomix.txt > 1.9MB)의 NotebookLM 업로드가 자동 분할되지 않던 문제 수정.
  - 기존: `enrich.md` "실행 순서"는 단일 업로드만 시도. "대용량 소스 분할" 섹션은 별도 문서로 존재했지만 자동 분기 없음 → 2MB 초과 시 400 Bad Request.
  - 수정: `repo` 분기에서 `stat`으로 사이즈 확인 → 1.9MB 초과 시 `split -b 1800k`로 자동 분할 + `.txt` 확장자 부여(NotebookLM "Unknown" 타입 회피) 후 순차 업로드.
  - macOS/Linux 양쪽에서 동작하도록 `stat -f%z` / `stat -c%s` fallback.

## [3.5.1] — 2026-04-30

### Changed

- `wc-cp-graph` 커맨드 정리: tracked 파일(`CLAUDE.md`, `.claude/settings.json`) 복사 단계 제거.
  - **이유**: 두 파일은 git에 tracked되어 있어 worktree 생성 시 브랜치에서 자동으로 함께 복사된다. 메인에서 덮어쓰면 브랜치별 차이가 사라지는 부작용이 있었음.
  - 대신 `graphify` PreToolUse 훅이 들어있는 **gitignored** 파일 `.claude/settings.local.json` 복사 단계 추가.
- 결과: worktree 생성 후 `/rakis:wc-cp-graph` 한 번이면 graphify 자동 사용 환경(`graphify-out/` + PreToolUse 훅)이 셋업됨.

## [3.5.0] — 2026-04-24

### Changed (⚠️ BREAKING)

- **Vault 경로 탐지 로직에서 iCloud default fallback 제거.** `OBSIDIAN_VAULT_PATH` 환경변수가 **필수**가 됐다. 미설정 시 모든 위키 스킬(`wiki-query`, `wiki-lint`, `wiki-ingest`, `wiki-wrap-up`, `source-fetch`)이 에러 메시지 출력 후 중단한다.
  - **이유**: 기존에는 env 누락 시 하드코딩된 iCloud 경로로 silent fallback 되어, vault 위치를 옮긴 사용자(iCloud → Nextcloud/Dropbox/로컬) 가 알아차리지 못한 채 구경로에 쓰는 사고 가능성이 있었음. "fail fast, fail loud" 원칙으로 전환.
  - **마이그레이션**: `~/.zshrc` 또는 `~/.bashrc` 에 `export OBSIDIAN_VAULT_PATH="$HOME/your/vault/path"` 추가 후 `source ~/.zshrc`. 대부분 사용자는 이미 설정돼 있어 영향 없음.
- `wiki-init` 스킬의 인터뷰 질문에서 "기본값 (iCloud Obsidian)" 문구 제거. 빈 입력 시 기본값으로 진행하지 않고 재질문.
- `README.md` setup 섹션 수정: env 필수임을 명시.
- `test.sh` 에서 `VAULT="${OBSIDIAN_VAULT_PATH:-...}"` 패턴 제거하고 env unset 시 명시적 실패.

## [3.4.1] — 2026-04-23

### Changed

- `weekly-report` 출력 포맷 개선 (v1.1.0):
  - 이번주 성과는 주제 단위로 묶어 bullet 1개 + PR 번호 나열로 압축 (20개 PR도 5~8 bullet로 수렴).
  - `다음주 계획 후보` → 세 개 섹션으로 분리:
    - `진행중 항목`: open PR/이슈 자동 + `— 목표: ____` 빈칸
    - `다음주 계획`: 빈 체크박스 3개 (수동 작성)
    - `이번주 일정`: 출장·외근·회의 등 수동 작성 안내

## [3.4.0] — 2026-04-23

### Added

- `weekly-report` 스킬 추가. `/rakis:weekly-report [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--force]`로 CWD 아래 git 레포를 순회해 지난 7일간 본인 커밋/PR/이슈를 수집·요약하고, `~/workspace/weekly-reports/YYYY-W##.md`에 저장.
- `skills/weekly-report/scripts/collect_weekly.sh`: 데이터 수집 스크립트. 다중 GitHub 계정(`hr-son_ktopen`/`raki-1203`)을 owner 기반 `GH_TOKEN` 우선순위 + fallback으로 자동 처리.
- `/rakis:setup` 의존성 체크에 `jq`, `yq` 추가.

## [3.3.0] — 2026-04-21

### Added

- `source-fetch` 스킬에 `--hint "<한 줄>"` 플래그 추가. NotebookLM `generate report` 호출 시 `--append`로 주입되어 briefing/study-guide가 해당 관점에 맞춰 생성된다.
- `meta.json` 스키마에 `domain_hint` 필드 추가 (선택, 재수집 이력 보존).

### Changed

- enrich 단계의 briefing/study-guide 생성 명령이 `DOMAIN_HINT` 환경변수 유무에 따라 `--append`를 조건부로 붙이도록 수정. mind-map은 해당 옵션 미지원이므로 힌트 무관.

## [3.0.0] — 2026-04-17

### BREAKING CHANGES

- `/rakis:source-analyze` 스킬 제거. `/rakis:source-fetch` + `/rakis:wiki-ingest` 2단계로 분리.
- Vault 구조 변경: `raw/`는 이제 LLM 분석 산출물을 저장하지 않음. 모든 enrich 결과는 `raw/{type}/{slug}/notebooklm/` 하위로 격리.
- frontmatter `confidence` 필드 제거.
- frontmatter `type` 필드가 enum으로 고정: `source-summary | project | concept | entity | comparison | index`.
- `Home.md` → `wiki/overview.md` 리네이밍.
- `outputs/` 디렉토리 추가 (lint 리포트 · archive-v2 · graph-report 시점 스냅샷).

### Added

- `source-fetch` 스킬: 외부 소스를 raw/에 저장. 임계값 기반 자동 NotebookLM enrich (briefing + study-guide + mindmap).
- `migrate-v3` 스킬: v2 → v3 1회성 자동 마이그레이션 (dry-run 지원).
- `wiki-init` 스킬 v3 스키마 반영 (overview.md · outputs/ · CLAUDE.md 스키마 자동 생성).
- `wiki-query --scope project` 플래그: 현재 프로젝트 범위로 탐색 한정.
- `wiki-lint` outputs/ 저장 + overview.md 통계 섹션 자동 갱신.
- 테스트 계층: 유닛 (slug, frontmatter) + golden (마이그레이션) + smoke E2E.

### Changed

- `wiki-ingest`: raw 전수 스캔 + 증분, index.md 기반 연결. `--full` 플래그로 전체 재컴파일 가능.
- `wiki-query`: overview.md를 index.md 이전에 먼저 참조 (답변형 분기).
- graphify 호출 target: `<vault>` → `<vault>/wiki` (코드 덤프 노이즈 제거).

### Migration

기존 v2.x 사용자는 **반드시** 다음 순서로 업그레이드:

```
/rakis:setup                  # v2 감지 시 자동으로 다음 단계 안내
/rakis:migrate-v3 --dry-run   # 영향 범위 확인
/rakis:migrate-v3             # 실제 실행
rm -rf "<vault>/graphify-out/"
cd "<vault>" && /graphify wiki  # v3 풀 빌드
```

## [2.5.2] — 2026-04-14

(이전 버전은 git history 참조)
