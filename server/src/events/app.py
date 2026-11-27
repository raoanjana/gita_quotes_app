"""Receives anonymous usage events from the Gita Quotes app and passes them to Firehose.

Request: POST /v1/events with a JSON body:
    {
      "install_id": "random UUID made by the app on first launch",
      "app_version": "1.0 (1)",
      "os_version": "iOS 26.1",
      "events": [
        {"name": "verse_view", "ts": "2026-11-27T09:15:02Z", "verse_id": "2.47",
         "source": "widget_small", "props": {"reason": "widget"}}
      ]
    }

Only known event names and fields are kept; anything else is dropped. Nothing that
identifies a person is accepted or stored, and the caller's IP address is not recorded.
Responds 202 with how many events were accepted and dropped.
"""
import base64
import json
import os
import re
from datetime import datetime, timedelta, timezone

MAX_BODY_BYTES = 64 * 1024
MAX_EVENTS = 50
MAX_PROPS = 10
MAX_PROP_LEN = 64

EVENT_NAMES = {
    "app_open",          # app came to the foreground
    "widget_tap",        # opened from a widget; source says which size
    "verse_view",        # a verse appeared on screen; props.reason: daily, another ("Another verse"), widget
    "explanation_open",  # "Explain this to me" opened; source: in_app or a widget
    "share_tap",         # share button tapped; props.what: verse or verse_and_explanation
    "sanskrit_toggle",   # props.on: true or false
    "crash",             # MetricKit crash report: props exception_type, signal, termination_reason,
                         # build, occurred, frame1..3, app_frame, app_uuid
    "hang",              # MetricKit hang report: props hang_seconds, build, occurred, frames as above
}
SOURCES = {"app_icon", "in_app", "widget_small", "widget_medium", "widget_large", "lock_screen"}

UUID_RE = re.compile(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
VERSE_RE = re.compile(r"^\d{1,2}\.\d{1,2}(–\d{1,2})?$")
VERSION_RE = re.compile(r"^[0-9A-Za-z .()_-]{1,24}$")
KEY_RE = re.compile(r"^[a-z0-9_]{1,24}$")

_firehose = None


def _client():
    global _firehose
    if _firehose is None:
        import boto3  # available in the Lambda runtime
        _firehose = boto3.client("firehose")
    return _firehose


def _response(status, body):
    return {"statusCode": status, "headers": {"content-type": "application/json"}, "body": json.dumps(body)}


def _parse_time(value, now):
    """Event time as an ISO string, or None if missing, unparseable or more than a week off."""
    if not isinstance(value, str) or len(value) > 40:
        return None
    try:
        t = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if t.tzinfo is None:
        return None
    if abs(t - now) > timedelta(days=7):
        return None
    return t.astimezone(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def _clean_event(e, now):
    """A cleaned event dict, or None if it should be dropped."""
    if not isinstance(e, dict) or e.get("name") not in EVENT_NAMES:
        return None
    event_time = _parse_time(e.get("ts"), now)
    if event_time is None:
        return None
    verse_id = e.get("verse_id")
    if verse_id is not None and not (isinstance(verse_id, str) and VERSE_RE.match(verse_id)):
        return None
    source = e.get("source")
    if source is not None and source not in SOURCES:
        return None
    props = {}
    raw_props = e.get("props") or {}
    if not isinstance(raw_props, dict) or len(raw_props) > MAX_PROPS:
        return None
    for k, v in raw_props.items():
        if not (isinstance(k, str) and KEY_RE.match(k)):
            return None
        if isinstance(v, bool):
            v = "true" if v else "false"
        if not isinstance(v, (str, int, float)):
            return None
        v = str(v)
        if len(v) > MAX_PROP_LEN:
            return None
        props[k] = v
    return {"event_time": event_time, "name": e["name"], "verse_id": verse_id, "source": source, "props": props}


def clean_batch(body, now):
    """Validate a request body. Returns (records, dropped) or raises ValueError with a message."""
    if not isinstance(body, dict):
        raise ValueError("body must be a JSON object")
    install_id = body.get("install_id")
    if not (isinstance(install_id, str) and UUID_RE.match(install_id)):
        raise ValueError("install_id must be a UUID")
    app_version = body.get("app_version")
    os_version = body.get("os_version")
    for label, v in (("app_version", app_version), ("os_version", os_version)):
        if not (isinstance(v, str) and VERSION_RE.match(v)):
            raise ValueError(label + " is missing or invalid")
    events = body.get("events")
    if not isinstance(events, list) or not 1 <= len(events) <= MAX_EVENTS:
        raise ValueError("events must be a list of 1 to %d items" % MAX_EVENTS)

    received_at = now.isoformat(timespec="seconds").replace("+00:00", "Z")
    records, dropped = [], 0
    for e in events:
        cleaned = _clean_event(e, now)
        if cleaned is None:
            dropped += 1
            continue
        records.append({
            "received_at": received_at,
            "install_id": install_id.lower(),
            "app_version": app_version,
            "os_version": os_version,
            **cleaned,
        })
    return records, dropped


def send(records, client, stream_name):
    """Write records to Firehose, retrying failed ones once. Returns how many failed."""
    pending = [{"Data": (json.dumps(r, ensure_ascii=False) + "\n").encode("utf-8")} for r in records]
    for _attempt in range(2):
        if not pending:
            return 0
        failed = []
        for i in range(0, len(pending), 500):
            chunk = pending[i:i + 500]
            result = client.put_record_batch(DeliveryStreamName=stream_name, Records=chunk)
            if result.get("FailedPutCount"):
                failed += [rec for rec, res in zip(chunk, result["RequestResponses"]) if res.get("ErrorCode")]
        pending = failed
    return len(pending)


def handler(event, context, client=None, now=None):
    now = now or datetime.now(timezone.utc)
    raw = event.get("body") or ""
    if event.get("isBase64Encoded"):
        try:
            raw = base64.b64decode(raw).decode("utf-8")
        except (ValueError, UnicodeDecodeError):
            return _response(400, {"error": "body is not valid base64 UTF-8"})
    if len(raw.encode("utf-8")) > MAX_BODY_BYTES:
        return _response(413, {"error": "body too large"})
    try:
        records, dropped = clean_batch(json.loads(raw), now)
    except json.JSONDecodeError:
        return _response(400, {"error": "body is not JSON"})
    except ValueError as err:
        return _response(400, {"error": str(err)})
    if not records:
        return _response(400, {"error": "no valid events", "dropped": dropped})

    failed = send(records, client or _client(), os.environ["STREAM_NAME"])
    if failed == len(records):
        return _response(503, {"error": "could not store events, try again later"})
    return _response(202, {"accepted": len(records) - failed, "dropped": dropped + failed})
