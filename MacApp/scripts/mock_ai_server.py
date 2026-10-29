"""Tiny stand-in for an AI provider, used by the CI self-test.

Answers both OpenAI-style /v1/chat/completions and Claude-style /v1/messages
requests with "OK", after checking the request contains an image.
"""
import json
from http.server import BaseHTTPRequestHandler, HTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        has_image = "image" in json.dumps(body)
        if not has_image:
            return self.reply(400, {"error": {"message": "no image in request"}})
        if self.path.endswith("/chat/completions"):
            self.reply(200, {"choices": [{"message": {"role": "assistant", "content": "OK"}}]})
        elif self.path.endswith("/messages"):
            self.reply(200, {"content": [{"type": "text", "text": "OK"}], "stop_reason": "end_turn"})
        else:
            self.reply(404, {"error": {"message": "unknown path " + self.path}})

    def reply(self, status, obj):
        data = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


HTTPServer(("127.0.0.1", 8787), Handler).serve_forever()
