#!/usr/bin/env python3
"""Minimal local WebDAV server used only by transport tests."""

from __future__ import annotations

import html
import pathlib
import sys
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


ROOT = pathlib.Path(sys.argv[1]).resolve()
PORT_FILE = pathlib.Path(sys.argv[2])


class Handler(BaseHTTPRequestHandler):
    def log_message(self, _format: str, *_args: object) -> None:
        return

    def target(self) -> pathlib.Path:
        relative = urllib.parse.unquote(self.path).lstrip("/")
        target = (ROOT / relative).resolve()
        if target != ROOT and ROOT not in target.parents:
            raise ValueError("unsafe path")
        return target

    def authenticate(self) -> bool:
        if not self.headers.get("Authorization", "").startswith("Basic "):
            self.send_response(401)
            self.end_headers()
            return False
        return True

    def do_MKCOL(self) -> None:
        if not self.authenticate():
            return
        target = self.target()
        if target.exists():
            self.send_response(405)
        else:
            target.mkdir(parents=False)
            self.send_response(201)
        self.end_headers()

    def do_PUT(self) -> None:
        if not self.authenticate():
            return
        target = self.target()
        length = int(self.headers.get("Content-Length", "0"))
        target.write_bytes(self.rfile.read(length))
        self.send_response(201)
        self.end_headers()

    def do_GET(self) -> None:
        if not self.authenticate():
            return
        target = self.target()
        if not target.is_file():
            self.send_response(404)
            self.end_headers()
            return
        payload = target.read_bytes()
        self.send_response(200)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_DELETE(self) -> None:
        if not self.authenticate():
            return
        target = self.target()
        if target.is_file():
            target.unlink()
            self.send_response(204)
        else:
            self.send_response(404)
        self.end_headers()

    def do_PROPFIND(self) -> None:
        if not self.authenticate():
            return
        target = self.target()
        if not target.is_dir():
            self.send_response(404)
            self.end_headers()
            return
        paths = [target] + sorted(target.iterdir())
        responses = []
        for path in paths:
            relative = path.relative_to(ROOT).as_posix()
            href = "/" + urllib.parse.quote(relative)
            if path.is_dir():
                href += "/"
            responses.append(
                "<d:response><d:href>"
                + html.escape(href)
                + "</d:href><d:propstat><d:status>HTTP/1.1 200 OK</d:status>"
                + "</d:propstat></d:response>"
            )
        payload = (
            '<?xml version="1.0" encoding="utf-8"?>'
            '<d:multistatus xmlns:d="DAV:">'
            + "".join(responses)
            + "</d:multistatus>"
        ).encode()
        self.send_response(207)
        self.send_header("Content-Type", "application/xml")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


ROOT.mkdir(parents=True, exist_ok=True)
server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
PORT_FILE.write_text(str(server.server_address[1]))
server.serve_forever()
