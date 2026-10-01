# eli5 v2 (graft 검증 지도 + 질문 패널) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** rakis `eli5` 스킬을 "LLM 이 쓴 HTML" 에서 "graft 로 근거를 기계 판정한 지도 + 지도 옆에서 여러 턴 질문하는 로컬 패널" 로 바꾼다.

**Architecture:** LLM 은 지도 모델 JSON(레이어·박스·화살표·근거)만 쓴다. `validate.py` 가 graft CLI·파일·git 으로 근거 등급을 결정적으로 판정·강등하고, `render.py` 가 고정 템플릿에 모델을 끼워 단일 HTML 을 만든다. `server.py` 는 그 HTML 에 질문 패널을 주입해 서빙하고, 질문마다 read-only `claude -p` 를 띄우며, 페이지의 SSE 연결이 끊기면 스스로 종료한다.

**Tech Stack:** Python 3 표준 라이브러리만 (`http.server`, `subprocess`, `json`), 바닐라 JS/SVG, bash 테스트(+ `jq`, `curl`), graft 0.16.0 CLI, Claude Code CLI.

**Spec:** `docs/superpowers/specs/2026-10-01-eli5-graft-chat-design.md`

## Global Constraints

- Python 은 **표준 라이브러리만**. 실행은 `python3` 직접 (플러그인 레포에 `pyproject.toml` 없음, 대상 레포 환경과 섞지 않는다). 로컬 실측 Python 3.14.5
- 외부 바이너리는 환경변수로 바꿔 끼울 수 있게 한다: `ELI5_GRAFT_BIN`(기본 `graft`), `ELI5_CLAUDE_BIN`(기본 `claude`)
- 대상 레포의 **추적 파일을 절대 바꾸지 않는다.** 생성물은 `.git/info/exclude` 로만 숨긴다. `.gitignore` 편집 금지
- 서버는 `127.0.0.1` 에만 bind. 수명 기본값: SSE 끊김 후 유예 30초(`ELI5_GRACE_SEC`), 첫 연결 대기 120초(`ELI5_INITIAL_GRACE_SEC`), 하드캡 86400초(`ELI5_MAX_LIFE_SEC`), ping 15초(`ELI5_PING_SEC`), 질문 타임아웃 180초(`ELI5_ASK_TIMEOUT_SEC`)
- `claude -p` 인자는 정확히: `-p --output-format stream-json --verbose --include-partial-messages --tools Read,Grep,Glob --strict-mcp-config [--mcp-config <graft only> --allowedTools mcp__graft] --setting-sources "" --settings {"disableAllHooks": true} --append-system-prompt <rules> [--resume <sid>]`
- 자식 프로세스 환경에서 `CLAUDECODE`·`CLAUDE_CODE_ENTRYPOINT`·`CLAUDE_CODE_SSE_PORT` 제거
- 근거 등급은 정확히 4개: `graft` `code` `record` `unknown`. `rules[]` 는 `code`·`record`·`unknown` 만
- 파일 이름: 모델 `<slug>.model.json`, 지도 `<slug>.html`, 사이드카 `<slug>.eli5.json`, 기본 출력 폴더 `<repo>/.eli5/`
- 테스트는 레포 관례대로 `tests/unit/test_*.sh` (bash, `pass`/`fail` 카운터, `=== N passed, M failed ===`). macOS 전제(`sed -i ''`, `stat -f`)
- arch-explorer(라이선스 없음) 코드를 복사하지 않는다. 이 계획의 코드는 새로 쓴 것이다
- 커밋 메시지 끝에 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. 버전 bump 는 pre-push 훅이 한다 — 수동 bump 금지

## Review Focus

1. **실제 graft 의 `callers --in` 동작이 가짜와 다를 위험** — 가짜 graft 로만 통과하면 실사용에서 graft 등급이 전부 강등될 수 있다. Task 2 에 실제 graft 로 픽스처를 판정하는 조건부 테스트를 넣었다
2. **공백·한글·콜론이 든 경로** — 사용자 vault 경로가 `Nextcloud-100.91.193.50:8080-손희락` 이다. `path:line` 파싱, 상태 파일 키, URL, argv 가 모두 견뎌야 한다. Task 4·5 서버 테스트의 레포 경로를 `저장소 a:1` 로 잡았고, `parse_ref` 는 마지막 콜론으로 자른다
3. **같은 지도를 탭 두 개로 연 경우** — 한 탭을 닫아도 서버가 살아 있어야 한다. Task 4 에 탭 2개 테스트
4. **claude 출력에 JSON 아닌 줄이 섞이는 경우** — 무시하고 계속해야 한다. Task 5 에 `noise` 모드 테스트
5. **답변 생성 중 탭을 닫는 경우** — 스트림 쓰기가 일어나지 않으면 끊김을 바로 못 본다. 대신 SSE 끊김 → 유예 → 서버 종료가 진행 중 자식까지 정리해야 한다. Task 5 에 "종료 시 진행 중 질문 정리" 테스트

---

## File Structure

```
skills/eli5/
  SKILL.md                    (Task 6 재작성)
  bin/graft_prep.py           (Task 1) graft 확인·빌드 + exclude
  bin/validate.py             (Task 2) 무결성·등급 판정·강등·누락 탐지
  bin/render.py               (Task 3) 모델 → HTML + 사이드카
  bin/server.py               (Task 4 수명·보안·서빙 / Task 5 질문)
  assets/map.html             (Task 3) 지도 템플릿
  assets/panel.html           (Task 4) 질문 패널
  assets/answer-rules.md      (Task 5) claude -p 답변 규칙
tests/fixtures/eli5/
  lib.sh                      (Task 1) 테스트 공용
  make_repo.sh                (Task 1) 픽스처 git 레포
  bin/graft  bin/claude       (Task 1) 가짜 CLI (python, 실행 권한)
  model.json  callers.json    (Task 1) 픽스처 모델·가짜 callers 응답
tests/unit/test_eli5_prep.sh      (Task 1)
tests/unit/test_eli5_validate.sh  (Task 2)
tests/unit/test_eli5_render.sh    (Task 3)
tests/unit/test_eli5_server.sh    (Task 4, 5)
lint.sh · test.sh · README.md · CHANGELOG.md   (Task 6)
```

---

### Task 1: 테스트 픽스처 + `graft_prep.py`

**Files:**
- Create: `tests/fixtures/eli5/lib.sh`, `tests/fixtures/eli5/make_repo.sh`, `tests/fixtures/eli5/bin/graft`, `tests/fixtures/eli5/bin/claude`, `tests/fixtures/eli5/model.json`, `tests/fixtures/eli5/callers.json`
- Create: `skills/eli5/bin/graft_prep.py`
- Test: `tests/unit/test_eli5_prep.sh`

**Interfaces:**
- Produces: `graft_prep.py --root <path> [--out-dir .eli5]` → stdout JSON `{"graft": "ok"|"absent"|"index-built", "version": str|null, "root": str, "excluded": [str]}`, exit 0 (git 레포 아님·build 실패는 `{"error": ...}` exit 1)
- Produces (테스트 공용): `lib.sh` 의 `pass`/`fail`/`finish`, `$ELI5_FIX`, `$ELI5_BIN`, `ELI5_GRAFT_BIN`·`ELI5_CLAUDE_BIN` export
- Produces (가짜 graft): `graft --version` → `0.16.0`; `graft build <root>` → `graft/INDEX.md` + `.gitignore` 에 `/graft/` 추가 + `.ignore` 생성; `graft callers <name> --in <path> --json <root>` → `FAKE_GRAFT_CALLERS` 파일(`{"<path>#<name>": ["<caller id>", ...]}`) 기반 응답; `graft mcp` → stdin EOF 까지 대기
- Produces (가짜 claude): 모드는 `FAKE_CLAUDE_MODE_FILE` 파일 내용 또는 `FAKE_CLAUDE_MODE` (`ok`|`noise`|`fail`|`empty`|`sleep`). 매 호출을 `FAKE_CLAUDE_ARGV_LOG` 에 `{"argv": [...], "stdin": str, "env_claudecode": str|null}` 한 줄로 누적. 세션 id 는 `FAKE_SESSION`(기본 `sess-1`)

- [ ] **Step 1: 픽스처 파일 작성**

`tests/fixtures/eli5/lib.sh`:

```bash
# eli5 테스트 공용 — source 해서 쓴다
ELI5_FIX="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$ELI5_FIX/../../.." && pwd)"
ELI5_BIN="$REPO_ROOT/skills/eli5/bin"
PASS=0
FAIL=0
pass() { PASS=$((PASS+1)); echo "  ✅ $1"; }
fail() { FAIL=$((FAIL+1)); echo "  ❌ $1${2:+ (got: $2)}"; }
finish() { echo "=== $PASS passed, $FAIL failed ==="; [ "$FAIL" -eq 0 ]; }
export ELI5_GRAFT_BIN="$ELI5_FIX/bin/graft"
export ELI5_CLAUDE_BIN="$ELI5_FIX/bin/claude"
```

`tests/fixtures/eli5/make_repo.sh`:

```bash
#!/bin/bash
# 사용: make_repo.sh <dir> — eli5 테스트용 git 레포 생성
set -euo pipefail
d="$1"
mkdir -p "$d/src/api" "$d/src/core" "$d/docs"
cat > "$d/src/api/server.py" <<'PY'
from src.core.engine import run_job


def handle(req):
    return run_job(req["id"])
PY
cat > "$d/src/core/engine.py" <<'PY'
import requests


def run_job(job_id):
    requests.post("http://agent/run", json={"id": job_id})
    return job_id
PY
echo "# ADR-1 엔진은 HTTP 로 에이전트를 부른다" > "$d/docs/adr-1.md"
touch "$d/src/__init__.py" "$d/src/api/__init__.py" "$d/src/core/__init__.py"
git -C "$d" init -q
git -C "$d" -c user.email=t@t -c user.name=t add -A
git -C "$d" -c user.email=t@t -c user.name=t commit -qm init
```

`tests/fixtures/eli5/bin/graft`:

```python
#!/usr/bin/env python3
"""eli5 테스트용 가짜 graft."""
import json
import os
import sys
from pathlib import Path

args = sys.argv[1:]
if not args or args[0] in ("--version", "-v", "version"):
    print("0.16.0")
    sys.exit(0)
cmd = args[0]
if cmd == "build":
    root = Path(args[1]) if len(args) > 1 else Path.cwd()
    (root / "graft" / ".graph").mkdir(parents=True, exist_ok=True)
    (root / "graft" / "INDEX.md").write_text("# fake\n")
    with (root / ".gitignore").open("a") as f:
        f.write("# graft's local graph cache\n/graft/\n")
    (root / ".ignore").write_text("!graft/\n")
    sys.exit(0)
if cmd == "callers":
    name = args[1]
    path = args[args.index("--in") + 1] if "--in" in args else ""
    src = os.environ.get("FAKE_GRAFT_CALLERS")
    table = json.loads(Path(src).read_text()) if src else {}
    key = f"{path}#{name}"
    matches = []
    if key in table:
        matches.append({"symbol": {"id": key, "name": name, "path": path},
                        "hits": [{"id": h, "relation": "calls", "depth": 1} for h in table[key]]})
    print(json.dumps({"query": name, "matches": matches}))
    sys.exit(0)
if cmd == "mcp":
    sys.stdin.read()
    sys.exit(0)
print(f"fake graft: unsupported {args}", file=sys.stderr)
sys.exit(2)
```

`tests/fixtures/eli5/bin/claude`:

```python
#!/usr/bin/env python3
"""eli5 테스트용 가짜 claude -p (stream-json)."""
import json
import os
import subprocess
import sys
import time
from pathlib import Path

mode_file = os.environ.get("FAKE_CLAUDE_MODE_FILE")
if mode_file and Path(mode_file).exists():
    mode = Path(mode_file).read_text().strip()
else:
    mode = os.environ.get("FAKE_CLAUDE_MODE", "ok")
question = sys.stdin.read()
log = os.environ.get("FAKE_CLAUDE_ARGV_LOG")
if log:
    with open(log, "a", encoding="utf-8") as f:
        f.write(json.dumps({"argv": sys.argv[1:], "stdin": question,
                            "env_claudecode": os.environ.get("CLAUDECODE")}, ensure_ascii=False) + "\n")
sid = os.environ.get("FAKE_SESSION", "sess-1")


def out(obj):
    print(json.dumps(obj, ensure_ascii=False), flush=True)


if mode == "fail":
    print("boom", file=sys.stderr)
    sys.exit(3)
if mode == "empty":
    sys.exit(0)
if mode == "noise":
    print("this is not json", flush=True)
out({"type": "system", "subtype": "init", "session_id": sid})
if mode == "sleep":
    subprocess.Popen(["sleep", "3001"])
    time.sleep(300)
    sys.exit(0)
out({"type": "assistant", "message": {"content": [
    {"type": "tool_use", "name": "Read", "input": {"file_path": "src/app.py"}}]}})
out({"type": "stream_event", "event": {"type": "content_block_delta",
                                       "delta": {"type": "text_delta", "text": "답: "}}})
out({"type": "result", "subtype": "success", "is_error": False,
     "result": "답: src/core/engine.py:4 에서 정의된다", "session_id": sid})
```

`tests/fixtures/eli5/model.json`:

```json
{
  "meta": {"target": "fixture 앱", "scope": ["src/"], "graft_version": "0.16.0"},
  "views": {
    "L0": {
      "title": "L0 · 실행 단위",
      "hint": "API 가 엔진을 부르고 엔진이 에이전트를 HTTP 로 부른다",
      "parent": null,
      "rules": [
        {"text": "엔진은 HTTP 로 에이전트를 부른다", "grade": "record", "evidence": {"ref": "docs/adr-1.md"}}
      ],
      "nodes": [
        {"id": "api", "title": "API 서버", "lines": ["handle(req)"], "row": 0, "col": 0, "paths": ["src/api/"]},
        {"id": "core", "title": "엔진", "lines": ["run_job(job_id)"], "row": 0, "col": 1, "paths": ["src/core/"], "drill": "L1-core"},
        {"id": "agent", "title": "에이전트 서비스", "lines": ["외부 HTTP"], "row": 1, "col": 1, "paths": []}
      ],
      "edges": [
        {"from": "api", "to": "core", "label": "run_job", "iface": "run_job", "grade": "graft",
         "evidence": {"from_sym": "src/api/server.py#handle", "to_sym": "src/core/engine.py#run_job"}},
        {"from": "core", "to": "agent", "label": "POST /run", "iface": "agent-http", "grade": "code",
         "evidence": {"ref": "src/core/engine.py:5", "quote": "requests.post"}},
        {"from": "agent", "to": "api", "label": "결과 콜백?", "grade": "unknown", "evidence": {}}
      ],
      "ifaces": [
        {"id": "run_job", "title": "작업 실행", "from": "api", "to": "core", "transport": "python call",
         "items": [{"sig": "run_job(job_id)", "desc": "작업 하나를 실행한다", "ref": "src/core/engine.py:4"}]},
        {"id": "agent-http", "title": "에이전트 호출", "from": "core", "to": "agent", "transport": "http",
         "items": [{"sig": "POST http://agent/run", "desc": "작업 id 전달", "ref": "src/core/engine.py:5"}]}
      ]
    },
    "L1-core": {
      "title": "L1 · 엔진",
      "hint": "엔진 내부",
      "parent": "L0",
      "rules": [],
      "nodes": [
        {"id": "engine", "title": "engine.py", "lines": ["run_job"], "row": 0, "col": 0, "paths": ["src/core/engine.py"]}
      ],
      "edges": [],
      "ifaces": []
    }
  },
  "unknowns": []
}
```

`tests/fixtures/eli5/callers.json`:

```json
{"src/core/engine.py#run_job": ["src/api/server.py#handle"]}
```

```bash
chmod +x tests/fixtures/eli5/make_repo.sh tests/fixtures/eli5/bin/graft tests/fixtures/eli5/bin/claude
```

- [ ] **Step 2: 실패하는 테스트 작성** — `tests/unit/test_eli5_prep.sh`

