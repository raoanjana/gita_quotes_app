"""Tests for the events function. Run from the server folder:  python3 -m unittest discover tests"""
import json
import os
import sys
import unittest
from datetime import datetime, timezone

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src", "events"))
os.environ.setdefault("STREAM_NAME", "test-stream")
import app  # noqa: E402

NOW = datetime(2026, 11, 27, 12, 0, tzinfo=timezone.utc)
ID = "3F2504E0-4F89-11D3-9A0C-0305E82C3301"


class FakeFirehose:
    def __init__(self, fail_first=0):
        self.records, self.fail_first = [], fail_first

    def put_record_batch(self, DeliveryStreamName, Records):
        responses, failed = [], 0
        for r in Records:
            if self.fail_first > 0:
                self.fail_first -= 1
                failed += 1
                responses.append({"ErrorCode": "ServiceUnavailableException"})
            else:
                self.records.append(json.loads(r["Data"]))
                responses.append({"RecordId": "x"})
        return {"FailedPutCount": failed, "RequestResponses": responses}


def request(body, raw=False):
    return {"body": body if raw else json.dumps(body), "isBase64Encoded": False}


def batch(*events, **overrides):
    b = {"install_id": ID, "app_version": "1.0 (1)", "os_version": "iOS 26.1", "events": list(events)}
    b.update(overrides)
    return b


def ev(name="verse_view", **kw):
    e = {"name": name, "ts": "2026-11-27T11:59:00Z"}
    e.update(kw)
    return e


class EventsTests(unittest.TestCase):
    def call(self, body, client=None, raw=False):
        client = client or FakeFirehose()
        res = app.handler(request(body, raw), None, client=client, now=NOW)
        return res["statusCode"], json.loads(res["body"]), client

    def test_valid_events_are_stored(self):
        status, body, fh = self.call(batch(
            ev("verse_view", verse_id="2.47", source="widget_small", props={"reason": "widget"}),
            ev("explanation_open", verse_id="12.13–14", source="in_app"),
            ev("sanskrit_toggle", props={"on": True}),
        ))
        self.assertEqual((status, body), (202, {"accepted": 3, "dropped": 0}))
        first = fh.records[0]
        self.assertEqual(first["install_id"], ID.lower())
        self.assertEqual(first["verse_id"], "2.47")
        self.assertEqual(first["props"], {"reason": "widget"})
        self.assertEqual(fh.records[2]["props"], {"on": "true"})
        self.assertEqual(first["received_at"], "2026-11-27T12:00:00Z")

    def test_no_ip_or_unknown_fields_are_stored(self):
        _, _, fh = self.call(batch(ev(email="someone@example.com", ip="1.2.3.4"), name="x", ip="1.2.3.4"))
        self.assertEqual(set(fh.records[0]), {"received_at", "install_id", "app_version", "os_version",
                                              "event_time", "name", "verse_id", "source", "props"})

    def test_bad_events_are_dropped_good_ones_kept(self):
        status, body, fh = self.call(batch(
            ev(),
            ev("delete_everything"),
            ev(verse_id="'; DROP TABLE"),
            ev(source="somewhere"),
            ev(ts="2020-01-01T00:00:00Z"),
            ev(ts="not a time"),
            ev(props={"Bad Key": "x"}),
            ev(props={"k": "x" * 65}),
            ev(props={"k": {"nested": 1}}),
        ))
        self.assertEqual((status, body), (202, {"accepted": 1, "dropped": 8}))
        self.assertEqual(len(fh.records), 1)

    def test_whole_request_rejected(self):
        for body, raw in [
            ("not json", True),
            ([1, 2], False),
            (batch(ev(), install_id="not-a-uuid"), False),
            (batch(ev(), app_version=""), False),
            (batch(), False),
            (batch(*[ev()] * 51), False),
            (batch(ev("nope")), False),
        ]:
            status, _, fh = self.call(body, raw=raw)
            self.assertEqual(status, 400, body)
            self.assertEqual(fh.records, [])

    def test_crash_and_hang_reports_are_stored(self):
        crash = {"exception_type": "1", "signal": "11", "termination_reason": "Namespace SIGNAL, Code 11",
                 "build": "1", "occurred": "2026-11-26", "frame1": "GitaQuotes+0x1a2b",
                 "frame2": "SwiftUI+0x99", "frame3": "UIKitCore+0x42", "app_frame": "GitaQuotes+0x1a2b",
                 "app_uuid": "5C4E1E46-0E5B-3C42-9C5E-7F3D1B2A9E10"}
        status, body, fh = self.call(batch(ev("crash", props=crash), ev("hang", props={"hang_seconds": "2.5"})))
        self.assertEqual((status, body), (202, {"accepted": 2, "dropped": 0}))
        self.assertEqual(fh.records[0]["props"]["frame1"], "GitaQuotes+0x1a2b")

    def test_body_size_limit(self):
        status, _, _ = self.call("x" * (64 * 1024 + 1), raw=True)
        self.assertEqual(status, 413)

    def test_retries_failed_records_once(self):
        fh = FakeFirehose(fail_first=1)
        status, body, _ = self.call(batch(ev(), ev()), client=fh)
        self.assertEqual((status, body), (202, {"accepted": 2, "dropped": 0}))
        self.assertEqual(len(fh.records), 2)

    def test_storage_down_returns_503(self):
        status, _, _ = self.call(batch(ev()), client=FakeFirehose(fail_first=10))
        self.assertEqual(status, 503)


if __name__ == "__main__":
    unittest.main()
