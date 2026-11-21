#!/usr/bin/env python3
"""A stand-in for mira-core, for UI tests that must not touch the real server.

It speaks just enough of the API for the app to connect, list conversations,
open them and run a chat turn, and it can misbehave on request, which the real
server cannot be asked to do:

  message contains STUBDROP   stream for 3 s, then go silent with the socket
                              open (no tokens, no heartbeat). The turn is still
                              saved 12 s after it started, like the real server,
                              which finishes a turn whether or not anyone listens.
  message contains STUBSLOW   a healthy 20 s stream with heartbeats, saved at the end.
  anything else               a healthy 2 s stream.

Like the real server it creates the conversation row when the turn starts,
saves the turn only when it ends, saves nothing for a cancelled turn, and
reports a new conversation's id only in the closing `title` event.

GET /_stub/log returns every mutating request it received (method, path and
body), so a test can assert that nothing was deleted or cancelled.
POST /_stub/set {"backend_ready": false} makes /health report the backend as
down, which puts the app's banner above the message list; true takes it away.
POST /_stub/reset restores the seeded conversations and clears the log.
Some conversations answer GET .../messages slowly, to hold the app in its
loading state.

Binds to 127.0.0.1 only. Usage: mira-stub-server.py [port]   (default 18765)
"""
import json
import re
import sys
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 18765
RUN = uuid.uuid4().hex[:6]  # ids differ per run, so the app's cache starts cold
LOCK = threading.Lock()
LOG = []          # mutating requests
CANCELLED = set() # conversation ids with a cancelled turn ("" = all)
CONVS = {}        # id -> dict(title, created_at, updated_at, messages, delay)
FLAGS = {"backend_ready": True}  # POST /_stub/set {"backend_ready": false} shows the app's banner

PARAGRAPH = (
    "The keeper climbed the spiral stair every evening, counting the steps as his "
    "father had, and trimmed the wick before the light left the water. Ships he "
    "would never meet passed beyond the reef, each one trusting a beam it could "
    "not thank. "
)


def long_reply(n: int, seed: int) -> str:
    parts = [f"## Section {seed}.{i + 1}\n\n" + PARAGRAPH * (2 + (i + seed) % 3) for i in range(n)]
    parts.insert(1, "- first point about the tide\n- second point about the lamp\n- third point about the log book\n")
    parts.insert(2, "```python\ndef beam(angle):\n    return (angle * 7) % 360\n```\n")
    parts.insert(3, "| Watch | Hours | Lamp |\n|---|---|---|\n| First | 4 | lit |\n| Middle | 4 | lit |\n| Morning | 4 | out |\n")
    return "\n\n".join(parts)


def make_conv(title, turns, sections, delay=0.0, thinking=False):
    now = int(time.time())
    cid = f"stub-{RUN}-{len(CONVS):02d}"
    messages = []
    for t in range(turns):
        messages.append({"role": "user", "content": f"Question {t + 1}: tell me more about the lighthouse."})
        messages.append({
            "role": "assistant",
            "content": long_reply(sections, t + 1),
            "thinking_content": ("The user wants more detail. " * 20) if thinking else None,
        })
    CONVS[cid] = {
        "title": title, "created_at": now - 86400 - len(CONVS), "updated_at": now - 3600 - len(CONVS),
        "messages": messages, "delay": delay,
    }
    return cid


def seed():
    CONVS.clear()
    make_conv("Long history", 30, 4)
    make_conv("Short chat", 3, 2)
    make_conv("With thinking", 12, 5, thinking=True)
    make_conv("Slow to load", 8, 4, delay=2.5)
    make_conv("Very long replies", 4, 40)
    make_conv("Very slow to load", 10, 3, delay=5.0)
    make_conv("Many short turns", 100, 1)


seed()


def conv_list():
    rows = [
        {"id": cid, "title": c["title"], "created_at": c["created_at"], "updated_at": c["updated_at"],
         "model_name": "stub/model", "message_count": len(c["messages"]), "project_id": None}
        for cid, c in CONVS.items()
    ]
    rows.sort(key=lambda r: r["updated_at"], reverse=True)
    return rows


