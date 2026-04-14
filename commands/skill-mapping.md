# 글로벌 CLAUDE.md에 추가할 rakis 스킬 매핑

`/rakis:setup` 단계 6에서 사용자가 동의하면 `~/.claude/CLAUDE.md`에 아래 섹션을 추가한다.

---

## Obsidian LLM Wiki

- **플러그인**: `rakis@raki-claude-plugins`
- **Vault 경로**: `~/Library/Mobile Documents/com~apple~CloudDocs/Documents/Vault`
- **구조**: Karpathy 3-Layer (raw/ → wiki/ → schema)

### 스킬 사용 (필수)

위키 관련 작업은 항상 rakis 플러그인 스킬을 사용한다. 직접 파일 조작은 스킬이 로드되지 않은 환경에서만.

| 상황 | 스킬 |
|------|------|
| 이전에 조사/저장한 내용 검색·질문 | `rakis:wiki-query` |
| URL·파일·repo 분석 | `rakis:source-analyze` |
| 새 지식을 위키에 저장 | `rakis:wiki-ingest` |
| 세션 마무리 시 학습 기록 | `rakis:wiki-wrap-up` |
| 위키 건강 점검 (주 1회) | `rakis:wiki-lint` |
| 프로젝트 코드 구조 분석 | `/graphify` (graphify 자체 스킬, setup에서 자동 설치) |
| vault 초기 세팅 (vault당 1회) | `rakis:wiki-init` |
| 플러그인 사용법 안내 | `/rakis:help` |
| 플러그인 의존성 설치 (최초 1회) | `rakis:setup` |

### Wrap-up → Wiki 규칙
작업 완료 시 (커밋, PR, 큰 태스크 마무리) 다음을 확인:
- 이 세션에서 **새로 알게 된 것** (도구, 패턴, 트러블슈팅)이 있는가?
- 위키에 아직 없는 내용인가?

해당되면 사용자에게 제안: "위키에 저장할까요? — {한 줄 요약}"
승인 시 wiki-ingest 스킬로 저장.
