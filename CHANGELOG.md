# Changelog

## [Unreleased]

### Added

- `wiki-query`: 판정형 질문("왜 뺐어", "지금 뭐 써?", "X 도입할까?")이면 `index.md` 보다 먼저 `verdicts.md` 를 읽는다. 판정이 있으면 "이미 판정됨"에서 답변을 시작해 모르고 재검토를 시작하는 것을 막고, `기각`(안 써보고 내린 판단)과 `제거`(써보고 내린 판단)를 구분해 전한다 — 재검토 가치가 다르기 때문. 판정이 없으면 "이력 없음"을 명시하고 일반 답변형으로 계속한다.
- `wiki-wrap-up`: 도구·접근 판정을 vault 루트 `verdicts.md` 색인에 기록. 판별 3조건(이름 붙는 대상 / 채택·기각·제거로 떨어짐 / 근거 페이지 존재)을 만족할 때만 올린다. 근거 본문은 상세 페이지에 그대로 두고 색인에는 한 줄과 링크만 둔다. 근거: WikiSkill(arXiv:2608.27454) `skill-impact.md` 대조 — `docs/superpowers/specs/2026-09-09-verdict-register-design.md`
- **Threads 작업 프롬프트 자동 라우터** — `UserPromptSubmit` hook이 요청 유형을 결정론적으로 분류해 7개 원문 중 하나만 `additionalContext`에 주입한다. 모호한 요청은 기존 동작을 유지한다.
- Orca `worker-start`와 `worktree create --agent claude`에 Main 세션 model/provider 상속 bridge 추가

### Fixed

- `wiki-lint`: `confidence` 누락을 데이터 갭으로 잡으면서 같은 파일의 v3 스키마 검사는 `confidence` 를 금지하던 자기모순 제거. 스캔 대상에 `wiki/projects/`·`wiki/meetings/` 추가(레거시 `projects/` 만 있어 현재 vault의 22개 페이지가 통째로 빠졌다). `meeting`·`deliverable` 이 정당하게 비우는 필드를 갭으로 오탐하지 않도록 타입별 예외표 추가.
- `wiki-ingest`: `description` "20자 이내" 규정 폐기. vault 실측 중앙값 65자이고 20자 이하는 5%뿐이며, 규정을 어긴 쪽이 실제로 유용했다. 색인 한 줄이 "페이지를 열지 말지"를 판단하게 해야 한다는 요구로 교체.

## [3.15.0] — 2026-08-24

### Added

