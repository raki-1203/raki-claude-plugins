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
CLAUDE_MODEL = "sonnet"  # 패널 답변은 지도·graft 근거 조회라 sonnet 으로 충분하다


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
        if urlparse(self.path).path == "/api/ask":
            return self._ask()
        return self._send(404, b"not found")

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
    argv = [CLAUDE_BIN, "-p", "--model", CLAUDE_MODEL, "--output-format", "stream-json", "--verbose", "--include-partial-messages",
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
