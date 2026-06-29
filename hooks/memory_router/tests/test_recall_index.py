import os
import shutil
import sqlite3
import tempfile
import unittest
from unittest import mock

from memory_router import recall_index

ISO = "2026-06-29T00:00:00Z"


class FtsQueryFromTermsCase(unittest.TestCase):
    def q(self, terms):
        return recall_index.fts_query_from_terms(terms)

    def test_basic_sorted_and_quoted(self):
        self.assertEqual(self.q(["build", "auth"]), '"auth" OR "build"')

    def test_strips_non_term_chars(self):
        self.assertEqual(self.q(["foo-bar!"]), '"foobar"')

    def test_drops_terms_shorter_than_three(self):
        self.assertEqual(self.q(["ab", "abc", "x"]), '"abc"')

    def test_unique_dedups_and_sorts(self):
        self.assertEqual(self.q(["zoo", "abc", "abc", "zoo"]), '"abc" OR "zoo"')

    def test_underscore_kept(self):
        self.assertEqual(self.q(["foo_bar"]), '"foo_bar"')

    def test_empty_when_all_filtered(self):
        self.assertEqual(self.q(["a", "b!", ""]), "")

    def test_length_measured_after_stripping(self):
        # "a-b" strips to "ab" (len 2) -> dropped.
        self.assertEqual(self.q(["a-b"]), "")


class FtsEngineCase(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.project = os.path.join(self.root, ".kimiflow", "project")
        os.makedirs(self.project, exist_ok=True)
        self.db = recall_index.recall_db_path(self.root)
        p = mock.patch("memory_router.clock.iso_now", return_value=ISO)
        p.start()
        self.addCleanup(p.stop)

    def build(self, rows):
        con = sqlite3.connect(self.db)
        recall_index.init_recall_db(con)
        for r in rows:
            recall_index.insert_fts_row(con, *r)
        con.commit()
        con.close()

    def test_fts5_available(self):
        self.assertTrue(recall_index.fts5_available())

    def test_init_stamps_updated_at(self):
        con = sqlite3.connect(self.db)
        recall_index.init_recall_db(con)
        con.commit()
        value = con.execute(
            "SELECT value FROM recall_meta WHERE key = 'updated_at'"
        ).fetchone()[0]
        con.close()
        self.assertEqual(value, ISO)

    def test_query_roundtrip_returns_hit_shape(self):
        self.build([
            ("learning", ".kimiflow/project/LEARNINGS.jsonl", "build flow",
             "we fixed the build flow and release convention", "src/foo.py:5"),
            ("memory", ".kimiflow/project/MEMORY.md", "Project Memory",
             "auth token rotation chosen", ".kimiflow/project/MEMORY.md"),
        ])
        hits = recall_index.fts_hits_json(self.root, ["build"], 10)
        self.assertEqual(len(hits), 1)
        self.assertEqual(hits[0], {
            "kind": "learning",
            "source": ".kimiflow/project/LEARNINGS.jsonl",
            "title": "build flow",
            "ref": "src/foo.py:5",
            "summary": "we fixed the build flow and release convention",
        })

    def test_or_query_matches_multiple(self):
        self.build([
            ("learning", "L", "t1", "build pipeline", "r1"),
            ("memory", "M", "t2", "auth rotation", "r2"),
            ("fact", "F", "t3", "unrelated text", "r3"),
        ])
        hits = recall_index.fts_hits_json(self.root, ["build", "auth"], 10)
        self.assertEqual({h["ref"] for h in hits}, {"r1", "r2"})

    def test_limit_respected(self):
        self.build([("learning", "L", "t%d" % i, "build flow", "r%d" % i) for i in range(5)])
        self.assertEqual(len(recall_index.fts_hits_json(self.root, ["build"], 2)), 2)

    def test_summary_truncated_to_420(self):
        self.build([("learning", "L", "t", "build " + "x" * 500, "r")])
        hits = recall_index.fts_hits_json(self.root, ["build"], 10)
        self.assertEqual(len(hits[0]["summary"]), 420)

    def test_missing_db_returns_empty(self):
        self.assertEqual(recall_index.fts_hits_json(self.root, ["build"], 10), [])

    def test_empty_query_returns_empty(self):
        self.build([("learning", "L", "t", "build flow", "r")])
        self.assertEqual(recall_index.fts_hits_json(self.root, ["ab", "x"], 10), [])

    def test_corrupt_db_returns_empty(self):
        with open(self.db, "w", encoding="utf-8") as fh:
            fh.write("this is not a sqlite database")
        self.assertEqual(recall_index.fts_hits_json(self.root, ["build"], 10), [])

    def test_unavailable_fts5_returns_empty(self):
        self.build([("learning", "L", "t", "build flow", "r")])
        with mock.patch("memory_router.recall_index.fts5_available", return_value=False):
            self.assertEqual(recall_index.fts_hits_json(self.root, ["build"], 10), [])


if __name__ == "__main__":
    unittest.main()