- **`eli5` 스킬** — 코드·구조를 큰 그림과 적은 글의 단일 HTML 파일로 설명한다. 구현 전에 에이전트가 파악한 구조를 사람이 눈으로 검토하는 단계용.

  앤트로픽 공식 `eli5`([anthropics/claude-plugins-community](https://github.com/anthropics/claude-plugins-community/tree/main/eli5), Thariq Shihipar, MIT, 2026-08-21)를 그대로 쓰지 않은 이유: 공식판 `SKILL.md`는 **본문이 두 문장**이라 조사 지시도 검증 절차도 없다. 잘 정돈된 상자와 화살표는 정확하다는 인상을 주지만, 사실성은 무엇을 읽고 그렸는지에만 달려 있다.

  더한 것은 세 가지다.

  | 단계 | 강제하는 것 |
  |---|---|
  | Phase 0 조사 | 그림보다 먼저 코드·설정·문서·`git log`를 읽고 **"그림 요소 / 근거 / 등급" 표**를 만든다. 등급은 확인(코드에서 직접) · 해석(PR·이슈 근거 추론) · 미확인 |
  | Phase 1 생성 | 3등급을 CSS 클래스 색으로 구분(인라인 색 금지 — 테마 전환에 반응 안 함), 주장마다 `file:line`, 마지막 섹션은 "확인 못 한 것" |
  | Phase 2 검증 | **두 종류를 모두** — 구조·렌더링(브라우저로 실제 열어 잘림·겹침 확인)과 의미(조사 표와 그림 역대조). 표에 없는 상자는 지어낸 것이므로 삭제 |

  `--quick`으로 의미 검증을 건너뛸 수 있으나 출력과 HTML 양쪽에 미검증 표시를 남긴다.

  근거: [desty 블로그 60번](https://desty.github.io/blog/60-eli5-visual-explainer/)의 보강 조건 5개, [tt-a1i/archify](https://github.com/tt-a1i/archify)의 이단계 검증·CSS 클래스 색상 규칙.

## [3.14.1] — 2026-08-10

### Fixed

- **v3.14.0이 `--logprob-threshold -0.5`의 근거를 과장했다. 정정한다.** 회의 2건(2026-06-12 상담지원 워크샵 3구간 / 2026-08-07 자체 스프린트 리뷰 2구간)으로 재현 검증한 결과 **재현되지 않았다**.

  | 클립 | prod (-0.5) | 기본 (-1.0) | 우세 |
  |---|---|---|---|
  | A 600s | x55 / 100% | x55 / 100% | 무승부(둘 다 붕괴) |
  | A 2400s | x2 / 8.29% (1013자) | x2 / 8.41% (1142자) | **기본** |
  | A 4200s | x55 / 89.8% | x55 / 100% | prod |
  | B 300s | x22 / 38.6% | x22 / **34.3%** | **기본** |
  | B 1200s | x44 / 76.9% | x44 / **71.8%** | **기본** |

  5구간 중 3구간에서 기본값이 근소 우위였다. v3.14.0은 회의 **1건**에서 관찰된 것을 일반 사실처럼 적었다. 코드 동작은 그대로 두되(교체 근거도 약하다) 주석의 확신 수준을 낮췄다.

### Notes — 재현 검증 결과 (회의 3건 8구간 누적)

- **`--compression-ratio-threshold` no-op은 확정** — 8/8 구간에서 prod와 출력 바이트 동일. v3.14.0의 플래그 제거는 안전하다.
- **`--condition-on-previous-text False`는 근거가 더 강해졌다** — 8/8 구간에서 되돌리면 반복률 100%. 최악은 스프린트리뷰 5분 지점의 **최장반복 x873, 4282자 전부 환각**.
- **현행 파이프라인이 회의에 따라 크게 깨진다** — 새로 측정한 5구간 중 4구간에서 반복률 38~100%. `한국어 자막을 통해` ×44 같은 유튜브 자막 클리셰 루프가 나온다. 원본 기준 무음 비율은 0~7%라 **디지털 무음이 원인은 아니며, 검증된 설명은 아직 없다.**
- **Qwen3-ASR-1.7B 우위는 재현됐고 격차가 커졌다** — 같은 5구간에서 유효 전사량 2072 → 5043자(**+143%**). v3.14.0 시점 +31%보다 훨씬 크다.
- **v3.14.0의 "1.7B는 `--context` 유출 0건"도 틀렸다** — 한 클립만 보고 내린 결론이었다. 새 5구간 중 **2구간에서 유출**됐다(A 600s 6건, B 300s 4건). 유출은 모델 크기 문제가 아니라 어려운 구간에서 드러나는 Qwen `--context` 일반 위험이다. whisper `--initial-prompt`는 8/8 구간 유출 0건.

## [3.14.0] — 2026-08-08

### Fixed

- **`transcribe.sh`의 환각 억제 플래그 5개 중 3개가 아무 일도 안 하고 있었다.** 제거해도 출력이 바이트 단위로 동일함을 확인했다(국민카드 2026-06-17 워크샵 90분 지점 300초 클립, `diff` 완전 일치).

  | 제거한 플래그 | 이유 |
  |---|---|
  | `--no-speech-threshold 0.6` | mlx_whisper 기본값과 동일 → no-op |
  | `--compression-ratio-threshold 2.0` | 기본 2.4로 되돌려도 3구간 출력 완전 동일 → no-op |
  | `--hallucination-silence-threshold 2` | `transcribe.py`의 `if word_timestamps:` 블록 안에 있어 `--word-timestamps True` 없이는 **dead code** |

  "환각을 5중으로 막고 있다"는 착시만 걷어낸 것이고 동작 변화는 없다.

- **남은 2개는 실측으로 필수임을 확인.** `ablate_flags.sh`로 3구간(10·40·90분 지점) × 300초 × 6구성을 돌린 결과, 되돌리면 붕괴한다 — 최장 연속 반복 / 반복률:

  | 구성 | 600s | 2400s | 5400s |
  |---|---|---|---|
  | 현행 | x3 / 3.3% | x8 / 28.6% | x2 / 5.6% |
  | `--logprob-threshold`를 -1.0(기본)으로 | **x55 / 64%** | x8 / 28.6% | **x55 / 93%** |
  | `--condition-on-previous-text`를 True(기본)로 | x10 / 36% | x1 / 28.9% | **x74 / 100%** |

  5400s의 기본 구성은 반복률 100% — 2002자가 전부 환각이다. 근거를 스크립트 주석에 실측치로 박아뒀다.

### Added

- **STT 벤치·ablation 스크립트 4종** (`skills/meeting-digest/scripts/`). v3.7.0에서 제거했던 벤치를 되살리되 비교 대상을 Qwen3-ASR로 바꾸고, 품질 지표를 CER에서 **환각 루프 탐지**로 교체했다.

  - `bench_stt.sh` — mlx-whisper large-v3 vs Qwen3-ASR 1.7B/0.6B. 세 엔진 모두 production과 동일한 ffmpeg 전처리를 거친 같은 wav로 비교하고, 도메인 용어 힌트도 동등 투입(whisper `--initial-prompt` ↔ qwen `--context`). Qwen은 `/tmp/.qwen3-bench-venv`에 자동 격리 설치 — **torch/transformers를 안 끌어온다**(mlx+numpy+regex+hf-hub만)라 v3.10.0의 torch 제거 결정과 충돌하지 않는다.
  - `ablate_flags.sh` — 억제 플래그 leave-one-out 측정.
  - `bench_repeat.py` — 최장 연속 반복·반복률·고유 4-gram 비율.
  - `bench_cer.py` — 문자 불일치율 (v3.7.0 것 재사용).

### Notes

- **CER은 STT 품질 판정에 쓸 수 없다.** 이번 실측에서 CER은 Qwen3-1.7B를 기준 대비 59% "오류"로 표시했지만, 실제로는 기준인 whisper 쪽이 그 구간을 `그 다음 / 그런 / 그가 / 그의 아들이 ×3`으로 파괴한 것이었다. 서로 독립인 세 엔진(whisper 기본설정·Qwen 1.7B·Qwen 0.6B)이 같은 내용(`데이터 파이프라인이 있어야 되거든요`, `테이블에 대한 메타 정보가 쌓여야 되고`)으로 수렴해 실재 발화임이 확인됐다. `SKILL.md`에 경고를 남겼다.

- **엔진 교체는 아직 안 했다.** Qwen3-ASR-1.7B가 far-field 3구간 모두에서 유효 전사량 +31%(2794 → 3665자)에 환각 루프도 없지만 **4.6배 느리다**(147분 회의 10분 → 47분). Apache 2.0이라 라이선스 제약은 없다. 판단 보류.

- **Qwen3-ASR-0.6B는 부적합.** `--context`로 넣은 도메인 용어가 전사문에 그대로 유출된다(`그 다음에 이제 전 에이전트 아키텍처 인터페이스 파이프라인 …`). 1.7B와 whisper는 유출 0건.

## [3.13.1] — 2026-08-06

### Fixed

- **NotebookLM enrich가 항상 실패하던 경쟁 상태 수정.** `source add`는 업로드만 하고 반환하는데, 소스가 `status: preparing`인 상태에서 `generate report`를 부르면 서버가 CREATE_ARTIFACT에 null을 반환해 `Error: Report generation is unavailable`로 죽었다. enrich 절차에 `source wait` 단계가 처음부터 없었다.

  - `generate --wait`로는 해결되지 않는다 — `--wait`는 *생성* 완료를 기다리지 *소스 처리*를 기다리지 않는다.
  - 실측 A/B (동일 4.5MB PDF, 같은 노트북): `preparing`에서 ❌ / `source wait` 후 `ready`에서 ✅. 대기 비용은 **2.6초**였다.
  - 수정: `source add --json`으로 id를 수집해 생성 전에 전부 `source wait --timeout 300`. 타임아웃·실패 시 노트북을 정리하고 enrich만 건너뛴다(기존 skip 정책 유지).
  - 에러 문구가 "unavailable"이라 기능 차단·계정 게이팅으로 오해하기 쉬워, `enrich.md`에 실측 A/B 표와 함께 경고를 박아뒀다.

- **사내망(TLS 가로채기) 환경에서 enrich가 SSL 오류로 죽던 문제 대응.** KT 사내망은 TLS를 가로채며(리프 발급자 `CN=Kt Corporate Forward Trust CA ECDSA`), `curl`은 macOS 키체인 덕에 통과하지만 Python은 certifi만 봐서 실패한다. CLI는 이를 **"Cookies may be expired"로 잘못 안내**한다.

  - 원인이 두 겹이다. **CA 번들만으로는 안 고쳐진다** — 번들을 넣으면 에러가 `self-signed certificate` → `Missing Authority Key Identifier`로 바뀔 뿐이다. Python 3.13이 `VERIFY_X509_STRICT`를 기본 활성화하는데 KT CA 인증서에 RFC 5280의 SKI/AKI 확장이 없기 때문. 실측 5개 Google 호스트 × strict on/off에서 **ON 전부 실패 / OFF 전부 통과**, Python 3.12는 정상.
  - 수정 1: `enrich.md` 사전 조건에서 `~/.config/rakis/corp-ca-bundle.pem`이 있으면 **스킬 실행 중에만** `SSL_CERT_FILE`로 export(셸 전역 설정 아님). 번들 생성 절차도 문서화.
  - 수정 2: `commands/setup.md`의 notebooklm-py 설치를 **`--python 3.12`로 핀 고정**하고 제거 금지 사유를 명시.
  - 사내망 밖에서는 무해하다 — 번들은 certifi를 그대로 포함하고, 파일이 없으면 export 자체가 일어나지 않는다.
  - 참고: `uv` 자체도 같은 MITM에 막히므로(`invalid peer certificate: UnknownIssuer`) 설치 시 `--system-certs`가 필요하다.

## [3.13.0] — 2026-07-31

### Removed

- **NotebookLM enrich에서 `study-guide`·`mindmap` 생성 제거. briefing만 남긴다.** vault 실측(raw 소스 108개 / enrich 72개) 근거:

  | 산출물 | 생성 | 위키가 인용 | 판정 |
  |--------|-----:|-----------:|------|
  | briefing | 73 | 23 (32%) | 유지 |
  | study-guide | 73 | 21 (29%) | 제거 |
  | mindmap | 73 | 11 (15%) | 제거 |

  - **study-guide**: 분량의 **35.6%가 퀴즈(18.8%)와 서술형 질문(16.8%)** — 학습 장치지 위키 콘텐츠가 아니다. 26.7%는 briefing과 중복이고, 고유하게 쓸모 있는 건 용어 사전 21.2%뿐이었다.
  - **mindmap**: 어휘의 41%가 briefing에 없어 정보 자체는 중복이 아니다. 다만 인용률 15%로 워크플로에 읽는 단계가 없었다. 정보가 있어도 소비되지 않으면 비용만 남는다.
  - 참고로 **enrich 유무는 위키 페이지 품질을 가르지 못했다** (평균 3,210자 vs 3,113자, enrich 없는 `multica-ai-multica`가 상위권 / enrich 있는 `talecoco-com`이 하위권). briefing을 남긴 이유는 "품질을 올려서"가 아니라, 수백만 토큰 repomix에서 직접 읽어선 못 건질 사실(9-Wave 파이프라인·-15 LUFS·`ClipChannelGroupVectorSerializer` 등)을 뽑아주기 때문이다.
  - 부수 효과: 소스당 NotebookLM 생성 호출이 3회 → 1회로 줄어 수집 시간이 짧아진다.

### Changed

- `wiki-ingest`: 소스 페이지 작성 절차에서 study-guide 기반 "연관 질문" 섹션 제거. 과거 수집분에 남아 있는 산출물은 참고 가능하다고 명시.
- `source-fetch`: `--hint`는 이제 briefing에만 적용(mind-map `--append` 미지원 관련 주석 삭제). Mock 모드도 briefing 스텁만 생성.

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
