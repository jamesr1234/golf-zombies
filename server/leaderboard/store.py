"""Codes, ranked tries, and scores for the bottle QR leaderboard.

One SQLite file. Each bottle code gets TRIES ranked rounds. A try is spent
when the round starts, so quitting a bad round does not hand it back. The
leaderboard shows each code's best holed round: fewest strokes, then the
fastest time as the server measured it.
"""

import secrets
import sqlite3
import time
from contextlib import contextmanager

TRIES = 3
## No real round of the demo hole is this quick. Anything faster was not played.
MIN_SECONDS = 15.0
MAX_STROKES = 15
## A ticket left open this long is treated as abandoned.
TICKET_HOURS = 3
## No 0/O or 1/I/L, so a code read off a label cannot be misread.
ALPHABET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ"
CODE_LENGTH = 10

_SCHEMA = """
CREATE TABLE IF NOT EXISTS codes (
    code TEXT PRIMARY KEY,
    batch TEXT NOT NULL,
    nickname TEXT,
    tries_used INTEGER NOT NULL DEFAULT 0,
    created REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS runs (
    ticket TEXT PRIMARY KEY,
    code TEXT NOT NULL REFERENCES codes(code),
    started REAL NOT NULL,
    finished REAL,
    holed INTEGER NOT NULL DEFAULT 0,
    strokes INTEGER,
    seconds REAL,
    hidden INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS runs_by_code ON runs(code);
"""

## Best visible holed round per code, ranked.
_BEST = """
SELECT code, nickname, strokes, seconds FROM (
    SELECT r.code, c.nickname, r.strokes, r.seconds,
        ROW_NUMBER() OVER (PARTITION BY r.code ORDER BY r.strokes, r.seconds) AS pick
    FROM runs r JOIN codes c ON c.code = r.code
    WHERE r.holed = 1 AND r.hidden = 0
) WHERE pick = 1
ORDER BY strokes, seconds
"""


class Store:
    def __init__(self, path):
        self.path = path
        with self._db() as db:
            db.executescript(_SCHEMA)

    @contextmanager
    def _db(self):
        db = sqlite3.connect(self.path, timeout=10, isolation_level=None)
        db.row_factory = sqlite3.Row
        try:
            yield db
        finally:
            if db.in_transaction:
                db.execute("ROLLBACK")
            db.close()

    def add_codes(self, count, batch, now=None):
        now = time.time() if now is None else now
        made = []
        with self._db() as db:
            db.execute("BEGIN IMMEDIATE")
            while len(made) < count:
                code = "".join(secrets.choice(ALPHABET) for _ in range(CODE_LENGTH))
                cur = db.execute(
                    "INSERT OR IGNORE INTO codes (code, batch, created) VALUES (?, ?, ?)",
                    (code, batch, now),
                )
                if cur.rowcount == 1:
                    made.append(code)
            db.execute("COMMIT")
        return made

    def status(self, code):
        with self._db() as db:
            row = db.execute("SELECT * FROM codes WHERE code = ?", (code,)).fetchone()
            if row is None:
                return None
            return {
                "tries_left": max(0, TRIES - row["tries_used"]),
                "tries": TRIES,
                "nickname": row["nickname"] or "",
                "best": self._best_for(db, code),
            }

    def set_nickname(self, code, nickname):
        """Once per code, so a leaderboard name cannot be swapped after the fact."""
        with self._db() as db:
            row = db.execute("SELECT nickname FROM codes WHERE code = ?", (code,)).fetchone()
            if row is None:
                return "unknown code"
            if row["nickname"]:
                return "nickname already set"
            db.execute("UPDATE codes SET nickname = ? WHERE code = ?", (nickname, code))
        return None

    def start_run(self, code, now=None):
        now = time.time() if now is None else now
        with self._db() as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute("SELECT * FROM codes WHERE code = ?", (code,)).fetchone()
            if row is None:
                db.execute("ROLLBACK")
                return None, "unknown code"
            if not row["nickname"]:
                db.execute("ROLLBACK")
                return None, "pick a nickname first"
            if row["tries_used"] >= TRIES:
                db.execute("ROLLBACK")
                return None, "no tries left"
            ticket = secrets.token_urlsafe(18)
            db.execute("UPDATE codes SET tries_used = tries_used + 1 WHERE code = ?", (code,))
            db.execute("INSERT INTO runs (ticket, code, started) VALUES (?, ?, ?)", (ticket, code, now))
            db.execute("COMMIT")
        return ticket, None

    def finish_run(self, ticket, holed, strokes, now=None):
        now = time.time() if now is None else now
        with self._db() as db:
            db.execute("BEGIN IMMEDIATE")
            run = db.execute("SELECT * FROM runs WHERE ticket = ?", (ticket,)).fetchone()
            error = self._finish_error(run, holed, strokes, now)
            if error:
                db.execute("ROLLBACK")
                return None, error
            seconds = round(now - run["started"], 2)
            db.execute(
                "UPDATE runs SET finished = ?, holed = ?, strokes = ?, seconds = ? WHERE ticket = ?",
                (now, 1 if holed else 0, strokes if holed else None, seconds, ticket),
            )
            db.execute("COMMIT")
            return {"seconds": seconds, "rank": self._rank_of(db, run["code"])}, None

    @staticmethod
    def _finish_error(run, holed, strokes, now):
        if run is None:
            return "unknown ticket"
        if run["finished"] is not None:
            return "round already finished"
        if now - run["started"] > TICKET_HOURS * 3600:
            return "round expired"
        if not holed:
            return None
        if not isinstance(strokes, int) or isinstance(strokes, bool):
            return "bad strokes"
        if strokes < 1 or strokes > MAX_STROKES:
            return "bad strokes"
        if now - run["started"] < MIN_SECONDS:
            return "round too fast"
        return None

    def leaderboard(self, limit=50):
        with self._db() as db:
            rows = db.execute(_BEST + " LIMIT ?", (limit,)).fetchall()
        return [
            {"rank": i + 1, "nickname": r["nickname"], "strokes": r["strokes"], "seconds": r["seconds"]}
            for i, r in enumerate(rows)
        ]

    def _best_for(self, db, code):
        row = db.execute(
            "SELECT strokes, seconds FROM runs WHERE code = ? AND holed = 1 AND hidden = 0 "
            "ORDER BY strokes, seconds LIMIT 1",
            (code,),
        ).fetchone()
        return None if row is None else {"strokes": row["strokes"], "seconds": row["seconds"]}

    def _rank_of(self, db, code):
        for i, row in enumerate(db.execute(_BEST).fetchall()):
            if row["code"] == code:
                return i + 1
        return None

    def recent_runs(self, limit=200):
        with self._db() as db:
            rows = db.execute(
                "SELECT r.ticket, r.code, c.nickname, r.started, r.finished, r.holed, r.strokes, "
                "r.seconds, r.hidden FROM runs r JOIN codes c ON c.code = r.code "
                "ORDER BY r.started DESC LIMIT ?",
                (limit,),
            ).fetchall()
        return [dict(r) for r in rows]

    def set_hidden(self, ticket, hidden):
        with self._db() as db:
            cur = db.execute("UPDATE runs SET hidden = ? WHERE ticket = ?", (1 if hidden else 0, ticket))
        return cur.rowcount == 1