```bash
#!/bin/bash
set -uo pipefail
source "$(dirname "$0")/../fixtures/eli5/lib.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
P="$ELI5_BIN/graft_prep.py"

echo "🔧 graft_prep — 인덱스 없음"
bash "$ELI5_FIX/make_repo.sh" "$T/r"
out=$(python3 "$P" --root "$T/r/src")
[ "$(echo "$out" | jq -r .graft)" = "index-built" ] && pass "인덱스 없으면 빌드" || fail "인덱스 없으면 빌드" "$out"
[ "$(echo "$out" | jq -r .root)" = "$(cd "$T/r" && pwd -P)" ] && pass "하위 경로에서도 레포 루트 탐지" || fail "루트 탐지" "$out"
[ -f "$T/r/graft/INDEX.md" ] && pass "graft/ 생성" || fail "graft/ 생성"
[ ! -f "$T/r/.gitignore" ] && pass "graft 가 새로 만든 .gitignore 제거" || fail ".gitignore 제거"
[ -z "$(git -C "$T/r" status --short)" ] && pass "git status 깨끗" || fail "git status 깨끗" "$(git -C "$T/r" status --short | tr '\n' ' ')"
EX="$T/r/.git/info/exclude"
grep -qx '/graft/' "$EX" && grep -qx '/.ignore' "$EX" && grep -qx '/.eli5/' "$EX" && pass "exclude 3항목" || fail "exclude 3항목" "$(cat "$EX")"

echo "🔧 graft_prep — 재실행"
out2=$(python3 "$P" --root "$T/r")
[ "$(echo "$out2" | jq -r .graft)" = "ok" ] && pass "인덱스 있으면 ok" || fail "재실행 ok" "$out2"
[ "$(grep -cx '/graft/' "$EX")" = "1" ] && pass "exclude 중복 없음" || fail "exclude 중복" "$(cat "$EX")"

echo "🔧 graft_prep — 추적 중인 .gitignore"
bash "$ELI5_FIX/make_repo.sh" "$T/r2"
echo "node_modules/" > "$T/r2/.gitignore"
git -C "$T/r2" add .gitignore
git -C "$T/r2" -c user.email=t@t -c user.name=t commit -qm gi
python3 "$P" --root "$T/r2" >/dev/null
[ "$(cat "$T/r2/.gitignore")" = "node_modules/" ] && pass "추적 .gitignore 원복" || fail "추적 .gitignore 원복" "$(cat "$T/r2/.gitignore")"
[ -z "$(git -C "$T/r2" status --short)" ] && pass "r2 git status 깨끗" || fail "r2 git status" "$(git -C "$T/r2" status --short)"

echo "🔧 graft_prep — graft 없음 / git 아님"
bash "$ELI5_FIX/make_repo.sh" "$T/r3"
out3=$(ELI5_GRAFT_BIN=/nonexistent/graft python3 "$P" --root "$T/r3")
[ "$(echo "$out3" | jq -r .graft)" = "absent" ] && pass "graft 없음 → absent" || fail "absent" "$out3"
grep -qx '/.eli5/' "$T/r3/.git/info/exclude" && pass "graft 없어도 .eli5 exclude" || fail ".eli5 exclude"
mkdir -p "$T/plain"
python3 "$P" --root "$T/plain" >/dev/null && fail "git 아니면 exit 1" || pass "git 아니면 exit 1"
finish
```

- [ ] **Step 3: 실행해서 실패 확인**

Run: `bash tests/unit/test_eli5_prep.sh`
Expected: FAIL — `graft_prep.py` 없음(`can't open file`)으로 다수 ❌

- [ ] **Step 4: `skills/eli5/bin/graft_prep.py` 구현**

```python
#!/usr/bin/env python3
"""eli5 Phase 0: graft 준비 + 생성물을 로컬 전용으로 숨긴다.

사용: graft_prep.py --root <레포 안의 경로> [--out-dir .eli5]
stdout JSON: {"graft": "ok|absent|index-built", "version": str|null, "root": str, "excluded": [...]}

업무 레포의 추적 파일을 바꾸지 않는다 — graft build 가 .gitignore 에 남긴 변경은 원복하고,
graft/ · .ignore · 출력 폴더는 .git/info/exclude 에만 올린다.
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

GRAFT_BIN = os.environ.get("ELI5_GRAFT_BIN", "graft")


def git(root, *args):
    return subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True)


def ensure_exclude(root, entries):
    p = git(root, "rev-parse", "--git-path", "info/exclude").stdout.strip()
    path = Path(p) if os.path.isabs(p) else Path(root) / p
    path.parent.mkdir(parents=True, exist_ok=True)
    have = path.read_text().splitlines() if path.exists() else []
    add = [e for e in dict.fromkeys(entries) if e not in have]
    if add:
        with path.open("a") as f:
            if have and have[-1] != "":
                f.write("\n")
            f.write("# rakis eli5 — 로컬 전용\n" + "\n".join(add) + "\n")
    return add


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--out-dir", default=".eli5")
    a = ap.parse_args()
    top = git(a.root, "rev-parse", "--show-toplevel")
    if top.returncode != 0:
        print(json.dumps({"error": f"git 레포가 아니다: {a.root}"}, ensure_ascii=False))
        return 1
    root = Path(top.stdout.strip()).resolve()
    entries = []
    out_dir = (root / a.out_dir).resolve()
    if out_dir.is_relative_to(root) and out_dir != root:
        entries.append("/" + out_dir.relative_to(root).as_posix() + "/")

    exe = shutil.which(GRAFT_BIN)
    status, version = "absent", None
    if exe:
        r = subprocess.run([exe, "--version"], capture_output=True, text=True)
        version = r.stdout.strip() or None
        status = "ok"
        if not (root / "graft" / "INDEX.md").exists():
            before = {n: ((root / n).read_bytes() if (root / n).exists() else None) for n in (".gitignore", ".ignore")}
            r = subprocess.run([exe, "build", str(root)], capture_output=True, text=True)
            if r.returncode != 0:
                print(json.dumps({"error": "graft build 실패", "stderr": r.stderr[-2000:]}, ensure_ascii=False))
                return 1
            status = "index-built"
            gi = root / ".gitignore"
            if before[".gitignore"] is None:
                gi.unlink(missing_ok=True)
            else:
                gi.write_bytes(before[".gitignore"])
            if before[".ignore"] is not None:
                (root / ".ignore").write_bytes(before[".ignore"])
        if (root / "graft").exists() and git(root, "check-ignore", "-q", "graft/INDEX.md").returncode != 0:
            entries.append("/graft/")
        ign = root / ".ignore"
        if ign.exists() and git(root, "ls-files", "--error-unmatch", ".ignore").returncode != 0 \
                and git(root, "check-ignore", "-q", ".ignore").returncode != 0:
            entries.append("/.ignore")
    added = ensure_exclude(root, entries) if entries else []
    print(json.dumps({"graft": status, "version": version, "root": str(root), "excluded": added}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

```bash
chmod +x skills/eli5/bin/graft_prep.py
```

- [ ] **Step 5: 테스트 통과 확인**

Run: `bash tests/unit/test_eli5_prep.sh`
Expected: `=== 13 passed, 0 failed ===`

- [ ] **Step 6: 커밋**

```bash
git add tests/fixtures/eli5 tests/unit/test_eli5_prep.sh skills/eli5/bin/graft_prep.py
git commit -m "feat(eli5): graft 준비 스크립트 + 테스트 픽스처

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `validate.py` — 무결성·근거 등급 판정·강등·누락 탐지

**Files:**
- Create: `skills/eli5/bin/validate.py`
- Test: `tests/unit/test_eli5_validate.sh`

**Interfaces:**
- Consumes: Task 1 픽스처(`model.json`, `callers.json`, 가짜 graft, `make_repo.sh`)
- Produces: `validate.py <model.json> --root <repo> [--quick] [--graft-status ok|absent|index-built]`
  - 무결성 오류: stdout `{"integrity_errors": [str]}`, **exit 1**, 모델 파일 불변
  - 정상: 모델 파일을 강등 반영해 덮어쓰고 `model["validation"] = report`, stdout 에 같은 report, exit 0
  - report: `{"counts": {"graft","code","record","unknown"}, "downgrades": [{"view","kind":"edge"|"rule","id","claimed","result","reason"}], "integrity_errors": [], "missing_edges": [{"view","from","to","example"}], "missing_edges_skipped": str, "graft": str, "quick": bool}`
  - unknown 등급 요소는 `unknowns[]` 에 `{"text": "<view>: <from> → <to> (<label>)" | "<view>: 규칙 — <text>", "why": str}` 로 자동 추가(같은 text 있으면 생략)
- Produces (Task 3 이 의존): `model["validation"]` 키가 있어야 render 가 동작한다

- [ ] **Step 1: 실패하는 테스트 작성** — `tests/unit/test_eli5_validate.sh`

```bash
#!/bin/bash
set -uo pipefail
source "$(dirname "$0")/../fixtures/eli5/lib.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
bash "$ELI5_FIX/make_repo.sh" "$T/r"
export FAKE_GRAFT_CALLERS="$ELI5_FIX/callers.json"
V="$ELI5_BIN/validate.py"
fresh() { cp "$ELI5_FIX/model.json" "$T/m.model.json"; }
run() { python3 "$V" "$T/m.model.json" --root "$T/r" "$@"; }
edit() { python3 - "$T/m.model.json" "$1" <<'PY'
import json, sys
p, code = sys.argv[1], sys.argv[2]
m = json.load(open(p, encoding="utf-8"))
exec(code, {"m": m})
json.dump(m, open(p, "w", encoding="utf-8"), ensure_ascii=False)
PY
}
grade() { jq -r "$1" "$T/m.model.json"; }

echo "🔧 validate — 정상 모델"
fresh; out=$(run); rc=$?
[ $rc -eq 0 ] && pass "exit 0" || fail "exit 0" "$rc $out"
[ "$(echo "$out" | jq -c .counts)" = '{"graft":1,"code":1,"record":1,"unknown":1}' ] && pass "등급 집계" || fail "등급 집계" "$(echo "$out" | jq -c .counts)"
[ "$(echo "$out" | jq '.downgrades|length')" = "0" ] && pass "강등 없음" || fail "강등 없음" "$out"
[ "$(grade '.unknowns[0].text')" = "L0: agent → api (결과 콜백?)" ] && pass "unknown edge 를 unknowns 에 자동 추가" || fail "unknowns 자동 추가" "$(grade .unknowns)"
[ "$(grade '.validation.counts.graft')" = "1" ] && pass "model.validation 기록" || fail "validation 기록"
run >/dev/null; [ "$(grade '.unknowns|length')" = "1" ] && pass "재실행해도 unknowns 중복 없음" || fail "unknowns 중복"

echo "🔧 강등"
fresh; edit 'm["views"]["L0"]["edges"][0]["evidence"].update(from_sym="src/api/server.py#other", ref="src/api/server.py:5", quote="run_job(")'
run >/dev/null; [ "$(grade '.views.L0.edges[0].grade')" = "code" ] && pass "graft 실패 + code 통과 → code" || fail "graft→code" "$(grade '.views.L0.edges[0].grade')"
fresh; edit 'm["views"]["L0"]["edges"][0]["evidence"]["from_sym"]="src/api/server.py#other"'
out=$(run); [ "$(grade '.views.L0.edges[0].grade')" = "unknown" ] && pass "graft 실패, code 근거 없음 → unknown" || fail "graft→unknown"
echo "$out" | jq -e '.downgrades[0] | .claimed=="graft" and .result=="unknown" and (.reason|test("callers"))' >/dev/null && pass "강등 사유 기록" || fail "강등 사유" "$out"
fresh; edit 'm["views"]["L0"]["edges"][0]["evidence"]["to_sym"]="src/api/server.py#handle"'
out=$(run); echo "$out" | jq -e '.downgrades[0].reason|test("paths 밖")' >/dev/null && pass "to_sym 이 박스 paths 밖 → 강등" || fail "paths 밖" "$out"
fresh; edit 'm["views"]["L0"]["edges"][0]["evidence"]["from_sym"]="handle"'
run >/dev/null; [ "$(grade '.views.L0.edges[0].grade')" = "unknown" ] && pass "노드 id 형식 아님 → unknown" || fail "id 형식"
fresh; edit 'm["views"]["L0"]["edges"][1]["evidence"]["quote"]="requests.get"'
run >/dev/null; [ "$(grade '.views.L0.edges[1].grade')" = "unknown" ] && pass "quote 불일치 → unknown" || fail "quote 불일치"
fresh; edit 'm["views"]["L0"]["edges"][1]["evidence"]["quote"]="requests.get"'
run --quick >/dev/null; [ "$(grade '.views.L0.edges[1].grade')" = "code" ] && pass "--quick 은 quote 검사 생략" || fail "--quick"
fresh; edit 'm["views"]["L0"]["edges"][1]["evidence"]["ref"]="src/core/nope.py:5"'
run >/dev/null; [ "$(grade '.views.L0.edges[1].grade')" = "unknown" ] && pass "없는 파일 인용 → unknown" || fail "없는 파일"
fresh; edit 'm["views"]["L0"]["rules"][0]["evidence"]["ref"]="deadbeefdeadbeef"'
run >/dev/null; [ "$(grade '.views.L0.rules[0].grade')" = "unknown" ] && pass "없는 커밋 → unknown" || fail "없는 커밋"
fresh; HEAD=$(git -C "$T/r" rev-parse HEAD); edit "m['views']['L0']['rules'][0]['evidence']['ref']='$HEAD'"
run >/dev/null; [ "$(grade '.views.L0.rules[0].grade')" = "record" ] && pass "실제 커밋 → record 유지" || fail "실제 커밋"
fresh; out=$(run --graft-status absent)
[ "$(grade '.views.L0.edges[0].grade')" = "unknown" ] && echo "$out" | jq -e '.downgrades[0].reason=="graft 없음"' >/dev/null && pass "graft 없음 → 강등" || fail "graft 없음" "$out"

echo "🔧 무결성 오류 (exit 1)"
integrity() {
  fresh; edit "$1"; local before; before=$(cat "$T/m.model.json"); out=$(run); local rc=$?
  if [ $rc -eq 1 ] && echo "$out" | jq -e --arg k "$2" '.integrity_errors|any(test($k))' >/dev/null \
     && [ "$(cat "$T/m.model.json")" = "$before" ]; then pass "$3"; else fail "$3" "rc=$rc $out"; fi
}
integrity 'm["views"]["L0"]["edges"][0]["to"]="ghost"' "노드 없음" "없는 노드"
integrity 'm["views"]["L0"]["nodes"][1]["drill"]="ghost"' "drill 대상" "없는 drill"
integrity 'm["views"]["L0"]["edges"][0]["iface"]="ghost"' "iface .ghost. 없음" "없는 iface"
integrity 'm["views"]["L0"]["edges"][0].pop("iface")' "참조하는 edge 가 없다" "고아 iface"
integrity 'm["views"]["L0"]["nodes"][1]["col"]=0' "겹쳐" "격자 겹침"
integrity 'm["views"]["L0"]["rules"][0]["grade"]="graft"' "규칙은" "규칙 graft 등급"

echo "🔧 누락 탐지"
mkdir -p "$T/r/graft/.graph"
cat > "$T/r/graft/.graph/wiring.json" <<'J'
{"meta":{"version":1},"edges":[
 {"source":"src/api/server.py#handle","target":"src/core/engine.py#run_job","relation":"calls"},
 {"source":"src/core/engine.py#run_job","target":"src/api/server.py#handle","relation":"calls"},
 {"source":"src/core/engine.py","target":"requests","relation":"imports"}]}
J
fresh; out=$(run)
[ "$(echo "$out" | jq -c '[.missing_edges[]|[.view,.from,.to]]')" = '[["L0","core","api"]]' ] && pass "그림에 없는 관계 1건 (방향 구분)" || fail "누락 탐지" "$(echo "$out" | jq -c .missing_edges)"
sed -i '' 's/"version":1/"version":2/' "$T/r/graft/.graph/wiring.json"
fresh; out=$(run)
echo "$out" | jq -e '(.missing_edges|length)==0 and (.missing_edges_skipped|test("버전"))' >/dev/null && pass "wiring 버전 불일치 → 건너뜀" || fail "버전 불일치" "$out"

echo "🔧 실제 graft (설치돼 있을 때만)"
REAL=$(PATH=/opt/homebrew/bin:/usr/local/bin:$PATH command -v graft || true)
if [ -n "$REAL" ]; then
  bash "$ELI5_FIX/make_repo.sh" "$T/real"
  (cd "$T/real" && "$REAL" build . >/dev/null 2>&1)
  cp "$ELI5_FIX/model.json" "$T/real.model.json"
  out=$(ELI5_GRAFT_BIN="$REAL" python3 "$V" "$T/real.model.json" --root "$T/real")
  [ "$(jq -r '.views.L0.edges[0].grade' "$T/real.model.json")" = "graft" ] && pass "실제 graft callers 로 graft 등급 유지" || fail "실제 graft" "$(echo "$out" | jq -c .downgrades)"
else
  echo "  ⏭️  graft 미설치 — 건너뜀"
fi
finish
```

- [ ] **Step 2: 실행해서 실패 확인**

Run: `bash tests/unit/test_eli5_validate.sh`
Expected: FAIL — `validate.py` 없음

- [ ] **Step 3: `skills/eli5/bin/validate.py` 구현**

