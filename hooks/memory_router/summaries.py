"""JSONL summary aggregators (status/type counters). Behavioral ports of the Bash
read_jsonl_summary / proposal_summary_json at kimiflow--v0.1.50 (135-171, 79-110).
Each reads a JSONL file (malformed lines skipped, matching jq `fromjson? // empty`)
and returns a fixed-shape summary dict; serialization stays at the contracts.dumps
boundary in the calling subcommand."""
import os

from . import store

_PROPOSALS_PATH = ".kimiflow/project/PROPOSALS.jsonl"
_USAGE_PATH = ".kimiflow/project/MEMORY-USAGE.json"


def _jq_or(value, default):
    # jq `value // default`: substitute when value is null (None) or false; "" / 0
    # are truthy in jq and pass through. (Mirrors recall_index._jq_or.)
    return default if value is None or value is False else value


def _max_present(values):
    # jq `[... // empty] | sort | last // null` (and the `// null` + select(!=null)
    # variant): keep values that are neither null nor false, sort, take the max;
    # null when nothing remains.
    kept = [v for v in values if v is not None and v is not False]
    return sorted(kept)[-1] if kept else None


def read_jsonl_summary(path):
    # Bash read_jsonl_summary (135-171): counts by status/sensitivity plus a
    # topic->count map. Missing file -> the all-zero shape (identical to an empty
    # file through the jq branch). `current` defaults missing status to "current";
    # the other status/sensitivity buckets default to "" so only explicit values count.
    if not os.path.isfile(path):
        rows = []
    else:
        rows = store.read_jsonl(path)

    counts = {}
    for row in rows:
        topic = _jq_or(row.get("topic"), "uncategorized")
        counts[topic] = counts.get(topic, 0) + 1
    by_topic = {key: counts[key] for key in sorted(counts)}  # jq sort_by + group_by

    def status_is(value):
        return sum(1 for r in rows if _jq_or(r.get("status"), "") == value)

    def sensitivity_is(value):
        return sum(1 for r in rows if _jq_or(r.get("sensitivity"), "") == value)

    return {
        "total": len(rows),
        "current": sum(1 for r in rows if _jq_or(r.get("status"), "current") == "current"),
        "stale": status_is("stale"),
        "superseded": status_is("superseded"),
        "archived": status_is("archived"),
        "private": sensitivity_is("private"),
        "security": sensitivity_is("security"),
        "by_topic": by_topic,
    }


def proposal_summary_json(path):
    # Bash proposal_summary_json (79-110): PROPOSALS.jsonl counts by status, plus a
    # type->count map. by_type uses jq `reduce` -> first-appearance key order (NOT
    # sorted, unlike read_jsonl_summary's by_topic). `pending` defaults missing
    # status to "pending"; the other buckets default to "".
    if not os.path.isfile(path):
        return {
            "present": False,
            "path": _PROPOSALS_PATH,
            "total": 0,
            "pending": 0,
            "approved": 0,
            "applied": 0,
            "rejected": 0,
            "needs_revalidation": 0,
            "by_type": {},
        }

    rows = store.read_jsonl(path)
    by_type = {}
    for row in rows:
        kind = _jq_or(row.get("type"), "unknown")
        by_type[kind] = by_type.get(kind, 0) + 1

    def status_is(value, default=""):
        return sum(1 for r in rows if _jq_or(r.get("status"), default) == value)

    return {
        "present": True,
        "path": _PROPOSALS_PATH,
        "total": len(rows),
        "pending": status_is("pending", "pending"),
        "approved": status_is("approved"),
        "applied": status_is("applied"),
        "rejected": status_is("rejected"),
        "needs_revalidation": status_is("needs_revalidation"),
        "by_type": by_type,
    }


def _usage_absent():
    return {
        "present": False,
        "path": _USAGE_PATH,
        "tracked_items": 0,
        "total_uses": 0,
        "last_used_at": None,
        "by_kind": {},
        "events_tracked": 0,
        "by_event": {},
        "economics": {
            "recall_writes": 0,
            "history_writes": 0,
            "total_hit_count": 0,
            "estimated_output_tokens": 0,
            "last_event_at": None,
        },
        "hot_items": 0,
    }


def usage_summary_json(path):
    # Bash usage_summary_json (184-241): reads MEMORY-USAGE.json (a single object with
    # `.items` map + `.events` array). The Bash guard `[ ! -f ] || ! jq -e .` falls to
    # the absent shape when the file is missing, invalid JSON, or top-level null/false;
    # store.read_json returns None for missing/invalid and the literal for null. We also
    # treat a valid-but-non-object top level as absent (Bash jq-errors on `.items` there
    # -- unreachable for real MEMORY-USAGE.json; see plan).
    data = store.read_json(path)
    if not isinstance(data, dict):
        return _usage_absent()

    items = _jq_or(data.get("items"), {})
    events = _jq_or(data.get("events"), [])
    if not isinstance(items, dict):
        items = {}
    if not isinstance(events, list):
        events = []
    item_values = list(items.values())

    by_kind = {}
    for item in item_values:
        kind = _jq_or(item.get("kind"), "unknown")
        by_kind[kind] = by_kind.get(kind, 0) + 1

    by_event = {}
    for event in events:
        kind = _jq_or(event.get("kind"), "unknown")
        acc = by_event.get(kind)
        if acc is None:
            acc = {"writes": 0, "hits": 0, "estimated_tokens": 0, "last_at": None}
            by_event[kind] = acc
        acc["writes"] += 1
        acc["hits"] += _jq_or(event.get("hit_count"), 0)
        acc["estimated_tokens"] += _jq_or(event.get("estimated_tokens"), 0)
        # jq: .last_at = ([.last_at, (.at // null)] | map(select(. != null)) | sort | last // null)
        at = _jq_or(event.get("at"), None)
        acc["last_at"] = _max_present([acc["last_at"], at])

    def count_event_kind(value):
        return sum(1 for e in events if _jq_or(e.get("kind"), "") == value)

    return {
        "present": True,
        "path": _USAGE_PATH,
        "tracked_items": len(items),
        "total_uses": sum(_jq_or(i.get("use_count"), 0) for i in item_values),
        "last_used_at": _max_present([i.get("last_used_at") for i in item_values]),
        "by_kind": by_kind,
        "events_tracked": len(events),
        "by_event": by_event,
        "economics": {
            "recall_writes": count_event_kind("recall"),
            "history_writes": count_event_kind("history"),
            "total_hit_count": sum(_jq_or(e.get("hit_count"), 0) for e in events),
            "estimated_output_tokens": sum(_jq_or(e.get("estimated_tokens"), 0) for e in events),
            "last_event_at": _max_present([e.get("at") for e in events]),
        },
        "hot_items": sum(1 for i in item_values if _jq_or(i.get("use_count"), 0) > 1),
    }
