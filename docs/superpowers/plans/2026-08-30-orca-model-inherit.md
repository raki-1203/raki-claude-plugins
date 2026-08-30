# Orca 동적 모델 상속 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Claude Code Main 세션에서 실행하는 Orca의 `worker-start`와 `worktree create --agent claude`가 Main 세션의 현재 모델과 provider 경로를 그대로 사용하게 한다.

**Architecture:** `PreToolUse:Bash` hook이 현재 세션 transcript의 최신 canonical model을 읽고, 직접 실행되는 단순 Orca 명령만 모델 bridge로 감싼다. Bridge는 `worker-start`의 `--model`을 교체하고, 모델 flag가 없는 `worktree create`는 worktree 생성과 명시적 Claude terminal 생성을 두 단계로 수행한다. Orca가 직접 실행하는 Claude binary에는 Orca terminal에서만 작동하는 launcher shim을 두어 `gpt-*` 요청에 loopback proxy 환경을 추가한다.

**Tech Stack:** Bash 3.2+, `jq`, `zsh`, `nc`, `base64`, Orca CLI 1.4.188, Claude Code `PreToolUse` hook, Codex OAuth proxy

**Spec:** `docs/superpowers/specs/2026-08-30-orca-model-inherit-design.md`

## Global Constraints

- `gpt-*` 모델은 `http://127.0.0.1:18765` loopback proxy를 통해 Codex OAuth provider를 사용한다.
- `claude-*` 모델은 Anthropic provider를 사용한다.
- 현재 모델은 settings 기본값이 아니라 transcript의 최신 assistant `message.model` canonical ID다.
- `worker-start`는 `--agent claude`이고 `--terminal`이 없을 때만 자동 모델 교체 대상이다.
- `worktree create --agent claude`는 worktree 생성 후 명시적 Claude terminal을 만드는 bridge 경로로 처리한다.
- 지원하지 않는 모델, 복잡한 shell command, 잘못된 입력은 원래 command를 유지하는 fail-open 동작을 한다.
- `eval`, 임의 command substitution, 사용자 prompt의 shell 재해석을 사용하지 않는다.
- proxy 주소는 loopback `127.0.0.1:18765`만 허용한다.
- 고객 자료·prompt 전문을 로그나 외부 서비스로 보내지 않는다.
- `CLAUDE.md`, 기존 skill, 기존 rakis skill의 내용을 변경하지 않는다.
- Orca 앱의 `app.asar`, runtime binary, undocumented database/config는 수정하지 않는다.
- `--terminal`로 이미 존재하는 terminal의 모델은 변경하지 않는다.
- commit·push·GitHub 업로드를 수행하지 않는다. 사용자 명시 승인 전 Git commit은 생략한다.
- 기존 task-router 테스트와 전체 plugin 테스트를 깨뜨리지 않는다.

---

### Task 1: 현재 모델 결정과 Orca command hook

**Files:**
- Create: `scripts/orca-model-inherit.sh`
- Test: `tests/unit/test_orca_model_inherit.sh`

**Interfaces:**
- Consumes: Claude Code `PreToolUse` JSON stdin의 `.tool_name`, `.tool_input.command`, `.transcript_path`와 hook 프로세스의 `ANTHROPIC_BASE_URL`
- Produces: 성공 시 `hookSpecificOutput.hookEventName == "PreToolUse"`와 `.updatedInput.command`를 가진 JSON, 그 외에는 빈 stdout와 exit 0
- Downstream contract: rewritten command는 `scripts/orca-worktree-model-bridge.sh --model <canonical-model> ...` 형식으로 실행되며, 원래 `orca` 뒤의 argv text를 그대로 보존한다.

- [ ] **Step 1: transcript fixture와 failing tests 작성**

`tests/unit/test_orca_model_inherit.sh`에서 임시 디렉터리에 다음 JSONL을 만든다.

```text
{"message":{"role":"assistant","model":"gpt-5.6-luna"}}
{"message":{"role":"assistant","model":"gpt-5.6-luna"}}
```

다음 입력을 각각 `scripts/orca-model-inherit.sh`에 전달하고 아직 구현되지 않았으므로 실패하게 만든다.

```json
{"tool_name":"Bash","tool_input":{"command":"orca orchestration worker-start --task task-1 --agent claude --model sonnet","description":"start worker"},"transcript_path":"/tmp/orca-gpt.jsonl"}
```