```python
#!/usr/bin/env python3
"""eli5 지도 모델 결정적 검증기.

사용: validate.py <model.json> --root <repo> [--quick] [--graft-status ok|absent|index-built]
- 무결성 오류가 있으면 exit 1 — 모델은 건드리지 않는다
- 근거 등급을 판정하고 강등을 모델에 반영한다. 리포트는 model["validation"] 과 stdout 에 남긴다
- graft 판정은 공개 CLI(`graft callers --json`)로만 한다. wiring.json(내부 포맷)은 누락 탐지에만 쓴다
"""
import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

GRADES = ("graft", "code", "record", "unknown")
RULE_GRADES = ("code", "record", "unknown")
GRAFT_BIN = os.environ.get("ELI5_GRAFT_BIN", "graft")
SHA_RE = re.compile(r"^[0-9a-f]{7,40}$")
PR_RE = re.compile(r"^PR#\d+$")


def integrity_errors(model):
    views = model.get("views") or {}
    if not views:
        return ["views 가 비어 있다"]
    errs = []
    for vid, v in views.items():
        nodes = {n["id"]: n for n in v.get("nodes", [])}
        ifaces = {i["id"] for i in v.get("ifaces", [])}
        used = set()
        if v.get("parent") and v["parent"] not in views:
            errs.append(f"{vid}: parent '{v['parent']}' 없음")
        cells = {}
        for n in v.get("nodes", []):
            if n.get("drill") and n["drill"] not in views:
                errs.append(f"{vid}/{n['id']}: drill 대상 view '{n['drill']}' 없음")
            row, col, span = n.get("row", 0), n.get("col", 0), n.get("span", 1)
            for c in range(col, col + span):
                if (row, c) in cells:
                    errs.append(f"{vid}: 격자 칸 ({row},{c}) 를 '{cells[(row, c)]}' 와 '{n['id']}' 가 겹쳐 쓴다")
                cells[(row, c)] = n["id"]
        for e in v.get("edges", []):
            name = f"{e.get('from')}→{e.get('to')}"
            for end in ("from", "to"):
                if e.get(end) not in nodes:
                    errs.append(f"{vid}: edge {name} 의 {end} 노드 없음")
            if e.get("grade") not in GRADES:
                errs.append(f"{vid}: edge {name} 등급 '{e.get('grade')}' 은 허용되지 않는다")
            if e.get("iface"):
                if e["iface"] not in ifaces:
                    errs.append(f"{vid}: edge {name} 의 iface '{e['iface']}' 없음")
                used.add(e["iface"])
        for i in sorted(ifaces - used):
            errs.append(f"{vid}: iface '{i}' 를 참조하는 edge 가 없다")
        for r in v.get("rules", []):
            if r.get("grade") not in RULE_GRADES:
                errs.append(f"{vid}: rule '{r.get('text')}' 등급 '{r.get('grade')}' — 규칙은 code/record/unknown 만 허용")
    return errs


def under(path, prefixes):
    for p in prefixes or []:
        p = p.rstrip("/")
        if path == p or path.startswith(p + "/"):
            return True
    return False


class Graft:
    def __init__(self, root, status):
        self.root, self.status, self.cache = root, status, {}

    def callers(self, to_sym):
        if to_sym not in self.cache:
            path, _, name = to_sym.partition("#")
            try:
                r = subprocess.run([GRAFT_BIN, "callers", name, "--in", path, "--json", str(self.root)],
                                   capture_output=True, text=True, timeout=60)
                data = json.loads(r.stdout or "{}")
            except (OSError, subprocess.TimeoutExpired, ValueError):
                data = {}
            hits = set()
            for m in data.get("matches", []):
                if (m.get("symbol") or {}).get("id") == to_sym:
                    hits.update(h.get("id") for h in m.get("hits", []))
            self.cache[to_sym] = hits
        return self.cache[to_sym]


def check_graft(ev, frm, to, graft):
    if graft.status != "ok":
        return False, "graft 없음"
    fs, ts = ev.get("from_sym", ""), ev.get("to_sym", "")
    if "#" not in fs or "#" not in ts:
        return False, "from_sym/to_sym 이 graft 노드 id 형식(path#symbol)이 아니다"
    if not under(fs.split("#")[0], frm.get("paths")):
        return False, f"{fs} 가 '{frm['id']}' 박스 paths 밖이다"
    if not under(ts.split("#")[0], to.get("paths")):
        return False, f"{ts} 가 '{to['id']}' 박스 paths 밖이다"
    if fs not in graft.callers(ts):
        return False, f"graft callers {ts} 에 {fs} 가 없다"
    return True, ""


def parse_ref(ref):
    path, sep, line = (ref or "").rpartition(":")
    if not sep or not path or not line.isdigit():
        return None, None
    return path, int(line)


def check_code(ev, root, quick):
    path, line = parse_ref(ev.get("ref"))
    if path is None:
        return False, f"ref '{ev.get('ref')}' 가 path:line 형식이 아니다"
    f = root / path
    if not f.is_file():
        return False, f"{path} 파일 없음"
    if quick:
        return True, ""
    quote = ev.get("quote") or ""
    if not quote:
        return False, "quote 없음"
    lines = f.read_text(encoding="utf-8", errors="replace").splitlines()
    window = "\n".join(lines[max(0, line - 3): line + 2])
    if quote not in window:
        return False, f"{path}:{line}±2 에 '{quote}' 없음"
    return True, ""


def check_record(ev, root):
    ref = (ev.get("ref") or "").strip()
    if not ref:
        return False, "ref 없음"
    if PR_RE.match(ref):
        return True, ""
    if SHA_RE.match(ref):
        r = subprocess.run(["git", "-C", str(root), "cat-file", "-e", ref + "^{commit}"], capture_output=True)
        return (True, "") if r.returncode == 0 else (False, f"커밋 {ref} 없음")
    path, line = parse_ref(ref)
    target = root / (path if path is not None else ref)
    return (True, "") if target.exists() else (False, f"{ref} 없음")


def judge(item, ctx):
    """등급을 판정하고 실패하면 강등한다. 강등했으면 기록 dict, 아니면 None."""
    grade, ev = item.get("grade"), item.get("evidence") or {}
    if grade == "graft":
        ok, why = check_graft(ev, ctx["from"], ctx["to"], ctx["graft"])
        if ok:
            return None
        if ev.get("ref"):
            ok2, why2 = check_code(ev, ctx["root"], ctx["quick"])
            if ok2:
                item["grade"] = "code"
                return {"claimed": "graft", "result": "code", "reason": why}
            why = f"{why}; code 판정도 실패: {why2}"
        item["grade"] = "unknown"
        return {"claimed": "graft", "result": "unknown", "reason": why}
    if grade == "code":
        ok, why = check_code(ev, ctx["root"], ctx["quick"])
    elif grade == "record":
        ok, why = check_record(ev, ctx["root"])
    else:
        return None
    if ok:
        return None
    item["grade"] = "unknown"
    return {"claimed": grade, "result": "unknown", "reason": why}


def missing_edges(model, root):
    wiring = root / "graft" / ".graph" / "wiring.json"
    if not wiring.is_file():
        return [], "wiring.json 없음 — 누락 탐지 건너뜀"
    try:
        data = json.loads(wiring.read_text(encoding="utf-8"))
    except ValueError:
        return [], "wiring.json 파싱 실패 — 누락 탐지 건너뜀"
    ver = (data.get("meta") or {}).get("version")
    if ver != 1:
        return [], f"wiring.json 버전 {ver} 미지원 — 누락 탐지 건너뜀"
    out, seen = [], set()
    for vid, v in model["views"].items():
        drawn = {(e["from"], e["to"]) for e in v.get("edges", [])}
        for ed in data.get("edges", []):
            if ed.get("relation") != "calls":
                continue
            sp, tp = ed["source"].split("#")[0], ed["target"].split("#")[0]
            a = next((n["id"] for n in v.get("nodes", []) if under(sp, n.get("paths"))), None)
            b = next((n["id"] for n in v.get("nodes", []) if under(tp, n.get("paths"))), None)
            if a and b and a != b and (a, b) not in drawn and (vid, a, b) not in seen:
                seen.add((vid, a, b))
                out.append({"view": vid, "from": a, "to": b, "example": f"{ed['source']} → {ed['target']}"})
    return out, ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("model")
    ap.add_argument("--root", required=True)
    ap.add_argument("--quick", action="store_true")
    ap.add_argument("--graft-status", choices=["ok", "absent", "index-built"], default="ok")
    a = ap.parse_args()
    mp, root = Path(a.model), Path(a.root).resolve()
    model = json.loads(mp.read_text(encoding="utf-8"))
    errs = integrity_errors(model)
    if errs:
        print(json.dumps({"integrity_errors": errs}, ensure_ascii=False, indent=2))
        return 1
    graft = Graft(root, "absent" if a.graft_status == "absent" else "ok")
    unknowns = model.setdefault("unknowns", [])

    def note_unknown(text, why):
        if not any(u.get("text") == text for u in unknowns):
            unknowns.append({"text": text, "why": why})

    downgrades = []
    for vid, v in model["views"].items():
        nodes = {n["id"]: n for n in v.get("nodes", [])}
        for e in v.get("edges", []):
            label = f"{vid}: {e['from']} → {e['to']}" + (f" ({e['label']})" if e.get("label") else "")
            d = judge(e, {"from": nodes[e["from"]], "to": nodes[e["to"]], "graft": graft, "root": root, "quick": a.quick})
            if d:
                downgrades.append({"view": vid, "kind": "edge", "id": label, **d})
            if e["grade"] == "unknown":
                note_unknown(label, d["reason"] if d else "근거 없음")
        for r in v.get("rules", []):
            label = f"{vid}: 규칙 — {r.get('text')}"
            d = judge(r, {"root": root, "quick": a.quick})
            if d:
                downgrades.append({"view": vid, "kind": "rule", "id": label, **d})
            if r["grade"] == "unknown":
                note_unknown(label, d["reason"] if d else "근거 없음")
    counts = {g: 0 for g in GRADES}
    for v in model["views"].values():
        for it in v.get("edges", []) + v.get("rules", []):
            counts[it["grade"]] += 1
    missing, skipped = missing_edges(model, root)
    report = {"counts": counts, "downgrades": downgrades, "integrity_errors": [],
              "missing_edges": missing, "missing_edges_skipped": skipped,
              "graft": a.graft_status, "quick": a.quick}
    model["validation"] = report
    mp.write_text(json.dumps(model, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

```bash
chmod +x skills/eli5/bin/validate.py
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `bash tests/unit/test_eli5_validate.sh`
Expected: `=== 26 passed, 0 failed ===` (graft 미설치 환경이면 25 + 건너뜀 1줄). **"실제 graft" 항목이 실패하면** 가짜 graft 의 `callers` 응답 형태가 실제와 다르다는 뜻이다 — 실제 `graft callers run_job --in src/core/engine.py --json <repo>` 출력을 확인해 `Graft.callers` 와 가짜 graft 를 실제에 맞춘다. 가짜에 맞춰 실제 판정을 바꾸지 않는다

- [ ] **Step 5: 커밋**

```bash
git add skills/eli5/bin/validate.py tests/unit/test_eli5_validate.sh
git commit -m "feat(eli5): 지도 모델 검증기 — graft 판정·강등·누락 탐지

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: 지도 템플릿 `map.html` + `render.py`

**Files:**
- Create: `skills/eli5/assets/map.html`, `skills/eli5/bin/render.py`
- Test: `tests/unit/test_eli5_render.sh`

**Interfaces:**
- Consumes: Task 2 의 `model["validation"]`
- Produces: `render.py <x.model.json> --root <repo>` → `<x>.html`, `<x>.eli5.json`(`{"version": 1, "commit", "scope", "dirty", "built_at", "graft_version", "quick"}`), 모델의 `meta.commit`·`meta.built_at` 갱신, stdout `{"html", "sidecar"}`. `validation` 키 없으면 exit 1
- Produces (Task 4 패널이 의존하는 페이지 계약):
  - 템플릿 자리표시자: `/*__ELI5_MODEL__*/null` (스크립트 안), `__ELI5_TITLE__` (`<title>`)
  - 전역 `window.ELI5 = {MODEL, state: {view, node}, go(viewId), select(nodeId|null), jumpRef(ref) → bool, refIndex: Map<"path:line", {view, iface}>}`
  - 이벤트: `window` 에 `eli5:view` (`detail: {view}`), `eli5:select` (`detail: {view, node}`)
  - 카드 DOM id: `card-<viewId>-<ifaceId>`
  - 지도 스크립트는 `<script>` 하나, 끝은 `</body>` 앞

- [ ] **Step 1: 실패하는 테스트 작성** — `tests/unit/test_eli5_render.sh`

```bash
#!/bin/bash
set -uo pipefail
source "$(dirname "$0")/../fixtures/eli5/lib.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
R="$T/저장소 a:1"
bash "$ELI5_FIX/make_repo.sh" "$R"
export FAKE_GRAFT_CALLERS="$ELI5_FIX/callers.json"
mkdir -p "$R/.eli5"; M="$R/.eli5/app.model.json"
cp "$ELI5_FIX/model.json" "$M"

