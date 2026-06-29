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


if __name__ == "__main__":
    unittest.main()
