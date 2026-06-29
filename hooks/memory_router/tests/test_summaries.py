import os
import shutil
import tempfile
import unittest

from memory_router import summaries


class _FixtureCase(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.dir, ignore_errors=True)

    def write(self, name, lines):
        path = os.path.join(self.dir, name)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write("".join(line + "\n" for line in lines))
        return path

    def missing(self, name="nope.jsonl"):
        return os.path.join(self.dir, name)

    def write_raw(self, name, text):
        path = os.path.join(self.dir, name)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(text)
        return path


class ReadJsonlSummaryCase(_FixtureCase):
    EMPTY = {
        "total": 0, "current": 0, "stale": 0, "superseded": 0, "archived": 0,
        "private": 0, "security": 0, "by_topic": {},
    }

    def test_missing_file_empty_shape(self):
        result = summaries.read_jsonl_summary(self.missing())
        self.assertEqual(result, self.EMPTY)
        self.assertEqual(list(result.keys()), list(self.EMPTY.keys()))

    def test_empty_file_matches_missing_shape(self):
        self.assertEqual(summaries.read_jsonl_summary(self.write("e.jsonl", [])), self.EMPTY)

    def test_status_buckets_and_defaults(self):
        path = self.write("L.jsonl", [
            '{"status":"current","topic":"b"}',
            '{"topic":"b"}',            # missing status -> current
            '{"status":null,"topic":"b"}',   # null -> current
            '{"status":"","topic":"b"}',     # "" -> counted nowhere but total
            '{"status":"stale","topic":"a"}',
            '{"status":"superseded","topic":"a"}',
            '{"status":"archived","topic":"a"}',
        ])
        r = summaries.read_jsonl_summary(path)
        self.assertEqual(r["total"], 7)
        self.assertEqual(r["current"], 3)   # explicit + missing + null
        self.assertEqual((r["stale"], r["superseded"], r["archived"]), (1, 1, 1))

    def test_sensitivity_buckets(self):
        path = self.write("L.jsonl", [
            '{"sensitivity":"private"}', '{"sensitivity":"security"}',
            '{"sensitivity":"normal"}', '{}',
        ])
        r = summaries.read_jsonl_summary(path)
        self.assertEqual((r["private"], r["security"]), (1, 1))

    def test_by_topic_sorted_with_uncategorized_default(self):
        path = self.write("L.jsonl", [
            '{"topic":"banana"}', '{"topic":"Apple"}', '{"topic":"apple"}', '{}', '{"topic":"Apple"}',
        ])
        r = summaries.read_jsonl_summary(path)
        # jq sort_by -> codepoint order: uppercase before lowercase.
        self.assertEqual(list(r["by_topic"].keys()), ["Apple", "apple", "banana", "uncategorized"])
        self.assertEqual(r["by_topic"], {"Apple": 2, "apple": 1, "banana": 1, "uncategorized": 1})

    def test_malformed_lines_skipped(self):
        path = self.write("L.jsonl", ['{"status":"current","topic":"x"}', 'NOT JSON', '   '])
        self.assertEqual(summaries.read_jsonl_summary(path)["total"], 1)

    def test_key_order(self):
        path = self.write("L.jsonl", ['{"topic":"x"}'])
        self.assertEqual(list(summaries.read_jsonl_summary(path).keys()), list(self.EMPTY.keys()))


class ProposalSummaryCase(_FixtureCase):
    PATH = ".kimiflow/project/PROPOSALS.jsonl"

    def test_missing_file_present_false(self):
        r = summaries.proposal_summary_json(self.missing())
        self.assertEqual(r, {
            "present": False, "path": self.PATH, "total": 0, "pending": 0,
            "approved": 0, "applied": 0, "rejected": 0, "needs_revalidation": 0,
            "by_type": {},
        })

    def test_status_buckets_and_defaults(self):
        path = self.write("P.jsonl", [
            '{"status":"pending"}', '{}', '{"status":null}',   # missing/null -> pending
            '{"status":""}',                                    # "" -> nowhere but total
            '{"status":"approved"}', '{"status":"applied"}',
            '{"status":"rejected"}', '{"status":"needs_revalidation"}',
        ])
        r = summaries.proposal_summary_json(path)
        self.assertTrue(r["present"])
        self.assertEqual(r["total"], 8)
        self.assertEqual(r["pending"], 3)
        self.assertEqual((r["approved"], r["applied"], r["rejected"], r["needs_revalidation"]),
                         (1, 1, 1, 1))

    def test_by_type_first_appearance_order_not_sorted(self):
        path = self.write("P.jsonl", [
            '{"type":"zeta"}', '{"type":"alpha"}', '{"type":"zeta"}', '{}',
        ])
        r = summaries.proposal_summary_json(path)
        # reduce -> first-appearance order (NOT sorted): zeta, alpha, unknown.
        self.assertEqual(list(r["by_type"].keys()), ["zeta", "alpha", "unknown"])
        self.assertEqual(r["by_type"], {"zeta": 2, "alpha": 1, "unknown": 1})

    def test_malformed_lines_skipped(self):
        path = self.write("P.jsonl", ['{"status":"pending","type":"x"}', 'GARBAGE'])
        self.assertEqual(summaries.proposal_summary_json(path)["total"], 1)

    def test_key_order(self):
        path = self.write("P.jsonl", ['{"status":"pending","type":"x"}'])
        self.assertEqual(list(summaries.proposal_summary_json(path).keys()), [
            "present", "path", "total", "pending", "approved", "applied",
            "rejected", "needs_revalidation", "by_type",
        ])


