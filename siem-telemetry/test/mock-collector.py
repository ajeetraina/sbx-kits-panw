#!/usr/bin/env python3
"""Mock SIEM HTTP event collector for the siem-telemetry test.

Captures the first POST it receives (method, path, headers, raw body) to a JSON
file, then keeps responding 200 so Fluent Bit stops retrying. The test harness
(run-test.sh) reads the capture file and asserts on it. No vendor account needed.

Usage: mock-collector.py <port> <capture-file>
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer


def main() -> None:
    port = int(sys.argv[1])
    capture_file = sys.argv[2]

    class Handler(BaseHTTPRequestHandler):
        captured = False

        def do_POST(self) -> None:  # noqa: N802 (stdlib naming)
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length).decode("utf-8", "replace")
            if not Handler.captured:
                Handler.captured = True
                with open(capture_file, "w", encoding="utf-8") as fh:
                    json.dump(
                        {
                            "method": self.command,
                            "path": self.path,
                            # Header names are case-insensitive; normalise to lower.
                            "headers": {k.lower(): v for k, v in self.headers.items()},
                            # All Content-Type values, so the test can catch a
                            # duplicated header (auto x-ndjson + our override).
                            "content_type_all": self.headers.get_all("Content-Type") or [],
                            "body": body,
                        },
                        fh,
                    )
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'{"status":"ok"}')

        def log_message(self, *args) -> None:  # silence per-request stderr noise
            return

    server = HTTPServer(("127.0.0.1", port), Handler)
    server.serve_forever()


if __name__ == "__main__":
    main()
