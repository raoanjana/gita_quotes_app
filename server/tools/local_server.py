"""A local stand-in for the AWS endpoint, for testing the app before (or without) deploying.

It runs the real events function (src/events/app.py), but instead of Firehose it keeps
accepted events in memory. Point a debug build of the app at it:

    python3 server/tools/local_server.py                # listens on http://localhost:8787
    xcrun simctl launch booted com.anjanarao.hinduwisdom -AnalyticsEndpoint http://localhost:8787/v1/events

Open http://localhost:8787 to see what has arrived.
"""
import html
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "src", "events"))
os.environ.setdefault("STREAM_NAME", "local")
import app  # noqa: E402

RECEIVED = []


class MemoryFirehose:
    def put_record_batch(self, DeliveryStreamName, Records):
        for r in Records:
            RECEIVED.append(json.loads(r["Data"]))
        return {"FailedPutCount": 0, "RequestResponses": [{"RecordId": "local"} for _ in Records]}


FIREHOSE = MemoryFirehose()


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != "/v1/events":
            self.send_error(404)
            return
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(min(length, 1024 * 1024)).decode("utf-8", "replace")
        result = app.handler({"body": body, "isBase64Encoded": False}, None, client=FIREHOSE)
        print("POST /v1/events ->", result["statusCode"], result["body"], flush=True)
        self.send_response(result["statusCode"])
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(result["body"].encode())

    def do_GET(self):
        if self.path == "/events.json":
            data = json.dumps(RECEIVED, indent=2).encode()
            ctype = "application/json"
        else:
            rows = "".join(
                "<tr>" + "".join("<td>%s</td>" % html.escape(str(e.get(k) or "")) for k in
                                 ("event_time", "name", "verse_id", "source")) +
                "<td>%s</td></tr>" % html.escape(json.dumps(e.get("props") or {}))
                for e in reversed(RECEIVED))
            data = ("<!DOCTYPE html><meta charset=utf-8><title>Hindu Wisdom local events</title>"
                    "<style>body{font:14px -apple-system,sans-serif;margin:24px}td,th{padding:4px 10px;"
                    "border-bottom:1px solid #eee;text-align:left}</style>"
                    "<h2>Events received: %d</h2><p>Newest first. Reload to update.</p>"
                    "<table><tr><th>Time (UTC)</th><th>Event</th><th>Verse</th><th>Source</th><th>Props</th></tr>%s</table>"
                    % (len(RECEIVED), rows)).encode()
            ctype = "text/html; charset=utf-8"
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8787"))
    print("Hindu Wisdom local events server on http://localhost:%d" % port, flush=True)
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
