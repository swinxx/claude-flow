"""RECALL.sqlite FTS5 engine: availability probe, schema init, row insert, term ->
MATCH-query construction, and the hit query with graceful degradation. Behavioral
port of the Bash sqlite_available / fts_query_from_terms / insert_fts_row / the
recall schema / fts_hits_json at kimiflow--v0.1.50 (2527-2644). Uses the Python
stdlib `sqlite3` module instead of shelling to the `sqlite3` CLI."""
import os
import re
import sqlite3

from . import clock

# Source of truth: Bash 2562-2563.
_SCHEMA = (
    "DROP TABLE IF EXISTS recall_meta;\n"
    "DROP TABLE IF EXISTS recall_fts;\n"
    "CREATE TABLE recall_meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);\n"
    "CREATE VIRTUAL TABLE recall_fts USING fts5(kind, source, title, body, ref);"
)

_NON_TERM = re.compile(r"[^A-Za-z0-9_]")


def fts5_available():
    # Bash gates on `command -v sqlite3` (the CLI). The stdlib sqlite3 module is
    # always importable, but FTS5 may not be compiled in, so we probe it. See spec 12.
    try:
        con = sqlite3.connect(":memory:")
    except sqlite3.Error:
        return False
    try:
        con.execute("CREATE VIRTUAL TABLE _probe USING fts5(x)")
        return True
    except sqlite3.Error:
        return False
    finally:
        con.close()


def recall_db_path(root):
    return os.path.join(root, ".kimiflow", "project", "RECALL.sqlite")


def init_recall_db(con):
    # Bash 2559-2565: drop+create the schema, then stamp recall_meta.updated_at.
    con.executescript(_SCHEMA)
    con.execute(
        "INSERT INTO recall_meta(key, value) VALUES('updated_at', ?)", (clock.iso_now(),)
    )


def insert_fts_row(con, kind, source, title, body, ref):
    # Bash 2542-2545 uses sql_quote string interpolation; the stdlib module binds
    # parameters instead (equivalent result, no quoting bugs).
    con.execute(
        "INSERT INTO recall_fts(kind, source, title, body, ref) VALUES(?, ?, ?, ?, ?)",
        (kind, source, title, body, ref),
    )


def fts_query_from_terms(terms):
    # Bash 2531-2540 (jq): strip each term to [A-Za-z0-9_], keep length >= 3,
    # `unique` (jq sorts + dedups), quote each, join with " OR ".
    cleaned = {_NON_TERM.sub("", str(term)) for term in terms}
    kept = sorted(t for t in cleaned if len(t) >= 3)
    return " OR ".join('"' + t + '"' for t in kept)


def fts_hits_json(root, terms, max_hits):
    # Bash 2623-2644: graceful degradation -> [] when sqlite/fts5 absent, db missing,
    # query empty, or any sqlite error.
    db = recall_db_path(root)
    if not fts5_available() or not os.path.isfile(db):
        return []
    query = fts_query_from_terms(terms)
    if not query:
        return []
    try:
        con = sqlite3.connect(db)
    except sqlite3.Error:
        return []
    try:
        cur = con.execute(
            "SELECT kind, source, title, ref, substr(body, 1, 420) AS summary "
            "FROM recall_fts WHERE recall_fts MATCH ? LIMIT ?",
            (query, max_hits),
        )
        columns = [d[0] for d in cur.description]
        return [dict(zip(columns, row)) for row in cur.fetchall()]
    except sqlite3.Error:
        return []
    finally:
        con.close()