def field(body: bytes, name: str) -> str:
    m = re.search(rb'name="' + name.encode() + rb'"\r\n\r\n(.*?)\r\n--', body, re.S)
    return m.group(1).decode("utf-8", "replace") if m else ""


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_):
        pass

    def _json(self, obj, status=200):
        data = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _body(self) -> bytes:
        n = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(n) if n else b""

    def _record(self, body: bytes):
        with LOCK:
            LOG.append({"method": self.command, "path": self.path, "time": time.time(),
                        "body": body[:400].decode("utf-8", "replace")})

    # ── GET ──────────────────────────────────────────────────────────────────
    def do_GET(self):
        p = self.path.split("?")[0]
        if p == "/health":
            return self._json({"status": "ok", "backend_ready": FLAGS["backend_ready"]})
        if p == "/backend":
            return self._json({"backend": "mlx", "model": "stub/model-it-4bit", "host": "127.0.0.1", "context_window": 32768})
        if p == "/backends":
            return self._json([])
        if p == "/projects":
            return self._json({"projects": []})
        if p == "/conversations":
            with LOCK:
                return self._json({"conversations": conv_list()})
        m = re.fullmatch(r"/conversations/([^/]+)/messages", p)
        if m:
            with LOCK:
                c = CONVS.get(m.group(1))
                delay = c["delay"] if c else 0
                messages = list(c["messages"]) if c else []
            if delay:
                time.sleep(delay)
            return self._json({"messages": messages})
        if p == "/_stub/log":
            with LOCK:
                return self._json({"log": list(LOG)})
        return self._json({"detail": "not found"}, 404)

    # ── Mutations ────────────────────────────────────────────────────────────
    def do_DELETE(self):
        self._record(b"")
        m = re.fullmatch(r"/conversations/([^/]+)", self.path)
        if m:
            with LOCK:
                CONVS.pop(m.group(1), None)
        return self._json({"status": "deleted"})

    def do_PATCH(self):
        body = self._body()
        self._record(body)
        m = re.fullmatch(r"/conversations/([^/]+)", self.path)
        if m:
            try:
                title = json.loads(body or b"{}").get("title")
            except Exception:
                title = None
            with LOCK:
                if title and m.group(1) in CONVS:
                    CONVS[m.group(1)]["title"] = title
        return self._json({"status": "ok"})

    def do_POST(self):
        body = self._body()
        p = self.path.split("?")[0]
        if p == "/_stub/reset":
            with LOCK:
                LOG.clear()
                CANCELLED.clear()
                FLAGS["backend_ready"] = True
                seed()
            return self._json({"status": "reset"})
        if p == "/_stub/set":
            try:
                FLAGS.update(json.loads(body or b"{}"))
            except Exception:
                pass
            return self._json(FLAGS)
        self._record(body if p != "/chat" else field(body, "message").encode())
        if p == "/cancel":
            try:
                cid = json.loads(body or b"{}").get("conversation_id", "") or ""
            except Exception:
                cid = ""
            with LOCK:
                CANCELLED.add(cid)
            return self._json({"status": "cancelled", "count": 1})
        if p == "/conversations":
            with LOCK:
                cid = f"stub-{RUN}-new-{uuid.uuid4().hex[:6]}"
                now = int(time.time())
                CONVS[cid] = {"title": "New conversation", "created_at": now, "updated_at": now, "messages": [], "delay": 0}
            return self._json({"id": cid, "title": "New conversation"})
        if p == "/chat":
            return self._chat(body)
        return self._json({"status": "ok"})

    # ── Chat ─────────────────────────────────────────────────────────────────
    def _emit(self, obj) -> bool:
        """Write one SSE event. False once the client has gone; the turn goes on."""
        try:
            data = ("data: " + json.dumps(obj) + "\n\n").encode()
            self.wfile.write(hex(len(data))[2:].encode() + b"\r\n" + data + b"\r\n")
            self.wfile.flush()
            return True
        except Exception:
            return False

    def _chat(self, body: bytes):
        message = field(body, "message")
        cid = field(body, "conversation_id")
        retry = field(body, "retry").lower() == "true"
        now = int(time.time())
        with LOCK:
            new = not cid or cid not in CONVS
            if not cid:
                cid = f"stub-{RUN}-chat-{uuid.uuid4().hex[:6]}"
            if cid not in CONVS:
                CONVS[cid] = {"title": "New conversation", "created_at": now, "updated_at": now, "messages": [], "delay": 0}
            first_turn = not CONVS[cid]["messages"]
            if retry and CONVS[cid]["messages"]:
                msgs = CONVS[cid]["messages"]
                while msgs and msgs[-1]["role"] != "user":
                    msgs.pop()
                if msgs:
                    msgs.pop()
            CANCELLED.discard(cid)
            CANCELLED.discard("")

        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()

        reply = "STUB-REPLY-START " + long_reply(6, 7) + "\n\nSTUB-REPLY-END for: " + message
        words = reply.split(" ")
        drop = "STUBDROP" in message
        slow = "STUBSLOW" in message
        stream_for = 3.0 if drop else (20.0 if slow else 2.0)
        save_at = 12.0 if drop else stream_for
        started = time.time()
        alive = self._emit({"type": "thinking", "content": "Considering the question. "})
        sent = 0
        last_beat = started
        while time.time() - started < stream_for:
            target = int(len(words) * (0.5 if drop else 1.0) * (time.time() - started) / stream_for)
            if target > sent and alive:
                alive = self._emit({"type": "token", "content": " ".join(words[sent:target]) + " "})
                sent = target
            if alive and time.time() - last_beat > 5:
                alive = self._emit({"type": "heartbeat"})
                last_beat = time.time()
            time.sleep(0.1)

        # The real server finishes the turn whether or not the client is there.
        while time.time() - started < save_at:
            time.sleep(0.1)  # STUBDROP: silent, socket left open, no heartbeat
        with LOCK:
            cancelled = cid in CANCELLED or "" in CANCELLED
            if not cancelled and cid in CONVS:
                CONVS[cid]["messages"] += [
                    {"role": "user", "content": message},
                    {"role": "assistant", "content": reply, "thinking_content": "Considering the question. "},
                ]
                CONVS[cid]["updated_at"] = int(time.time())
                if first_turn:
                    CONVS[cid]["title"] = "Stub: " + message[:30]
        if drop:
            # Stay silent well past the app's watchdog, then let the socket go.
            time.sleep(25)
        elif not cancelled and alive:
            self._emit({"type": "done", "content": reply})
            self._emit({"type": "stats", "input_tokens": 120, "output_tokens": len(words), "context_pct": 3.5})
            if first_turn or new:
                self._emit({"type": "title", "conv_id": cid, "title": "Stub: " + message[:30]})
        try:
            self.wfile.write(b"0\r\n\r\n")
            self.wfile.flush()
        except Exception:
            pass
        self.close_connection = True


if __name__ == "__main__":
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    server.daemon_threads = True
    print(f"mira stub server on http://127.0.0.1:{PORT} run={RUN}", flush=True)
    server.serve_forever()
