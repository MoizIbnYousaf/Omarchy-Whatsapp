"""Exercise the service's real event mask against a disposable SQLite WAL store."""

from contextlib import closing
import os
from pathlib import Path
import re
import select
import shutil
import sqlite3
import subprocess
import tempfile
import time
import unittest


@unittest.skipUnless(shutil.which("inotifywait"), "inotifywait is not installed")
class StoreWatcherTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="omawhatsapp-watch-test-")
        self.addCleanup(temporary.cleanup)
        self.store = Path(temporary.name)
        self.database = self.store / "wacli.db"
        self.writer = sqlite3.connect(self.database)
        self.addCleanup(self.writer.close)
        self.writer.execute("PRAGMA journal_mode=WAL")
        self.writer.execute("CREATE TABLE fixture (value TEXT)")
        self.writer.execute("INSERT INTO fixture VALUES ('initial')")
        self.writer.commit()

        service = (Path(__file__).resolve().parents[1]
                   / "plugins/omawhatsapp/Service.qml").read_text()
        mask = re.search(r'"inotifywait".*?"-e",\s*"([^"]+)"', service, re.S)
        self.assertIsNotNone(mask, "service must declare its store watcher mask")
        self.watcher = subprocess.Popen(
            ["inotifywait", "-m", "-e", mask.group(1),
             "--format", "%f", str(self.store)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        self.addCleanup(self.stop_watcher)
        ready = b""
        deadline = time.monotonic() + 3
        while b"Watches established." not in ready:
            remaining = deadline - time.monotonic()
            self.assertGreater(remaining, 0, "store watcher did not start")
            readable, _, _ = select.select([self.watcher.stderr], [], [], remaining)
            self.assertTrue(readable, "store watcher did not become ready")
            chunk = os.read(self.watcher.stderr.fileno(), 4096)
            self.assertTrue(chunk, "store watcher exited before becoming ready")
            ready += chunk

    def stop_watcher(self):
        self.watcher.terminate()
        try:
            self.watcher.communicate(timeout=3)
        except subprocess.TimeoutExpired:
            self.watcher.kill()
            self.watcher.communicate(timeout=3)

    def refresh_events(self):
        output = b""
        deadline = time.monotonic() + 0.25
        while (remaining := deadline - time.monotonic()) > 0:
            readable, _, _ = select.select([self.watcher.stdout], [], [], remaining)
            if not readable:
                break
            chunk = os.read(self.watcher.stdout.fileno(), 4096)
            self.assertTrue(chunk, "store watcher exited unexpectedly")
            output += chunk
        return [name for name in output.decode().splitlines()
                if name in {"wacli.db", "wacli.db-wal"}]

    def test_read_only_queries_do_not_trigger_another_refresh(self):
        # SQLite opens WAL sidecars writable even when the main DB is read-only.
        # Closing these readers used to emit CLOSE_WRITE and refresh forever.
        for _ in range(3):
            with closing(sqlite3.connect(f"{self.database.as_uri()}?mode=ro", uri=True)) as reader:
                reader.execute("PRAGMA query_only=ON")
                self.assertEqual(reader.execute("SELECT value FROM fixture").fetchall(),
                                 [("initial",)])
        self.assertEqual(self.refresh_events(), [])

    def test_committed_wal_write_triggers_refresh_while_writer_remains_open(self):
        self.writer.execute("INSERT INTO fixture VALUES ('new message')")
        self.writer.commit()
        self.assertIn("wacli.db-wal", self.refresh_events())

    def test_checkpoint_triggers_refresh_for_the_main_database(self):
        self.writer.execute("PRAGMA wal_checkpoint(FULL)").fetchall()
        self.assertIn("wacli.db", self.refresh_events())

    def read_values(self):
        with closing(sqlite3.connect(f"{self.database.as_uri()}?mode=ro", uri=True)) as reader:
            reader.execute("PRAGMA query_only=ON")
            return reader.execute("SELECT value FROM fixture").fetchall()

    def test_read_only_refresh_settles_without_a_persistent_writer(self):
        self.writer.close()
        self.refresh_events()  # Closing the writer can checkpoint/remove the WAL.
        self.assertEqual(self.read_values(), [("initial",)])
        # The first reader may create an empty WAL. That earns one refresh,
        # but subsequent reads must settle even when sync is stopped.
        self.refresh_events()
        for _ in range(3):
            self.assertEqual(self.read_values(), [("initial",)])
            self.assertEqual(self.refresh_events(), [])

    def test_writes_remain_visible_after_each_read_without_feedback(self):
        for index in range(3):
            self.writer.execute("INSERT INTO fixture VALUES (?)", (f"message {index}",))
            self.writer.commit()
            self.assertIn("wacli.db-wal", self.refresh_events())
            self.assertEqual(len(self.read_values()), index + 2)
            self.assertEqual(self.refresh_events(), [])

    def test_database_replacement_and_removal_are_observed(self):
        self.writer.close()
        self.refresh_events()
        replacement = self.store / "replacement.db"
        with closing(sqlite3.connect(replacement)) as writer:
            writer.execute("CREATE TABLE fixture (value TEXT)")
            writer.execute("INSERT INTO fixture VALUES ('replacement')")
            writer.commit()
        os.replace(replacement, self.database)
        self.assertIn("wacli.db", self.refresh_events())
        self.assertEqual(self.read_values(), [("replacement",)])
        self.assertEqual(self.refresh_events(), [])
        self.database.unlink()
        self.assertIn("wacli.db", self.refresh_events())

    def test_rollback_journal_commits_are_observed(self):
        self.writer.execute("PRAGMA journal_mode=DELETE")
        self.refresh_events()
        self.writer.execute("INSERT INTO fixture VALUES ('committed')")
        self.writer.commit()
        self.assertIn("wacli.db", self.refresh_events())
        self.assertEqual(self.read_values(), [("initial",), ("committed",)])
        self.assertEqual(self.refresh_events(), [])
