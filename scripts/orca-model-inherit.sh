#!/bin/bash
set -euo pipefail

noop() {
  exit 0
}

command -v jq >/dev/null 2>&1 || noop
command -v tail >/dev/null 2>&1 || noop

SCRIPT_PATH="${BASH_SOURCE[0]}"
SCRIPT_DIR="${SCRIPT_PATH%/*}"
if [ "$SCRIPT_DIR" = "$SCRIPT_PATH" ]; then
  SCRIPT_DIR='.'
fi
SCRIPT_DIR="$(cd "$SCRIPT_DIR" && pwd)" || noop

{ true >&0; } 2>/dev/null || noop
INPUT=$(cat) || noop

TOOL_NAME=$(printf '%s' "$INPUT" | jq -er '
  if type == "object" and (.tool_name? | type) == "string" then .tool_name
  else empty
  end
' 2>/dev/null) || noop
[ "$TOOL_NAME" = "Bash" ] || noop

COMMAND=$(printf '%s' "$INPUT" | jq -er '
  if (.tool_input? | type) == "object" and
     (.tool_input.command? | type) == "string" then .tool_input.command
  else empty
  end
' 2>/dev/null) || noop
[ -n "$COMMAND" ] || noop

TRANSCRIPT=$(printf '%s' "$INPUT" | jq -er '
  if (.transcript_path? | type) == "string" then .transcript_path
  else empty
  end
' 2>/dev/null) || noop
[ -f "$TRANSCRIPT" ] && [ -r "$TRANSCRIPT" ] || noop

double_quote_escape_char() {
  case "$1" in
    '$'|'`'|'"'|"\\"|$'\n') return 0 ;;
    *) return 1 ;;
  esac
}

shell_quote() {
  local value="$1"
  local quote="'"
  local escaped="'\\''"

  value="${value//$quote/$escaped}"
  printf "'%s'" "$value"
}

# Reject shell syntax that would make the command more than one safe command.
# Quotes and backslashes are tracked so prompt text inside quotes is untouched.
scan_simple_command() {
  local text="$1"
  local length="${#text}"
  local i=0 ch next next_ch quote=''

  while [ "$i" -lt "$length" ]; do
    ch="${text:i:1}"

    if [ "$quote" = "'" ]; then
      if [ "$ch" = "'" ]; then
        quote=''
      fi
      i=$((i + 1))
      continue
    fi

    if [ "$quote" = '"' ]; then
      if [ "$ch" = '"' ]; then
        quote=''
      elif [ "$ch" = "\\" ]; then
        next=$((i + 1))
        [ "$next" -lt "$length" ] || return 1
        next_ch="${text:next:1}"
        if double_quote_escape_char "$next_ch"; then
          i=$((i + 2))
          continue
        fi
      elif [ "$ch" = '`' ]; then
        return 1
      elif [ "$ch" = '$' ]; then
        next=$((i + 1))
        if [ "$next" -lt "$length" ] && [ "${text:next:1}" = '(' ]; then
          return 1
        fi
      fi
      i=$((i + 1))
      continue
    fi

    case "$ch" in
      "'")
        quote="'"
        ;;
      '"')
        quote='"'
        ;;
      "\\")
        i=$((i + 1))
        [ "$i" -lt "$length" ] || return 1
        ;;
      '&'|';'|'|'|'<'|'>'|'`'|$'\n'|$'\r')
        return 1
        ;;
      '$')
        next=$((i + 1))
        if [ "$next" -lt "$length" ] && [ "${text:next:1}" = '(' ]; then
          return 1
        fi
        ;;
    esac
    i=$((i + 1))
  done

  [ -z "$quote" ]
}

scan_simple_command "$COMMAND" || noop

