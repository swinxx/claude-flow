"""JSONL summary aggregators (status/type counters). Behavioral ports of the Bash
read_jsonl_summary / proposal_summary_json at kimiflow--v0.1.50 (135-171, 79-110).
Each reads a JSONL file (malformed lines skipped, matching jq `fromjson? // empty`)
and returns a fixed-shape summary dict; serialization stays at the contracts.dumps
boundary in the calling subcommand."""
import os

from . import store

_PROPOSALS_PATH = ".kimiflow/project/PROPOSALS.jsonl"


def _jq_or(value, default):
    # jq `value // default`: substitute when value is null (None) or false; "" / 0
    # are truthy in jq and pass through. (Mirrors recall_index._jq_or.)
    return default if value is None or value is False else value


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
