"""HTTP API for the bottle leaderboard. Caddy sends /api/*, /admin and
/leaderboard here; everything else on golfis.8bev.ca stays a static file.

Settings come from the environment so dev, test and the droplet share one file:
  LEADERBOARD_DB         SQLite path (default leaderboard.db next to this file)
  LEADERBOARD_HOST/PORT  where to listen (default 127.0.0.1:8787)
  LEADERBOARD_ADMIN_KEY  unlocks /admin. Empty turns the admin API off.
"""

import hmac
import json
import os
import re
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

import names
from store import ALPHABET, CODE_LENGTH, Store

HERE = Path(__file__).resolve().parent
MAX_BODY = 4096
## Unknown codes one address may try in a window before it is told to wait.
MISS_LIMIT = 20
MISS_WINDOW = 600.0
_CODE = re.compile("^[%s]{%d}$" % (ALPHABET, CODE_LENGTH))


class Misses:
    """Slows anyone walking through random codes looking for a live one."""

    def __init__(self):
        self._hits = {}

    def blocked(self, ip, now):
        recent = [t for t in self._hits.get(ip, []) if now - t < MISS_WINDOW]
        self._hits[ip] = recent
        return len(recent) >= MISS_LIMIT

    def note(self, ip, now):
        self._hits.setdefault(ip, []).append(now)


class Api:
    def __init__(self, store, admin_key=""):
        self.store = store
        self.admin_key = admin_key
        self.misses = Misses()

    def handle(self, method, path, body=None, ip="", headers=None):
        """(status, payload) for one request. Payload is a dict, or str for HTML."""
        headers = headers or {}
        url = urlparse(path)
        parts = [p for p in url.path.split("/") if p]
        try:
            if parts in (["admin"], ["leaderboard"]) and method == "GET":
                return 200, (HERE / ("%s.html" % parts[0])).read_text()
            if parts[:1] != ["api"]:
                return 404, {"error": "not found"}
            if parts[1:2] == ["admin"]:
                return self._admin(method, parts[2:], body, headers)
            return self._public(method, parts[1:], body, ip, parse_qs(url.query))
        except (AttributeError, KeyError, TypeError, ValueError):
            return 400, {"error": "bad request"}

    def _public(self, method, parts, body, ip, query):
        now = time.time()
        if parts == ["leaderboard"] and method == "GET":
            limit = max(1, min(100, int(query.get("limit", ["50"])[0])))
            return 200, {"scores": self.store.leaderboard(limit)}
        if parts[:1] == ["code"] and len(parts) >= 2:
            code = parts[1].upper()
            if self.misses.blocked(ip, now):
                return 429, {"error": "too many tries, wait a few minutes"}
            if not _CODE.match(code) or self.store.status(code) is None:
                self.misses.note(ip, now)
                return 404, {"error": "unknown code"}
            if len(parts) == 2 and method == "GET":
                return 200, self.store.status(code)
            if parts[2:] == ["nickname"] and method == "POST":
                nickname, error = names.clean(body["nickname"])
                error = error or self.store.set_nickname(code, nickname)
                return (400, {"error": error}) if error else (200, self.store.status(code))
        if parts == ["run", "start"] and method == "POST":
            code = str(body["code"]).upper()
            if self.misses.blocked(ip, now):
                return 429, {"error": "too many tries, wait a few minutes"}
            ticket, error = self.store.start_run(code)
            if error == "unknown code":
                self.misses.note(ip, now)
            if error:
                return 400, {"error": error}
            return 200, {"ticket": ticket, "tries_left": self.store.status(code)["tries_left"]}
        if parts == ["run", "finish"] and method == "POST":
            result, error = self.store.finish_run(str(body["ticket"]), bool(body["holed"]), body.get("strokes"))
            return (400, {"error": error}) if error else (200, result)
        return 404, {"error": "not found"}

    def _admin(self, method, parts, body, headers):
        given = headers.get("x-admin-key", "")
        if not self.admin_key or not hmac.compare_digest(given, self.admin_key):
            return 401, {"error": "admin key required"}
        if parts == ["runs"] and method == "GET":
            return 200, {"runs": self.store.recent_runs()}
        if len(parts) == 3 and parts[0] == "runs" and parts[2] == "hide" and method == "POST":
            if not self.store.set_hidden(parts[1], bool(body["hidden"])):
                return 404, {"error": "unknown run"}
            return 200, {"ok": True}
        return 404, {"error": "not found"}


def _handler(api):
    class Handler(BaseHTTPRequestHandler):
        def _send(self, status, payload):
            html = isinstance(payload, str)
            data = (payload if html else json.dumps(payload)).encode()
            self.send_response(status)
            self.send_header("Content-Type", "text/html; charset=utf-8" if html else "application/json")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def _ip(self):
            # Caddy is the only thing in front, and it always sets this.
            forwarded = self.headers.get("X-Forwarded-For", "")
            return forwarded.split(",")[0].strip() or self.client_address[0]

        def _headers(self):
            return {k.lower(): v for k, v in self.headers.items()}

        def do_GET(self):
            self._send(*api.handle("GET", self.path, None, self._ip(), self._headers()))

        def do_POST(self):
            length = int(self.headers.get("Content-Length", "0") or 0)
            if length > MAX_BODY:
                self._send(413, {"error": "too large"})
                return
            try:
                body = json.loads(self.rfile.read(length) or b"{}")
            except ValueError:
                self._send(400, {"error": "bad json"})
                return
            self._send(*api.handle("POST", self.path, body, self._ip(), self._headers()))

        def log_message(self, fmt, *args):
            pass

    return Handler


def main():
    db = os.environ.get("LEADERBOARD_DB", str(HERE / "leaderboard.db"))
    host = os.environ.get("LEADERBOARD_HOST", "127.0.0.1")
    port = int(os.environ.get("LEADERBOARD_PORT", "8787"))
    api = Api(Store(db), os.environ.get("LEADERBOARD_ADMIN_KEY", ""))
    print("leaderboard on %s:%d using %s" % (host, port, db), flush=True)
    ThreadingHTTPServer((host, port), _handler(api)).serve_forever()


if __name__ == "__main__":
    main()
