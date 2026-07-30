#!/usr/bin/env python3
import json
import os
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, _format, *_args):
        return

    def do_POST(self):
        length = int(self.headers.get("content-length", "0"))
        self.rfile.read(length)
        delay = float(os.environ.get("CADR_STUB_DELAY", "0.05"))
        time.sleep(delay)
        text = os.environ.get("CADR_STUB_TEXT", "stub-ok")
        events = [
            {"type": "response.created", "response": {"id": "resp_stub"}},
            {
                "type": "response.output_item.added",
                "output_index": 0,
                "item": {
                    "type": "message",
                    "id": "msg_stub",
                    "role": "assistant",
                    "content": [],
                },
            },
            {
                "type": "response.output_text.delta",
                "output_index": 0,
                "delta": text,
            },
            {
                "type": "response.output_item.done",
                "output_index": 0,
                "item": {
                    "type": "message",
                    "id": "msg_stub",
                    "role": "assistant",
                    "content": [{"type": "output_text", "text": text}],
                },
            },
            {
                "type": "response.completed",
                "response": {
                    "id": "resp_stub",
                    "status": "completed",
                    "usage": {
                        "input_tokens": 3,
                        "output_tokens": 1,
                        "total_tokens": 4,
                    },
                },
            },
        ]
        body = "".join(
            f"data: {json.dumps(event, separators=(',', ':'))}\n\n"
            for event in events
        ).encode()
        self.send_response(200)
        self.send_header("content-type", "text/event-stream")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        self.wfile.flush()


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: openai-sse-server.py PORT_FILE")
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    with open(sys.argv[1], "w", encoding="utf-8") as stream:
        stream.write(str(server.server_port))
    server.serve_forever()


if __name__ == "__main__":
    main()
