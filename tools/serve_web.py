#!/usr/bin/env python3
"""Serves build/web/ on port 8080 (no-cache; COOP/COEP so threaded builds also work).
Usage: python3 tools/serve_web.py   (run tools/build_web.sh first)"""
import functools
import http.server
import os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build", "web")


class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        super().end_headers()


http.server.ThreadingHTTPServer(("0.0.0.0", 8080), functools.partial(Handler, directory=ROOT)).serve_forever()