echo "🔧 render"
python3 "$ELI5_BIN/render.py" "$M" --root "$R" >/dev/null 2>&1 && fail "validate 전 render 거부" || pass "validate 전 render 거부"
python3 "$ELI5_BIN/validate.py" "$M" --root "$R" >/dev/null
python3 - "$M" <<'PY'
import json, sys
p = sys.argv[1]
m = json.load(open(p, encoding="utf-8"))
m["views"]["L0"]["hint"] = "</script><b>x</b>"
json.dump(m, open(p, "w", encoding="utf-8"), ensure_ascii=False)
PY
out=$(python3 "$ELI5_BIN/render.py" "$M" --root "$R"); rc=$?
[ $rc -eq 0 ] && pass "exit 0" || fail "exit 0" "$out"
H="$R/.eli5/app.html"; S="$R/.eli5/app.eli5.json"
[ -f "$H" ] && [ -f "$S" ] && pass "html + 사이드카 생성" || fail "출력 파일"
python3 - "$H" <<'PY' && pass "MODEL 파싱 가능 + </script> 이스케이프" || fail "MODEL 파싱"
import json, re, sys
h = open(sys.argv[1], encoding="utf-8").read()
assert h.count("</script>") == 1, h.count("</script>")
m = re.search(r"const MODEL = (.*?);\n\(function", h, re.S)
model = json.loads(m.group(1))
assert model["views"]["L0"]["hint"] == "</script><b>x</b>"
assert model["validation"]["counts"]["graft"] == 1
PY
[ "$(jq -r .commit "$S")" = "$(git -C "$R" rev-parse HEAD)" ] && pass "사이드카 commit = HEAD" || fail "사이드카 commit" "$(cat "$S")"
[ "$(jq -r .dirty "$S")" = "false" ] && [ "$(jq -r .version "$S")" = "1" ] && pass "dirty=false, version=1" || fail "사이드카 필드" "$(cat "$S")"
[ "$(jq -r .meta.commit "$M")" = "$(git -C "$R" rev-parse HEAD)" ] && pass "모델 meta.commit 갱신" || fail "meta.commit"
grep -q '<title>fixture 앱 — eli5</title>' "$H" && pass "title 치환" || fail "title"
grep -q 'window.ELI5' "$H" && grep -q 'eli5:select' "$H" && pass "패널 계약(window.ELI5·이벤트)" || fail "패널 계약"
echo "# x" >> "$R/src/core/engine.py"
python3 "$ELI5_BIN/render.py" "$M" --root "$R" >/dev/null
[ "$(jq -r .dirty "$S")" = "true" ] && pass "scope 안 미커밋 변경 → dirty=true" || fail "dirty 감지"
finish
```

- [ ] **Step 2: 실행해서 실패 확인**

Run: `bash tests/unit/test_eli5_render.sh`
Expected: FAIL — `render.py` 없음

- [ ] **Step 3: `skills/eli5/assets/map.html` 작성**

```html
<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>__ELI5_TITLE__ — eli5</title>
<style>
:root{--bg:#fbfaf7;--fg:#1f2328;--muted:#656d76;--line:#d0d7de;--box:#ffffff;--accent:#0969da;--sel:#fff8c5;
  --graft:#1a7f37;--code:#0969da;--record:#9a6700;--unknown:#cf222e}
@media (prefers-color-scheme: dark){:root:not([data-theme="light"]){--bg:#0d1117;--fg:#e6edf3;--muted:#8d96a0;--line:#30363d;--box:#161b22;--accent:#4493f8;--sel:#3b2e00;
  --graft:#3fb950;--code:#4493f8;--record:#d29922;--unknown:#f85149}}
:root[data-theme="dark"]{--bg:#0d1117;--fg:#e6edf3;--muted:#8d96a0;--line:#30363d;--box:#161b22;--accent:#4493f8;--sel:#3b2e00;
  --graft:#3fb950;--code:#4493f8;--record:#d29922;--unknown:#f85149}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);font:14px/1.5 -apple-system,BlinkMacSystemFont,"Apple SD Gothic Neo",sans-serif}
main{max-width:1200px;margin:0 auto;padding:16px}
h1{font-size:20px;margin:0 0 6px}
.badges span{display:inline-block;margin:0 6px 4px 0;padding:1px 8px;border-radius:10px;border:1px solid currentColor;font-size:12px}
.badges .plain{color:var(--muted)}
nav{margin:12px 0;font-size:13px} nav a{color:var(--accent);cursor:pointer}
.hint{color:var(--muted);margin:4px 0 8px}
ul{margin:0 0 12px;padding-left:18px}
.legend{font-size:12px;color:var(--muted);margin:8px 0}
.legend i{display:inline-block;width:22px;border-top:2px solid;margin:0 4px 3px 10px;vertical-align:middle}
.legend i.g-code,.legend i.g-record{border-top-style:dashed}.legend i.g-unknown{border-top-style:dotted}
.diagram{overflow-x:auto;border:1px solid var(--line);border-radius:8px;background:var(--box)}
svg text{fill:var(--fg);font-size:12px}
.node{cursor:pointer}
.node rect{fill:var(--box);stroke:var(--line);stroke-width:1.5}
.node.drill rect{stroke:var(--fg);stroke-width:2.5}
.node.sel rect{fill:var(--sel)}
.node .title{font-weight:600;font-size:13px}
.node .sub{fill:var(--muted);font-size:11px}
.node .go{fill:var(--accent);font-size:11px}
.edge path{fill:none;stroke-width:1.8}
.edge.dim{opacity:.15}
.edge .lbl-bg{fill:var(--box)}
.edge text{font-size:11px;stroke:none;fill:currentColor}
.g-graft{stroke:var(--graft);color:var(--graft)}
.g-code{stroke:var(--code);color:var(--code);stroke-dasharray:6 4}
.g-record{stroke:var(--record);color:var(--record);stroke-dasharray:4 3}
.g-unknown{stroke:var(--unknown);color:var(--unknown);stroke-dasharray:2 4}
h2{font-size:15px;margin:20px 0 8px}
.card{border:1px solid var(--line);border-radius:8px;padding:10px 12px;margin:8px 0;background:var(--box)}
.card.flash{outline:2px solid var(--accent)}
.card .t{font-weight:600}.card .m{color:var(--muted);font-size:12px}
code,.ref{font:12px ui-monospace,SFMono-Regular,Menlo,monospace}
.ref{color:var(--muted)}
.tag{font-size:11px;padding:0 6px;border-radius:8px;border:1px solid currentColor;margin-left:6px}
button.link{background:none;border:0;color:var(--accent);cursor:pointer;padding:0;font:inherit}
@media (max-width:640px){main{padding:12px 16px}}
</style>
</head>
<body>
<main>
<header><h1 id="title"></h1><div class="badges" id="badges"></div></header>
<nav id="crumbs"></nav>
<div class="hint" id="hint"></div>
<ul id="rules"></ul>
<div class="legend">근거: <i class="g-graft"></i>graft 증명 <i class="g-code"></i>코드 읽음 <i class="g-record"></i>기록 해석 <i class="g-unknown"></i>미확인 · 굵은 테두리 = 안으로 들어갈 수 있음 · 박스를 누르면 닿는 것만 남는다</div>
<div class="diagram"><svg id="svg" role="img" aria-label="아키텍처 지도"></svg></div>
<section><h2 id="cards-h"></h2><div id="cards"></div></section>
<section><h2>확인 못 한 것</h2><ul id="unknowns"></ul></section>
<section><h2>그림에 없는 관계 (graft 가 찾음)</h2><ul id="missing"></ul></section>
<section><h2>검증에서 강등된 주장</h2><ul id="downs"></ul></section>
</main>
<script>
const MODEL = /*__ELI5_MODEL__*/null;
(function () {
  const W = 200, H = 96, GX = 90, GY = 70, PAD = 30, NS = "http://www.w3.org/2000/svg";
  const GRADE = {graft: "graft 증명", code: "코드 읽음", record: "기록 해석", unknown: "미확인"};
  const $ = id => document.getElementById(id);
  const esc = s => String(s ?? "").replace(/[&<>"]/g, c => ({"&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;"}[c]));
  const views = MODEL.views;
  const rootView = Object.keys(views).find(k => !views[k].parent) || Object.keys(views)[0];
  const state = {view: null, node: null};
  const refIndex = new Map();
  for (const [vid, v] of Object.entries(views))
    for (const f of v.ifaces || [])
      for (const it of f.items || [])
        if (it.ref && !refIndex.has(it.ref)) refIndex.set(it.ref, {view: vid, iface: f.id});

  function el(tag, attrs, parent) {
    const e = document.createElementNS(NS, tag);
    for (const k in attrs) e.setAttribute(k, attrs[k]);
    if (parent) parent.appendChild(e);
    return e;
  }
  function box(n) {
    const span = n.span || 1;
    return {x: PAD + (n.col || 0) * (W + GX), y: PAD + (n.row || 0) * (H + GY), w: span * W + (span - 1) * GX, h: H};
  }
  function clip(b, tx, ty) {
    const cx = b.x + b.w / 2, cy = b.y + b.h / 2, dx = tx - cx, dy = ty - cy;
    if (!dx && !dy) return [cx, cy];
    const s = Math.min(Math.abs(b.w / 2 / (dx || 1e-9)), Math.abs(b.h / 2 / (dy || 1e-9)));
    return [cx + dx * s, cy + dy * s];
  }
  function evText(ev) {
    if (!ev) return "";
    if (ev.ref) return ev.ref;
    if (ev.from_sym) return `${ev.from_sym} → ${ev.to_sym}`;
    return "";
  }

  function header() {
    const meta = MODEL.meta || {}, val = MODEL.validation || {}, c = val.counts || {};
    $("title").textContent = meta.target || "eli5";
    const b = [`<span class="g-graft">graft ${c.graft || 0}</span>`, `<span class="g-code">코드 ${c.code || 0}</span>`,
      `<span class="g-record">기록 ${c.record || 0}</span>`, `<span class="g-unknown">미확인 ${c.unknown || 0}</span>`];
    if (val.quick) b.push('<span class="g-unknown">미검증 (--quick)</span>');
    if (val.graft === "absent") b.push('<span class="g-unknown">graft 없음 — 실선 판정 불가</span>');
    if (meta.commit) b.push(`<span class="plain">commit ${esc(meta.commit.slice(0, 7))}</span>`);
    $("badges").innerHTML = b.join("");
  }
  function crumbs() {
    const chain = [];
    for (let v = state.view; v; v = views[v].parent) chain.unshift(v);
    $("crumbs").innerHTML = chain.map((v, i) => i < chain.length - 1
      ? `<a data-v="${esc(v)}">${esc(views[v].title)}</a> › ` : `<b>${esc(views[v].title)}</b>`).join("");
    $("crumbs").querySelectorAll("a").forEach(a => a.onclick = () => go(a.dataset.v));
  }
  function draw() {
    const v = views[state.view], svg = $("svg");
    svg.innerHTML = "";
    const nodes = Object.fromEntries((v.nodes || []).map(n => [n.id, n]));
    let mx = 0, my = 0;
    for (const n of v.nodes || []) { const b = box(n); mx = Math.max(mx, b.x + b.w); my = Math.max(my, b.y + b.h); }
    svg.setAttribute("viewBox", `0 0 ${mx + PAD} ${my + PAD}`);
    svg.setAttribute("width", mx + PAD);
    svg.setAttribute("height", my + PAD);
    const defs = el("defs", {}, svg);
    for (const g of Object.keys(GRADE)) {
      const m = el("marker", {id: "ah-" + g, viewBox: "0 0 10 10", refX: "9", refY: "5", markerWidth: "7", markerHeight: "7", orient: "auto-start-reverse"}, defs);
      el("path", {d: "M0,0 L10,5 L0,10 z", class: "g-" + g, style: "fill:currentColor;stroke:none;stroke-dasharray:none"}, m);
    }
    for (const e of v.edges || []) {
      const a = nodes[e.from], b = nodes[e.to];
      if (!a || !b) continue;
      const A = box(a), B = box(b);
      const [x1, y1] = clip(A, B.x + B.w / 2, B.y + B.h / 2), [x2, y2] = clip(B, A.x + A.w / 2, A.y + A.h / 2);
      const dim = state.node && e.from !== state.node && e.to !== state.node;
      const g = el("g", {class: "edge" + (dim ? " dim" : "")}, svg);
      el("path", {d: `M${x1},${y1} L${x2},${y2}`, class: "g-" + e.grade, "marker-end": `url(#ah-${e.grade})`}, g);
      if (e.label) {
        const t = el("text", {x: (x1 + x2) / 2, y: (y1 + y2) / 2 - 4, "text-anchor": "middle", class: "g-" + e.grade}, g);
        t.textContent = e.label;
        requestAnimationFrame(() => {
          try { const bb = t.getBBox(); g.insertBefore(el("rect", {x: bb.x - 3, y: bb.y - 1, width: bb.width + 6, height: bb.height + 2, class: "lbl-bg"}), t); } catch (_) {}
        });
      }
      el("title", {}, g).textContent = GRADE[e.grade] + (evText(e.evidence) ? " — " + evText(e.evidence) : "");
      if (e.iface) { g.style.cursor = "pointer"; g.addEventListener("click", () => flash(state.view, e.iface)); }
    }
    for (const n of v.nodes || []) {
      const B = box(n);
      const g = el("g", {class: "node" + (n.drill ? " drill" : "") + (state.node === n.id ? " sel" : "")}, svg);
      el("rect", {x: B.x, y: B.y, width: B.w, height: B.h, rx: 6}, g);
      el("text", {x: B.x + 10, y: B.y + 20, class: "title"}, g).textContent = n.title;
      (n.lines || []).slice(0, 3).forEach((ln, i) => { el("text", {x: B.x + 10, y: B.y + 38 + i * 15, class: "sub"}, g).textContent = ln; });
      if (n.drill) {
        const d = el("text", {x: B.x + B.w - 10, y: B.y + B.h - 8, "text-anchor": "end", class: "go"}, g);
        d.textContent = "안으로 ▸";
        d.addEventListener("click", ev => { ev.stopPropagation(); go(n.drill); });
      }
      g.addEventListener("click", () => select(state.node === n.id ? null : n.id));
    }
  }
  function cards() {
    const v = views[state.view];
    const list = (v.ifaces || []).filter(f => !state.node || f.from === state.node || f.to === state.node);
    $("cards-h").innerHTML = `인터페이스 ${list.length}개` + (state.node
      ? ` — <b>${esc(state.node)}</b> 에 닿는 것만 <button class="link" id="showall">모두 보기</button>` : "");
    if (state.node) $("showall").onclick = () => select(null);
    $("cards").innerHTML = list.map(f => `<div class="card" id="card-${esc(state.view)}-${esc(f.id)}">
      <div class="t">${esc(f.title)}</div><div class="m">${esc(f.from)} → ${esc(f.to)} · ${esc(f.transport || "")}</div>
      ${(f.items || []).map(it => `<div><code>${esc(it.sig)}</code> ${esc(it.desc || "")} <span class="ref">${esc(it.ref || "")}</span></div>`).join("")}
    </div>`).join("");
  }
  function lists() {
    const v = views[state.view], val = MODEL.validation || {};
    $("hint").textContent = v.hint || "";
    $("rules").innerHTML = (v.rules || []).map(r =>
      `<li>${esc(r.text)} <span class="tag g-${esc(r.grade)}">${GRADE[r.grade] || esc(r.grade)}</span> <span class="ref">${esc(evText(r.evidence))}</span></li>`).join("");
    $("unknowns").innerHTML = (MODEL.unknowns || []).map(u => `<li>${esc(u.text)} <span class="ref">— ${esc(u.why || "")}</span></li>`).join("") || "<li>없음</li>";
    const miss = val.missing_edges || [];
    $("missing").innerHTML = miss.length
      ? miss.map(m => `<li>[${esc(views[m.view] ? views[m.view].title : m.view)}] ${esc(m.from)} → ${esc(m.to)} <span class="ref">예: ${esc(m.example)}</span></li>`).join("")
      : `<li>${esc(val.missing_edges_skipped || "없음")}</li>`;
    const d = val.downgrades || [];
    $("downs").innerHTML = d.length
      ? d.map(x => `<li>${esc(x.id)} — ${GRADE[x.claimed]} → <b>${GRADE[x.result]}</b> <span class="ref">${esc(x.reason)}</span></li>`).join("")
      : "<li>없음</li>";
  }
  function go(vid) {
    if (!views[vid]) return;
    state.view = vid; state.node = null;
    if (location.hash !== "#view=" + encodeURIComponent(vid)) history.replaceState(null, "", "#view=" + encodeURIComponent(vid));
    crumbs(); lists(); draw(); cards();
    window.dispatchEvent(new CustomEvent("eli5:view", {detail: {view: vid}}));
  }
  function select(nid) {
    state.node = nid; draw(); cards();
    window.dispatchEvent(new CustomEvent("eli5:select", {detail: {view: state.view, node: nid}}));
  }
  function flash(vid, ifaceId) {
    if (state.view !== vid) go(vid);
    if (state.node) select(null);
    const c = document.getElementById(`card-${vid}-${ifaceId}`);
    if (!c) return;
    c.scrollIntoView({behavior: "smooth", block: "center"});
    c.classList.add("flash");
    setTimeout(() => c.classList.remove("flash"), 1600);
  }
  function jumpRef(ref) { const t = refIndex.get(ref); if (t) flash(t.view, t.iface); return !!t; }
  window.addEventListener("hashchange", () => {
    const m = location.hash.match(/^#view=(.+)$/);
    if (m) { const v = decodeURIComponent(m[1]); if (v !== state.view) go(v); }
  });
  window.ELI5 = {MODEL, state, go, select, jumpRef, refIndex};
  header();
  const m = location.hash.match(/^#view=(.+)$/);
  go(m && views[decodeURIComponent(m[1])] ? decodeURIComponent(m[1]) : rootView);
})();
</script>
</body>
</html>
```

- [ ] **Step 4: `skills/eli5/bin/render.py` 구현**

```python
#!/usr/bin/env python3
"""eli5 지도 모델 → 단일 HTML + 사이드카.

사용: render.py <x.model.json> --root <repo>
출력: 같은 폴더의 <x>.html, <x>.eli5.json. LLM 은 HTML 을 직접 쓰지 않는다 — 모양은 모델로만 바꾼다.
"""
import argparse
import datetime
import json
import subprocess
import sys
from pathlib import Path

TEMPLATE = Path(__file__).resolve().parent.parent / "assets" / "map.html"


def git(root, *args):
    r = subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else ""


def stem_of(p):
    return p.name[: -len(".model.json")] if p.name.endswith(".model.json") else p.stem


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("model")
    ap.add_argument("--root", required=True)
    a = ap.parse_args()
    mp, root = Path(a.model).resolve(), Path(a.root).resolve()
    model = json.loads(mp.read_text(encoding="utf-8"))
    if "validation" not in model:
        print(json.dumps({"error": "validate.py 를 먼저 실행한다 (model.validation 없음)"}, ensure_ascii=False))
        return 1
    meta = model.setdefault("meta", {})
    meta["commit"] = git(root, "rev-parse", "HEAD")
    meta["built_at"] = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
    scope = meta.get("scope") or ["."]
    dirty = bool(git(root, "status", "--porcelain", "--", *scope))
    payload = json.dumps(model, ensure_ascii=False).replace("</", "<\\/")
    title = str(meta.get("target") or stem_of(mp)).replace("&", "&amp;").replace("<", "&lt;")
    html = TEMPLATE.read_text(encoding="utf-8")
    html = html.replace("/*__ELI5_MODEL__*/null", payload, 1).replace("__ELI5_TITLE__", title, 1)
    out = mp.with_name(stem_of(mp) + ".html")
    out.write_text(html, encoding="utf-8")
    sidecar = mp.with_name(stem_of(mp) + ".eli5.json")
    sidecar.write_text(json.dumps({
        "version": 1, "commit": meta["commit"], "scope": scope, "dirty": dirty, "built_at": meta["built_at"],
        "graft_version": meta.get("graft_version"), "quick": bool(model["validation"].get("quick")),
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    mp.write_text(json.dumps(model, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"html": str(out), "sidecar": str(sidecar)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

```bash
chmod +x skills/eli5/bin/render.py
```

- [ ] **Step 5: 테스트 통과 확인**

Run: `bash tests/unit/test_eli5_render.sh`
Expected: `=== 10 passed, 0 failed ===`

- [ ] **Step 6: 브라우저로 눈 확인 (자동 테스트가 못 보는 것)**

```bash
T=$(mktemp -d); bash tests/fixtures/eli5/make_repo.sh "$T/r"; mkdir -p "$T/r/.eli5"
cp tests/fixtures/eli5/model.json "$T/r/.eli5/app.model.json"
FAKE_GRAFT_CALLERS=tests/fixtures/eli5/callers.json ELI5_GRAFT_BIN=tests/fixtures/eli5/bin/graft \
  python3 skills/eli5/bin/validate.py "$T/r/.eli5/app.model.json" --root "$T/r" >/dev/null
python3 skills/eli5/bin/render.py "$T/r/.eli5/app.model.json" --root "$T/r"
open "$T/r/.eli5/app.html"
```

확인할 것: 실선·점선·주황·빨강 화살표 4종이 보인다 / "엔진" 박스 "안으로 ▸" 클릭 → `L1 · 엔진` + 브레드크럼 / 박스 클릭 → 닿지 않는 화살표 흐려짐 + 카드 필터 / run_job 화살표 클릭 → 카드 하이라이트 / 다크·라이트 모두 글자 읽힘 / 하단 "확인 못 한 것" 1건. 문제 있으면 `map.html` 수정 후 Step 5 재실행

- [ ] **Step 7: 커밋**

```bash
git add skills/eli5/assets/map.html skills/eli5/bin/render.py tests/unit/test_eli5_render.sh
git commit -m "feat(eli5): 지도 템플릿 + 렌더러 (모델 → 단일 HTML + 사이드카)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: `server.py` 수명·보안·서빙 + `panel.html`

**Files:**
- Create: `skills/eli5/bin/server.py`, `skills/eli5/assets/panel.html`
- Test: `tests/unit/test_eli5_server.sh`

**Interfaces:**
- Consumes: Task 3 의 `<x>.html`·`<x>.eli5.json`, 페이지 계약(`window.ELI5`, `eli5:view`/`eli5:select`, `card-<view>-<iface>`)
- Produces (CLI, 모두 stdout JSON):
  - `server.py open --model <m> [--root <r>] [--no-browser]` → `{"url", "panel": true, "reused": bool, "pid", "map": "missing|unknown|stale|fresh"}` 또는 claude 없음 `{"url": "file://…", "panel": false, "reason"}`, 실패 `{"error"}` exit 1
  - `server.py status --model <m>` → `{"server": "running"|"stopped", "url"?, "map"}`
  - `server.py stop --model <m>` → `{"stopped": bool, ...}` — health 가 맞지 않는 pid 는 죽이지 않는다
  - `server.py serve --model <m> --root <r> --port <n>` (내부)
- Produces (모듈): `Paths(model, root=None)` → `.model .html .sidecar .root .key .state .conv .portfile .log`; `map_status(paths)`; `kill_group(proc)`; `Eli5Server` 속성 `paths token port convs children busy stopping lock` 와 메서드 `save_conv(conv_id, session_id)`
- Produces (HTTP): `GET /health` (인증 없음, `{"ok","key","pid"}`), `GET /?t=<token>` → 303 + 쿠키 `eli5`, `GET /` (쿠키) → 패널 주입 HTML, `GET /api/life` (쿠키) → SSE (`event: hello` 후 `: ping`), `POST /api/ask` → Task 5 (이 Task 에서는 404 대신 `run_ask` 미정의 상태가 되지 않도록 아래 코드 그대로 쓴다 — `_ask` 는 Task 5 에서 추가)
- Produces (패널 자리표시자): `__ELI5_CMD__`(재시작 명령 JSON 문자열), `__ELI5_STALE__`(map 상태 JSON 문자열)

- [ ] **Step 1: 실패하는 테스트 작성** — `tests/unit/test_eli5_server.sh`

```bash
#!/bin/bash
set -uo pipefail
source "$(dirname "$0")/../fixtures/eli5/lib.sh"
T=$(mktemp -d)
export TMPDIR="$T/tmp"; mkdir -p "$TMPDIR"
export ELI5_GRACE_SEC=1 ELI5_INITIAL_GRACE_SEC=60 ELI5_PING_SEC=0.3 ELI5_ASK_TIMEOUT_SEC=2 ELI5_MAX_LIFE_SEC=86400
export FAKE_CLAUDE_ARGV_LOG="$T/argv.log" FAKE_CLAUDE_MODE_FILE="$T/mode" FAKE_GRAFT_CALLERS="$ELI5_FIX/callers.json"
export CLAUDECODE=1
S="$ELI5_BIN/server.py"
R="$T/저장소 a:1"
bash "$ELI5_FIX/make_repo.sh" "$R"; mkdir -p "$R/.eli5"; M="$R/.eli5/app.model.json"
cp "$ELI5_FIX/model.json" "$M"
python3 "$ELI5_BIN/validate.py" "$M" --root "$R" >/dev/null
python3 "$ELI5_BIN/render.py" "$M" --root "$R" >/dev/null
STATE=$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import server; print(server.Paths(sys.argv[2]).state)' "$ELI5_BIN" "$M")
JAR="$T/jar"; BGPIDS=()
cleanup() {
  for p in "${BGPIDS[@]:-}"; do [ -n "$p" ] && kill "$p" 2>/dev/null; done
  python3 "$S" stop --model "$M" >/dev/null 2>&1
  pkill -f "sleep 3001" 2>/dev/null
  rm -rf "$T"
}
trap cleanup EXIT
alive() { kill -0 "$1" 2>/dev/null; }
wait_dead() { local i; for i in $(seq 1 $(($2 * 10))); do alive "$1" || return 0; sleep 0.1; done; return 1; }
start() {
  OUT=$(python3 "$S" open --model "$M" --no-browser)
  URL=$(echo "$OUT" | jq -r .url); PID=$(echo "$OUT" | jq -r .pid); BASE=${URL%%/\?*}
  rm -f "$JAR"; curl -s -o /dev/null -c "$JAR" "$URL"
}
life() { curl -s -N -b "$JAR" "$BASE/api/life" >/dev/null 2>&1 & LIFE=$!; BGPIDS+=("$LIFE"); }
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }

echo "🔧 기동·보안"
start
[ "$(echo "$OUT" | jq -r .panel)" = "true" ] && alive "$PID" && pass "open → 서버 기동" || fail "open" "$OUT"
[ -f "$STATE" ] && [ "$(stat -f %Lp "$STATE")" = "600" ] && pass "상태 파일 0600" || fail "상태 파일 권한"
curl -s "$BASE/health" | jq -e .ok >/dev/null && pass "/health" || fail "/health"
[ "$(code "$BASE/")" = "403" ] && pass "토큰 없으면 403" || fail "토큰 없음"
[ "$(code "$BASE/?t=wrong")" = "403" ] && pass "틀린 토큰 403" || fail "틀린 토큰"
grep -q 'eli5' "$JAR" && pass "토큰 → 쿠키" || fail "쿠키"
PAGE=$(curl -s -b "$JAR" "$BASE/")
echo "$PAGE" | grep -q 'eli5-panel-host' && echo "$PAGE" | grep -q 'const MODEL' && pass "패널 주입된 지도" || fail "패널 주입"
grep -q 'eli5-panel-host' "$R/.eli5/app.html" && fail "디스크 html 불변" || pass "디스크 html 불변"
[ "$(code -b "$JAR" -H 'Host: evil.example' "$BASE/")" = "403" ] && pass "잘못된 Host 403" || fail "Host 검사"
[ "$(code -b "$JAR" -X POST -H 'Content-Type: application/json' -d '{}' "$BASE/api/ask")" = "403" ] && pass "Origin 없는 POST 403" || fail "Origin 검사"
OUT2=$(python3 "$S" open --model "$M" --no-browser)
[ "$(echo "$OUT2" | jq -r .reused)" = "true" ] && [ "$(echo "$OUT2" | jq -r .pid)" = "$PID" ] && pass "재실행은 기존 서버 재사용" || fail "재사용" "$OUT2"
[ "$(python3 "$S" status --model "$M" | jq -r .server)" = "running" ] && pass "status: running" || fail "status running"
[ "$(python3 "$S" status --model "$M" | jq -r .map)" = "fresh" ] && pass "status: map fresh" || fail "status fresh"

echo "🔧 수명"
life; L1=$LIFE; life; L2=$LIFE; sleep 0.8
kill "$L1"; sleep 2
alive "$PID" && pass "탭 2개 중 1개 닫힘 → 유지" || fail "탭 하나 닫힘"
kill "$L2"
wait_dead "$PID" 4 && pass "마지막 탭 닫힘 → 유예 후 종료" || fail "SSE 끊김 종료"
[ ! -f "$STATE" ] && pass "종료 시 상태 파일 정리" || fail "상태 파일 정리"
OLDPORT=${BASE##*:}
start
[ "${BASE##*:}" = "$OLDPORT" ] && pass "재기동 시 이전 포트 재사용" || fail "포트 재사용" "$BASE vs $OLDPORT"
python3 "$S" stop --model "$M" | jq -e .stopped >/dev/null && wait_dead "$PID" 3 && pass "stop" || fail "stop"
python3 -m http.server "$OLDPORT" --bind 127.0.0.1 >/dev/null 2>&1 & BLOCK=$!; BGPIDS+=("$BLOCK"); sleep 0.5
start
[ "${BASE##*:}" != "$OLDPORT" ] && alive "$PID" && pass "이전 포트 점유 시 다른 포트" || fail "포트 충돌" "$BASE"
kill "$BLOCK"
python3 "$S" stop --model "$M" >/dev/null; wait_dead "$PID" 3
export ELI5_INITIAL_GRACE_SEC=1; start; export ELI5_INITIAL_GRACE_SEC=60
wait_dead "$PID" 4 && pass "아무도 안 열면 초기 유예 후 종료" || fail "초기 유예"
export ELI5_MAX_LIFE_SEC=2; start; export ELI5_MAX_LIFE_SEC=86400; life
wait_dead "$PID" 5 && pass "하드캡 — 연결 있어도 종료" || fail "하드캡"
kill "$LIFE" 2>/dev/null
printf '{"pid": 999999, "port": 1, "token": "x"}' > "$STATE"
start
[ "$(echo "$OUT" | jq -r .reused)" = "false" ] && alive "$PID" && pass "죽은 pid 상태 파일 → 새로 기동" || fail "죽은 pid" "$OUT"
python3 "$S" stop --model "$M" >/dev/null; wait_dead "$PID" 3
printf '{"pid": %d, "port": 1, "token": "x"}' $$ > "$STATE"
python3 "$S" stop --model "$M" | jq -e '.stopped==false' >/dev/null && alive $$ && pass "health 안 맞는 pid 는 죽이지 않음" || fail "pid 재사용 보호"
echo "# changed" >> "$R/src/core/engine.py"
[ "$(python3 "$S" status --model "$M" | jq -r .map)" = "stale" ] && pass "status: 코드 바뀌면 stale" || fail "stale"
git -C "$R" checkout -q -- src/core/engine.py
OUT3=$(ELI5_CLAUDE_BIN=/nonexistent/claude python3 "$S" open --model "$M" --no-browser)
[ "$(echo "$OUT3" | jq -r .panel)" = "false" ] && echo "$OUT3" | jq -e '.url|startswith("file://")' >/dev/null && pass "claude 없음 → file:// 로 패널 없이" || fail "claude 없음" "$OUT3"
finish
```

- [ ] **Step 2: 실행해서 실패 확인**

Run: `bash tests/unit/test_eli5_server.sh`
Expected: FAIL — `server.py` 없음

- [ ] **Step 3: `skills/eli5/bin/server.py` 구현 (질문 기능 제외)**

```python
#!/usr/bin/env python3
"""eli5 지도 서버 — 질문 패널 주입 + 수명 관리 + claude -p 답변.

사용:
  server.py open   --model <x.model.json> [--root <repo>] [--no-browser]
  server.py status --model <x.model.json> [--root <repo>]
  server.py stop   --model <x.model.json> [--root <repo>]
  server.py serve  --model … --root … --port N   (내부용 — open 이 분리 기동한다)

수명은 세션이 아니라 페이지에 묶인다: SSE 연결이 0 개가 된 뒤 GRACE 초가 지나면 스스로 종료하고,
종료할 때 진행 중인 claude 프로세스 그룹을 전부 정리한다.
"""
import argparse
import collections
import hashlib
import hmac
import json
import os
import re
import secrets
import shutil
import signal
import subprocess
import sys
import threading
import time
import urllib.request
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

HERE = Path(__file__).resolve().parent
ASSETS = HERE.parent / "assets"
CLAUDE_BIN = os.environ.get("ELI5_CLAUDE_BIN", "claude")
GRAFT_BIN = os.environ.get("ELI5_GRAFT_BIN", "graft")


def env_f(name, default):
    try:
        return float(os.environ.get(name, default))
    except ValueError:
        return float(default)


GRACE = env_f("ELI5_GRACE_SEC", 30)
INITIAL_GRACE = env_f("ELI5_INITIAL_GRACE_SEC", 120)
MAX_LIFE = env_f("ELI5_MAX_LIFE_SEC", 86400)
PING = env_f("ELI5_PING_SEC", 15)
ASK_TIMEOUT = env_f("ELI5_ASK_TIMEOUT_SEC", 180)
MAX_CONTEXT = 6000
STRIP_ENV = ("CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_SSE_PORT")
CONV_RE = re.compile(r"^[A-Za-z0-9-]{1,64}$")


class Paths:
    def __init__(self, model, root=None):
        self.model = Path(model).resolve()
        name = self.model.name
        stem = name[: -len(".model.json")] if name.endswith(".model.json") else self.model.stem
        self.html = self.model.with_name(stem + ".html")
        self.sidecar = self.model.with_name(stem + ".eli5.json")
        if root:
            self.root = Path(root).resolve()
        else:
            r = subprocess.run(["git", "-C", str(self.model.parent), "rev-parse", "--show-toplevel"],
                               capture_output=True, text=True)
            self.root = Path(r.stdout.strip()).resolve() if r.returncode == 0 else self.model.parent
        self.key = hashlib.sha1(f"{self.root}\n{self.model}".encode()).hexdigest()[:16]
        base = Path(os.environ.get("TMPDIR", "/tmp")) / "rakis-eli5"
        base.mkdir(parents=True, exist_ok=True)
        self.state = base / f"{self.key}.json"
        self.conv = base / f"{self.key}.conv.json"
        self.portfile = base / f"{self.key}.port.json"
        self.log = base / f"{self.key}.log"


def read_json(p, default=None):
    try:
        return json.loads(Path(p).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return default


def write_json_private(p, data):
    tmp = Path(str(p) + ".tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)
    os.chmod(tmp, 0o600)
    os.replace(tmp, p)


def pid_alive(pid):
    try:
        os.kill(int(pid), 0)
        return True
    except (OSError, ValueError, TypeError):
        return False


def health(port, key):
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{port}/health", timeout=1) as r:
            return json.loads(r.read()).get("key") == key
    except Exception:
        return False


def same(a, b):
    return hmac.compare_digest(a.encode("utf-8", "replace"), b.encode("utf-8", "replace"))


def map_status(paths):
    if not paths.html.exists():
        return "missing"
    sc = read_json(paths.sidecar)
    if not sc or sc.get("version") != 1 or sc.get("dirty") or not sc.get("commit"):
        return "unknown"
    r = subprocess.run(["git", "-C", str(paths.root), "diff", "--name-only", sc["commit"], "--", *(sc.get("scope") or ["."])],
                       capture_output=True, text=True)
    if r.returncode != 0:
        return "unknown"
    changed = [l for l in r.stdout.splitlines() if l and not l.startswith((".eli5/", "graft/"))]
    return "stale" if changed else "fresh"


def kill_group(proc):
    """프로세스 그룹 전체를 정리한다. 리더가 이미 끝났어도 남은 손자까지 SIGKILL 한다."""
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except OSError:
        return
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        pass
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except OSError:
        pass


class Eli5Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, addr, paths, token):
        super().__init__(addr, Handler)
        self.paths, self.token = paths, token
        self.port = self.server_address[1]
        self.started = time.monotonic()
        self.lock = threading.Lock()
        self.conns = 0
        self.ever_connected = False
        self.zero_since = time.monotonic()
        self.children = set()
        self.busy = set()
        self.stopping = threading.Event()
        self.convs = read_json(paths.conv, {}) or {}

    def hosts(self):
        return {f"127.0.0.1:{self.port}", f"localhost:{self.port}"}

    def save_conv(self, conv_id, session_id):
        with self.lock:
            self.convs[conv_id] = session_id
            write_json_private(self.paths.conv, self.convs)


def shutdown(srv):
    if srv.stopping.is_set():
        return
    srv.stopping.set()
    for p in list(srv.children):
        kill_group(p)
    st = read_json(srv.paths.state, {})
    if st and st.get("pid") == os.getpid():
        srv.paths.state.unlink(missing_ok=True)
    threading.Thread(target=srv.shutdown, daemon=True).start()


def watchdog(srv):
    while not srv.stopping.is_set():
        time.sleep(0.2)
        now = time.monotonic()
        with srv.lock:
            limit = GRACE if srv.ever_connected else INITIAL_GRACE
            expired = srv.conns == 0 and now - srv.zero_since > limit
        if expired or now - srv.started > MAX_LIFE:
            shutdown(srv)
            return


def page(srv):
    html = srv.paths.html.read_text(encoding="utf-8")
    panel = (ASSETS / "panel.html").read_text(encoding="utf-8")
    cmd = f"/rakis:eli5 open {srv.paths.model}"
    panel = panel.replace("__ELI5_CMD__", json.dumps(cmd, ensure_ascii=False).replace("</", "<\\/"))
    panel = panel.replace("__ELI5_STALE__", json.dumps(map_status(srv.paths)))
    i = html.rfind("</body>")
    html = html[:i] + panel + html[i:] if i >= 0 else html + panel
    return html.encode("utf-8")


class Handler(BaseHTTPRequestHandler):
    server_version = "eli5"

    def log_message(self, fmt, *args):
        pass

    def _send(self, code, body=b"", ctype="text/plain; charset=utf-8", headers=None):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.end_headers()
        if body:
            self.wfile.write(body)

    def _host_ok(self):
        return self.headers.get("Host", "") in self.server.hosts()

    def _authed(self):
        m = re.search(r"(?:^|;\s*)eli5=([^;]+)", self.headers.get("Cookie", ""))
        return bool(m) and same(m.group(1), self.server.token)

    def _origin_ok(self):
        return self.headers.get("Origin", "") in {f"http://{h}" for h in self.server.hosts()}

    def do_GET(self):
        if not self._host_ok():
            return self._send(403, b"bad host")
        u = urlparse(self.path)
        if u.path == "/health":
            body = json.dumps({"ok": True, "key": self.server.paths.key, "pid": os.getpid()}).encode()
            return self._send(200, body, "application/json")
        if u.path == "/":
            t = parse_qs(u.query).get("t", [""])[0]
            if t:
                if not same(t, self.server.token):
                    return self._send(403, b"bad token")
                return self._send(303, headers={
                    "Set-Cookie": f"eli5={self.server.token}; HttpOnly; SameSite=Strict; Path=/", "Location": "/"})
            if not self._authed():
                return self._send(403, b"token required")
            return self._send(200, page(self.server), "text/html; charset=utf-8")
        if u.path == "/api/life":
            if not self._authed():
                return self._send(403, b"token required")
            return self._life()
        return self._send(404, b"not found")

    def do_POST(self):
        if not self._host_ok():
            return self._send(403, b"bad host")
        if not self._authed() or not self._origin_ok():
            return self._send(403, b"forbidden")
        if urlparse(self.path).path == "/api/ask" and hasattr(self, "_ask"):
            return self._ask()
        return self._send(404, b"not found")

    def _life(self):
        srv = self.server
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        with srv.lock:
            srv.conns += 1
            srv.ever_connected = True
        try:
            self.wfile.write(b"event: hello\ndata: {}\n\n")
            self.wfile.flush()
            while not srv.stopping.wait(PING):
                self.wfile.write(b": ping\n\n")
                self.wfile.flush()
        except OSError:
            pass
        finally:
            with srv.lock:
                srv.conns -= 1
                if srv.conns == 0:
                    srv.zero_since = time.monotonic()


def cmd_serve(a):
    paths = Paths(a.model, a.root)
    token = secrets.token_urlsafe(24)
    srv = None
    for port in ([a.port] if a.port else []) + [0]:
        try:
            srv = Eli5Server(("127.0.0.1", port), paths, token)
            break
        except OSError:
            continue
    if srv is None:
        return 1
    write_json_private(paths.state, {"pid": os.getpid(), "port": srv.port, "token": token,
                                     "started_at": time.time(), "model": str(paths.model), "root": str(paths.root)})
    write_json_private(paths.portfile, {"port": srv.port})
    signal.signal(signal.SIGTERM, lambda *_: shutdown(srv))
    signal.signal(signal.SIGINT, lambda *_: shutdown(srv))
    threading.Thread(target=watchdog, args=(srv,), daemon=True).start()
    try:
        srv.serve_forever(poll_interval=0.2)
    finally:
        shutdown(srv)
        srv.server_close()
    return 0


def url_of(st):
    return f"http://127.0.0.1:{st['port']}/?t={st['token']}"


def out(obj, code=0):
    print(json.dumps(obj, ensure_ascii=False))
    return code


def cmd_open(a):
    paths = Paths(a.model, a.root)
    if not paths.html.exists():
        return out({"error": f"지도 없음: {paths.html}"}, 1)
    if not shutil.which(CLAUDE_BIN):
        url = paths.html.as_uri()
        if not a.no_browser:
            webbrowser.open(url)
        return out({"url": url, "panel": False, "reason": "claude CLI 없음 — 패널 없이 연다"})
    st = read_json(paths.state)
    reused = bool(st) and pid_alive(st.get("pid")) and health(st.get("port"), paths.key)
    if not reused:
        paths.state.unlink(missing_ok=True)
        prev = (read_json(paths.portfile, {}) or {}).get("port") or 0
        with open(paths.log, "ab") as log:
            subprocess.Popen([sys.executable, str(Path(__file__).resolve()), "serve", "--model", str(paths.model),
                              "--root", str(paths.root), "--port", str(prev)],
                             stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True, close_fds=True)
        st, deadline = None, time.monotonic() + 15
        while time.monotonic() < deadline:
            cand = read_json(paths.state)
            if cand and health(cand.get("port"), paths.key):
                st = cand
                break
            time.sleep(0.1)
        if not st:
            return out({"error": "서버 기동 실패", "log": str(paths.log)}, 1)
    url = url_of(st)
    if not a.no_browser:
        webbrowser.open(url)
    return out({"url": url, "panel": True, "reused": reused, "pid": st["pid"], "map": map_status(paths)})


def cmd_status(a):
    paths = Paths(a.model, a.root)
    st = read_json(paths.state)
    running = bool(st) and pid_alive(st.get("pid")) and health(st.get("port"), paths.key)
    res = {"server": "running" if running else "stopped", "map": map_status(paths)}
    if running:
        res["url"] = url_of(st)
    return out(res)


def cmd_stop(a):
    paths = Paths(a.model, a.root)
    st = read_json(paths.state)
    if not st or not pid_alive(st.get("pid")) or not health(st.get("port"), paths.key):
        paths.state.unlink(missing_ok=True)
        return out({"stopped": False, "reason": "실행 중인 eli5 서버 없음"})
    pid = st["pid"]
    os.kill(pid, signal.SIGTERM)
    for _ in range(100):
        if not pid_alive(pid):
            break
        time.sleep(0.1)
    else:
        os.kill(pid, signal.SIGKILL)
    paths.state.unlink(missing_ok=True)
    return out({"stopped": True, "pid": pid})


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("open", "status", "stop", "serve"):
        p = sub.add_parser(name)
        p.add_argument("--model", required=True)
        p.add_argument("--root")
        if name == "open":
            p.add_argument("--no-browser", action="store_true")
        if name == "serve":
            p.add_argument("--port", type=int, default=0)
    a = ap.parse_args()
    return {"open": cmd_open, "status": cmd_status, "stop": cmd_stop, "serve": cmd_serve}[a.cmd](a)


if __name__ == "__main__":
    sys.exit(main())
```

`collections` 는 Task 5 에서 쓴다 (지금 import 해 두어도 무해).

```bash
chmod +x skills/eli5/bin/server.py
```

- [ ] **Step 4: `skills/eli5/assets/panel.html` 작성**

```html
<div id="eli5-panel-host"></div>
<script>
(function () {
  const CMD = __ELI5_CMD__;
  const STALE = __ELI5_STALE__;
  const ELI5 = window.ELI5;
  const host = document.getElementById("eli5-panel-host");
  const root = host.attachShadow({mode: "open"});
  document.documentElement.style.paddingRight = "400px";
  root.innerHTML = `<style>
  .p{position:fixed;top:0;right:0;width:400px;height:100vh;display:flex;flex-direction:column;z-index:2147483000;
     background:#161b22;color:#e6edf3;border-left:1px solid #30363d;font:13px/1.55 -apple-system,BlinkMacSystemFont,"Apple SD Gothic Neo",sans-serif}
  @media (prefers-color-scheme: light){.p{background:#ffffff;color:#1f2328;border-left-color:#d0d7de}}
  header{display:flex;gap:8px;align-items:center;padding:10px 12px;border-bottom:1px solid #30363d}
  header b{flex:1}
  .badge{font-size:11px;border:1px solid currentColor;border-radius:8px;padding:0 6px;opacity:.8}
  button{font:inherit;cursor:pointer;border:1px solid #30363d;background:transparent;color:inherit;border-radius:6px;padding:3px 10px}
  button:disabled{opacity:.5;cursor:default}
  .banner{display:none;padding:8px 12px;font-size:12px;background:#3b2e00;color:#f2cc60}
  .banner.on{display:block}
  .banner.dead{background:#3d1214;color:#ff9a9a}
  .log{flex:1;overflow-y:auto;padding:12px}
  .msg{margin:0 0 12px;word-break:break-word}
  .msg.user{margin-left:40px;background:#1f6feb33;padding:8px 10px;border-radius:8px}
  .msg .chip{font-size:11px;opacity:.7;display:block}
  .msg.bot{white-space:pre-wrap}
  .msg.err{white-space:pre-wrap;color:#ff7b72}
  .reading{font-size:11px;opacity:.6;margin:-8px 0 10px}
  code{font:12px ui-monospace,Menlo,monospace;background:#6e768133;padding:0 4px;border-radius:4px}
  a.ref{color:#4493f8;cursor:pointer;text-decoration:underline}
  .chipbar{padding:4px 12px;font-size:12px;min-height:24px;opacity:.85}
  .chipbar span{border:1px solid #30363d;border-radius:10px;padding:1px 8px}
  .chipbar button{border:0;padding:0 4px}
  form{display:flex;gap:8px;padding:10px 12px;border-top:1px solid #30363d}
  textarea{flex:1;resize:none;height:56px;font:inherit;background:transparent;color:inherit;border:1px solid #30363d;border-radius:6px;padding:6px}
  </style>
  <div class="p">
    <header><b>코드 질문</b><span class="badge">claude</span><button id="new" type="button">새 대화</button></header>
    <div class="banner" id="stale">지도가 코드보다 낡았습니다 — 답은 현재 코드 기준이라 그림과 다를 수 있습니다</div>
    <div class="banner dead" id="dead"></div>
    <div class="log" id="log"></div>
    <div class="chipbar" id="chip"></div>
    <form id="f"><textarea id="q" placeholder="이 코드에 대해 물어보세요 (Enter 전송, Shift+Enter 줄바꿈)"></textarea><button id="send">보내기</button></form>
  </div>`;
  const $ = id => root.getElementById(id);
  const esc = s => String(s ?? "").replace(/[&<>"]/g, c => ({"&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;"}[c]));
  const KEY = "eli5:conv:" + CMD;
  const newId = () => (crypto.randomUUID ? crypto.randomUUID() : Date.now() + "-" + Math.random().toString(16).slice(2)).replace(/[^A-Za-z0-9-]/g, "");
  let conv = null;
  try { conv = localStorage.getItem(KEY); } catch (_) {}
  if (!conv) { conv = newId(); try { localStorage.setItem(KEY, conv); } catch (_) {} }
  if (STALE === "stale") $("stale").classList.add("on");

  function greet() {
    $("log").innerHTML = '<div class="msg bot">지도와 graft 를 근거로 답합니다. 박스를 고르면 그 박스에 대해 물을 수 있어요.</div>';
  }
  greet();

  function current() {
    const st = ELI5.state, v = ELI5.MODEL.views[st.view] || {};
    const n = st.node ? (v.nodes || []).find(x => x.id === st.node) : null;
    return {st, v, n};
  }
  function chipText() { const {v, n} = current(); return (v.title || "") + (n ? " › " + n.title : ""); }
  function renderChip() {
    const {n} = current();
    $("chip").innerHTML = `<span>${esc(chipText())}${n ? ' <button id="unsel" type="button">×</button>' : ""}</span>`;
    const u = $("unsel");
    if (u) u.onclick = () => ELI5.select(null);
  }
  window.addEventListener("eli5:view", renderChip);
  window.addEventListener("eli5:select", renderChip);
  renderChip();

  function context() {
    const {st, v, n} = current();
    return {
      view: {id: st.view, title: v.title, hint: v.hint},
      node: n ? {id: n.id, title: n.title, lines: (n.lines || []).slice(0, 6)} : null,
      ifaces: (v.ifaces || []).slice(0, 30).map(f => ({title: f.title, from: f.from, to: f.to,
        items: (f.items || []).slice(0, 4).map(i => ({sig: i.sig, ref: i.ref}))}))
    };
  }

  const REF = /([A-Za-z0-9_.\/-]+\.[A-Za-z0-9]+):(\d+)/g;
  function md(text) {
    let h = esc(text);
    h = h.replace(/`([^`]+)`/g, "<code>$1</code>").replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>");
    return h.replace(REF, (m, p, l) => ELI5.refIndex.has(p + ":" + l) ? `<a class="ref" data-ref="${p}:${l}">${m}</a>` : m);
  }
  root.addEventListener("click", e => {
    const a = e.target.closest && e.target.closest("a.ref");
    if (a) ELI5.jumpRef(a.dataset.ref);
  });

  function add(cls, html) {
    const d = document.createElement("div");
    d.className = "msg " + cls;
    d.innerHTML = html;
    $("log").appendChild(d);
    $("log").scrollTop = 1e9;
    return d;
  }
  function dead() {
    $("dead").innerHTML = `서버가 종료됐습니다. 터미널에서 다시 여세요: <code>${esc(CMD)}</code> <button id="copy" type="button">복사</button>`;
    $("dead").classList.add("on");
    $("copy").onclick = () => { try { navigator.clipboard.writeText(CMD); } catch (_) {} };
  }

  let busy = false;
  async function ask(q) {
    if (busy || !q.trim()) return;
    busy = true; $("send").disabled = true;
    add("user", `<span class="chip">${esc(chipText())}</span>${esc(q)}`);
    const bot = add("bot", "…");
    const reading = document.createElement("div");
    reading.className = "reading";
    $("log").appendChild(reading);
    let text = "", done = false;
    try {
      const r = await fetch("/api/ask", {method: "POST", headers: {"Content-Type": "application/json"},
        body: JSON.stringify({conv_id: conv, question: q, context: context()})});
      if (r.status === 409) throw new Error("이 대화의 이전 질문이 아직 처리 중입니다");
      if (r.status === 403) { dead(); throw new Error("서버 인증이 끊겼습니다 (서버가 재시작됨)"); }
      if (!r.ok) throw new Error("서버 응답 " + r.status);
      $("q").value = "";
      const rd = r.body.getReader(), dec = new TextDecoder();
      let buf = "";
      for (;;) {
        const {value, done: end} = await rd.read();
        if (end) break;
        buf += dec.decode(value, {stream: true});
        let i;
        while ((i = buf.indexOf("\n")) >= 0) {
          const line = buf.slice(0, i); buf = buf.slice(i + 1);
          if (!line.trim()) continue;
          const ev = JSON.parse(line);
          if (ev.type === "delta") { text += ev.text; bot.textContent = text; }
          else if (ev.type === "tool") reading.textContent = "읽는 중: " + (ev.detail || ev.name);
          else if (ev.type === "final") { done = true; bot.innerHTML = md(ev.text || text); }
          else if (ev.type === "error") { done = true; bot.className = "msg err"; bot.textContent = ev.message; }
          $("log").scrollTop = 1e9;
        }
      }
      if (!done) { bot.className = "msg err"; bot.textContent = "답변이 중간에 끊겼습니다"; }
    } catch (e) {
      bot.className = "msg err";
      bot.textContent = String((e && e.message) || e);
      if (e instanceof TypeError) dead();
    } finally {
      reading.remove(); busy = false; $("send").disabled = false;
    }
  }
  $("f").addEventListener("submit", e => { e.preventDefault(); ask($("q").value); });
  $("q").addEventListener("keydown", e => {
    if (e.key === "Enter" && !e.shiftKey && !e.isComposing) { e.preventDefault(); ask($("q").value); }
  });
  $("new").onclick = () => { conv = newId(); try { localStorage.setItem(KEY, conv); } catch (_) {} greet(); };

  let deadTimer = null;
  const es = new EventSource("/api/life");
  es.addEventListener("hello", () => {
    if (deadTimer) { clearTimeout(deadTimer); deadTimer = null; }
    $("dead").classList.remove("on");
  });
  es.onerror = () => { if (!deadTimer) deadTimer = setTimeout(() => { es.close(); dead(); }, 30000); };
})();
</script>
```

- [ ] **Step 5: 테스트 통과 확인**

Run: `bash tests/unit/test_eli5_server.sh`
Expected: `=== 25 passed, 0 failed ===`. 실행 후 `ps -Ao pid,args | grep -c '[s]erver.py serve'` 가 0 (테스트가 띄운 서버가 남지 않음)

- [ ] **Step 6: 커밋**

```bash
git add skills/eli5/bin/server.py skills/eli5/assets/panel.html tests/unit/test_eli5_server.sh
git commit -m "feat(eli5): 지도 서버 — 패널 주입·토큰 인증·SSE 수명·open/stop/status

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: 질문 — `/api/ask` → `claude -p` + `answer-rules.md`

**Files:**
- Modify: `skills/eli5/bin/server.py` (함수 추가 + `Handler._ask`/`_emit`)
- Create: `skills/eli5/assets/answer-rules.md`
- Test: `tests/unit/test_eli5_server.sh` (섹션 추가)

**Interfaces:**
- Consumes: Task 4 의 `Eli5Server`(`convs`, `save_conv`, `children`, `busy`, `lock`, `paths`), `kill_group`, 가짜 claude 모드(`ok`/`noise`/`fail`/`empty`/`sleep`)
- Produces: `POST /api/ask {conv_id, question, context}` → `application/x-ndjson` 스트림. 이벤트 `{"type":"session","id"}` / `{"type":"delta","text"}` / `{"type":"tool","name","detail"}` / `{"type":"final","text","session"}` / `{"type":"error","message"}` — **항상 final 또는 error 하나로 끝남**. 400(형식) / 409(같은 대화 진행 중)
- Produces (모듈): `format_context(ctx) -> str`, `build_argv(srv, session) -> list[str]`, `child_env() -> dict`, `parse_line(obj) -> list[dict]`, `run_ask(srv, conv, question, ctx, emit)`

- [ ] **Step 1: 실패하는 테스트 추가** — `tests/unit/test_eli5_server.sh` 의 마지막 `finish` 줄 **바로 위**에 삽입

```bash
echo "🔧 질문"
start; life
ask() { curl -s -N -b "$JAR" -H "Origin: $BASE" -H 'Content-Type: application/json' -d "$1" "$BASE/api/ask"; }
Q='{"conv_id":"c1","question":"이거 뭐야?","context":{"view":{"id":"L0","title":"L0"},"node":{"id":"core","title":"엔진","lines":["run_job"]},"ifaces":[]}}'
echo ok > "$T/mode"
r=$(ask "$Q")
[ "$(echo "$r" | tail -1 | jq -r .type)" = "final" ] && pass "스트림이 final 로 끝남" || fail "final" "$r"
echo "$r" | jq -s -e 'map(.type) | (index("session") != null) and (index("tool") != null) and (index("delta") != null)' >/dev/null && pass "session·tool·delta 이벤트" || fail "이벤트 종류" "$r"
echo "$r" | jq -s -e 'map(select(.type=="tool"))[0].detail=="src/app.py"' >/dev/null && pass "tool detail" || fail "tool detail" "$r"
A=$(tail -1 "$T/argv.log")
echo "$A" | jq -e '.env_claudecode==null' >/dev/null && pass "CLAUDECODE 제거" || fail "CLAUDECODE" "$A"
echo "$A" | jq -e '.argv as $a | ($a|index("--allowedTools")) as $i | $a[$i+1]=="mcp__graft"' >/dev/null && pass "--allowedTools mcp__graft" || fail "allowedTools" "$A"
echo "$A" | jq -e '.argv as $a | ($a|index("--setting-sources")) as $i | $a[$i+1]==""' >/dev/null \
  && echo "$A" | jq -e '.argv|index("{\"disableAllHooks\": true}") != null' >/dev/null && pass "hook 차단 플래그" || fail "hook 차단" "$A"
echo "$A" | jq -e '.argv|index("--strict-mcp-config") != null' >/dev/null && pass "--strict-mcp-config" || fail "strict-mcp" "$A"
echo "$A" | jq -e '.argv|index("--resume")==null' >/dev/null && pass "첫 질문은 --resume 없음" || fail "첫 질문 resume" "$A"
echo "$A" | jq -e '.stdin|contains("[map context]") and contains("selected box: core") and contains("이거 뭐야?")' >/dev/null && pass "[map context] + 질문 전달" || fail "map context" "$A"
ask "$Q" >/dev/null
tail -1 "$T/argv.log" | jq -e '.argv as $a | ($a|index("--resume")) as $i | $a[$i+1]=="sess-1"' >/dev/null && pass "같은 대화 → --resume sess-1" || fail "resume"
echo noise > "$T/mode"; r=$(ask "${Q/c1/c2}")
[ "$(echo "$r" | tail -1 | jq -r .type)" = "final" ] && pass "JSON 아닌 줄 무시" || fail "noise" "$r"
echo fail > "$T/mode"; r=$(ask "${Q/c1/c3}")
echo "$r" | tail -1 | jq -e '.type=="error" and (.message|contains("boom")) and (.message|contains("3"))' >/dev/null && pass "비정상 종료 → error + stderr" || fail "fail" "$r"
echo empty > "$T/mode"; r=$(ask "${Q/c1/c4}")
echo "$r" | tail -1 | jq -e '.type=="error" and (.message|contains("비어"))' >/dev/null && pass "빈 출력 → error" || fail "empty" "$r"
echo sleep > "$T/mode"
ask "${Q/c1/c5}" > "$T/slow.out" & SLOW=$!; BGPIDS+=("$SLOW"); sleep 0.5
[ "$(code -b "$JAR" -H "Origin: $BASE" -H 'Content-Type: application/json' -d "${Q/c1/c5}" "$BASE/api/ask")" = "409" ] && pass "같은 대화 동시 질문 409" || fail "409"
wait "$SLOW"
tail -1 "$T/slow.out" | jq -e '.type=="error" and (.message|contains("시간 초과"))' >/dev/null && pass "타임아웃 → error" || fail "timeout" "$(cat "$T/slow.out")"
sleep 1; pgrep -f "sleep 3001" >/dev/null && fail "타임아웃 후 손자 프로세스 정리" || pass "타임아웃 후 손자 프로세스 정리"
[ "$(code -b "$JAR" -H "Origin: $BASE" -H 'Content-Type: application/json' -d '{"conv_id":"bad id!","question":"x"}' "$BASE/api/ask")" = "400" ] && pass "잘못된 conv_id 400" || fail "400"

echo "🔧 재기동 후 대화 유지"
echo ok > "$T/mode"
kill "$LIFE"; python3 "$S" stop --model "$M" >/dev/null; wait_dead "$PID" 3
start; life; ask "$Q" >/dev/null
tail -1 "$T/argv.log" | jq -e '.argv as $a | ($a|index("--resume")) as $i | $a[$i+1]=="sess-1"' >/dev/null && pass "서버 재기동 후 --resume" || fail "재기동 resume" "$(tail -1 "$T/argv.log")"

echo "🔧 종료 시 진행 중 질문 정리"
kill "$LIFE"; python3 "$S" stop --model "$M" >/dev/null; wait_dead "$PID" 3
export ELI5_ASK_TIMEOUT_SEC=30; start; export ELI5_ASK_TIMEOUT_SEC=2; life
echo sleep > "$T/mode"
ask "${Q/c1/c6}" >/dev/null & BGPIDS+=("$!"); sleep 0.5
pgrep -f "sleep 3001" >/dev/null && pass "(전제) 질문 진행 중" || fail "(전제) 질문 진행 중"
kill "$LIFE"
wait_dead "$PID" 4 && pass "탭 닫힘 → 서버 종료" || fail "서버 종료"
sleep 0.5; pgrep -f "sleep 3001" >/dev/null && fail "진행 중 자식까지 정리" || pass "진행 중 자식까지 정리"
```

- [ ] **Step 2: 실행해서 실패 확인**

Run: `bash tests/unit/test_eli5_server.sh`
Expected: Task 4 항목은 통과, "🔧 질문" 이후 FAIL (POST 가 404)

- [ ] **Step 3: `skills/eli5/assets/answer-rules.md` 작성**

```markdown
너는 브라우저에서 아키텍처 지도를 보는 사람의 질문에 답한다. 답은 지도 옆 패널에 표시된다. 읽기 전용이다 — 파일을 수정하거나 명령을 실행하지 않는다.

## 근거 우선순위

1. 지도 모델 JSON (아래 "이 지도" 경로) — 박스·화살표·인터페이스 카드와 각 요소의 근거 등급(`graft` 증명 / `code` 코드 읽음 / `record` 기록 해석 / `unknown` 미확인)
2. graft 도구 (`mcp__graft__*`) — 호출 관계와 심볼 위치. 소스 트리를 통째로 훑지 말고 graft 로 좁힌다
3. 소스 파일 — 지도나 graft 로 위치를 안 다음, 필요한 파일만 Read 한다

## 답하는 법

- 질문한 언어로 답한다. 코드 이름·경로는 원문 그대로 둔다
- 모든 사실 주장에 근거를 단다. 소스는 레포 루트 기준 `path:line` 형식으로 쓴다 — 패널이 이 형식을 지도 카드 링크로 바꾼다
- 질문 앞의 `[map context]` 는 사용자가 지금 보는 레이어와 선택한 박스다. "이거", "여기" 는 선택한 박스를 가리킨다
- 지도에서 등급이 `unknown` 인 요소를 설명할 때는 "지도에서도 미확인" 이라고 먼저 밝힌다. `record` 는 "기록 기반 해석" 이라고 밝힌다
- 근거를 못 찾으면 모른다고 말하고, 무엇을 확인하면 되는지 한 줄로 적는다. "이런 시스템은 보통…" 식으로 추측하지 않는다
- 짧게 답한다. 한 줄로 충분하면 한 줄로
```

- [ ] **Step 4: `server.py` 에 질문 함수 추가** — `def cmd_serve(a):` **바로 위**에 삽입

```python
def format_context(ctx):
    lines = ["[map context]"]
    v = ctx.get("view") or {}
    if v:
        lines.append(f"current layer: {v.get('id', '')} — {v.get('title', '')}")
        if v.get("hint"):
            lines.append(f"layer hint: {v['hint']}")
    n = ctx.get("node")
    if n:
        lines.append(f"selected box: {n.get('id', '')} — {n.get('title', '')}")
        lines += [f"  {l}" for l in (n.get("lines") or [])[:6]]
    ifaces = (ctx.get("ifaces") or [])[:30]
    if ifaces:
        lines.append("interfaces on this layer:")
        for f in ifaces:
            lines.append(f"- {f.get('title', '')} ({f.get('from', '')} → {f.get('to', '')})")
            lines += [f"    {it.get('sig', '')}  @ {it.get('ref', '')}" for it in (f.get("items") or [])[:4]]
    text = "\n".join(lines)
    return text if len(text) <= MAX_CONTEXT else text[:MAX_CONTEXT] + "\n…(truncated)"


def build_argv(srv, session):
    rules = (ASSETS / "answer-rules.md").read_text(encoding="utf-8")
    rules += f"\n\n## 이 지도\n\n- 지도 모델: `{srv.paths.model}`\n- 레포 루트: `{srv.paths.root}`\n"
    argv = [CLAUDE_BIN, "-p", "--output-format", "stream-json", "--verbose", "--include-partial-messages",
            "--tools", "Read,Grep,Glob", "--strict-mcp-config"]
    graft = shutil.which(GRAFT_BIN)
    if graft:
        mcp = {"mcpServers": {"graft": {"command": graft, "args": ["mcp", str(srv.paths.root)]}}}
        argv += ["--mcp-config", json.dumps(mcp), "--allowedTools", "mcp__graft"]
    argv += ["--setting-sources", "", "--settings", json.dumps({"disableAllHooks": True}),
             "--append-system-prompt", rules]
    if session:
        argv += ["--resume", session]
    return argv


def child_env():
    env = dict(os.environ)
    for k in STRIP_ENV:
        env.pop(k, None)
    return env


def tool_detail(inp):
    if isinstance(inp, dict):
        for k in ("file_path", "path", "pattern", "symbol", "query", "file"):
            if inp.get(k):
                return str(inp[k])[:120]
    return ""


def parse_line(obj):
    t = obj.get("type")
    if t == "system" and obj.get("subtype") == "init":
        return [{"type": "session", "id": obj.get("session_id")}]
    if t == "stream_event":
        ev = obj.get("event") or {}
        d = ev.get("delta") or {}
        if ev.get("type") == "content_block_delta" and d.get("type") == "text_delta":
            return [{"type": "delta", "text": d.get("text", "")}]
        return []
    if t == "assistant":
        return [{"type": "tool", "name": c.get("name", ""), "detail": tool_detail(c.get("input"))}
                for c in (obj.get("message") or {}).get("content", []) if c.get("type") == "tool_use"]
    if t == "result":
        if obj.get("is_error") or obj.get("subtype") != "success":
            return [{"type": "error", "message": str(obj.get("result") or obj.get("subtype") or "실패")}]
        return [{"type": "final", "text": obj.get("result") or "", "session": obj.get("session_id")}]
    return []


def run_ask(srv, conv, question, ctx, emit):
    try:
        proc = subprocess.Popen(build_argv(srv, srv.convs.get(conv)), cwd=str(srv.paths.root), env=child_env(),
                                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                start_new_session=True, text=True, encoding="utf-8", errors="replace")
    except OSError as e:
        emit({"type": "error", "message": f"claude 실행 실패: {e}"})
        return
    srv.children.add(proc)
    tail = collections.deque(maxlen=20)
    err_reader = threading.Thread(target=lambda: [tail.append(l.rstrip()) for l in proc.stderr], daemon=True)
    err_reader.start()
    timed_out = threading.Event()

    def on_timeout():
        timed_out.set()
        kill_group(proc)

    timer = threading.Timer(ASK_TIMEOUT, on_timeout)
    timer.daemon = True
    timer.start()
    ended = False
    try:
        try:
            proc.stdin.write(format_context(ctx) + "\n\n" + question)
            proc.stdin.close()
        except OSError:
            pass
        for line in proc.stdout:
            try:
                obj = json.loads(line)
            except ValueError:
                continue
            for ev in parse_line(obj):
                if ev["type"] == "session" and ev.get("id"):
                    srv.save_conv(conv, ev["id"])
                if ev["type"] in ("final", "error"):
                    if ended:
                        continue
                    ended = True
                    if ev["type"] == "final" and ev.get("session"):
                        srv.save_conv(conv, ev["session"])
                emit(ev)
        proc.wait()
        err_reader.join(timeout=2)
        if not ended:
            if timed_out.is_set():
                emit({"type": "error", "message": f"시간 초과 ({int(ASK_TIMEOUT)}초) — 질문을 좁혀 다시 시도하세요"})
            elif proc.returncode != 0:
                emit({"type": "error", "message": f"claude 종료 코드 {proc.returncode}\n" + "\n".join(tail)})
            else:
                emit({"type": "error", "message": "답변이 비어 있다 (claude 가 결과 없이 종료)"})
    except OSError:
        pass  # 브라우저 연결 끊김 — finally 에서 정리
    finally:
        timer.cancel()
        kill_group(proc)
        srv.children.discard(proc)
```

- [ ] **Step 5: `Handler` 에 `_ask`/`_emit` 추가** — `class Handler` 안, `def _life(self):` **바로 위**에 삽입

```python
    def _ask(self):
        srv = self.server
        try:
            n = int(self.headers.get("Content-Length", "0"))
            if n > 65536:
                raise ValueError("too large")
            req = json.loads(self.rfile.read(n) or b"{}")
            conv, q = str(req.get("conv_id", "")), str(req.get("question", "")).strip()
            if not CONV_RE.match(conv) or not q or len(q) > 4000:
                raise ValueError("bad request")
        except ValueError:
            return self._send(400, b"bad request")
        with srv.lock:
            busy = conv in srv.busy
            if not busy:
                srv.busy.add(conv)
        if busy:
            return self._send(409, b"busy")
        try:
            self.send_response(200)
            self.send_header("Content-Type", "application/x-ndjson; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            run_ask(srv, conv, q, req.get("context") or {}, self._emit)
        finally:
            with srv.lock:
                srv.busy.discard(conv)

    def _emit(self, ev):
        self.wfile.write((json.dumps(ev, ensure_ascii=False) + "\n").encode("utf-8"))
        self.wfile.flush()
```

`do_POST` 의 `hasattr(self, "_ask")` 분기는 이제 항상 참이므로 정리한다:

```python
        if urlparse(self.path).path == "/api/ask":
            return self._ask()
        return self._send(404, b"not found")
```

- [ ] **Step 6: 테스트 통과 확인**

Run: `bash tests/unit/test_eli5_server.sh`
Expected: `=== 46 passed, 0 failed ===` (Task 4 25 + Task 5 21). 이후 `pgrep -f 'sleep 3001'` 와 `pgrep -f 'server.py serve'` 모두 출력 없음

- [ ] **Step 7: 커밋**

```bash
git add skills/eli5/bin/server.py skills/eli5/assets/answer-rules.md tests/unit/test_eli5_server.sh
git commit -m "feat(eli5): 질문 패널 백엔드 — claude -p 스트리밍·대화 이어가기·타임아웃 정리

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: `SKILL.md` 재작성 + lint/test 연결 + 문서

**Files:**
- Modify: `skills/eli5/SKILL.md` (전체 교체)
- Modify: `lint.sh` (task-router 유닛 테스트 블록 다음), `test.sh` (`test_orca` 함수 다음 + `case`), `README.md:58`, `README.md:108`, `CHANGELOG.md` (`## [Unreleased]` → `### Added` 첫 항목)

**Interfaces:**
- Consumes: Task 1~5 의 CLI 전부 (인자·출력 JSON 그대로)
- Produces: 사용자 명령 `/rakis:eli5 <대상> [--out <dir>] [--quick] [--no-open]`, `/rakis:eli5 open [<model.json>]`, `/rakis:eli5 stop [<model.json>]`

- [ ] **Step 1: `skills/eli5/SKILL.md` 전체 교체**

````markdown
---
name: eli5
description: "코드베이스·시스템 구조를 사람이 따라 내려갈 수 있는 드릴다운 HTML 지도로 만들고, 지도 옆 패널에서 바로 여러 턴으로 질문할 수 있게 연다. 화살표마다 graft 호출 그래프·소스 인용·기록으로 근거를 기계 판정해 실선(graft 증명)·점선(코드 읽음)·주황(기록 해석)·빨강(미확인)으로 구분한다. '그림으로 설명해줘', '구조 좀 그려줘', '이 코드 어떻게 도는지 보여줘', '아키텍처 지도', '/rakis:eli5 <대상>' 일 때 사용. 낯선 모듈 파악·설계 검토·장애 경로 추적·구현 전 정렬 확인."
version: 2.0.0
license: MIT
---

# eli5 — 근거가 검증된 지도 + 질문 패널

정돈된 상자와 화살표는 정확하다는 인상을 준다. 하지만 그림의 사실성은 무엇을 읽고 그렸는지에만 달려 있다. v1 은 그 판단을 LLM 의 성실성에 맡겼다. v2 는 **LLM 은 내용만 쓰고, 판정과 그리기는 스크립트가 한다.**

- 화살표의 진위는 `validate.py` 가 graft 호출 그래프·파일·git 으로 판정한다. 주장한 근거가 확인되지 않으면 자동으로 강등된다
- HTML 은 `render.py` 가 고정 템플릿으로 만든다. LLM 은 HTML 을 쓰지 않는다
- 지도는 `server.py` 가 질문 패널을 붙여 연다. 답은 read-only `claude -p` 가 지도 모델과 graft 를 근거로 만든다

쓰임은 쉬운 설명이 아니다. **구현 전에 사람과 에이전트가 같은 시스템을 보고 있는지 확인하는 것**이다.

## 인자

```
/rakis:eli5 <설명할 대상> [--out <dir>] [--quick] [--no-open]
/rakis:eli5 open [<model.json>]      기존 지도를 패널과 함께 다시 연다
/rakis:eli5 stop [<model.json>]      패널 서버 수동 종료
```

- `--out` — 출력 폴더. 기본 `<레포>/.eli5/` (`.git/info/exclude` 로 숨긴다)
- `--quick` — 인용 줄 대조(quote)와 Phase 5 렌더링 확인을 생략한다. 지도에 "미검증" 배지가 붙고, **구현·리뷰의 근거로 쓰지 않는다.** 무결성 검사와 graft 판정은 생략하지 않는다
- `--no-open` — 지도만 만들고 서버는 띄우지 않는다

## 경로 약속

- `$SKILL` = 이 스킬의 base directory (호출 시 "Base directory for this skill" 로 주어진다). 스크립트는 `$SKILL/bin/`
- `$ROOT` = 대상 git 레포 루트. `$OUT` = `--out` 또는 `$ROOT/.eli5`
- slug = 대상을 영문 kebab-case 3~5 단어로 축약
- `$MODEL` = `$OUT/<slug>.model.json` → 지도 `$OUT/<slug>.html`, 사이드카 `$OUT/<slug>.eli5.json`

## 원칙

- 코드 실행 순서가 아니라 **사람과 시스템이 주고받는 일의 순서**로 그린다
- **모르는 것은 그리지 않는다.** 그려야 한다면 `unknown` 등급으로 그리고 `unknowns` 에 남긴다
- 글은 박스 라벨 수준으로. 상세는 인터페이스 카드로
- 대상 레포의 추적 파일을 바꾸지 않는다

## Phase 0: graft 준비

```bash
git -C "$ROOT" status --short    # 출력을 기억해 둔다 — Phase 6 에서 대조
python3 "$SKILL/bin/graft_prep.py" --root "$ROOT" --out-dir "<$OUT 의 $ROOT 상대경로>"
```

출력의 `graft` 값(`ok`·`index-built`·`absent`)을 기억해 Phase 3 에 넘긴다. `absent` 면 "graft 가 없어 실선(증명) 화살표를 만들 수 없다" 고 한 줄 알리고 계속한다. `error` 면 내용을 보여주고 멈춘다.

## Phase 1: 조사 — 그림보다 먼저

읽지 않은 것은 그리지 않는다. 추적 순서: 진입점 → 호출 경로 → 데이터 저장소 → 오류·롤백 경로.

1. `graft map` — 디렉터리 클러스터·허브로 레이어 후보를 잡는다
2. `graft ask "<대상>" --source` — 흐름의 핵심 심볼과 `file:line`
3. 박스 간 관계 후보마다 `graft callers <심볼> --json` (`--direction out` 으로 callee) — **여기서 본 노드 id(`path#symbol`)를 그대로 메모한다.** 이것이 graft 등급의 증거다
4. graft 가 못 보는 관계 — HTTP·큐·subprocess·설정 기반 연결 — 는 소스를 직접 읽는다. 호출하는 줄의 `path:line` 과 그 줄의 짧은 문자열(quote)을 메모한다
5. 코드로 "왜" 가 확정되지 않으면 ADR·`docs/`·이슈·PR 본문·`git log -p --follow <file>` 을 읽는다

대상이 코드가 아니면(개념·프로토콜·외부 서비스) 조사 대상을 문서로 바꾸되 근거는 똑같이 남긴다.

## Phase 2: 모델 작성

`$MODEL` 을 쓴다.

```json
{
  "meta": {"target": "<대상>", "scope": ["src/"], "graft_version": "<Phase 0 version>"},
  "views": {
    "L0": {
      "title": "L0 · 실행 단위", "hint": "<이 층을 한 문장으로>", "parent": null,
      "rules": [{"text": "<설계 규칙>", "grade": "code|record|unknown", "evidence": {}}],
      "nodes": [{"id": "api", "title": "API 서버", "lines": ["<2~3줄>"], "row": 0, "col": 0, "span": 1,
                 "paths": ["src/api/"], "drill": "L1-api"}],
      "edges": [{"from": "api", "to": "core", "label": "<인터페이스 이름>", "iface": "<iface id>",
                 "grade": "graft|code|record|unknown", "evidence": {}}],
      "ifaces": [{"id": "...", "title": "...", "from": "api", "to": "core", "transport": "python call|http|queue|subprocess|file",
                  "items": [{"sig": "<시그니처>", "desc": "<한 줄>", "ref": "path:line"}]}]
    }
  },
  "unknowns": [{"text": "...", "why": "..."}]
}
```

**등급과 evidence** — 검증기가 이 형식으로만 판정한다:

| 등급 | 언제 | evidence |
|---|---|---|
| `graft` | Phase 1-3 에서 `graft callers` 로 직접 본 호출 | `{"from_sym": "src/api/server.py#handle", "to_sym": "src/core/engine.py#run_job"}` — 노드 id 를 **복사**. 지어내면 검증기가 강등한다. 같은 관계를 코드로도 읽었다면 `ref`·`quote` 를 함께 넣는다 (graft 판정 실패 시 code 로 강등되는 안전망) |
| `code` | 소스에서 직접 읽은 관계 (HTTP·큐·subprocess 등) | `{"ref": "src/core/engine.py:5", "quote": "requests.post"}` — quote 는 그 줄(±2)에 실제로 있는 10~40자 |
| `record` | ADR·PR·커밋 메시지 기반 해석 | `{"ref": "<커밋 해시 | PR#123 | docs/adr-1.md>"}` |
| `unknown` | 근거 없음 | `{}` |

작성 규칙:

- 레이어: L0 = 프로세스·저장소·외부 시스템. 분해할 게 남은 박스는 `drill` 로 하위 view 를 만든다. view 하나에 박스 5~9 개
- 모든 박스에 `paths[]` — 그 박스가 담당하는 경로 접두사. 외부 시스템은 `[]`. graft 판정은 증거 심볼이 이 경로 안에 있는지까지 본다
- `rules[]` 는 "A 는 B 를 import 하지 않는다" 같은 설계 규칙. **`graft` 등급 금지** (부재는 callers 로 증명할 수 없다)
- 격자: 흐름 방향대로 왼→오, 위→아래. 같은 칸 금지. 화살표는 직선이므로 사이에 다른 박스가 끼지 않게 배치한다
- 모든 iface 는 최소 한 edge 가 참조해야 한다

## Phase 3: 검증

```bash
python3 "$SKILL/bin/validate.py" "$MODEL" --root "$ROOT" --graft-status <Phase 0 값> [--quick]
```

- **exit 1** — `integrity_errors` 를 고치고 다시 실행한다. 3 회 연속 실패하면 멈추고 오류 목록을 보고한다
- **exit 0** — 리포트를 읽는다
  - `downgrades`: **받아들인다.** 강등을 피하려고 근거를 바꾸지 않는다. 예외는 하나 — 사유가 "paths 밖" 이고 박스 `paths[]` 를 실제로 잘못 잡은 경우에만 paths 를 고쳐 재검증한다
  - `missing_edges`: graft 가 찾았는데 그림에 없는 관계. 의미 있는 관계면 graft 등급 edge 로 추가하고 재검증한다. 의도적으로 뺐다면 그대로 둔다 (지도 하단에 노출된다)

## Phase 4: 렌더

```bash
python3 "$SKILL/bin/render.py" "$MODEL" --root "$ROOT"
```

HTML 을 직접 쓰거나 고치지 않는다. 모양을 바꾸려면 모델을 고쳐 Phase 3 부터 다시.

## Phase 5: 렌더링 확인

`--quick` 이면 생략하고 출력에 "렌더링 미확인" 을 남긴다.

- Chrome 자동화(`mcp__claude-in-chrome__*`)가 있으면 `file://<html>` 을 열고 view 마다(`#view=<id>`) 스크린샷을 찍어 박스 겹침·라벨 충돌·박스를 관통하는 화살표·잘린 글자를 확인한다. 문제는 모델의 격자를 고쳐 Phase 3~4 를 다시 돈다
- 없으면 `open "<html>"` 후 사용자에게 확인을 요청한다. "열릴 것이다" 로 넘어가지 않는다

## Phase 6: 열기

`--no-open` 이 아니면:

```bash
python3 "$SKILL/bin/server.py" open --model "$MODEL"
```

- `panel: false` 면 `reason` 을 전한다 (claude CLI 없음 → 패널 없는 지도만 열림)
- `git -C "$ROOT" status --short` 가 Phase 0 기록과 같은지 대조한다. 다르면 무엇이 생겼는지 보고한다

## Phase 7: 출력

```
✓ <slug>.html   패널: <url>
  근거: graft a · 코드 b · 기록 c · 미확인 d   (검증 강등 n건)
  그림에 없는 관계: m건
  확인 못 한 것:
    - <unknowns 항목>
  서버: 탭을 닫으면 30초 뒤 자동 종료 · 수동 종료 /rakis:eli5 stop
```

마지막 줄로 안내한다:

> 이 지도는 코드를 대신하지 않는다. 어디부터 어떤 관점으로 읽을지 정해주는 첫 지도다. 중요한 결론은 원본 코드·로그·변경 이력으로 다시 확인한다.

## open / stop

- `open` — 모델 경로가 없으면 `$ROOT/.eli5/*.model.json` 중 가장 최근 것. 먼저 `python3 "$SKILL/bin/server.py" status --model "$MODEL"` 로 지도 상태를 본다. `stale` 이면 "지도가 코드보다 낡았다 — 다시 만들까요, 그대로 열까요?" 를 묻는다 (기본 그대로 열기 — 열면 패널에 경고 배너). 다시 만들기는 기존 모델을 출발점으로 Phase 1 부터
- `stop` — `python3 "$SKILL/bin/server.py" stop --model "$MODEL"`

## 하지 않는 것

- 보안 검토·장애 원인 보고서를 대체하지 않는다
- 그림이 틀렸다는 지적을 받기 전에 구현으로 넘어가지 않는다 — 이 스킬의 존재 이유가 그 확인 단계다
- 조사 없이 그림부터 그리지 않는다
- graft 등급을 graft 로 보지 않고 주장하지 않는다

## 출처

- 공식 `eli5` 스킬 — [anthropics/claude-plugins-community](https://github.com/anthropics/claude-plugins-community/tree/main/eli5) (Thariq Shihipar, MIT)
- 보강 조건 — [앤트로픽의 ELI5 스킬 (desty, 2026-08-23)](https://desty.github.io/blog/60-eli5-visual-explainer/)
- 레이어 드릴다운·인터페이스 카드·패널 주입 구조 — [robintech-seoul/agent-toolkit](https://github.com/robintech-seoul/agent-toolkit) `arch-explorer` (설계만 참고, 코드 미사용 — 라이선스 없음)
- 호출 그래프 — [graft](https://github.com/trailhq/Graft) (MIT)
- 설계 문서 — `docs/superpowers/specs/2026-10-01-eli5-graft-chat-design.md`
````

- [ ] **Step 2: `lint.sh` 에 빠른 유닛 테스트 연결** — `task-router 유닛 테스트` 블록(`fi` 로 끝나는 부분) **바로 다음**에 삽입

```bash
for t in prep validate render; do
  if bash "tests/unit/test_eli5_$t.sh" >/dev/null 2>&1; then
    pass "eli5 $t 유닛 테스트"
  else
    fail "eli5 $t 유닛 테스트 — bash tests/unit/test_eli5_$t.sh"
  fi
done
```

- [ ] **Step 3: `test.sh` 에 서버 테스트 연결** — `test_orca()` 함수 정의 **바로 다음**에 함수를 추가하고, `case "$TARGET" in` 의 `all)` 블록 `test_orca` 다음 줄에 `test_eli5` 를, `orca)` 항목 다음에 `eli5)` 항목을 추가

```bash
# ─── eli5 서버 테스트 ───

test_eli5() {
  echo "🔬 eli5 서버 테스트"
  if bash tests/unit/test_eli5_server.sh; then
    pass "eli5 서버 (수명·보안·질문)"
  else
    fail "eli5 서버 (수명·보안·질문)"
  fi
  echo ""
}
```

```bash
  eli5)
    test_eli5
    ;;
```

- [ ] **Step 4: README·CHANGELOG**

`README.md:58` 행을 교체:

```markdown
| `eli5` | 코드 구조를 graft 로 근거 검증한 드릴다운 HTML 지도 + 지도 옆 질문 패널 |
```

`README.md:108` 행 다음 줄에 추가:

```markdown
/rakis:eli5 open                                   # 만들어 둔 지도를 질문 패널과 함께 다시 열기
```

`CHANGELOG.md` 의 `## [Unreleased]` → `### Added` 바로 아래 첫 항목으로 추가:

```markdown
- `eli5` **v2 — graft 로 근거를 기계 판정하는 지도 + 지도 옆 질문 패널.** v1 은 LLM 이 HTML 을 직접 쓰고 "확인" 등급도 스스로 매겼다 — 그림의 사실성이 LLM 의 성실성에 달려 있었다. v2 는 역할을 나눈다: LLM 은 지도 모델 JSON(레이어·박스·화살표·근거)만 쓰고, `validate.py` 가 근거를 판정하고, `render.py` 가 고정 템플릿으로 그린다. 등급 4종 — `graft`(`graft callers` 로 호출이 확인됨, 실선) / `code`(인용한 `path:line` ±2 줄에 quote 가 실제로 있음, 점선) / `record`(커밋·PR·문서 존재, 주황) / `unknown`(빨강). 확인되지 않은 주장은 자동 강등되고 사유가 지도 하단에 남는다. graft `wiring.json` 으로 **graft 가 아는데 그림에 없는 관계**도 보고한다. 질문 패널은 로컬 서버가 지도에 주입하고, 질문마다 read-only `claude -p`(Read/Grep/Glob + graft MCP 만)가 지도 모델과 graft 를 근거로 `path:line` 을 달아 답한다. `--resume` 으로 여러 턴, 서버를 재시작해도 대화가 이어진다. **좀비 방지**: 서버 수명을 세션이 아니라 페이지의 SSE 연결에 묶었다 — 마지막 탭을 닫으면 30초 뒤 스스로 종료하며 진행 중인 claude 프로세스 그룹까지 정리하고, 하드캡 24시간. 실측으로 찾은 함정 둘: `--allowedTools mcp__graft` 가 없으면 MCP 호출이 `permission_denied` 로 막혀 답이 "권한이 필요합니다" 로 끝나고, `--setting-sources "" --settings '{"disableAllHooks":true}'` 가 없으면 사용자 전역 hook(실측 SessionStart 6개)이 질문마다 돈다. 업무 레포에서도 추적 파일을 바꾸지 않는다 — `graft build` 가 만든 `.gitignore` 변경은 원복하고 생성물은 `.git/info/exclude` 로만 숨긴다. 설계: `docs/superpowers/specs/2026-10-01-eli5-graft-chat-design.md`
```

- [ ] **Step 5: lint·테스트 실행**

Run: `./lint.sh 2>&1 | tail -15 && bash test.sh eli5`
Expected: lint 에 `eli5 prep/validate/render 유닛 테스트` ✅ 3줄, 실패 0. `test.sh eli5` 는 `eli5 서버 (수명·보안·질문)` ✅. `skills/eli5/SKILL.md` 라인 수 500 이하

- [ ] **Step 6: 커밋**

```bash
git add skills/eli5/SKILL.md lint.sh test.sh README.md CHANGELOG.md
git commit -m "feat(eli5): v2 스킬 절차 — 조사→모델→검증→렌더→패널

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: 실측 검증 (가짜 CLI 통과는 실행 검증이 아니다)

**Files:** 없음 (검증만. 발견한 결함은 해당 Task 파일을 고치고 그 Task 의 테스트에 재현 케이스를 추가한 뒤 커밋)

**Interfaces:**
- Consumes: 완성된 스킬 전체, 실제 `claude`·`graft`

- [ ] **Step 1: 실제 레포에서 스킬 완주** — rakis 레포 자신을 대상으로

이 브랜치의 플러그인을 로드한 새 Claude Code 세션에서 (`claude --plugin-dir ~/workspace/raki-claude-plugins` 또는 설치본 업데이트 후):

```
/rakis:eli5 "source-fetch 가 링크를 따라가는 흐름"
```

확인: Phase 0~7 출력이 나온다 / `.eli5/` 에 model·html·sidecar 3개 / `git status --short` 가 실행 전과 같다 / 출력의 강등·누락 목록을 사람이 훑어 **오판(맞는 graft 관계가 강등됨, 엉뚱한 누락)** 이 없는지 본다. 오판이 있으면 `validate.py` 판정 로직 결함이므로 Task 2 테스트에 그 케이스를 추가해 고친다

- [ ] **Step 2: 패널 실사용 — 2턴 + 재기동**

열린 패널에서:
1. 박스 하나를 선택하고 "이거 뭐 하는 거야?" → 답에 `path:line` 이 있고, 그중 카드 ref 와 일치하는 것은 링크로 표시되며 클릭하면 카드로 이동한다. "읽는 중: …" 이 잠깐 보인다
2. "그럼 실패하면 어떻게 돼?" → 1번 맥락을 이어서 답한다
3. 터미널에서 `python3 <skill>/bin/server.py stop --model <model>` → 30초 안에 패널에 "서버가 종료됐습니다" 배너 + 복사 버튼
4. `/rakis:eli5 open` 으로 다시 열고 "아까 내가 뭘 물었지?" → 1번 질문을 기억한다

- [ ] **Step 3: 좀비 없음 확인**

탭을 닫고 40초 기다린 뒤:

```bash
ps -Ao pid,ppid,etime,args | grep -E '[s]erver.py serve|[c]laude -p --output-format stream-json'
```

Expected: 출력 없음

- [ ] **Step 4: 업무 레포 1곳 (graft 인덱스가 이미 있는 곳)**

`~/workspace/KT/agent-production-profitability` 의 워크트리 하나에서 작은 대상으로 실행. 확인: `graft_prep` 결과 `ok` / `git status --short` 무변화 / 프로세스 경계(HTTP) 화살표가 `code` 등급으로 그려짐

- [ ] **Step 5: 결과 기록 + 최종 커밋**

결함이 없으면 커밋할 것이 없다. 발견·수정이 있었다면 해당 Task 형식대로 커밋하고, 실측 결과(대상·등급 집계·강등 건수·좀비 확인)를 PR 본문에 적는다
