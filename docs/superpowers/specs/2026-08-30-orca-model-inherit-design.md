# Orca 동적 모델 상속 디자인

**Date**: 2026-08-30  
**Status**: Spec (설계 승인 후 구현 예정)  
**Target**: Claude Code 전역 hook과 Orca local runtime 연동

## 목표

Claude Code Main 세션에서 실행하는 Orca의 두 작업 경로가 Main 세션의 현재 모델을 그대로 사용하도록 한다.

- `gpt-*` 모델: `claude-codex` loopback proxy를 통해 Codex OAuth provider 사용
- `claude-*` 모델: Anthropic provider 사용
- Main 세션의 현재 모델이 바뀌면 다음 Orca launch도 새 모델을 사용
- 사용자가 명시한 모델을 GPT나 Claude로 임의 강제하지 않음

여기서 현재 모델은 settings의 기본값이 아니라, 해당 Main 세션 transcript의 최신 assistant `message.model` canonical ID를 뜻한다.

## 배경과 확인된 제약

[High] 현재 Native Claude Code `Agent`는 `PreToolUse:Agent`의 `updatedInput`으로 명시적 `model` 필드를 제거하면 부모 모델을 상속한다.

[High] Orca daemon은 Main Claude Code 프로세스와 별도 프로세스이며, Main 프로세스의 `ANTHROPIC_BASE_URL`을 자동 상속하지 않는다.

[High] Orca `orchestration worker-start`는 새 agent launch에 `--model <id>`를 제공하지만, `--terminal`과는 함께 사용할 수 없다.

[High] Orca `worktree create --agent <id>`는 `--model`을 제공하지 않는다. Claude TUI agent의 launch command는 `claude`로 고정되어 있다.

따라서 단일 `ANTHROPIC_BASE_URL` export만으로는 두 Orca 경로 모두의 모델·provider 상속을 보장할 수 없다.

## 범위

### 포함

1. Claude Code `PreToolUse:Bash` hook에서 Main 세션의 현재 모델을 결정
2. 직접 실행되는 단순 `orca orchestration worker-start` 명령의 Claude agent model override를 현재 모델로 교체
3. 직접 실행되는 단순 `orca worktree create --agent claude` 명령을 전용 bridge로 연결
4. bridge가 새 worktree를 먼저 만들고, 해당 worktree에 명시적 모델·provider 환경을 가진 Claude terminal을 생성
5. Orca가 직접 `claude`를 실행하는 경우 GPT 모델만 loopback proxy로 연결하는 Orca 전용 launcher shim
6. 지원하지 않는 모델, 복잡한 shell command, 잘못된 입력은 원래 명령을 유지하는 fail-open 동작
7. hook·bridge·shim의 로컬 테스트와 실제 throwaway worktree smoke test

### 제외

- Orca 앱의 `app.asar` 또는 runtime binary patch
- Orca daemon의 undocumented 설정·database 직접 수정
- `CLAUDE.md`, 기존 skill, 기존 rakis skill의 내용 변경
- 자동 provider fallback 또는 quota 감지
- 일반 terminal에서 수동으로 실행한 Orca 명령의 모델 추정
- `--terminal`로 이미 존재하는 terminal의 모델 변경
- Orca의 다른 TUI agent(`codex`, `cursor` 등) 변경

## 아키텍처

```text
Claude Code Main
  │
  ├─ PreToolUse:Bash payload
  │    ├─ transcript_path에서 current model 읽기
  │    ├─ 단순 Orca command인지 확인
  │    └─ updatedInput.command 생성 또는 no-op
  │
  ├─ orchestration worker-start
  │    └─ --model <current model> 주입
  │         └─ Orca 전용 claude launcher가 gpt-*에 proxy 환경 추가
  │
  └─ worktree create --agent claude
       └─ orca-worktree-model-bridge
            ├─ worktree create (--agent/--prompt 분리)
            ├─ 결과 JSON에서 worktree path 추출
            └─ terminal create
                 └─ env ... claude --model <current> --prefill <prompt>
```

hook은 shell command 전체를 실행하지 않고 `updatedInput`만 반환한다. 실제 Orca 호출은 bridge가 배열 인자로 수행하며 `eval`을 사용하지 않는다.

## 현재 모델 결정

hook은 다음 순서로 현재 모델을 찾는다.

1. 입력 JSON의 `transcript_path`가 읽을 수 있는 일반 파일인지 확인
2. JSONL transcript에서 `message.role == "assistant"`인 레코드의 `message.model`을 순서대로 확인
3. 빈 값과 `<synthetic>`을 제외하고, `gpt-*` 또는 `claude-*`로 시작하는 canonical model ID만 남긴다.
4. 남은 값 중 가장 마지막 model을 선택한다.
5. 유효한 model이 하나도 없으면 no-op한다.