# Tokenize without eval. The raw start/end offsets let us remove only model
# flags while retaining the original shell text for every other argument.
TOKENS=()
TOKEN_STARTS=()
TOKEN_ENDS=()
parse_words() {
  local text="$1"
  local length="${#text}"
  local i=0 ch next next_ch quote='' token='' active=0 start=0 count=0

  while [ "$i" -lt "$length" ]; do
    ch="${text:i:1}"

    if [ "$quote" = "'" ]; then
      if [ "$ch" = "'" ]; then
        quote=''
      else
        token="${token}${ch}"
      fi
      i=$((i + 1))
      continue
    fi

    if [ "$quote" = '"' ]; then
      if [ "$ch" = '"' ]; then
        quote=''
      elif [ "$ch" = "\\" ]; then
        next=$((i + 1))
        [ "$next" -lt "$length" ] || return 1
        next_ch="${text:next:1}"
        if double_quote_escape_char "$next_ch"; then
          if [ "$next_ch" != $'\n' ]; then
            token="${token}${next_ch}"
          fi
          i=$((i + 2))
          continue
        fi
        token="${token}${ch}"
      else
        token="${token}${ch}"
      fi
      i=$((i + 1))
      continue
    fi

    case "$ch" in
      ' '|$'\t')
        if [ "$active" -eq 1 ]; then
          TOKENS[$count]="$token"
          TOKEN_STARTS[$count]="$start"
          TOKEN_ENDS[$count]="$i"
          count=$((count + 1))
          token=''
          active=0
        fi
        ;;
      "'")
        if [ "$active" -eq 0 ]; then
          start="$i"
          active=1
        fi
        quote="'"
        ;;
      '"')
        if [ "$active" -eq 0 ]; then
          start="$i"
          active=1
        fi
        quote='"'
        ;;
      "\\")
        if [ "$active" -eq 0 ]; then
          start="$i"
          active=1
        fi
        i=$((i + 1))
        [ "$i" -lt "$length" ] || return 1
        token="${token}${text:i:1}"
        ;;
      *)
        if [ "$active" -eq 0 ]; then
          start="$i"
          active=1
        fi
        token="${token}${ch}"
        ;;
    esac
    i=$((i + 1))
  done

  [ -z "$quote" ] || return 1
  if [ "$active" -eq 1 ]; then
    TOKENS[$count]="$token"
    TOKEN_STARTS[$count]="$start"
    TOKEN_ENDS[$count]="$length"
  fi
}

parse_words "$COMMAND" || noop
TOKEN_COUNT="${#TOKENS[@]}"
[ "$TOKEN_COUNT" -ge 3 ] || noop
[ "${TOKEN_STARTS[0]}" -eq 0 ] || noop
[ "${TOKENS[0]}" = "orca" ] || noop

if [ "${TOKENS[1]}" = "orchestration" ] && [ "${TOKENS[2]}" = "worker-start" ]; then
  COMMAND_KIND='worker-start'
elif [ "${TOKENS[1]}" = "worktree" ] && [ "${TOKENS[2]}" = "create" ]; then
  COMMAND_KIND='worktree-create'
else
  noop
fi

MODEL=$(
  jq -r '
    select(.message?.role == "assistant" and
      (.message.model? | type == "string") and
      (.message.model | test("^claude-")))
    | .message.model
  ' "$TRANSCRIPT" 2>/dev/null | tail -1 2>/dev/null
) || noop
[ -n "$MODEL" ] || noop

MODEL_FAMILY="$MODEL"
case "$MODEL_FAMILY" in
  *'[1m]') MODEL_FAMILY="${MODEL_FAMILY%\[1m\]}" ;;
esac

case "$MODEL_FAMILY" in
  ''|*[!A-Za-z0-9._:-]*) noop ;;
esac
case "$MODEL_FAMILY" in
  claude-*) ;;
  *) noop ;;
esac

AGENT_CLAUDE_COUNT=0
AGENT_OTHER_COUNT=0
TERMINAL_COUNT=0
MODEL_OPTION_COUNT=0
REMOVE_TOKEN=()

