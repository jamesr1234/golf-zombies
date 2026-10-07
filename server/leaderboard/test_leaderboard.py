"""Run with: python3 -m unittest discover server/leaderboard"""

import csv
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import names  # noqa: E402
from app import MISS_LIMIT, Api  # noqa: E402
from make_codes import write_batch  # noqa: E402
from store import MIN_SECONDS, TRIES, Store  # noqa: E402


class Fresh(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.store = Store(os.path.join(self.dir.name, "test.db"))
        self.code = self.store.add_codes(1, "test")[0]

    def tearDown(self):
        self.dir.cleanup()

    def named(self, code=None, nickname="Ace"):
        code = code or self.code
        self.store.set_nickname(code, nickname)
        return code

    def play(self, code, strokes, seconds, holed=True):
        ticket, error = self.store.start_run(code, now=1000.0)
        self.assertIsNone(error)
        return self.store.finish_run(ticket, holed, strokes, now=1000.0 + seconds)


class StoreTest(Fresh):
    def test_a_code_gets_three_tries_spent_at_the_start(self):
        self.named()
        for left in range(TRIES - 1, -1, -1):
            ticket, error = self.store.start_run(self.code)
            self.assertIsNone(error)
            self.assertEqual(self.store.status(self.code)["tries_left"], left)
        self.assertEqual(self.store.start_run(self.code), (None, "no tries left"))

    def test_a_ranked_round_needs_a_nickname_first(self):
        self.assertEqual(self.store.start_run(self.code), (None, "pick a nickname first"))
        self.assertEqual(self.store.status(self.code)["tries_left"], TRIES)

    def test_a_nickname_is_set_once(self):
        self.assertIsNone(self.store.set_nickname(self.code, "Ace"))
        self.assertEqual(self.store.set_nickname(self.code, "Other"), "nickname already set")
        self.assertEqual(self.store.status(self.code)["nickname"], "Ace")

    def test_unknown_code_has_no_status(self):
        self.assertIsNone(self.store.status("ZZZZZZZZZZ"))
        self.assertEqual(self.store.start_run("ZZZZZZZZZZ"), (None, "unknown code"))

    def test_the_board_keeps_each_code_best_round(self):
        self.named()
        self.play(self.code, 5, 60)
        self.play(self.code, 3, 90)
        board = self.store.leaderboard()
        self.assertEqual(len(board), 1)
        self.assertEqual(board[0]["strokes"], 3)

    def test_fewer_strokes_rank_first_then_the_faster_time(self):
        a, b, c = self.store.add_codes(3, "test")
        self.named(a, "Slow")
        self.named(b, "Fast")
        self.named(c, "Best")
        self.play(a, 4, 120)
        self.play(b, 4, 50)
        result, _ = self.play(c, 3, 200)
        self.assertEqual(result["rank"], 1)
        self.assertEqual([s["nickname"] for s in self.store.leaderboard()], ["Best", "Fast", "Slow"])

    def test_a_round_cannot_be_finished_twice(self):
        self.named()
        ticket, _ = self.store.start_run(self.code, now=0.0)
        self.assertIsNotNone(self.store.finish_run(ticket, True, 4, now=100.0)[0])
        self.assertEqual(self.store.finish_run(ticket, True, 1, now=101.0), (None, "round already finished"))

    def test_impossible_rounds_are_refused(self):
        self.named()
        self.assertEqual(self.play(self.code, 2, MIN_SECONDS - 1), (None, "round too fast"))
        self.assertEqual(self.play(self.code, 0, 60), (None, "bad strokes"))
        self.assertEqual(self.play(self.code, "3", 60), (None, "bad strokes"))
        self.assertEqual(self.store.leaderboard(), [])

    def test_a_lost_round_spends_the_try_but_scores_nothing(self):
        self.named()
        result, error = self.play(self.code, None, 5, holed=False)
        self.assertIsNone(error)
        self.assertIsNone(result["rank"])
        self.assertEqual(self.store.status(self.code)["tries_left"], TRIES - 1)
        self.assertEqual(self.store.leaderboard(), [])

    def test_a_hidden_round_leaves_the_board(self):
        self.named()
        self.play(self.code, 3, 60)
        ticket = self.store.recent_runs()[0]["ticket"]
        self.assertTrue(self.store.set_hidden(ticket, True))
        self.assertEqual(self.store.leaderboard(), [])
        self.store.set_hidden(ticket, False)
        self.assertEqual(len(self.store.leaderboard()), 1)


class ApiTest(Fresh):
    def setUp(self):
        super().setUp()
        self.api = Api(self.store, admin_key="secret")

    def test_a_ranked_round_end_to_end(self):
        status, body = self.api.handle("POST", "/api/code/%s/nickname" % self.code.lower(), {"nickname": "  Big  Hitter "})
        self.assertEqual(status, 200)
        self.assertEqual(body["nickname"], "Big Hitter")
        status, body = self.api.handle("POST", "/api/run/start", {"code": self.code})
        self.assertEqual((status, body["tries_left"]), (200, TRIES - 1))
        status, body = self.api.handle("POST", "/api/run/finish", {"ticket": body["ticket"], "holed": False})
        self.assertEqual(status, 200)
        status, body = self.api.handle("GET", "/api/leaderboard?limit=5")
        self.assertEqual((status, body["scores"]), (200, []))

    def test_rude_nicknames_are_refused(self):
        status, body = self.api.handle("POST", "/api/code/%s/nickname" % self.code, {"nickname": "sh1t"})
        self.assertEqual(status, 400)
        self.assertEqual(self.store.status(self.code)["nickname"], "")

    def test_guessing_codes_gets_slowed_down(self):
        for _ in range(MISS_LIMIT):
            self.assertEqual(self.api.handle("GET", "/api/code/ZZZZZZZZZZ", ip="1.2.3.4")[0], 404)
        self.assertEqual(self.api.handle("GET", "/api/code/%s" % self.code, ip="1.2.3.4")[0], 429)
        self.assertEqual(self.api.handle("GET", "/api/code/%s" % self.code, ip="5.6.7.8")[0], 200)

    def test_admin_needs_the_key(self):
        self.assertEqual(self.api.handle("GET", "/api/admin/runs")[0], 401)
        self.assertEqual(self.api.handle("GET", "/api/admin/runs", headers={"x-admin-key": "nope"})[0], 401)
        self.assertEqual(self.api.handle("GET", "/api/admin/runs", headers={"x-admin-key": "secret"})[0], 200)
        self.assertEqual(Api(self.store, "").handle("GET", "/api/admin/runs", headers={"x-admin-key": ""})[0], 401)

    def test_bad_bodies_are_a_400_not_a_crash(self):
        self.assertEqual(self.api.handle("POST", "/api/run/start", [])[0], 400)
        self.assertEqual(self.api.handle("POST", "/api/run/finish", {})[0], 400)

    def test_pages_are_served(self):
        for page in ("/leaderboard", "/admin"):
            status, body = self.api.handle("GET", page)
            self.assertEqual(status, 200)
            self.assertIn("<html", body)


class NamesTest(unittest.TestCase):
    def test_plain_names_pass_and_tidy_up(self):
        self.assertEqual(names.clean(" Tiger   W "), ("Tiger W", None))
        for ok in ("Grape", "Peacock", "Fagundes", "Spicy_Al"):
            self.assertEqual(names.clean(ok)[0], ok)

    def test_bad_names_are_refused(self):
        for bad in ("x", "a" * 15, "emoji\U0001f600", "F.U.C.K", "5h1t", None):
            self.assertIsNone(names.clean(bad)[0], bad)


class CodesTest(Fresh):
    def test_a_batch_writes_one_qr_address_per_code(self):
        out = os.path.join(self.dir.name, "batch.csv")
        codes = write_batch(self.store, 25, "spring", out, "https://golfis.8bev.ca/")
        with open(out) as f:
            rows = list(csv.DictReader(f))
        self.assertEqual(len(rows), 25)
        self.assertEqual(len(set(codes)), 25)
        self.assertEqual(rows[0]["url"], "https://golfis.8bev.ca/?c=" + rows[0]["code"])
        self.assertIsNotNone(self.store.status(rows[-1]["code"]))


if __name__ == "__main__":
    unittest.main()