`[1m]` suffix는 모델 ID의 일부로 보존한다. provider 판정 시에는 suffix를 제거한 값으로 비교한다.

현재 모델을 settings의 `model` 값이나 `CLAUDE_CODE_SUBAGENT_MODEL`에서 추정하지 않는다. 이렇게 해야 `/model`로 중간에 바뀐 Main 세션과 일치한다.

## Hook 계약

예상 파일: `scripts/orca-model-inherit.sh`

입력은 Claude Code `PreToolUse` JSON이며, hook은 다음 외의 필드를 읽지 않는다.

- `.tool_name`
- `.tool_input.command`
- `.transcript_path`
- hook 실행 환경의 `ANTHROPIC_BASE_URL`은 loopback 여부를 판단할 때만 읽는다.

대상 command는 공백으로 시작하지 않는 단일 command인 경우에만 처리한다.

### `worker-start`

다음 조건을 모두 만족할 때만 처리한다.

- command가 `orca orchestration worker-start`로 시작
- `--agent claude`가 존재
- `--terminal`이 없음
- current model이 `gpt-*` 또는 `claude-*`
- 기존 `--model`이 있으면 제거 가능한 일반 flag 형태

결과 command는 기존 flag 순서를 최대한 보존하고 `--model <current model>`을 한 번만 포함한다. 기존 `--effort`, worktree, task, setup flag는 변경하지 않는다.

### `worktree create`

다음 조건을 모두 만족할 때만 bridge로 교체한다.

- command가 `orca worktree create`로 시작
- `--agent claude`가 존재
- `--agent`가 다른 agent ID이거나 둘 이상이면 no-op
- shell operator(`&&`, `||`, `;`, `|`, redirection) 또는 command substitution이 없음
- current model이 `gpt-*` 또는 `claude-*`

변경된 command는 bridge에 parsed argv와 current model을 전달한다. 그 밖의 command는 변경하지 않는다.

### 실패 동작

- JSON 파싱 실패
- transcript 누락·읽기 실패
- 모델 누락·지원되지 않는 모델
- 명령이 복잡하거나 flag 구조가 해석되지 않음
- `jq`, `base64`, `orca` 등 필수 의존성 누락

위 상황에서는 stdout에 오류를 쓰지 않고 exit 0으로 종료하며 `updatedInput`을 반환하지 않는다. Claude Code는 원래 Bash command를 실행한다.

## Worktree bridge

예상 파일: `scripts/orca-worktree-model-bridge.sh`

bridge는 hook이 전달한 모델과 parsed argv를 사용한다.

### 생성 단계

1. GPT 모델인 경우 loopback proxy가 `127.0.0.1:18765`에서 listen 중인지 확인한다. proxy가 없으면 bridge를 실행하지 않고 실패 전에 원래 명령으로 돌아갈 수 있도록 hook이 no-op한다.
2. `--agent claude`와 `--prompt`를 원래 생성 flag에서 분리한다.
3. `orca worktree create`를 `--json`으로 실행한다.
4. 결과의 `.result.worktree.path` 또는 runtime이 제공하는 동등한 worktree path를 검증한다.
5. 원래 `--setup`, `--base-branch`, `--repo`, parent, issue, activate, run-hooks 등 생성 관련 flag는 그대로 전달한다.
6. `--prompt`가 있으면 Claude launch command의 `--prefill` 인자로 전달한다.

### terminal 단계

새 worktree path에 대해 다음 형태의 command를 생성한다.

```text
env ANTHROPIC_BASE_URL=http://127.0.0.1:18765 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 claude --model <current> [--prefill <prompt>]
```

- `gpt-*`: loopback proxy 환경을 반드시 붙인다.
- `claude-*`: Main hook 환경이 loopback proxy를 사용 중이면 같은 loopback 환경을 붙이고, 아니면 기본 Anthropic 환경을 사용한다.
- 외부 host의 `ANTHROPIC_BASE_URL`은 복사하지 않는다.
- 모델·prompt는 shell quoting을 거쳐 하나의 terminal command로 전달한다.

`orca terminal create --worktree path:<path> --command <command> --json`을 실행한다. terminal 생성이 실패하면 생성된 worktree를 삭제하지 않는다. bridge는 worktree path와 실패 원인을 보고하고, 자동 삭제나 강제 rollback을 시도하지 않는다.

원래 `--json`이 없으면 worktree show 결과와 terminal handle을 사람이 읽을 수 있는 형태로 출력한다. 원래 `--json`이면 다음 envelope을 출력한다.