i=3
while [ "$i" -lt "$TOKEN_COUNT" ]; do
  token="${TOKENS[$i]}"
  case "$token" in
    --agent)
      next=$((i + 1))
      [ "$next" -lt "$TOKEN_COUNT" ] || noop
      agent_value="${TOKENS[$next]}"
      if [ "$agent_value" = "claude" ]; then
        AGENT_CLAUDE_COUNT=$((AGENT_CLAUDE_COUNT + 1))
      else
        AGENT_OTHER_COUNT=$((AGENT_OTHER_COUNT + 1))
      fi
      i=$((i + 2))
      continue
      ;;
    --agent=*)
      agent_value="${token#--agent=}"
      if [ "$agent_value" = "claude" ]; then
        AGENT_CLAUDE_COUNT=$((AGENT_CLAUDE_COUNT + 1))
      else
        AGENT_OTHER_COUNT=$((AGENT_OTHER_COUNT + 1))
      fi
      ;;
    --terminal|--terminal=*)
      TERMINAL_COUNT=$((TERMINAL_COUNT + 1))
      ;;
    --model)
      next=$((i + 1))
      [ "$next" -lt "$TOKEN_COUNT" ] || noop
      model_value="${TOKENS[$next]}"
      [ -n "$model_value" ] || noop
      case "$model_value" in --*) noop ;; esac
      MODEL_OPTION_COUNT=$((MODEL_OPTION_COUNT + 1))
      if [ "$COMMAND_KIND" = 'worker-start' ]; then
        REMOVE_TOKEN[$i]=1
        REMOVE_TOKEN[$next]=1
      fi
      i=$((i + 2))
      continue
      ;;
    --model=*)
      model_value="${token#--model=}"
      [ -n "$model_value" ] || noop
      MODEL_OPTION_COUNT=$((MODEL_OPTION_COUNT + 1))
      if [ "$COMMAND_KIND" = 'worker-start' ]; then
        REMOVE_TOKEN[$i]=1
      fi
      ;;
  esac
  i=$((i + 1))
done

[ "$MODEL_OPTION_COUNT" -le 1 ] || noop
[ "$AGENT_CLAUDE_COUNT" -eq 1 ] || noop
[ "$AGENT_OTHER_COUNT" -eq 0 ] || noop
if [ "$COMMAND_KIND" = 'worker-start' ]; then
  [ "$TERMINAL_COUNT" -eq 0 ] || noop
fi

CLEAN_COMMAND=''
build_without_removed() {
  local text="$1"
  local cursor=0 start end index
  local result=''

  index=0
  while [ "$index" -lt "$TOKEN_COUNT" ]; do
    if [ "${REMOVE_TOKEN[$index]-0}" -eq 1 ]; then
      start="${TOKEN_STARTS[$index]}"
      end="${TOKEN_ENDS[$index]}"
      result="${result}${text:cursor:start-cursor}"
      cursor="$end"
    fi
    index=$((index + 1))
  done
  result="${result}${text:cursor}"
  CLEAN_COMMAND="$result"
}

build_without_removed "$COMMAND"
REST="${CLEAN_COMMAND:${TOKEN_ENDS[0]}}"
BRIDGE="$SCRIPT_DIR/orca-worktree-model-bridge.sh"
command -v orca >/dev/null 2>&1 || noop
[ -x "$BRIDGE" ] || noop
BRIDGE_QUOTED="$(shell_quote "$BRIDGE")"
MODEL_QUOTED="$(shell_quote "$MODEL")"
REWRITTEN="${BRIDGE_QUOTED} --model ${MODEL_QUOTED}${REST}"

OUTPUT=$(printf '%s' "$INPUT" | jq -c --arg command "$REWRITTEN" '
  {
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      updatedInput: (.tool_input | .command = $command),
      additionalContext: "Orca model override replaced with the Main session model."
    }
  }
' 2>/dev/null) || noop
printf '%s\n' "$OUTPUT"
