#!/usr/bin/env python3
"""Push router: lets Quarkmost and the official mobile app get notifications from one server.

Mattermost can send pushes to exactly one push proxy. This sits in that slot and forwards each push by
the app it's for:

  * device registered by Quarkmost   (platform == APP_PLATFORM, default "apple")
        -> APP_UPSTREAM      (your own mattermost-push-proxy, holding your Apple push key)
  * everything else (the official apps register as "apple_rn" / "android_rn")
        -> DEFAULT_UPSTREAM  (whatever the server used before, e.g. https://push-test.mattermost.com)

So people on the official app keep their notifications, untouched, while some of you use Quarkmost.
Standard library only; no dependencies. Message contents are forwarded as-is and never logged.
"""
import json
import os
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

APP_PLATFORM = os.environ.get("APP_PLATFORM", "apple")
APP_UPSTREAM = os.environ.get("APP_UPSTREAM", "http://127.0.0.1:8066").rstrip("/")
DEFAULT_UPSTREAM = os.environ.get("DEFAULT_UPSTREAM", "https://push-test.mattermost.com").rstrip("/")
PORT = int(os.environ.get("PORT", "8067"))
BIND = os.environ.get("BIND", "127.0.0.1")   # localhost only: just Mattermost on this machine talks to it
TIMEOUT = float(os.environ.get("UPSTREAM_TIMEOUT", "15"))


def forward(base, method, path, body, headers):
    request = urllib.request.Request(base + path, data=body, method=method)
    for name in ("Content-Type", "Authorization", "User-Agent"):
        if headers.get(name):
            request.add_header(name, headers[name])
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            return response.status, response.headers.get("Content-Type", "application/json"), response.read()
    except urllib.error.HTTPError as error:        # pass upstream errors through unchanged
        return error.code, error.headers.get("Content-Type", "application/json"), error.read()
    except Exception as error:                     # upstream unreachable
        return 502, "application/json", json.dumps({"status": "FAIL", "error": str(error)}).encode()


class Router(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _reply(self, status, content_type, body):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/healthz":
            return self._reply(200, "text/plain", b"ok")
        self._reply(*forward(DEFAULT_UPSTREAM, "GET", self.path, None, self.headers))

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        platform = ""
        try:
            platform = json.loads(body or b"{}").get("platform", "")
        except (ValueError, AttributeError):
            pass
        upstream = APP_UPSTREAM if platform == APP_PLATFORM else DEFAULT_UPSTREAM
        status, content_type, response = forward(upstream, "POST", self.path, body, self.headers)
        print(f"{self.path} platform={platform or '?'} -> {'app' if upstream == APP_UPSTREAM else 'default'} {status}", flush=True)
        self._reply(status, content_type, response)

    def log_message(self, *args):   # our own one-line log above is enough
        pass


if __name__ == "__main__":
    print(f"push-router on {BIND}:{PORT}  {APP_PLATFORM} -> {APP_UPSTREAM}, others -> {DEFAULT_UPSTREAM}", flush=True)
    ThreadingHTTPServer((BIND, PORT), Router).serve_forever()