```json
{
  "worktree": {"...": "original worktree result"},
  "terminal": {"...": "created terminal result"}
}
```

## Orca Claude launcher shim

예상 파일: `scripts/claude-orca-launch.sh`

`.zshrc`에는 Orca agent terminal에서만 이 shim을 거치는 함수가 추가된다. 일반 shell의 `claude` 호출은 바꾸지 않는다.

shim은 `--model` 값을 확인한다.

- `gpt-*`이고 proxy가 listen 중이면 `ANTHROPIC_BASE_URL=http://127.0.0.1:18765`와 `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`을 설정한 뒤 실제 Claude binary를 실행한다.
- `claude-*` 또는 model flag가 없으면 기존 환경으로 실행한다.
- proxy가 없으면 기존 command를 변경하지 않는다.

실제 binary 호출은 shell function 재귀를 피하기 위해 절대 경로 또는 `command` lookup을 사용한다. shim은 `ORCA_AGENT_LAUNCH_TOKEN` 또는 Orca가 제공하는 동등한 launch marker가 있는 terminal에서만 동작한다.

이 shim은 worker-start의 `--model`이 runtime을 통해 새 Claude terminal에 전달된다는 Orca documented contract에 의존한다. runtime이 model flag를 command에 전달하지 않는 경우 worker-start는 자동 상속 대상으로 보고하지 않고, smoke test가 실패한다.

## 안전성

- 고객 자료·prompt 전문을 로그나 외부 서비스로 보내지 않는다.
- proxy 주소는 loopback `127.0.0.1:18765`만 허용한다.
- `eval`, 임의 command substitution, 사용자 prompt의 shell 재해석을 사용하지 않는다.
- hook은 `orca` 호출 성공 여부를 기다리거나 자동 재시도하지 않는다.
- ambiguous command는 수정하지 않는다.
- bridge가 worktree를 만든 뒤 terminal 생성에 실패해도 파일 삭제를 시도하지 않는다.
- commit·push·GitHub 업로드를 수행하지 않는다.

## 테스트 전략

### 단위 테스트

`scripts/orca-model-inherit.sh`에 synthetic `PreToolUse:Bash` payload를 제공한다.

1. GPT transcript + worker-start → `--model gpt-*` 한 번
2. Claude transcript + worker-start → `--model claude-*` 한 번
3. 기존 model flag → current model로 교체
4. `--terminal` → no-op
5. `worktree create --agent claude` → bridge command로 교체
6. prompt와 특수문자 → shell injection 없이 보존
7. compound command → no-op
8. unknown model → no-op
9. transcript 누락·잘못된 JSON → no-op
10. 일반 Bash/일반 Orca agent → no-op

### Mock integration

실제 Orca daemon을 호출하지 않는 fake `orca` executable을 `PATH` 앞에 두고 다음을 검증한다.

- worktree create argv에서 `--agent claude`·`--prompt` 분리
- 모든 생성 flag 보존
- create JSON의 path를 terminal create에 전달
- 모델·provider 환경이 terminal command에 정확히 포함
- create 또는 terminal failure 시 exit code와 잔여 리소스 보고

### 실제 smoke test

사용자 자료가 없는 throwaway Git repository에서 한 번씩 실행한다.

- GPT Main model → Orca worker-start 및 worktree create의 Claude process command line 확인
- Claude Main model은 Claude weekly limit이 허용될 때 provider 확인
- proxy log에서 GPT 요청의 `provider: codex` 확인
- 일반 Bash와 non-Claude agent command가 동일하게 유지되는지 확인

실제 smoke test가 끝난 뒤 throwaway worktree와 process를 정리하되, KB카드·고객 자료가 있는 worktree에서는 실행하지 않는다.

## 성공 기준

- Main의 canonical model이 `gpt-5.6-luna`일 때 두 Orca 경로 모두 `claude --model gpt-5.6-luna`을 실행하고 loopback proxy를 사용한다.
- Main의 canonical model이 `claude-*`일 때 두 Orca 경로 모두 같은 Claude model ID를 사용한다.
- proxy log에서 GPT 요청은 `provider: codex`, Claude 요청은 `provider: anthropic`으로 나타난다.
- 기존 `--model`을 지정한 Orca worker도 Main current model로 일관되게 교체된다.
- 해석할 수 없는 command는 원문 그대로 실행된다.
- `CLAUDE.md`, skills, 고객 자료, 외부 repository는 변경·업로드되지 않는다.
- 기존 task-router 테스트와 전체 plugin 테스트가 계속 통과한다.