class UsageSummaryCase(_FixtureCase):
    PATH = ".kimiflow/project/MEMORY-USAGE.json"
    ABSENT = {
        "present": False, "path": PATH, "tracked_items": 0, "total_uses": 0,
        "last_used_at": None, "by_kind": {}, "events_tracked": 0, "by_event": {},
        "economics": {
            "recall_writes": 0, "history_writes": 0, "total_hit_count": 0,
            "estimated_output_tokens": 0, "last_event_at": None,
        },
        "hot_items": 0,
    }

    def test_missing_file_absent_shape(self):
        r = summaries.usage_summary_json(self.missing("none.json"))
        self.assertEqual(r, self.ABSENT)
        self.assertEqual(list(r.keys()), list(self.ABSENT.keys()))
        self.assertEqual(list(r["economics"].keys()), list(self.ABSENT["economics"].keys()))

    def test_invalid_json_absent(self):
        self.assertEqual(summaries.usage_summary_json(self.write_raw("b.json", "not json{")), self.ABSENT)

    def test_literal_null_absent(self):
        self.assertEqual(summaries.usage_summary_json(self.write_raw("n.json", "null")), self.ABSENT)

    def test_literal_false_absent(self):
        self.assertEqual(summaries.usage_summary_json(self.write_raw("f.json", "false")), self.ABSENT)

    def test_non_object_json_absent_divergence(self):
        # Bash jq-errors on `.items` for a non-object top level (empty output, breaks the
        # caller); the port returns the absent shape instead. Unreachable for real files.
        self.assertEqual(summaries.usage_summary_json(self.write_raw("a.json", "[1,2,3]")), self.ABSENT)

    def test_empty_object_present_all_zero(self):
        r = summaries.usage_summary_json(self.write_raw("e.json", "{}"))
        self.assertTrue(r["present"])
        self.assertEqual(r["tracked_items"], 0)
        self.assertEqual(r["by_kind"], {})
        self.assertEqual(r["economics"]["total_hit_count"], 0)

    def test_items_and_events_null_default_to_empty(self):
        r = summaries.usage_summary_json(self.write_raw("z.json", '{"items":null,"events":null}'))
        self.assertTrue(r["present"])
        self.assertEqual(r["tracked_items"], 0)
        self.assertEqual(r["events_tracked"], 0)

    def test_full_mixed_aggregation(self):
        path = self.write_raw("full.json", """
        {"items":{"learning:a":{"kind":"learning","use_count":3,"last_used_at":"2026-06-10T00:00:00Z"},
                  "learning:b":{"kind":"learning","use_count":1,"last_used_at":"2026-06-20T00:00:00Z"},
                  "user:c":{"kind":"user","use_count":0},
                  "d":{"use_count":5,"last_used_at":"2026-06-01T00:00:00Z"}},
         "events":[{"kind":"recall","hit_count":2,"estimated_tokens":100,"at":"2026-06-10T00:00:00Z"},
                   {"kind":"recall","hit_count":3,"estimated_tokens":150,"at":"2026-06-15T00:00:00Z"},
                   {"kind":"history","hit_count":1,"estimated_tokens":50,"at":"2026-06-12T00:00:00Z"},
                   {"kind":"recall","hit_count":0,"at":null},
                   {"hit_count":7,"estimated_tokens":9}]}
        """)
        r = summaries.usage_summary_json(path)
        self.assertEqual(r["tracked_items"], 4)
        self.assertEqual(r["total_uses"], 9)
        self.assertEqual(r["last_used_at"], "2026-06-20T00:00:00Z")
        self.assertEqual(list(r["by_kind"].keys()), ["learning", "user", "unknown"])  # first-appearance
        self.assertEqual(r["by_kind"], {"learning": 2, "user": 1, "unknown": 1})
        self.assertEqual(r["events_tracked"], 5)
        self.assertEqual(list(r["by_event"].keys()), ["recall", "history", "unknown"])
        self.assertEqual(r["by_event"]["recall"],
                         {"writes": 3, "hits": 5, "estimated_tokens": 250, "last_at": "2026-06-15T00:00:00Z"})
        self.assertEqual(r["by_event"]["history"],
                         {"writes": 1, "hits": 1, "estimated_tokens": 50, "last_at": "2026-06-12T00:00:00Z"})
        self.assertEqual(r["by_event"]["unknown"],
                         {"writes": 1, "hits": 7, "estimated_tokens": 9, "last_at": None})
        self.assertEqual(r["economics"], {
            "recall_writes": 3, "history_writes": 1, "total_hit_count": 13,
            "estimated_output_tokens": 309, "last_event_at": "2026-06-15T00:00:00Z",
        })
        self.assertEqual(r["hot_items"], 2)   # use_count > 1: a(3), d(5)

    def test_output_key_order(self):
        r = summaries.usage_summary_json(self.write_raw("e.json", "{}"))
        self.assertEqual(list(r.keys()), list(self.ABSENT.keys()))


if __name__ == "__main__":
    unittest.main()