기대 assertion:

```bash
jq -e '
  .hookSpecificOutput.hookEventName == "PreToolUse" and
  (.hookSpecificOutput.updatedInput.command | contains("--model gpt-5.6-luna")) and
  (.hookSpecificOutput.updatedInput.command | contains("--model sonnet") | not)
' <<<"$out"
```

같은 fixture와 다음 회귀 입력도 추가한다.

```json
{"tool_name":"Bash","tool_input":{"command":"orca orchestration worker-start --task task-1 --agent claude","description":"start worker"},"transcript_path":"/tmp/orca-gpt.jsonl"}
{"tool_name":"Bash","tool_input":{"command":"orca orchestration worker-start --task task-1 --terminal term_1","description":"reuse terminal"},"transcript_path":"/tmp/orca-gpt.jsonl"}
{"tool_name":"Bash","tool_input":{"command":"orca worktree create --name task-1 --agent claude --prompt 'read only'","description":"create worktree"},"transcript_path":"/tmp/orca-gpt.jsonl"}
{"tool_name":"Bash","tool_input":{"command":"orca worktree create --name task-1 --agent codex","description":"create codex worktree"},"transcript_path":"/tmp/orca-gpt.jsonl"}
{"tool_name":"Bash","tool_input":{"command":"orca worktree create --name task-1 --agent claude && rm -rf /tmp/x","description":"compound command"},"transcript_path":"/tmp/orca-gpt.jsonl"}
{"tool_name":"Read","tool_input":{"file_path":"README.md"},"transcript_path":"/tmp/orca-gpt.jsonl"}
```

각 결과의 기대값은 순서대로 `rewritten`, `rewritten`, `empty`, `rewritten`, `empty`, `empty`다. `--terminal` 입력과 compound command는 반드시 빈 stdout이어야 한다.

Claude fixture도 만든다.

```text
{"message":{"role":"assistant","model":"claude-opus-5"}}
```

`worktree create --agent claude` 결과에 `--model claude-opus-5`가 들어가고, `gpt-*` 전용 proxy flag가 hook command에 직접 들어가지 않는지 검사한다. 모델이 다음과 같은 unsupported 값이면 빈 stdout이어야 한다.

