"""Check the bundled query with SQLite data spanning both DST transitions."""
import sqlite3
import unittest
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo


class HighScoreClock(unittest.TestCase):
    def test_api_preserves_instants_and_score_fields(self):
        patch = (Path(__file__).resolve().parents[1] / "home.admin/assets/public-pool-highscore-utc.patch").read_text()
        projection, = [line.split("`")[1] for line in patch.splitlines() if line.startswith("+") and ".select(`" in line]
        with sqlite3.connect(":memory:") as db:
            db.execute("CREATE TABLE score (updatedAt TEXT, bestDifficulty REAL, bestDifficultyUserAgent TEXT)")
            samples = [
                ("2026-03-29 01:30:00", "2026-03-29T01:30:00.000Z", "03:30 +0200"),
                ("2026-10-25 00:30:00.123", "2026-10-25T00:30:00.123Z", "02:30 +0200"),
                ("2026-10-25T02:30:00+01:00", "2026-10-25T01:30:00.000Z", "02:30 +0100"),
                ("2026-10-25T01:30:00Z", "2026-10-25T01:30:00.000Z", "02:30 +0100"),
            ]
            for source, utc, local in samples:
                with self.subTest(source=source):
                    db.execute("DELETE FROM score")
                    db.execute("INSERT INTO score VALUES (?, 42, 'miner')", (source,))
                    row = db.execute(f"SELECT {projection} FROM score").fetchone()
                    self.assertEqual(row, (utc, 42, "miner"))
                    instant = datetime.fromisoformat(row[0].replace("Z", "+00:00"))
                    self.assertEqual(instant.astimezone(ZoneInfo("Europe/Berlin")).strftime("%H:%M %z"), local)


if __name__ == "__main__":
    unittest.main()