```text
{"message":{"role":"assistant","model":"composer-2.5"}}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

실행:

```bash
bash tests/unit/test_orca_model_inherit.sh
```

예상 결과: `scripts/orca-model-inherit.sh`가 없어 `FAIL`이 발생한다.

- [ ] **Step 3: 최소 hook 구현**

`scripts/orca-model-inherit.sh`를 다음 동작으로 구현한다.

1. `jq`·stdin·JSON 파싱이 실패하면 즉시 exit 0
2. `.tool_name`이 `Bash`가 아니면 no-op
3. `.tool_input.command`가 `orca orchestration worker-start` 또는 `orca worktree create`로 시작하지 않으면 no-op
4. command를 single/double quote와 backslash를 추적하는 작은 scanner로 확인한다. quote 밖의 `[;&|<>]` operator와 `$(` command substitution은 no-op하고, quote 안의 prompt 문자(`$HOME`, `&&` 등)는 보존한다.
5. `transcript_path`가 regular file이 아니면 no-op한다.
6. 다음 jq filter로 assistant의 유효한 model 레코드만 읽고 마지막 값을 선택한다. `<synthetic>`, 빈 값, `composer-2.5` 같은 provider family 외 값은 filter 단계에서 제외한다.

```bash
MODEL=$(
  jq -r '
    select(.message?.role == "assistant" and
      (.message.model? | type == "string") and
      (.message.model | test("^(gpt-|claude-)")))
    | .message.model
  ' "$TRANSCRIPT" 2>/dev/null | tail -1
) || exit 0
[ -n "$MODEL" ] || exit 0
```

7. 모델에서 `[1m]` suffix를 분리한 family가 `gpt-*` 또는 `claude-*`가 아니면 no-op한다.
8. `gpt-*`인 경우 `nc -z 127.0.0.1 18765`가 성공할 때만 rewrite한다. `nc`가 없거나 proxy가 꺼져 있으면 원래 command를 보존한다.
9. `worker-start`는 `--agent claude`가 있고 `--terminal`이 없을 때만 rewrite한다.
10. `worktree create`는 정확히 하나의 `--agent claude`가 있을 때만 rewrite한다. `--agent=claude`도 허용하고, 다른 agent와의 중복은 no-op한다.
11. command의 첫 `orca` token만 bridge absolute path로 교체하고, `orca` 뒤의 원래 shell token text는 보존한다. 모델 ID는 `[A-Za-z0-9._:-]+(\[1m\])?`만 허용해 shell quoting 없이 안전하게 삽입한다.
12. 기존 `tool_input`의 다른 필드는 보존한다.
13. `chmod +x scripts/orca-model-inherit.sh scripts/orca-worktree-model-bridge.sh scripts/claude-orca-launch.sh`는 세 script가 모두 생성된 뒤 Task 4에서 실행한다.

성공 출력은 다음 구조로 제한한다.

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "updatedInput": {"command":"/absolute/path/scripts/orca-worktree-model-bridge.sh --model gpt-5.6-luna ..."},
    "additionalContext": "Orca model override replaced with the Main session model."
  }
}
```

- [ ] **Step 4: 단위 테스트 통과 확인**

실행:

```bash
bash tests/unit/test_orca_model_inherit.sh
PATH=/usr/bin:/bin bash tests/unit/test_orca_model_inherit.sh
```

예상 결과: 모든 hook·no-op·잘못된 transcript 테스트가 통과하고 두 실행 모두 exit 0이다.

- [ ] **Step 5: hook syntax와 diff 검증**

실행:

```bash
bash -n scripts/orca-model-inherit.sh
bash tests/unit/test_orca_model_inherit.sh
```

예상 결과: syntax error 0건, 테스트 failure 0건. 사용자 승인 전 commit은 하지 않는다.

---

### Task 2: Orca model bridge 구현

**Files:**
- Create: `scripts/orca-worktree-model-bridge.sh`
- Test: `tests/unit/test_orca_model_bridge.sh`

**Interfaces:**
- Consumes: `--model gpt-5.6-luna` 또는 `--model claude-opus-5` 뒤의 `worker-start`·`worktree create` argv
- Produces: 실제 `orca` 호출, worktree 경로에 대한 `orca terminal create`, 그리고 원래 `--json` 여부에 맞춘 출력
- Test seam: `ORCA_MODEL_BRIDGE_ORCA_BIN`이 설정되면 해당 executable을 사용하고, unset이면 `command -v orca`를 사용한다.

- [ ] **Step 1: fake Orca와 failing bridge 계약 테스트 작성**

`tests/unit/test_orca_model_bridge.sh`는 임시 `orca` executable을 만들고 argv와 환경을 파일에 기록하게 한다.

`worktree create` 응답 fixture는 다음 JSON을 stdout으로 출력한다.

```json
{"result":{"worktree":{"id":"wt-1","path":"/private/tmp/orca-smoke/task-1"}}}
```

`terminal create` 응답 fixture는 다음 JSON을 출력한다.

```json
{"result":{"terminal":{"handle":"term-1"}}}
```

다음 호출을 테스트한다.

```bash
ORCA_MODEL_BRIDGE_ORCA_BIN="$fake_orca" \
  bash scripts/orca-worktree-model-bridge.sh --model gpt-5.6-luna \
  orchestration worker-start --task task-1 --agent claude --model sonnet
```

fake argv에 다음이 정확히 있어야 한다.

```text
orchestration worker-start --task task-1 --agent claude --model gpt-5.6-luna
```

기존 `sonnet` model은 없어야 한다. `--terminal term-1` 입력은 bridge가 변경하지 않고 exit 0으로 no-op해야 한다.

다음 worktree 호출도 테스트한다.

```bash
ORCA_MODEL_BRIDGE_ORCA_BIN="$fake_orca" \
  bash scripts/orca-worktree-model-bridge.sh --model gpt-5.6-luna \
  worktree create --name task-1 --repo path:/private/tmp/orca-smoke \
  --agent claude --prompt 'read only: $HOME && do not edit' --json
```

기대값:

- 첫 호출: `worktree create --name task-1 --repo path:/private/tmp/orca-smoke --json`
- 두 번째 호출: `terminal create --worktree path:/private/tmp/orca-smoke/task-1 --command <launch> --json`
- `<launch>`에 다음 순서가 포함된다.

```text
env ANTHROPIC_BASE_URL=http://127.0.0.1:18765 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 claude --model gpt-5.6-luna --prefill 'read only: $HOME && do not edit'
```

prompt의 `$HOME`, `&&`는 bridge shell에서 다시 실행되지 않고 launch command의 단일 argument로 보존되어야 한다.

- [ ] **Step 2: failing 상태 확인**

실행:

```bash
bash tests/unit/test_orca_model_bridge.sh
```

예상 결과: bridge 파일이 없어 failure가 발생한다.

- [ ] **Step 3: worker-start bridge 구현**

다음 parsing 규칙을 사용한다.

```bash
MODEL=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --model)
      [ "$#" -ge 2 ] || exit 1
      MODEL="$2"
      shift 2
      ;;
    --model=*)
      MODEL="${1#--model=}"
      shift
      ;;
    *)
      break
      ;;
  esac
done
[ -n "$MODEL" ] || exit 1
```

실제 구현에서는 `--model`을 첫 option으로 읽은 뒤 `worker-start` 또는 `worktree create` subcommand를 판정한다. `$MODEL`이 `^(gpt-|claude-)[A-Za-z0-9._:-]*(\[1m\])?$`에 맞지 않으면 bridge를 호출하지 않고 exit 0한다. worker-start에서는 다음만 허용한다.

- argv에 `--agent claude` 또는 `--agent=claude`가 정확히 한 번 존재
- `--terminal`·`--terminal=*` 없음
- `--model`·`--model=*`는 기존 값과 무관하게 제거

나머지 argv를 배열로 보존한 뒤 마지막에 `--model "$MODEL"`을 한 번 추가하여 `ORCA_BIN orchestration worker-start ...`를 실행한다. `eval`은 금지한다.

- [ ] **Step 4: worktree two-phase bridge 구현**

`worktree create` parsing은 다음 flag만 bridge가 소비한다.

- `--agent` 또는 `--agent=claude`: 제거하고 값 저장
- `--prompt` 또는 `--prompt=<text>`: 제거하고 값 저장
- `--model` 또는 `--model=<id>`: 제거
- `--json`: 원래 요청 여부 저장

`--agent` 값이 claude가 아니거나 두 번 이상 나타나면 exit 0 no-op한다. 나머지 creation flag는 배열 순서대로 보존한다.

1. GPT model이면 bridge 시작 직전에 `nc -z 127.0.0.1 18765`를 다시 확인한다. 실패 시 `orca`를 호출하지 않고 exit 0한다.
2. `ORCA_BIN worktree create`에 `--json`을 한 번만 추가한다.
3. stdout JSON에서 다음 filter로 path를 얻는다.

```bash
WORKTREE_PATH=$(
  printf '%s' "$CREATE_JSON" \
    | jq -er '.result.worktree.path // .worktree.path // empty' 2>/dev/null
) || exit 1
```

4. path가 absolute path가 아니거나 `/`가 아니면 terminal을 만들지 않고 오류를 보고한다.
5. GPT model이면 고정된 loopback 환경을 launch command 앞에 붙인다. Claude model이면 hook 실행 환경의 `ANTHROPIC_BASE_URL`이 정확히 `http://127.0.0.1:18765`일 때만 같은 환경을 붙이고, 그 외에는 base URL을 생략한다.
6. model은 `--model gpt-5.6-luna`처럼 shell-safe 값만 허용한다. prompt는 `shell_quote`로 한 번만 quote하고 `--prefill`에 붙인다.
7. 다음 호출을 실행한다.

```bash
ORCA_BIN terminal create \
  --worktree "path:$WORKTREE_PATH" \
  --command "$LAUNCH_COMMAND" \
  --json
```

8. terminal create가 실패해도 생성된 worktree를 삭제하거나 `rm -rf`하지 않는다.
9. 원래 `--json`이면 다음 envelope을 출력한다.

```json
{"worktree":<create-json>,"terminal":<terminal-json>}
```

`--json`이 없으면 `worktree` path와 terminal handle을 사람이 읽을 수 있는 두 줄로 출력한다.

- [ ] **Step 5: bridge failure 회귀 테스트 추가**

다음을 테스트한다.

```bash
bash scripts/orca-worktree-model-bridge.sh --model gpt-5.6-luna \
  worktree create --name task-1 --agent codex
```

기대값: exit 0, fake Orca 호출 0회.

```bash
bash scripts/orca-worktree-model-bridge.sh --model gpt-5.6-luna \
  worktree create --name task-1 --agent claude --prompt 'x'
```

proxy listener를 fake `nc`가 실패하도록 하면 기대값은 exit 0, worktree 호출 0회다.

create JSON에 path가 없거나 invalid JSON이면 기대값은 non-zero 진단이며 terminal 호출 0회다. terminal create failure에서는 worktree 호출 1회, terminal 호출 1회, 삭제 호출 0회다.

- [ ] **Step 6: bridge 테스트와 syntax 검증**

실행:

```bash
bash -n scripts/orca-worktree-model-bridge.sh
bash tests/unit/test_orca_model_bridge.sh
```

예상 결과: 모든 fake argv·JSON·quote·failure 테스트가 통과한다. 사용자 승인 전 commit은 하지 않는다.

---

### Task 3: Orca 전용 Claude launcher shim

**Files:**
- Create: `scripts/claude-orca-launch.sh`
- Modify: `/Users/raki-1203/.zshrc:144-155` 주변의 Claude wrapper 영역
- Test: `tests/unit/test_claude_orca_launch.sh`

**Interfaces:**
- Consumes: Claude CLI argv, `ORCA_AGENT_LAUNCH_TOKEN` 또는 `ORCA_WORKTREE_ID`, `CLAUDE_ORCA_REAL_BIN` optional test seam
- Produces: 실제 Claude binary를 `exec`하고, Orca terminal의 `gpt-*` launch에만 loopback env를 추가
- Invariant: 일반 shell에서 `command claude`를 직접 실행하는 경로는 shim을 거치지 않는다.

- [ ] **Step 1: fake binary 기반 failing 테스트 작성**

fake binary는 argv와 다음 env를 파일에 기록한다.

```text
ANTHROPIC_BASE_URL
CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC
```

`nc`도 fake executable로 만들어 성공·실패를 제어한다. 다음을 테스트한다.

```bash
ORCA_AGENT_LAUNCH_TOKEN=token-1 \
CLAUDE_ORCA_REAL_BIN="$fake_claude" \
PATH="$fake_bin:$PATH" \
  bash scripts/claude-orca-launch.sh --model gpt-5.6-luna --dangerously-skip-permissions
```

proxy probe가 성공하면 fake binary 기록은 다음과 같아야 한다.

```text
args: --model gpt-5.6-luna --dangerously-skip-permissions
ANTHROPIC_BASE_URL=http://127.0.0.1:18765
CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
```

다음도 검사한다.

- `--model claude-opus-5`: base URL을 새로 설정하지 않음
- `--model composer-2.5`: base URL을 새로 설정하지 않음
- proxy probe 실패: GPT여도 기존 env를 덮어쓰지 않음
- `ORCA_AGENT_LAUNCH_TOKEN`과 `ORCA_WORKTREE_ID`가 모두 없을 때: script는 기존 env와 argv 그대로 exec

- [ ] **Step 2: failing 상태 확인**

실행:

```bash
bash tests/unit/test_claude_orca_launch.sh
```

예상 결과: shim 파일이 없어 failure가 발생한다.

- [ ] **Step 3: launcher shim 구현**

구현 규칙:

1. 실제 binary는 `CLAUDE_ORCA_REAL_BIN`이 있으면 사용하고, 없으면 script process의 `command -v claude` 결과를 사용한다.
2. 현재 process가 Orca marker 없이 직접 실행되면 기존 env 그대로 `exec`한다.
3. argv에서 `--model value`와 `--model=value`를 읽는다.
4. `[1m]` suffix를 제거한 family가 `gpt-*`이고 `nc -z 127.0.0.1 18765`가 성공하면 다음 env로 `exec`한다.

```bash
ANTHROPIC_BASE_URL=http://127.0.0.1:18765 \
CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
exec "$REAL_CLAUDE" "$@"
```

5. `claude-*`, unknown model, model flag 없음, proxy unavailable은 기존 env로 exec한다.
6. script 자체는 `eval`이나 prompt logging을 사용하지 않는다.

`.zshrc`에는 다음 gated function을 `cc()` 정의 뒤에 추가한다.

```zsh
claude() {
  if [[ -n "${ORCA_AGENT_LAUNCH_TOKEN-}" || -n "${ORCA_WORKTREE_ID-}" ]]; then
    "$HOME/workspace/raki-claude-plugins/scripts/claude-orca-launch.sh" "$@"
  else
    command claude "$@"
  fi
}
```

`cc()`의 기존 `ANTHROPIC_BASE_URL` prefix 동작과 `alias ㅊㅊ=cc`는 변경하지 않는다. 함수 정의 후 `cc()` 호출이 function recursion 없이 `command claude`로 끝나는지 확인한다.

- [ ] **Step 4: shim·zsh syntax 테스트**

실행:

```bash
bash -n scripts/claude-orca-launch.sh
zsh -n /Users/raki-1203/.zshrc
bash tests/unit/test_claude_orca_launch.sh
```

예상 결과: 세 명령 모두 성공하고 fake binary의 env·argv assertion이 통과한다. 현재 shell에 즉시 적용하려면 별도 `source ~/.zshrc`가 필요하지만, 기존 shell을 강제로 재시작하지 않는다.

---

### Task 4: 전역 hook 등록과 사용자 문서

**Files:**
- Modify: `/Users/raki-1203/.claude/settings.json`의 `hooks.PreToolUse`
- Modify: `/Users/raki-1203/workspace/raki-claude-plugins/README.md`
- Modify: `/Users/raki-1203/workspace/raki-claude-plugins/CHANGELOG.md`
- Test: `tests/unit/test_orca_install_contract.sh`

**Interfaces:**
- Consumes: Task 1의 executable hook과 Task 3의 absolute launcher path
- Produces: 새 Claude Code 세션에서 모든 `Bash` tool call에 hook이 등록되는 전역 설정
- Preserves: 기존 `Agent` model hook, Python lint hook, wildcard Orca hook, SessionStart/UserPromptSubmit hook

- [ ] **Step 1: 등록 계약 failing 테스트 작성**

`tests/unit/test_orca_install_contract.sh`는 다음을 검사한다.

```bash
jq -e '
  .hooks.PreToolUse[]
  | select(.matcher == "Bash")
  | .hooks[]
  | select(.command | contains("orca-model-inherit.sh"))
' /Users/raki-1203/.claude/settings.json >/dev/null

test -x scripts/orca-model-inherit.sh
test -x scripts/orca-worktree-model-bridge.sh
test -x scripts/claude-orca-launch.sh
```

현재 등록 전에는 첫 assertion이 실패해야 한다.

- [ ] **Step 2: settings.json에 Bash hook 추가**

기존 `hooks.PreToolUse` 배열을 통째로 재작성하지 말고, 기존 Python lint `matcher: "Bash"` 항목과 wildcard 항목 사이에 다음 항목을 증분 추가한다.

```json
{
  "matcher": "Bash",
  "hooks": [
    {
      "type": "command",
      "command": "${HOME}/workspace/raki-claude-plugins/scripts/orca-model-inherit.sh",
      "timeout": 5
    }
  ]
}
```

기존 `Agent` matcher와 `Bash` Python lint matcher는 삭제·병합하지 않는다. hook script는 모든 no-op 경로에서 exit 0이어야 하므로 Python lint와 stdin 경쟁이 발생하지 않는다. Claude Code는 각 hook process에 같은 event payload를 별도로 전달한다.

스크립트는 전역 settings에서 직접 실행되므로 다음을 한 번 실행해 executable bit를 설정한다.

```bash
chmod +x scripts/orca-model-inherit.sh scripts/orca-worktree-model-bridge.sh scripts/claude-orca-launch.sh
```

- [ ] **Step 3: 실행 문서 추가**

README에 `## Orca model inheritance` 섹션을 추가하고 다음 사실만 기록한다.

```markdown
## Orca model inheritance

Claude Code에서 직접 실행한 다음 Orca 경로는 Main 세션의 현재 canonical model을 사용합니다.

- `orca orchestration worker-start --agent claude`
- `orca worktree create --agent claude`

`gpt-*` 모델은 loopback `claude-codex` proxy를 통해 Codex OAuth로 라우팅되고, `claude-*` 모델은 Anthropic 경로를 사용합니다. `--terminal`, 복합 shell command, 지원되지 않는 model, 일반 terminal에서 직접 실행한 Orca command는 자동 변경하지 않습니다.

현재 Claude Code 세션에 이미 열려 있는 terminal에는 새 설정이 소급되지 않습니다. 새 Claude Code/Orca terminal을 열거나 해당 shell에서 `source ~/.zshrc`를 실행해야 합니다.
```

CHANGELOG 최상단에는 다음 한 항목을 추가한다.

```markdown
- Orca `worker-start`와 `worktree create --agent claude`에 Main 세션 model/provider 상속 bridge 추가
```

`CLAUDE.md`, skill 파일, KB카드 자료에는 설명을 추가하지 않는다.

- [ ] **Step 4: 등록·문서 검증**

실행:

```bash
jq empty /Users/raki-1203/.claude/settings.json
bash tests/unit/test_orca_install_contract.sh
bash tests/unit/test_orca_model_inherit.sh
bash tests/unit/test_orca_model_bridge.sh
bash tests/unit/test_claude_orca_launch.sh
```

예상 결과: settings JSON parse·등록 계약·세 unit suite가 모두 통과한다. 사용자 승인 전 commit은 하지 않는다.

---

### Task 5: Mock integration과 실제 throwaway smoke test

**Files:**
- Modify: `test.sh`의 router test 영역에 local Orca bridge test 진입점 추가
- Modify: `lint.sh`의 shell script 검사 목록
- Test: `tests/e2e/orca-model-inherit-smoke.sh`

**Interfaces:**
- Consumes: Task 1–4의 hook, bridge, launcher, settings registration
- Produces: 실제 launch command line과 proxy provider를 확인하는 검증 결과
- Safety boundary: `/private/tmp`의 throwaway Git repository만 사용하며 KB카드·고객 자료가 있는 worktree는 사용하지 않는다.

- [ ] **Step 1: mock integration failing test 작성**

`tests/e2e/orca-model-inherit-smoke.sh`에 fake Orca, fake nc, fake Claude를 연결하고 다음 sequence를 검사한다.

```bash
printf '%s\n' '{"message":{"role":"assistant","model":"gpt-5.6-luna"}}' > "$tmp/transcript.jsonl"
printf '%s\n' '{"tool_name":"Bash","tool_input":{"command":"orca worktree create --name task-1 --agent claude --prompt '\''read only'\''"},"transcript_path":"'$tmp'/transcript.jsonl"}' \
  | bash scripts/orca-model-inherit.sh > "$tmp/hook.json"
```

`hook.json`의 rewritten command를 실행하면 fake Orca log에 다음 두 호출이 기록되어야 한다.

```text
worktree create --name task-1 --json
terminal create --worktree path:/private/tmp/orca-smoke/task-1 --command env ... claude --model gpt-5.6-luna --prefill read only --json
```

GPT launch command에는 `ANTHROPIC_BASE_URL=http://127.0.0.1:18765`가 정확히 한 번만 있어야 한다.

- [ ] **Step 2: mock test가 실패하는지 확인**

실행:

```bash
bash tests/e2e/orca-model-inherit-smoke.sh
```

예상 결과: 아직 `test.sh`·`lint.sh`에 연결되지 않았거나 integration assertions가 없어 실패한다.

- [ ] **Step 3: integration test 연결**

`test.sh`에 `test_orca()`를 추가한다.

```bash
test_orca() {
  echo "🔬 Orca model inheritance 테스트"
  if bash tests/unit/test_orca_model_inherit.sh \
      && bash tests/unit/test_orca_model_bridge.sh \
      && bash tests/unit/test_claude_orca_launch.sh \
      && bash tests/e2e/orca-model-inherit-smoke.sh; then
    pass "Orca model inheritance"
  else
    fail "Orca model inheritance"
  fi
  echo ""
}
```

`case "$TARGET" in`에는 다음 두 branch를 추가하고, `all` branch에서 `test_router` 다음에 `test_orca`를 호출한다.

```bash
  orca)
    test_orca
    ;;
```

Usage 문구는 다음처럼 갱신한다.

```text
Usage: ./test.sh [all|deps|source|wiki|router|orca|smoke|v3]
```

`lint.sh`에는 세 새 executable script를 기존 shell syntax 검사 대상에 추가한다. 외부 Orca daemon·proxy를 호출하는 테스트는 `test.sh all`에서 실행하지 않고 fake integration으로 유지한다.

- [ ] **Step 4: 실제 GPT smoke test 실행**

외부 고객 자료가 없는 throwaway repo를 만든다.

```bash
SMOKE_ROOT=$(mktemp -d /private/tmp/orca-model-inherit.XXXXXX)
mkdir -p "$SMOKE_ROOT/repo"
git -C "$SMOKE_ROOT/repo" init -q
printf '# Orca smoke\n' > "$SMOKE_ROOT/repo/README.md"
git -C "$SMOKE_ROOT/repo" add README.md
git -C "$SMOKE_ROOT/repo" -c user.name=smoke -c user.email=smoke@example.invalid commit -qm initial
```

현재 Main model이 `gpt-5.6-luna`인 세션에서 직접 실행한 단순 `orca worktree create --repo path:$SMOKE_ROOT/repo --name model-check --agent claude --prompt 'read only; report model' --json` 경로를 확인한다. 다음을 모두 기록한다.

1. Orca가 반환한 worktree path와 terminal handle
2. `ps`에서 새 Claude process의 `--model gpt-5.6-luna`
3. 해당 process 환경의 `ANTHROPIC_BASE_URL=http://127.0.0.1:18765`
4. proxy log의 동일 시간대 `model:gpt-5.6-luna`, `provider:codex`, 성공 status

`worker-start`도 `--task`, `--agent claude`와 현재 worktree를 사용해 같은 process command line을 확인한다. 기존 worktree를 삭제하거나 사용자 repository를 건드리지 않는다.

- [ ] **Step 5: Claude 경로는 quota 제약을 명시한 mock 검증**

Claude 주간 quota가 허용되지 않는 동안 실제 Claude generation을 반복하지 않는다. `claude-opus-5` fixture와 fake Orca/launcher에서 다음만 확인한다.

```text
child argv: --model claude-opus-5
new base URL: absent when parent is direct Anthropic
new base URL: http://127.0.0.1:18765 when parent already uses loopback proxy
provider family: anthropic
```

quota가 회복된 뒤에만 실제 Claude parent → Orca child provider를 별도 실행한다.

- [ ] **Step 6: 전체 회귀 검증과 cleanup**

실행:

```bash
bash tests/unit/test_task_router.sh
bash tests/unit/test_orca_model_inherit.sh
bash tests/unit/test_orca_model_bridge.sh
bash tests/unit/test_claude_orca_launch.sh
bash tests/e2e/orca-model-inherit-smoke.sh
bash lint.sh
bash test.sh router
bash test.sh orca
```

실제 smoke test에서 만든 terminal을 `orca terminal stop`으로 종료하고, throwaway worktree를 Orca CLI로 제거한 뒤 `$SMOKE_ROOT`를 삭제한다. cleanup 대상 path가 `$SMOKE_ROOT` 아래인지 확인한 뒤에만 삭제한다. KB카드·고객 자료 경로는 cleanup command에 포함하지 않는다.

예상 결과: 모든 local test가 0 failure, 기존 task-router suite가 회귀 없이 통과, proxy GPT route가 Codex로 확인된다. 사용자 승인 전 commit·push는 수행하지 않는다.

---

## 완료 기준

- [ ] `gpt-5.6-luna` Main 세션에서 두 Orca 경로 모두 `claude --model gpt-5.6-luna`을 실행한다.
- [ ] GPT Orca process가 `http://127.0.0.1:18765`를 사용하고 proxy log에 `provider: codex`가 남는다.
- [ ] Claude model fixture와 quota 허용 시 실제 Claude 경로가 동일 model ID와 Anthropic family를 사용한다.
- [ ] 기존 Orca `--terminal`, non-Claude agent, compound command, unknown model은 자동 변경하지 않는다.
- [ ] bridge failure 시 생성된 worktree를 자동 삭제하지 않고 원인을 보고한다.
- [ ] hook·bridge·shim이 prompt 전문을 기록하지 않는다.
- [ ] 기존 `CLAUDE.md`, skills, 고객 자료, 외부 repository가 변경·업로드되지 않는다.
- [ ] 변경사항은 uncommitted 상태로 유지되며 commit·push는 사용자 명시 승인 후에만 수행한다.
