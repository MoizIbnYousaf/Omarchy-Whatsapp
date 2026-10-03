from __future__ import annotations

import importlib.util
from importlib.machinery import SourceFileLoader
from contextlib import closing
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest import mock


SCRIPT = Path(os.environ["OMAW_SCRIPT"])
SPEC = importlib.util.spec_from_loader(
    "omawhatsapp_backend", SourceFileLoader("omawhatsapp_backend", str(SCRIPT))
)
assert SPEC and SPEC.loader
backend_module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(backend_module)
# The suite must never play a real notification sound on the developer's desk.
backend_module.SOUND_PLAYER = Path("/nonexistent/omawhatsapp-test-player")


def installed_units(root: Path) -> Path:
    """A private unit folder where the first-run setup already wrote the sync
    units, so no test reads the developer's own systemd folder."""
    units = root / "units"
    units.mkdir(exist_ok=True)
    for name in backend_module.SETUP_UNITS:
        (units / name).write_text(backend_module.stamped("[Unit]\nDescription=test unit\n"),
                                  encoding="utf-8")
    return units


SCHEMA = """
CREATE TABLE chats (
  jid TEXT PRIMARY KEY, kind TEXT NOT NULL, name TEXT, last_message_ts INTEGER,
  archived INTEGER NOT NULL DEFAULT 0, pinned INTEGER NOT NULL DEFAULT 0,
  muted_until INTEGER NOT NULL DEFAULT 0, unread INTEGER NOT NULL DEFAULT 0,
  unread_count INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE groups (
  jid TEXT PRIMARY KEY, name TEXT, owner_jid TEXT, created_ts INTEGER,
  is_parent INTEGER NOT NULL DEFAULT 0, linked_parent_jid TEXT,
  left_at INTEGER, updated_at INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE group_participants (
  group_jid TEXT NOT NULL, user_jid TEXT NOT NULL, role TEXT, updated_at INTEGER,
  PRIMARY KEY (group_jid, user_jid)
);
CREATE TABLE contacts (
  jid TEXT PRIMARY KEY, phone TEXT, push_name TEXT, full_name TEXT,
  first_name TEXT, business_name TEXT, system_name TEXT, updated_at INTEGER
);
CREATE TABLE contact_aliases (
  jid TEXT PRIMARY KEY, alias TEXT NOT NULL, notes TEXT, updated_at INTEGER NOT NULL
);
CREATE TABLE messages (
  rowid INTEGER PRIMARY KEY AUTOINCREMENT, chat_jid TEXT NOT NULL, chat_name TEXT,
  msg_id TEXT NOT NULL, sender_jid TEXT, sender_name TEXT, ts INTEGER NOT NULL,
  from_me INTEGER NOT NULL, text TEXT, display_text TEXT, quoted_msg_id TEXT,
  quoted_sender_jid TEXT, is_forwarded INTEGER NOT NULL DEFAULT 0,
  forwarding_score INTEGER NOT NULL DEFAULT 0, reaction_to_id TEXT,
  reaction_emoji TEXT, media_type TEXT, media_caption TEXT, filename TEXT,
  mime_type TEXT, direct_path TEXT, media_key BLOB, file_sha256 BLOB,
  file_enc_sha256 BLOB, file_length INTEGER, local_path TEXT, downloaded_at INTEGER,
  media_unavailable_at INTEGER, revoked INTEGER NOT NULL DEFAULT 0,
  deleted_for_me INTEGER NOT NULL DEFAULT 0, deleted_at INTEGER,
  deletion_reason TEXT, payload_purged_at INTEGER, edited INTEGER NOT NULL DEFAULT 0,
  edited_ts INTEGER NOT NULL DEFAULT 0, buttons TEXT,
  UNIQUE(chat_jid, msg_id)
);
CREATE TABLE starred (
  chat_jid TEXT NOT NULL, msg_id TEXT NOT NULL, sender_jid TEXT,
  from_me INTEGER NOT NULL DEFAULT 0, starred_at INTEGER NOT NULL,
  PRIMARY KEY (chat_jid, msg_id)
);
CREATE TABLE message_locations (
  chat_jid TEXT NOT NULL, msg_id TEXT NOT NULL, latitude REAL,
  longitude REAL, name TEXT, address TEXT, is_live INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (chat_jid, msg_id)
);
"""


class BackendTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        # Session markers (quit, launch) live in the runtime directory; keep
        # them in the test's own tree, never the desktop session's.
        runtime = self.root / "runtime"
        runtime.mkdir(mode=0o700, exist_ok=True)
        environment = mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": str(runtime)})
        environment.start()
        self.addCleanup(environment.stop)
        self.store = self.root / "wacli"
        self.store.mkdir()
        self.wacli = self.root / "wacli-bin"
        self.wacli.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        self.wacli.chmod(0o700)
        self.preview = self.root / "mock.png"
        self.preview.write_bytes(b"png")
        self.preview_two = self.root / "second.jpg"
        self.preview_two.write_bytes(b"jpg")
        self.document = self.root / "notes.pdf"
        self.document.write_bytes(b"pdf")
        self.sticker = self.root / "sticker.webp"
        self.sticker.write_bytes(b"webp")
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.executescript(SCHEMA)
            connection.executemany(
                "INSERT INTO chats VALUES (?, ?, ?, ?, 0, ?, 0, 0, ?)",
                [
                    ("team@g.us", "group", "Design team", 30, 1, 3),
                    ("alex@s.whatsapp.net", "dm", "Alex", 40, 0, 1),
                    ("archive@g.us", "group", "Archive", 10, 0, 0),
                    ("news@newsletter", "newsletter", "News", 50, 0, 4),
                    ("legacy@newsletter", "unknown", "Legacy channel", 49, 0, 0),
                    ("community@g.us", "group", "Community", 48, 0, 0),
                    ("subgroup@g.us", "group", "Community subgroup", 47, 0, 0),
                ],
            )
            connection.executemany(
                """INSERT INTO groups
                (jid, name, is_parent, linked_parent_jid, updated_at)
                VALUES (?, ?, ?, ?, 1)""",
                [
                    ("community@g.us", "Community", 1, None),
                    ("subgroup@g.us", "Community subgroup", 0, "community@g.us"),
                ],
            )
            connection.executemany(
                """INSERT INTO messages
                (chat_jid, chat_name, msg_id, sender_jid, sender_name, ts, from_me,
                 text, reaction_to_id, media_type, mime_type, local_path)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, '', ?, ?, ?)""",
                [
                    ("team@g.us", "Design team", "t1", "member@s.whatsapp.net", "Sam", 30, 0, "ship it", "", "", ""),
                    ("alex@s.whatsapp.net", "Alex", "a1", "me@s.whatsapp.net", "", 40, 1, "hello", "", "", ""),
                    ("team@g.us", "Design team", "t2", "me@s.whatsapp.net", "", 20, 1, "mockup", "image", "image/png", str(self.preview)),
                    # The chat's three unread messages are all stored after
                    # your last message, as in a real mirror.
                    ("team@g.us", "Design team", "t0a", "member@s.whatsapp.net", "Sam", 25, 0, "earlier", "", "", ""),
                    ("team@g.us", "Design team", "t0b", "member@s.whatsapp.net", "Sam", 26, 0, "earlier too", "", "", ""),
                ],
            )
            connection.executemany(
                "INSERT INTO contacts VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                [
                    ("member@s.whatsapp.net", "15551234567", "Sam", "Sam Rivera", "Sam", "", "", 1),
                    ("admin@s.whatsapp.net", "15557654321", "Alex", "Alex Kim", "Alex", "", "", 1),
                ],
            )
            connection.executemany(
                "INSERT INTO group_participants VALUES (?, ?, ?, ?)",
                [
                    ("team@g.us", "member@s.whatsapp.net", "member", 1),
                    ("team@g.us", "admin@s.whatsapp.net", "admin", 1),
                ],
            )
        self.backend = backend_module.Backend(
            store_dir=self.store, state_dir=self.root / "state", wacli=self.wacli,
            unit_dir=installed_units(self.root),
        )

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_sync_health_scopes_logout_to_current_invocation(self) -> None:
        invocation = "a" * 32
        results = [subprocess.CompletedProcess([], 0, invocation + "\n", ""),
                   subprocess.CompletedProcess([], 0,
                       "Connected.\nLogged out of WhatsApp (401: logged out from another device). Stopping sync.\n", "")]
        with mock.patch.object(backend_module, "run_bounded", side_effect=results) as run:
            self.assertEqual(self.backend._sync_health(self.backend.active), "relink-required")
        self.assertIn("_SYSTEMD_INVOCATION_ID=" + invocation, run.call_args.args[0])

    def test_failed_relink_does_not_restart_a_revoked_session(self) -> None:
        with mock.patch.object(self.backend, "_sync_health", return_value="relink-required"), \
                mock.patch.object(self.backend, "_systemctl_user") as systemctl:
            self.assertEqual(self.backend._finalize_link(self.backend.active, 1), 1)
            systemctl.assert_not_called()

    def test_sync_health_does_not_read_old_logs_without_invocation(self) -> None:
        with mock.patch.object(backend_module, "run_bounded", return_value=
                subprocess.CompletedProcess([], 0, "", "")) as run:
            self.assertEqual(self.backend._sync_health(self.backend.active), "unknown")
            self.assertEqual(run.call_count, 1)

    def test_sync_health_tracks_disconnect_and_reconnect(self) -> None:
        for logs, expected in [("Connected.\nDisconnected.\n", "unknown"),
                               ("Disconnected.\nConnected.\n", "connected")]:
            with self.subTest(logs=logs), mock.patch.object(backend_module, "run_bounded", side_effect=[
                    subprocess.CompletedProcess([], 0, "b" * 32, ""),
                    subprocess.CompletedProcess([], 0, logs, "")]):
                self.assertEqual(self.backend._sync_health(self.backend.active), expected)

    def test_revoked_link_keeps_archive_ready_without_claiming_authentication(self) -> None:
        with mock.patch.object(self.backend, "_doctor_cached", return_value={"authenticated": True}), \
                mock.patch.object(self.backend, "_sync_active", return_value=False), \
                mock.patch.object(self.backend, "_sync_health", return_value="relink-required"):
            status = self.backend.status()
        self.assertFalse(status["authenticated"])
        self.assertTrue(status["needs_relink"])
        self.assertTrue(status["rail_ready"])
        self.assertEqual(status["connection_state"], "relink-required")
        self.assertNotIn("401", json.dumps(status))

    def test_chat_rail_contains_every_local_chat(self) -> None:
        result = self.backend.chats()
        self.assertEqual({chat["name"] for chat in result["chats"]},
                         {"Design team", "Alex", "Archive", "Community subgroup"})
        self.assertEqual(result["chats"][0]["name"], "Design team")  # pinned first
        self.assertEqual(result["chats"][0]["unread"], 3)

    def _unread(self, jid: str) -> int:
        return next(chat for chat in self.backend.chats()["chats"] if chat["jid"] == jid)["unread"]

    def _insert(self, jid: str, msg_id: str, ts: int, from_me: int = 0, text: str = "",
                display: str = "", reaction: str = "") -> None:
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute(
                """INSERT INTO messages (chat_jid, chat_name, msg_id, sender_jid, sender_name,
                   ts, from_me, text, display_text, reaction_to_id, media_type, mime_type, local_path)
                   VALUES (?, '', ?, '', '', ?, ?, ?, ?, ?, '', '', '')""",
                [jid, msg_id, ts, from_me, text, display, reaction])

    def _set_unread(self, jid: str, count: int) -> None:
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute("UPDATE chats SET unread_count = ?, unread = ? WHERE jid = ?",
                               [count, 1 if count else 0, jid])

    def test_a_placeholder_wacli_could_not_decode_is_not_unread(self) -> None:
        # Found on the owner's mirror: four chats "unread" for months over a
        # "(message)" row the app never shows; the phone counted none of them.
        self._insert("archive@g.us", "p1", 12, display="(message)")
        self._set_unread("archive@g.us", 1)
        self.assertEqual(self._unread("archive@g.us"), 0)
        self._insert("archive@g.us", "p2", 13, text="a real one")
        self._set_unread("archive@g.us", 2)
        self.assertEqual(self._unread("archive@g.us"), 1)

    def _store_schema(self, version: int) -> None:
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute("CREATE TABLE IF NOT EXISTS schema_migrations "
                               "(version INTEGER PRIMARY KEY, name TEXT, applied_at INTEGER)")
            connection.execute("INSERT OR REPLACE INTO schema_migrations VALUES (?, 'x', 1)", [version])

    def test_wacli_019_counts_are_not_discounted_twice(self) -> None:
        # wacli 0.19 (migration 27) leaves reactions and undecodable rows out
        # of its count; subtracting them again would hide real messages.
        for index, msg_id in enumerate(("m1", "m2", "m3")):
            self._insert("archive@g.us", msg_id, 12 + index, text=f"real {index}")
        self._insert("archive@g.us", "r1", 20, reaction="m1")
        self._insert("archive@g.us", "r2", 21, reaction="m2")
        self._set_unread("archive@g.us", 3)
        self._store_schema(26)
        self.assertEqual(self._unread("archive@g.us"), 1,
                         "0.18: two of the last three rows are reactions it counted")
        self._store_schema(27)
        self.assertEqual(self._unread("archive@g.us"), 3, "0.19: the count is already right")
        self._insert("archive@g.us", "me1", 30, from_me=1, text="reply")
        self.assertEqual(self._unread("archive@g.us"), 0, "a reply still bounds it")

    def test_a_reaction_is_not_an_unread_message(self) -> None:
        self._insert("archive@g.us", "r1", 12, reaction="some-message")
        self._set_unread("archive@g.us", 1)
        self.assertEqual(self._unread("archive@g.us"), 0)

    def test_your_reply_marks_the_chat_read(self) -> None:
        self._insert("archive@g.us", "in1", 12, text="question")
        self._insert("archive@g.us", "me1", 13, from_me=1, text="answer")
        self._set_unread("archive@g.us", 1)
        self.assertEqual(self._unread("archive@g.us"), 0, "a reply from the phone left wacli's count behind")
        self._insert("archive@g.us", "in2", 14, text="thanks")
        self._set_unread("archive@g.us", 2)
        self.assertEqual(self._unread("archive@g.us"), 1, "only what came after the reply is waiting")

    def test_a_count_from_the_phone_without_stored_messages_is_kept(self) -> None:
        # History sync can report unread messages the mirror never received;
        # with no reply to bound it, the count stands.
        self._set_unread("archive@g.us", 4)
        self.assertEqual(self._unread("archive@g.us"), 4)

    def test_a_chat_is_marked_when_an_unread_message_mentions_you(self) -> None:
        # L222: with a wacli that records mentions, the rail knows a chat's
        # unread messages @mention this account; without the table it never does.
        def team() -> dict:
            return next(chat for chat in self.backend.chats()["chats"] if chat["jid"] == "team@g.us")
        self.assertFalse(team()["mentioned"], "an official wacli records no mentions")
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute("""CREATE TABLE message_mentions (chat_jid TEXT NOT NULL, msg_id TEXT NOT NULL,
                jid TEXT NOT NULL, is_self INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (chat_jid, msg_id, jid))""")
            connection.execute("INSERT INTO message_mentions VALUES ('team@g.us', 't1', 'me@s.whatsapp.net', 1)")
            connection.execute("UPDATE chats SET unread_count = 1 WHERE jid = 'team@g.us'")
        self.assertTrue(team()["mentioned"], "the unread message mentions you")
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute("UPDATE message_mentions SET is_self = 0")
        self.assertFalse(team()["mentioned"], "someone else was mentioned")
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute("UPDATE message_mentions SET is_self = 1")
            connection.execute("UPDATE chats SET unread_count = 0, unread = 0 WHERE jid = 'team@g.us'")
        self.assertFalse(team()["mentioned"], "read: no badge")

    def test_a_chat_marked_unread_elsewhere_counts_as_one(self) -> None:
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute("UPDATE chats SET unread = 1, unread_count = 0 WHERE jid = 'archive@g.us'")
        archive = next(chat for chat in self.backend.chats()["chats"] if chat["jid"] == "archive@g.us")
        self.assertEqual(archive["unread"], 1)
        self.assertEqual(archive["notification_unread"], 1)
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute("UPDATE chats SET unread = 0, unread_count = 0 WHERE jid = 'archive@g.us'")
        archive = next(chat for chat in self.backend.chats()["chats"] if chat["jid"] == "archive@g.us")
        self.assertEqual(archive["unread"], 0)

    def test_a_healthy_doctor_answer_is_reused_for_a_minute(self) -> None:
        account = self.backend.account("")
        healthy = {"authenticated": True, "fts_enabled": True, "store_dir": str(self.store)}
        with mock.patch.object(self.backend, "_doctor", return_value=healthy) as doctor:
            self.assertTrue(self.backend._doctor_cached(account)["authenticated"])
            self.assertTrue(self.backend._doctor_cached(account)["authenticated"])
        self.assertEqual(doctor.call_count, 1, "the status poll stops opening the session store every 12 s")
        later = time.time() + backend_module.DOCTOR_CACHE_TTL + 1
        with mock.patch.object(self.backend, "_doctor", return_value=healthy) as doctor, \
             mock.patch.object(backend_module.time, "time", return_value=later):
            self.backend._doctor_cached(account)
        self.assertEqual(doctor.call_count, 1, "an old answer is asked again")

    def test_an_unhealthy_doctor_answer_is_never_reused(self) -> None:
        account = self.backend.account("")
        with mock.patch.object(self.backend, "_doctor",
                               return_value={"authenticated": False}) as doctor:
            self.backend._doctor_cached(account)
            self.backend._doctor_cached(account)
        self.assertEqual(doctor.call_count, 2, "a pairing in progress shows up on the next poll")
        with mock.patch.object(self.backend, "_doctor", return_value={
                "authenticated": True, "store_error": "synthetic"}) as doctor:
            self.backend._doctor_cached(account)
            self.backend._doctor_cached(account)
        self.assertEqual(doctor.call_count, 2)

    def test_chat_search_is_literal(self) -> None:
        self.assertEqual(self.backend.chats("Design%team")["chats"], [])
        self.assertEqual(self.backend.chats("design")["chats"][0]["jid"], "team@g.us")

    def test_profile_photos_are_explicit_private_cached_remote_reads(self) -> None:
        with self.assertRaisesRegex(
                backend_module.OmaWhatsAppError, "authorization='remote-read'"):
            self.backend.refresh_avatars("")

        def metadata(account, candidates):
            return ([{
                "key": candidate["key"], "picture_id": "synthetic-picture",
                "url": "https://cdn.example.test/avatar.jpg", "unchanged": False,
            } for candidate in candidates], [])

        jpeg = b"\xff\xd8\xff" + b"synthetic-avatar"
        with mock.patch.object(
                self.backend, "_profile_picture_metadata", side_effect=metadata), \
                mock.patch.object(
                    backend_module, "fetch_https_image", return_value=jpeg) as fetch:
            result = self.backend.refresh_avatars("remote-read")
        # Every rail chat, the group inside a Community included.
        self.assertEqual(result["refreshed"], 4)
        self.assertEqual(fetch.call_count, 4)
        chats = self.backend.chats()["chats"]
        self.assertTrue(all(Path(chat["avatar_path"]).is_file() for chat in chats))
        self.assertTrue(all("http" not in chat["avatar_path"] for chat in chats))
        self.assertTrue(all(
            Path(chat["avatar_path"]).is_relative_to(self.root / "state" / "avatars")
            for chat in chats
        ))

        # The rail is strictly local: a fresh cache is not fetched again until
        # its TTL expires, and merely reading chats never invokes WhatsApp.
        with mock.patch.object(self.backend, "_profile_picture_metadata") as remote:
            current = self.backend.refresh_avatars("remote-read")
            self.backend.chats()
        self.assertEqual(current["checked"], 0)
        remote.assert_not_called()

    def test_profile_metadata_yields_sync_once_for_the_whole_account_batch(self) -> None:
        account = self.backend.account("")
        candidates = [
            {"key": "one", "jid": "alex@s.whatsapp.net", "picture_id": ""},
            {"key": "two", "jid": "team@g.us", "picture_id": "old"},
        ]
        results = [subprocess.CompletedProcess(
            [], 0, json.dumps({"success": True, "data": {
                "id": key, "url": "", "unchanged": True,
            }}), ""
        ) for key in ("new-one", "new-two")]
        systemctl_result = subprocess.CompletedProcess([], 0, "", "")
        with mock.patch.object(
                self.backend, "_sync_active", return_value=True), \
                mock.patch.object(
                    self.backend, "_systemctl_user",
                    return_value=systemctl_result,
                ) as systemctl, mock.patch.object(
                    self.backend, "_run_after_sync_yield", side_effect=results,
                ) as run:
            records, failed = self.backend._profile_picture_metadata(
                account, candidates
            )
        self.assertEqual([record["picture_id"] for record in records],
                         ["new-one", "new-two"])
        self.assertEqual(failed, [])
        self.assertEqual([call.args[0] for call in systemctl.call_args_list], [
            ["stop", account.unit], ["start", account.unit],
        ])
        self.assertEqual(run.call_count, 2)
        run.assert_any_call(
            ["--json", "profile", "picture-info", "--jid",
             "alex@s.whatsapp.net", "--preview"],
            timeout=20, account=account,
        )

    def test_avatar_refresh_advances_past_fresh_rows_and_repairs_missing_files(self) -> None:
        account = self.backend.account("")
        rows = [{"account": account.name, "jid": f"synthetic-{index}@example"}
                for index in range(15)]
        keys = [self.backend._avatar_key(account, row["jid"]) for row in rows]
        now = int(time.time())
        entries = {
            key: {"picture_id": f"picture-{index}", "checked_at": now,
                  "missing": False, "filename": f"file-{index}.jpg"}
            for index, key in enumerate(keys[:12])
        }
        paths = {key: f"/synthetic/{index}.jpg"
                 for index, key in enumerate(keys[:11])}
        captured = []

        def metadata(selected, candidates):
            captured.extend(candidates)
            return ([{"key": item["key"], "picture_id": "", "url": "",
                      "unchanged": False} for item in candidates], [])

        with mock.patch.object(self.backend, "chats", return_value={"chats": rows}), \
                mock.patch.object(self.backend.avatar_cache, "entries", return_value=entries), \
                mock.patch.object(self.backend.avatar_cache, "paths", return_value=paths), \
                mock.patch.object(
                    self.backend, "_profile_picture_metadata", side_effect=metadata), \
                mock.patch.object(self.backend.avatar_cache, "update"):
            result = self.backend.refresh_avatars("remote-read")
        self.assertEqual(result["checked"], 4)
        self.assertEqual([item["jid"] for item in captured],
                         [rows[11]["jid"], rows[12]["jid"], rows[13]["jid"],
                          rows[14]["jid"]])
        self.assertEqual(captured[0]["picture_id"], "")

    def test_failed_avatar_batch_backs_off_so_later_chats_are_not_starved(self) -> None:
        account = self.backend.account("")
        limit = backend_module.AVATAR_REFRESH_LIMIT
        rows = [{"account": account.name, "jid": f"synthetic-{index}@example"}
                for index in range(limit + 3)]
        batches = []

        def fail(selected, candidates):
            batches.append([item["jid"] for item in candidates])
            return [], [item["key"] for item in candidates]

        with mock.patch.object(self.backend, "chats", return_value={"chats": rows}), \
                mock.patch.object(
                    self.backend, "_profile_picture_metadata", side_effect=fail):
            first = self.backend.refresh_avatars("remote-read")
            second = self.backend.refresh_avatars("remote-read")
        self.assertEqual((first["checked"], first["failed"]), (limit, limit))
        self.assertEqual((second["checked"], second["failed"]), (3, 3))
        self.assertEqual(batches[1], [row["jid"] for row in rows[limit:]])

    def test_a_photo_batch_stops_after_its_time_budget_and_leaves_the_rest_due(self) -> None:
        account = self.backend.account("")
        rows = [{"account": account.name, "jid": f"synthetic-{index}@example"}
                for index in range(10)]
        clock = iter([0.0] + [float(step) * 7.0 for step in range(40)])
        looked_up = []

        def lookup(args, **_kwargs):
            looked_up.append(args)
            return subprocess.CompletedProcess(args, 1, "", "no photo")

        with mock.patch.object(self.backend, "chats", return_value={"chats": rows}), \
                mock.patch.object(self.backend, "_yield_active_sync", return_value=False), \
                mock.patch.object(self.backend, "_run_after_sync_yield", side_effect=lookup), \
                mock.patch.object(backend_module.time, "monotonic", side_effect=lambda: next(clock)):
            result = self.backend.refresh_avatars("remote-read")
        self.assertLess(len(looked_up), 10, "the batch stopped at its time budget")
        self.assertEqual(result["checked"], len(looked_up))
        self.assertEqual(result["pending"], 10 - len(looked_up))

    def test_failed_avatar_download_retries_from_the_cached_generation(self) -> None:
        account = self.backend.account("")
        jid = "synthetic@example"
        key = self.backend._avatar_key(account, jid)
        self.backend.avatar_cache.update([{
            "key": key, "picture_id": "generation-a", "checked_at": 0,
            "missing": False, "data": b"\xff\xd8\xffold-avatar",
        }])
        observed_ids = []

        def metadata(selected, candidates):
            observed_ids.append(candidates[0]["picture_id"])
            return ([{
                "key": key, "picture_id": "generation-b",
                "url": "https://cdn.example.test/avatar.jpg",
                "unchanged": False,
            }], [])

        with mock.patch.object(
                self.backend, "chats",
                return_value={"chats": [{"account": account.name, "jid": jid}]},
        ), mock.patch.object(
                self.backend, "_profile_picture_metadata", side_effect=metadata,
        ), mock.patch.object(
                backend_module.time, "time", side_effect=[10_000, 13_601],
        ), mock.patch.object(
                backend_module, "fetch_https_image", side_effect=[
                    backend_module.AvatarCacheError("synthetic download failure"),
                    b"\xff\xd8\xffnew-avatar",
                ],
        ):
            first = self.backend.refresh_avatars("remote-read")
            second = self.backend.refresh_avatars("remote-read")
        self.assertEqual((first["failed"], second["refreshed"]), (1, 1))
        self.assertEqual(observed_ids, ["generation-a", "generation-a"])
        self.assertEqual(
            self.backend.avatar_cache.entries([key])[key]["picture_id"],
            "generation-b",
        )

    def test_notification_dismissal_is_local_and_new_messages_reappear(self) -> None:
        original = next(chat for chat in self.backend.chats()["chats"]
                        if chat["jid"] == "team@g.us")
        self.assertEqual(original["unread"], 3)
        self.assertEqual(original["notification_unread"], 3)

        with mock.patch.object(self.backend, "_write") as write:
            self.backend.acknowledge_notifications("team@g.us")
        write.assert_not_called()
        dismissed = next(chat for chat in self.backend.chats()["chats"]
                         if chat["jid"] == "team@g.us")
        self.assertEqual(dismissed["unread"], 3)
        self.assertEqual(dismissed["notification_unread"], 0)
        preferences = self.root / "state" / "preferences.json"
        self.assertEqual(preferences.stat().st_mode & 0o777, 0o600)

        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute(
                "UPDATE chats SET last_message_ts = 31, unread_count = 4 WHERE jid = ?",
                ["team@g.us"],
            )
            connection.execute(
                """INSERT INTO messages
                (chat_jid, chat_name, msg_id, sender_jid, sender_name, ts,
                 from_me, text, reaction_to_id)
                VALUES (?, 'Design team', 't3', 'member@s.whatsapp.net', 'Sam',
                        31, 0, 'new', '')""",
                ["team@g.us"],
            )
        updated = next(chat for chat in self.backend.chats()["chats"]
                       if chat["jid"] == "team@g.us")
        self.assertEqual(updated["notification_unread"], 1)

    def test_muted_and_archived_chats_stay_unread_without_alerting(self) -> None:
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute(
                "UPDATE chats SET muted_until = -1 WHERE jid = ?",
                ["team@g.us"],
            )
            connection.execute(
                "UPDATE chats SET archived = 1, unread_count = 2 WHERE jid = ?",
                ["archive@g.us"],
            )

        chats = {chat["jid"]: chat for chat in self.backend.chats()["chats"]}
        self.assertTrue(chats["team@g.us"]["muted"])
        self.assertEqual(chats["team@g.us"]["unread"], 3)
        self.assertEqual(chats["team@g.us"]["notification_unread"], 0)
        self.assertTrue(chats["archive@g.us"]["archived"])
        self.assertEqual(chats["archive@g.us"]["unread"], 2)
        self.assertEqual(chats["archive@g.us"]["notification_unread"], 0)

    def _enable_notifications(self, preview: bool = True) -> None:
        with mock.patch.object(self.backend, "_notify_send_ready", return_value=True):
            self.backend.set_notifications(True, preview)

    def _arrive(self, jid: str, msg_id: str, timestamp: int, unread: int,
                text: str = "new", sender: str = "Sam") -> None:
        # wacli stores one row for every unread it adds, so a jump from 3 to 5
        # unread lands two messages; the last one carries the given id.
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            previous = connection.execute(
                "SELECT unread_count FROM chats WHERE jid = ?", [jid]).fetchone()[0] or 0
            connection.execute(
                "UPDATE chats SET last_message_ts = ?, unread_count = ? WHERE jid = ?",
                [timestamp, unread, jid],
            )
            arrivals = max(1, unread - int(previous))
            for index in range(arrivals):
                last = index == arrivals - 1
                connection.execute(
                    """INSERT INTO messages
                    (chat_jid, chat_name, msg_id, sender_jid, sender_name, ts, from_me,
                     text, reaction_to_id, media_type, mime_type, local_path)
                    VALUES (?, '', ?, 'member@s.whatsapp.net', ?, ?, 0, ?, '', '', '', '')""",
                    [jid, msg_id if last else f"{msg_id}-earlier-{index}", sender,
                     timestamp,
                     text if last else "earlier"],
                )

    def _notify(self, skip_jid: str = "") -> tuple[dict, list]:
        with mock.patch.object(self.backend, "_notify_send_ready", return_value=True), \
                mock.patch.object(self.backend, "_deliver_notification",
                                  return_value=True) as deliver:
            result = self.backend.notify(skip_jid)
        self.last_targets = [call.args[2] if len(call.args) > 2 else None
                             for call in deliver.call_args_list]
        return result, [call.args[:2] for call in deliver.call_args_list]

    def test_desktop_notifications_are_on_by_default_but_need_notify_send(self) -> None:
        # The owner found notifications "not working": they were off by default.
        self.assertEqual(self.backend._preferences()["notifications"],
                         {"enabled": True, "preview": True, "sound": True})
        with mock.patch.object(self.backend, "_notify_send_ready", return_value=False):
            with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "notify-send"):
                self.backend.set_notifications(True, None)
            result = self.backend.notify()
        self.assertTrue(result["enabled"])
        self.assertFalse(result["available"])
        self.assertEqual(result["sent"], 0)
        self.backend.set_notifications(False, None)
        result, sent = self._notify()
        self.assertFalse(result["enabled"])
        self.assertEqual(sent, [])

    def test_version_3_preserves_notifications_and_disables_photo_refresh(self) -> None:
        state = self.root / "state"
        state.mkdir(mode=0o700)
        target = state / "preferences.json"
        target.write_text(json.dumps({
            "version": 3, "auto_refresh_avatars": True,
            "notifications": {"enabled": False, "preview": False},
            "stores": {str(self.store): {"notified": {"team@g.us": {"unread": 1, "timestamp": 1}}}},
        }), encoding="utf-8")
        target.chmod(0o600)
        preferences = self.backend._preferences()
        self.assertEqual(preferences["notifications"],
                         {"enabled": False, "preview": False, "sound": True},
                         "the existing notification choice is preserved")
        self.assertFalse(preferences["auto_refresh_avatars"])
        self.assertEqual(preferences["stores"][str(self.store)]["notified"], {},
                         "a fresh watermark adopts the archive instead of replaying it")
        self.backend._update_preferences(
            lambda value: value["notifications"].update({"enabled": True}))
        result, sent = self._notify()
        self.assertTrue(result["seeded"])
        self.assertEqual(sent, [])
        self.assertEqual(json.loads(target.read_text(encoding="utf-8"))["version"], 4)
        self.backend.settings({"auto_refresh_avatars": True})
        self.assertTrue(self.backend._preferences()["auto_refresh_avatars"],
                        "after the migration an explicit choice sticks")

    def test_enabling_notifications_adopts_the_archive_instead_of_replaying_it(self) -> None:
        self.backend._update_preferences(
            lambda value: value["notifications"].update({"enabled": True}))
        result, sent = self._notify()
        self.assertTrue(result["seeded"])
        self.assertEqual(sent, [])

        self._enable_notifications()
        stored = json.loads((self.root / "state" / "preferences.json").read_text(encoding="utf-8"))
        self.assertEqual(stored["notifications"], {"enabled": True, "preview": True, "sound": True})
        self.assertIn("team@g.us", stored["stores"][str(self.store)]["notified"])

        self._arrive("team@g.us", "t3", 31, 4)
        result, sent = self._notify()
        self.assertEqual(result["sent"], 1)

    def test_media_notifications_read_like_the_phone(self) -> None:
        preview = backend_module.Backend._notification_preview
        self.assertEqual(preview({"preview": "hello", "last_media_type": ""}), "hello")
        self.assertEqual(preview({"preview": "[image]", "last_media_type": "image"}), "📷 Photo")
        self.assertEqual(preview({"preview": "look at this", "last_media_type": "image"}),
                         "📷 look at this")
        self.assertEqual(preview({"preview": "report.pdf", "last_media_type": "document"}),
                         "📄 report.pdf")
        self.assertEqual(preview({"preview": "[audio]", "last_media_type": "audio"}), "🎵 Audio")
        self.assertEqual(preview({"preview": "", "last_media_type": "sticker"}), "Sticker")
        self.assertEqual(preview({"preview": "[weird]", "last_media_type": "weird"}),
                         "📎 Attachment")

    def test_popup_carries_the_cached_chat_photo_and_the_app_icon(self) -> None:
        self._enable_notifications()
        self._arrive("team@g.us", "t3", 31, 4)

        def attach(chats, accounts):
            for chat in chats:
                chat["avatar_path"] = str(self.preview)

        with mock.patch.object(self.backend, "_attach_cached_avatars", side_effect=attach), \
             mock.patch.object(self.backend, "_play_message_sound", return_value=False):
            with mock.patch.object(self.backend, "_notify_send_ready", return_value=True), \
                 mock.patch.object(self.backend, "_deliver_notification",
                                   return_value=True) as deliver:
                self.backend.notify()
        self.assertEqual(deliver.call_args.args[3], str(self.preview))
        with mock.patch.object(backend_module.subprocess, "Popen") as popen:
            self.backend._deliver_notification(
                "Design team", "Sam: new", {"account": "", "jid": "team@g.us"}, str(self.preview))
        request = json.loads(popen.return_value.stdin.write.call_args.args[0].decode("utf-8"))
        self.assertIn("--icon=whatsapp", request["command"])
        self.assertIn(f"--hint=string:image-path:{self.preview}", request["command"])

    def test_one_sound_per_pass_and_none_when_turned_off(self) -> None:
        self._enable_notifications()
        self._arrive("team@g.us", "t3", 31, 4)
        self._arrive("alex@s.whatsapp.net", "a2", 41, 2)
        with mock.patch.object(self.backend, "_play_message_sound", return_value=True) as play:
            result, sent = self._notify()
        self.assertEqual(len(sent), 2)
        self.assertEqual(play.call_count, 1)
        self.assertTrue(result["sound"])
        with mock.patch.object(self.backend, "_notify_send_ready", return_value=True):
            self.backend.set_notifications(None, None, False)
        self._arrive("team@g.us", "t4", 50, 5)
        with mock.patch.object(self.backend, "_play_message_sound", return_value=True) as play:
            result, sent = self._notify()
        self.assertEqual(len(sent), 1)
        play.assert_not_called()
        self.assertFalse(result["sound"])
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "sound"):
            self.backend.set_notifications(None, None, "loud")

    def test_the_sound_respects_omarchy_do_not_disturb(self) -> None:
        dnd = self.root / "omarchy-notifications.json"
        dnd.write_text(json.dumps({"dnd": True}), encoding="utf-8")
        sound = self.root / "sound.oga"
        sound.write_bytes(b"ogg")
        with mock.patch.object(backend_module, "OMARCHY_NOTIFICATION_STATE", dnd), \
             mock.patch.object(backend_module, "NOTIFY_SOUND", sound), \
             mock.patch.object(backend_module, "SOUND_PLAYER", self.wacli), \
             mock.patch.object(backend_module.subprocess, "Popen") as popen:
            self.assertFalse(self.backend._play_message_sound())
            popen.assert_not_called()
            dnd.write_text(json.dumps({"dnd": False}), encoding="utf-8")
            self.assertTrue(self.backend._play_message_sound())
            self.assertEqual(popen.call_args.args[0], [str(self.wacli), str(sound)])

    def test_an_edit_or_reaction_that_moves_the_chat_does_not_pop_up(self) -> None:
        self._enable_notifications()
        self._arrive("team@g.us", "t3", 31, 4, text="first")
        result, sent = self._notify()
        self.assertEqual(result["sent"], 1)
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            # wacli rewrites the edited row and moves the chat time forward.
            connection.execute("UPDATE messages SET text = 'first, edited' WHERE msg_id = 't3'")
            connection.execute("UPDATE chats SET last_message_ts = 45 WHERE jid = 'team@g.us'")
        result, sent = self._notify()
        self.assertEqual(sent, [], "the same last message is not news")
        self._arrive("team@g.us", "t4", 50, 5, text="second")
        result, sent = self._notify()
        self.assertEqual(result["sent"], 1)

    def test_group_popup_names_the_sender_and_counts_arrivals(self) -> None:
        self._enable_notifications()
        self._arrive("team@g.us", "t3", 31, 5, text="ship it now", sender="Sam")
        result, sent = self._notify()
        self.assertEqual(result["sent"], 1)
        self.assertEqual(sent[0], ("Design team · 2 new", "Sam: ship it now"))

    def test_preview_off_reports_counts_without_message_text(self) -> None:
        self._enable_notifications(preview=False)
        self._arrive("team@g.us", "t3", 31, 5, text="secret")
        result, sent = self._notify()
        self.assertEqual(sent[0], ("Design team · 2 new", "2 new messages"))

    def test_a_chat_read_elsewhere_still_notifies_with_zero_unread(self) -> None:
        self._enable_notifications()
        self._arrive("alex@s.whatsapp.net", "a2", 41, 0, text="on my way")
        rail = {chat["jid"]: chat for chat in self.backend.chats()["chats"]}
        self.assertEqual(rail["alex@s.whatsapp.net"]["unread"], 0)
        self.assertEqual(rail["alex@s.whatsapp.net"]["notification_unread"], 0)
        result, sent = self._notify()
        self.assertEqual(result["sent"], 1)
        self.assertEqual(sent[0], ("Alex", "on my way"))

    def test_bar_badge_settings_and_dismissal_never_silence_popups(self) -> None:
        self._enable_notifications()
        self.backend.settings({"show_unread_count": False})
        self._arrive("team@g.us", "t3", 31, 4)
        with mock.patch.object(self.backend, "_write") as write:
            self.backend.acknowledge_notifications("team@g.us")
        write.assert_not_called()
        rail = {chat["jid"]: chat for chat in self.backend.chats()["chats"]}
        self.assertEqual(rail["team@g.us"]["notification_unread"], 0)
        result, sent = self._notify()
        self.assertEqual(result["sent"], 1)
        self.assertEqual(sent[0][0], "Design team")

    def test_only_the_visible_chat_is_skipped_while_a_surface_is_open(self) -> None:
        self._enable_notifications()
        self._arrive("team@g.us", "t3", 31, 4)
        self._arrive("alex@s.whatsapp.net", "a2", 42, 2)
        result, sent = self._notify("team@g.us")
        self.assertEqual(result["sent"], 1)
        self.assertEqual(sent[0][0], "Alex")

        # A skipped chat still adopts the watermark, so only later arrivals
        # count. With every surface closed nothing is skipped.
        self._arrive("team@g.us", "t4", 33, 6)
        result, sent = self._notify()
        self.assertEqual(result["sent"], 1)
        self.assertEqual(sent[0][0], "Design team · 2 new")

    def test_muted_and_archived_chats_never_pop_up(self) -> None:
        self._enable_notifications()
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute("UPDATE chats SET muted_until = -1 WHERE jid = ?",
                               ["team@g.us"])
            connection.execute("UPDATE chats SET archived = 1 WHERE jid = ?",
                               ["archive@g.us"])
        self._arrive("team@g.us", "t3", 31, 4)
        self._arrive("archive@g.us", "r1", 32, 2)
        result, sent = self._notify()
        self.assertEqual(result["pending"], 0)
        self.assertEqual(sent, [])

    def test_each_popup_carries_the_chat_it_opens(self) -> None:
        self._enable_notifications()
        self._arrive("team@g.us", "t3", 31, 5, text="ship it now", sender="Sam")
        self._notify()
        self.assertEqual(self.last_targets[0]["jid"], "team@g.us")

    def test_a_clickable_popup_is_handed_to_a_detached_notify_open_child(self) -> None:
        with mock.patch.object(backend_module.subprocess, "Popen") as popen:
            popen.return_value.stdin = mock.MagicMock()
            self.assertTrue(self.backend._deliver_notification(
                "Design team", "hi", {"account": "", "jid": "team@g.us"}))
        argv = popen.call_args.args[0]
        self.assertEqual(argv[-1], "notify-open")
        self.assertTrue(popen.call_args.kwargs["start_new_session"])
        request = json.loads(popen.return_value.stdin.write.call_args.args[0].decode("utf-8"))
        self.assertIn("--action=default=Open chat", request["command"])
        self.assertEqual(request["command"][-2:], ["Design team", "hi"])
        self.assertEqual(request["target"]["jid"], "team@g.us")

    @staticmethod
    def _fake_notify_send(output: bytes):
        read, write = os.pipe()
        os.write(write, output)
        os.close(write)
        process = mock.MagicMock()
        process.stdout = os.fdopen(read, "rb")
        process.poll.return_value = 0
        return process

    def test_clicking_the_popup_opens_that_chat_and_dismissing_does_nothing(self) -> None:
        command = [str(backend_module.NOTIFY_SEND), "--print-id",
                   "--action=default=Open chat", "--", "X"]
        calls = []

        def run(argv, **_kwargs):
            calls.append(list(argv))
            return subprocess.CompletedProcess(argv, 0, "", "")

        shell = self.root / "omarchy-shell"
        shell.write_text("#!/bin/sh\n", encoding="utf-8")
        with mock.patch.object(backend_module.subprocess, "Popen",
                               return_value=self._fake_notify_send(b"42\ndefault\n")) as popen, \
                mock.patch.object(backend_module, "run_bounded", side_effect=run), \
                mock.patch.object(backend_module, "OMARCHY_SHELL", shell):
            opened = self.backend.notify_open(
                {"command": command, "target": {"account": "work", "jid": "team@g.us"}})
        self.assertEqual(popen.call_args.args[0], command)
        self.assertTrue(opened["opened"])
        # The owner's report: a click opened the full app with no quick reply.
        self.assertEqual(calls[0][:3], [str(shell), backend_module.PLUGIN_ID, "openDropdown"],
                         "a click opens the reply view by the bar")
        self.assertEqual(json.loads(calls[0][3]), {"account": "work", "jid": "team@g.us"})
        self.assertEqual(self.backend._notify_ids(), {"work\nteam@g.us": 42},
                         "the popup id is kept for the next message in that chat")
        self.backend.settings({"notify_reply": False})
        with mock.patch.object(backend_module.subprocess, "Popen",
                               return_value=self._fake_notify_send(b"44\ndefault\n")), \
                mock.patch.object(backend_module, "run_bounded", side_effect=run), \
                mock.patch.object(backend_module, "OMARCHY_SHELL", shell):
            self.backend.notify_open({"command": command, "target": {"account": "work", "jid": "team@g.us"}})
        self.assertEqual(calls[1][2], "openApp", "the setting can keep the full app")
        self.backend.settings({"notify_reply": True})

        with mock.patch.object(backend_module.subprocess, "Popen",
                               return_value=self._fake_notify_send(b"43\n")), \
                mock.patch.object(backend_module, "run_bounded") as run2:
            self.assertFalse(self.backend.notify_open(
                {"command": command, "target": {"jid": "team@g.us"}})["opened"])
        run2.assert_not_called()
        with self.assertRaises(backend_module.OmaWhatsAppError):
            self.backend.notify_open({"command": ["/bin/sh", "-c", "id"]})

    def test_the_next_message_in_a_chat_replaces_its_popup(self) -> None:
        with mock.patch.object(backend_module.subprocess, "Popen") as popen:
            popen.return_value.stdin = mock.MagicMock()
            self.backend._deliver_notification("Design team", "hi", {"account": "", "jid": "team@g.us"})
        first = json.loads(popen.return_value.stdin.write.call_args.args[0].decode("utf-8"))
        self.assertIn("--print-id", first["command"])
        self.assertFalse(any(part.startswith("--replace-id") for part in first["command"]))
        self.backend._remember_notify_id("\nteam@g.us", 42)
        with mock.patch.object(backend_module.subprocess, "Popen") as popen:
            popen.return_value.stdin = mock.MagicMock()
            self.backend._deliver_notification("Design team", "again", {"account": "", "jid": "team@g.us"})
        second = json.loads(popen.return_value.stdin.write.call_args.args[0].decode("utf-8"))
        self.assertIn("--replace-id=42", second["command"])
        later = time.time() + backend_module.NOTIFY_ID_TTL + 5
        with mock.patch.object(backend_module.time, "time", return_value=later):
            self.assertEqual(self.backend._notify_ids(), {}, "an old popup id is forgotten")

    def test_a_replacing_popup_counts_everything_still_unseen(self) -> None:
        self._enable_notifications()
        self._arrive("team@g.us", "t3", 31, 4)
        result, sent = self._notify()
        self.assertEqual(sent[0][0], "Design team")
        self.assertEqual(self.last_targets[0]["account"], backend_module.LEGACY_ACCOUNT_NAME)
        self.backend._remember_notify_id(f"{backend_module.LEGACY_ACCOUNT_NAME}\nteam@g.us", 42)
        self._arrive("team@g.us", "t4", 32, 5)
        result, sent = self._notify()
        self.assertEqual(sent[0][0], "Design team · 5 new",
                         "the replaced popup said 1; this one covers all five")

    def test_popup_text_stays_one_markup_inert_line(self) -> None:
        self._enable_notifications()
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute("UPDATE chats SET name = ? WHERE jid = ?",
                               ["<b>Design</b> team", "team@g.us"])
        self._arrive("team@g.us", "t3", 31, 4, text="line one\nline <i>two</i>",
                     sender="S&M")
        result, sent = self._notify()
        summary, body = sent[0]
        self.assertEqual(summary, "&lt;b&gt;Design&lt;/b&gt; team")
        self.assertEqual(body, "S&amp;M: line one line &lt;i&gt;two&lt;/i&gt;")

    def test_notification_burst_is_bounded_by_one_summary(self) -> None:
        self._enable_notifications()
        arrivals = backend_module.MAX_NOTIFY_BURST + 2
        for index in range(arrivals):
            jid = f"burst{index}@s.whatsapp.net"
            with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
                connection.execute(
                    "INSERT INTO chats VALUES (?, 'dm', ?, 0, 0, 0, 0, 0, 0)",
                    [jid, f"Burst {index}"],
                )
            self._arrive(jid, f"b{index}", 60 + index, 1, text="hi")
        result, sent = self._notify()
        self.assertEqual(result["pending"], arrivals)
        self.assertEqual(len(sent), backend_module.MAX_NOTIFY_BURST + 1)
        self.assertEqual(sent[-1][0], "OmaWhatsApp")
        self.assertEqual(sent[-1][1], "2 more chats have new messages")

    def test_mute_deadlines_support_seconds_milliseconds_and_forever(self) -> None:
        now = 2_000_000_000.0
        self.assertTrue(backend_module.muted_until_active(-1, now))
        self.assertTrue(backend_module.muted_until_active(2_000_000_001, now))
        self.assertTrue(backend_module.muted_until_active(2_000_000_001_000, now))
        self.assertFalse(backend_module.muted_until_active(1_999_999_999, now))
        self.assertFalse(backend_module.muted_until_active(1_999_999_999_000, now))
        self.assertFalse(backend_module.muted_until_active(0, now))

    def test_chat_surface_is_people_and_groups_including_community_groups(self) -> None:
        visible = {chat["jid"] for chat in self.backend.chats()["chats"]}
        self.assertEqual(visible, {"team@g.us", "alex@s.whatsapp.net", "archive@g.us",
                                   "subgroup@g.us"},
                         "a group inside a Community is an ordinary chat, as on the phone")
        self.assertEqual(self.backend._chat("subgroup@g.us")["kind"], "group")
        for hidden in ("news@newsletter", "legacy@newsletter", "community@g.us"):
            with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "not available"):
                self.backend._chat(hidden)

    def test_chat_previews_are_always_one_line(self) -> None:
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute(
                "UPDATE messages SET text = ? WHERE chat_jid = ? AND msg_id = ?",
                ["first line\nsecond\tline", "alex@s.whatsapp.net", "a1"],
            )
        chat = next(item for item in self.backend.chats()["chats"]
                    if item["jid"] == "alex@s.whatsapp.net")
        self.assertEqual(chat["preview"], "first line second line")

    def test_older_pages_follow_the_oldest_loaded_message(self) -> None:
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            for index in range(7):
                connection.execute(
                    """INSERT INTO messages (chat_jid, chat_name, msg_id, sender_jid, sender_name,
                       ts, from_me, text, reaction_to_id, media_type, mime_type, local_path)
                       VALUES ('alex@s.whatsapp.net', '', ?, '', '', ?, 0, ?, '', '', '', '')""",
                    [f"old{index}", 30 if index < 3 else 20 + index, f"old {index}"])
        first = self.backend.messages("alex@s.whatsapp.net", "", 3)
        self.assertTrue(first["has_more"])
        seen = [m["id"] for m in first["messages"]]
        cursor = first["messages"][-1]
        while True:
            page = self.backend.messages("alex@s.whatsapp.net", "", 3,
                                         {"ts": cursor["timestamp"], "id": cursor["id"]})
            ids = [m["id"] for m in page["messages"]]
            self.assertFalse(set(ids) & set(seen), "pages never repeat a message")
            seen.extend(ids)
            if not page["has_more"]:
                break
            cursor = page["messages"][-1]
        self.assertEqual(len(seen), 8, "every message once, including three sharing a second")
        self.assertEqual(seen[0], "a1")

    PHONE_CHAT = "15550004444@s.whatsapp.net"

    def _file_under_lid(self) -> str:
        # Found on the owner's mirror: a delegated file send is filed under
        # the @lid WhatsApp answered the recipient warmup with.
        lid = "123456789012345@lid"
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute("INSERT INTO chats VALUES (?, 'dm', 'Robin', 45, 0, 0, 0, 0, 0)",
                               [self.PHONE_CHAT])
            connection.execute(
                """INSERT INTO messages (chat_jid, chat_name, msg_id, sender_jid, sender_name,
                   ts, from_me, text, reaction_to_id, media_type, mime_type, local_path)
                   VALUES (?, 'Robin', 'r1', '', 'Robin', 45, 0, 'hi', '', '', '', '')""",
                [self.PHONE_CHAT])
            connection.execute("INSERT INTO chats VALUES (?, 'unknown', '', 90, 0, 0, 0, 0, 0)", [lid])
            connection.execute(
                """INSERT INTO messages (chat_jid, chat_name, msg_id, sender_jid, sender_name,
                   ts, from_me, text, reaction_to_id, media_type, mime_type, filename, local_path)
                   VALUES (?, '', 'SENT-FILE', '', 'me', 90, 1, '', '', 'document',
                           'application/pdf', 'report.pdf', '')""", [lid])
        return lid

    def _resolve_lid(self, lid: str, phone: str):
        def run(args, **_kwargs):
            if args[:4] == ["--read-only", "--json", "contacts", "show"] and args[-1] == lid:
                return subprocess.CompletedProcess(args, 0, json.dumps(
                    {"success": True, "data": {"jid": phone}}), "")
            raise AssertionError(args)
        return mock.patch.object(self.backend, "_run", side_effect=run)

    def test_a_file_filed_under_the_contacts_lid_shows_in_their_chat(self) -> None:
        lid = self._file_under_lid()
        with self._resolve_lid(lid, self.PHONE_CHAT) as run:
            messages = self.backend.messages(self.PHONE_CHAT)["messages"]
            chats = self.backend.chats()["chats"]
        self.assertEqual([m["id"] for m in messages], ["SENT-FILE", "r1"],
                         "the sent file is the newest message of the contact's chat")
        robin = next(chat for chat in chats if chat["jid"] == self.PHONE_CHAT)
        self.assertEqual(robin["timestamp"], 90)
        self.assertEqual(robin["last_message_id"], "SENT-FILE")
        self.assertEqual(robin["preview"], "report.pdf")
        self.assertEqual(chats[1]["jid"], self.PHONE_CHAT,
                         "the chat moves up with its newest message (after the pinned one)")
        self.assertNotIn(lid, [chat["jid"] for chat in chats])
        self.assertEqual(run.call_count, 1, "each @lid is resolved once and then cached")
        with mock.patch.object(self.backend, "_run") as again:
            self.backend.messages(self.PHONE_CHAT)
        again.assert_not_called()

    def test_actions_on_a_lid_filed_message_use_its_real_chat(self) -> None:
        lid = self._file_under_lid()
        with self._resolve_lid(lid, self.PHONE_CHAT):
            chat, message = self.backend._message(self.PHONE_CHAT, "SENT-FILE")
        self.assertEqual(message["chat_jid"], lid)
        sent = subprocess.CompletedProcess([], 0, json.dumps({"success": True}), "")
        with mock.patch.object(self.backend, "_write", return_value=sent) as write:
            self.backend.delete_message(self.PHONE_CHAT, "SENT-FILE", True)
        command = write.call_args.args[0]
        self.assertEqual(command[command.index("--chat") + 1], lid,
                         "wacli finds the stored message only under the chat it was filed in")

    def test_an_unresolved_lid_stays_out_and_is_not_asked_again(self) -> None:
        self._file_under_lid()
        def run(args, **_kwargs):
            return subprocess.CompletedProcess(args, 0, json.dumps({"success": True, "data": {}}), "")
        with mock.patch.object(self.backend, "_run", side_effect=run) as first:
            ids = [m["id"] for m in self.backend.messages(self.PHONE_CHAT)["messages"]]
            self.backend.messages(self.PHONE_CHAT)
        self.assertNotIn("SENT-FILE", ids, "a row is never shown in a chat it cannot be tied to")
        self.assertEqual(first.call_count, 1)

    def _insert_sticker(self, msg_id: str, ts: int, sha: bytes, path: str = "") -> None:
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute(
                """INSERT INTO messages (chat_jid, chat_name, msg_id, sender_jid, sender_name,
                   ts, from_me, text, reaction_to_id, media_type, mime_type, local_path, file_sha256)
                   VALUES ('team@g.us', '', ?, '', '', ?, 0, '', '', 'sticker', 'image/webp', ?, ?)""",
                [msg_id, ts, path, sha])

    def test_the_sticker_picker_lists_each_sticker_once_newest_first(self) -> None:
        webp = self.root / "synthetic.webp"
        webp.write_bytes(b"RIFF....WEBP")
        self._insert_sticker("s1", 50, b"same", str(webp))
        self._insert_sticker("s2", 60, b"same", str(webp))
        self._insert_sticker("s3", 40, b"other", "")
        stickers = self.backend.stickers()["stickers"]
        self.assertEqual([s["id"] for s in stickers], ["s2", "s3"], "the same file appears once")
        self.assertEqual(stickers[0]["path"], str(webp))
        self.assertEqual(stickers[1]["path"], "", "not on this computer yet")

    def test_expired_stickers_are_fetched_once_and_then_skipped(self) -> None:
        self._insert_sticker("s1", 50, b"gone", "")
        calls = []

        def fetch(*args):
            calls.append(args)
            raise backend_module.OmaWhatsAppError("download failed with status code 403")

        with mock.patch.object(self.backend, "_fetch_media_file", side_effect=fetch):
            first = self.backend.fetch_stickers()
            second = self.backend.fetch_stickers()
        self.assertEqual((first["fetched"], first["failed"]), (0, 1))
        self.assertEqual(second["failed"], 0, "an expired sticker is not asked for again")
        self.assertEqual(len(calls), 1)
        self.assertTrue(second["stickers"][0]["unavailable"])

    def test_fetching_stickers_respects_offline_mode(self) -> None:
        with mock.patch.object(self.backend, "online", return_value=False), \
             self.assertRaisesRegex(backend_module.OmaWhatsAppError, "Offline mode"):
            self.backend.fetch_stickers()

    def test_the_media_browser_reads_media_links_and_docs_over_the_whole_history(self) -> None:
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.executemany(
                """INSERT INTO messages (chat_jid, chat_name, msg_id, sender_jid, sender_name,
                   ts, from_me, text, reaction_to_id, media_type, mime_type, filename, local_path)
                   VALUES ('team@g.us', '', ?, '', 'Sam', ?, 0, ?, '', ?, ?, ?, '')""",
                [("d1", 5, "", "document", "application/pdf", "plan.pdf"),
                 ("l1", 6, "see https://example.test/page", "", "", ""),
                 ("v1", 7, "", "video", "video/mp4", "")])
        ids = lambda kind: [m["id"] for m in self.backend.messages("team@g.us", "", 50, None, kind)["messages"]]
        self.assertEqual(ids("media"), ["t2", "v1"], "newest first")
        self.assertEqual(ids("docs"), ["d1"])
        self.assertEqual(ids("links"), ["l1"])
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "media, links or docs"):
            self.backend.messages("team@g.us", "", 50, None, "stickers")

    def test_messages_never_cross_chat_boundary(self) -> None:
        values = self.backend.messages("team@g.us")["messages"]
        self.assertEqual([value["id"] for value in values], ["t1", "t0b", "t0a", "t2"])
        self.assertNotIn("a1", [value["id"] for value in values])

    def test_sent_messages_carry_the_delivery_state_wacli_recorded(self) -> None:
        # The owner asked for sent, delivered and read ticks. Only wacli builds
        # that keep receipts have message_status; without it nothing is claimed.
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.executemany(
                """INSERT INTO messages (chat_jid, chat_name, msg_id, sender_jid, sender_name,
                  ts, from_me, text, display_text, reaction_to_id, media_type)
                VALUES ('team@g.us', 'Design team', ?, '', 'me', ?, ?, ?, ?, '', '')""",
                [("mine-read", 70, 1, "read one", "read one"),
                 ("mine-unknown", 71, 1, "older one", "older one"),
                 ("mine-odd", 72, 1, "odd code", "odd code"),
                 ("theirs", 73, 0, "incoming", "incoming")],
            )
        values = {value["id"]: value for value in self.backend.messages("team@g.us")["messages"]}
        self.assertFalse(any("status" in value for value in values.values()),
                         "official wacli keeps no receipts: no ticks")
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute("""CREATE TABLE message_status (
              chat_jid TEXT NOT NULL, msg_id TEXT NOT NULL, status INTEGER NOT NULL,
              updated_at INTEGER NOT NULL, PRIMARY KEY (chat_jid, msg_id))""")
            connection.executemany(
                "INSERT INTO message_status VALUES ('team@g.us', ?, ?, 1)",
                [("mine-read", 4), ("mine-odd", 99), ("theirs", 4)],
            )
        values = {value["id"]: value for value in self.backend.messages("team@g.us")["messages"]}
        self.assertEqual(values["mine-read"]["status"], "read")
        self.assertNotIn("status", values["mine-unknown"], "no record, no tick")
        self.assertNotIn("status", values["mine-odd"], "an unknown code is not shown")
        self.assertNotIn("status", values["theirs"], "ticks belong to sent messages")
        chat = next(item for item in self.backend.chats()["chats"] if item["jid"] == "team@g.us")
        self.assertEqual(chat["last_status"], "", "the last message is theirs")
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute(
                """INSERT INTO messages (chat_jid, chat_name, msg_id, sender_jid, sender_name,
                  ts, from_me, text, display_text, reaction_to_id, media_type)
                VALUES ('team@g.us', 'Design team', 'mine-last', '', 'me', 80, 1,
                  'latest', 'latest', '', '')""")
            connection.execute("INSERT INTO message_status VALUES ('team@g.us', 'mine-last', 3, 1)")
        chat = next(item for item in self.backend.chats()["chats"] if item["jid"] == "team@g.us")
        self.assertEqual(chat["last_status"], "delivered", "the rail shows the last tick")

    def test_synthetic_placeholder_rows_are_neither_bubbles_nor_previews(self) -> None:
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.executemany(
                """INSERT INTO messages
                (chat_jid, chat_name, msg_id, sender_jid, sender_name, ts,
                 from_me, text, display_text, reaction_to_id, media_type)
                VALUES ('team@g.us', 'Design team', ?, 'member@s.whatsapp.net',
                  'Sam', ?, 0, ?, ?, '', ?)""",
                [
                    ("protocol", 50, "", "(message)", ""),
                    ("album-head", 51, "[Album: 3 images]", "[Album: 3 images]", ""),
                    ("album-bare", 52, "[Album]", "[Album]", ""),
                    ("typed", 53, "[Album: my trip]", "[Album: my trip]", ""),
                ],
            )
        ids = [value["id"] for value in self.backend.messages("team@g.us")["messages"]]
        self.assertNotIn("protocol", ids)
        self.assertNotIn("album-head", ids)
        self.assertNotIn("album-bare", ids)
        self.assertIn("typed", ids, "only wacli's exact header shape is synthetic")
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute(
                "DELETE FROM messages WHERE msg_id = 'typed'")
        team = next(chat for chat in self.backend.chats()["chats"]
                    if chat["jid"] == "team@g.us")
        self.assertEqual(team["preview"], "ship it",
                         "the preview skips placeholders to the latest real message")

    def test_audio_without_caption_has_no_synthetic_text(self) -> None:
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.executemany(
                """INSERT INTO messages
                (chat_jid, chat_name, msg_id, sender_jid, sender_name, ts,
                 from_me, text, media_caption, reaction_to_id, media_type, mime_type)
                VALUES ('team@g.us', 'Design team', ?, 'member@s.whatsapp.net',
                  'Sam', ?, 0, ?, ?, '', 'audio', 'audio/ogg')""",
                [
                    ("voice", 60, "[Audio]", ""),
                    ("voice-caption", 61, "listen to this", "listen to this"),
                ],
            )
        by_id = {value["id"]: value for value in self.backend.messages("team@g.us")["messages"]}
        self.assertEqual(by_id["voice"]["text"], "")
        self.assertEqual(by_id["voice-caption"]["text"], "listen to this")
        team = next(chat for chat in self.backend.chats()["chats"]
                    if chat["jid"] == "team@g.us")
        self.assertEqual(team["preview"], "listen to this")

    def test_message_search_and_media_metadata(self) -> None:
        values = self.backend.messages("team@g.us", "mock")["messages"]
        self.assertEqual(len(values), 1)
        self.assertEqual(values[0]["mime_type"], "image/png")
        self.assertEqual(values[0]["local_path"], str(self.preview))

    def test_reply_reaction_star_and_location_metadata(self) -> None:
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute(
                "UPDATE messages SET quoted_msg_id = ? WHERE chat_jid = ? AND msg_id = ?",
                ["t1", "team@g.us", "t2"],
            )
            connection.execute(
                """INSERT INTO messages
                (chat_jid, chat_name, msg_id, sender_jid, sender_name, ts,
                 from_me, text, reaction_to_id, reaction_emoji)
                VALUES (?, ?, ?, ?, ?, ?, ?, '', ?, ?)""",
                ["team@g.us", "Design team", "r1", "member@s.whatsapp.net",
                 "Sam", 31, 0, "t2", "🔥"],
            )
            connection.execute(
                "INSERT INTO starred VALUES (?, ?, ?, ?, ?)",
                ["team@g.us", "t2", "me@s.whatsapp.net", 1, 32],
            )
            connection.execute(
                "INSERT INTO message_locations VALUES (?, ?, ?, ?, ?, ?, ?)",
                ["team@g.us", "t2", 40.7, -74.0, "Studio", "New York", 0],
            )
        item = next(value for value in self.backend.messages("team@g.us")["messages"]
                    if value["id"] == "t2")
        self.assertEqual(item["quoted_id"], "t1")
        self.assertEqual(item["quoted_text"], "ship it")
        self.assertEqual(item["reactions"][0]["emoji"], "🔥")
        self.assertTrue(item["starred"])
        self.assertEqual(item["location_name"], "Studio")

    def test_reaction_stored_under_the_contacts_lid_chat_still_shows(self) -> None:
        # wacli 0.18.3 can store an outgoing reaction under the contact's
        # opaque @lid chat while the reacted message lives in the phone chat.
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.executemany(
                """INSERT INTO messages
                (chat_jid, chat_name, msg_id, sender_jid, sender_name, ts,
                 from_me, text, reaction_to_id, reaction_emoji)
                VALUES (?, '', ?, ?, '', ?, ?, '', ?, ?)""",
                [
                    ("123456789012345@lid", "r-lid", "me@s.whatsapp.net", 45, 1, "a1", "👍"),
                    ("other@s.whatsapp.net", "r-foreign", "other@s.whatsapp.net", 46, 0, "a1", "😡"),
                ],
            )
        item = next(value for value in self.backend.messages("alex@s.whatsapp.net")["messages"]
                    if value["id"] == "a1")
        self.assertEqual([reaction["emoji"] for reaction in item["reactions"]], ["👍"],
                         "an @lid reaction joins its target; another contact's chat never does")

    def test_reaction_changes_keep_only_each_users_latest_emoji(self) -> None:
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.executemany(
                """INSERT INTO messages
                (chat_jid, chat_name, msg_id, sender_jid, sender_name, ts,
                 from_me, text, reaction_to_id, reaction_emoji)
                VALUES (?, 'Design team', ?, ?, ?, ?, 0, '', 't2', ?)""",
                [
                    ("team@g.us", "r-old", "member@s.whatsapp.net", "Sam", 31, "🔥"),
                    ("team@g.us", "r-new", "member@s.whatsapp.net", "Sam", 32, "❤️"),
                    ("team@g.us", "r-other", "admin@s.whatsapp.net", "Alex", 33, "❤️"),
                ],
            )
        item = next(value for value in self.backend.messages("team@g.us")["messages"]
                    if value["id"] == "t2")
        self.assertEqual([reaction["emoji"] for reaction in item["reactions"]],
                         ["❤️", "❤️"])
        self.assertEqual({reaction["sender"] for reaction in item["reactions"]},
                         {"Sam", "Alex"})

    def test_reaction_removal_hides_the_users_previous_emoji(self) -> None:
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.executemany(
                """INSERT INTO messages
                (chat_jid, chat_name, msg_id, sender_jid, sender_name, ts,
                 from_me, text, reaction_to_id, reaction_emoji)
                VALUES (?, 'Design team', ?, ?, ?, ?, 0, '', 't2', ?)""",
                [
                    ("team@g.us", "r-old", "member@s.whatsapp.net", "Sam", 31, "🔥"),
                    ("team@g.us", "r-remove", "member@s.whatsapp.net", "Sam", 32, ""),
                    ("team@g.us", "r-other", "admin@s.whatsapp.net", "Alex", 33, "👍"),
                ],
            )
        item = next(value for value in self.backend.messages("team@g.us")["messages"]
                    if value["id"] == "t2")
        self.assertEqual(item["reactions"], [{
            "emoji": "👍",
            "from_me": False,
            "sender": "Alex",
            "sender_jid": "admin@s.whatsapp.net",
        }])

    def test_media_placeholder_is_not_rendered_as_a_caption(self) -> None:
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute(
                "UPDATE messages SET text = '', display_text = 'Sent gif', "
                "media_type = 'gif', mime_type = 'video/mp4' "
                "WHERE chat_jid = ? AND msg_id = ?",
                ["team@g.us", "t2"],
            )
        message = next(item for item in self.backend.messages("team@g.us")["messages"]
                       if item["id"] == "t2")
        self.assertEqual(message["media_type"], "gif")
        self.assertEqual(message["text"], "")

    def test_existing_media_returns_without_network_write(self) -> None:
        with mock.patch.object(self.backend, "_write") as write:
            result = self.backend.download_media("team@g.us", "t2")
        self.assertEqual(result["local_path"], str(self.preview))
        write.assert_not_called()

    def test_missing_media_download_is_scoped_to_selected_chat(self) -> None:
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute(
                "UPDATE messages SET local_path = '' WHERE chat_jid = ? AND msg_id = ?",
                ["team@g.us", "t2"],
            )
        commands = []

        def download(command, **_kwargs):
            commands.append(list(command))
            output = Path(command[command.index("--output") + 1])
            output.write_bytes(b"png")
            return subprocess.CompletedProcess(
                command, 0, json.dumps({"success": True, "data": {"path": str(output)}}), "")

        with mock.patch.object(self.backend, "_run", side_effect=download), \
                mock.patch.object(self.backend, "_write") as write:
            result = self.backend.download_media("team@g.us", "t2")
        self.assertTrue(result["ok"])
        write.assert_not_called()
        command = commands[0]
        self.assertEqual(command[:1], ["--read-only"], "no store lock, so sync keeps running")
        self.assertEqual(command[command.index("--chat") + 1], "team@g.us")
        self.assertEqual(command[command.index("--id") + 1], "t2")
        saved = Path(result["local_path"])
        self.assertTrue(saved.is_file())
        self.assertTrue(str(saved).startswith(str(self.root / "state" / "media")))
        self.assertEqual(saved.stat().st_mode & 0o777, 0o600)
        message = next(item for item in self.backend.messages("team@g.us")["messages"]
                       if item["id"] == "t2")
        self.assertEqual(message["local_path"], str(saved), "the timeline sees the download")
        with mock.patch.object(self.backend, "_run") as again:
            self.assertEqual(self.backend.download_media("team@g.us", "t2")["local_path"], str(saved))
        again.assert_not_called()

    def test_offline_mode_blocks_attachment_download(self) -> None:
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute(
                "UPDATE messages SET local_path = '' WHERE chat_jid = ? AND msg_id = ?",
                ["team@g.us", "t2"])
        with mock.patch.object(self.backend, "online", return_value=False), \
                mock.patch.object(self.backend, "_run") as run:
            with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "Offline"):
                self.backend.download_media("team@g.us", "t2")
        run.assert_not_called()

    def _check_reply(self, digits: str, jid: str, registered: bool = True):
        return subprocess.CompletedProcess([], 0, json.dumps({"success": True, "data": [{
            "query": "+" + digits, "phone": digits, "jid": jid,
            "registered": registered, "responded": True}]}), "")

    def test_new_chat_search_lists_people_the_mirror_knows(self) -> None:
        people = self.backend.contacts_search("")["people"]
        self.assertEqual({person["jid"] for person in people}, {
            "member@s.whatsapp.net", "admin@s.whatsapp.net", "alex@s.whatsapp.net"})
        sam = self.backend.contacts_search("sam")["people"]
        self.assertEqual([(p["name"], p["has_chat"]) for p in sam], [("Sam Rivera", False)])
        by_phone = self.backend.contacts_search("+1 555 765")["people"]
        self.assertEqual([p["jid"] for p in by_phone], ["admin@s.whatsapp.net"])
        self.assertTrue(self.backend.contacts_search("alex")["people"][0]["has_chat"])
        self.assertEqual(self.backend.contacts_search("%")["people"], [])

    def test_checking_a_number_is_an_explicit_remote_read(self) -> None:
        with mock.patch.object(self.backend, "_mutate") as mutate:
            with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "remote-read"):
                self.backend.check_number("+55 11 91234-5678")
            for bad in ["", "abc", "12", "+55 11 9123 4567 8901 23", "0800 123 4567", "5511@x"]:
                with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "country code"):
                    self.backend.check_number(bad, "remote-read")
        mutate.assert_not_called()

    def test_checking_a_number_respects_offline_mode(self) -> None:
        with mock.patch.object(self.backend, "online", return_value=False), \
             mock.patch.object(self.backend, "_run") as run, \
             self.assertRaisesRegex(backend_module.OmaWhatsAppError, "Offline mode"):
            self.backend.check_number("+55 11 91234-5678", "remote-read")
        run.assert_not_called()

    def test_first_message_needs_a_confirmed_or_known_recipient(self) -> None:
        sent = subprocess.CompletedProcess([], 0, json.dumps({"success": True}), "")
        with mock.patch.object(self.backend, "_write", return_value=sent) as write:
            with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "Check that number"):
                self.backend.send_new({"phone": "+55 11 91234-5678"}, "hi")
            with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "Check that number"):
                self.backend.send_new({"jid": "5511912345678@s.whatsapp.net"}, "hi")
            with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "contacts"):
                self.backend.send_new({"jid": "team@g.us"}, "hi")
            with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "Type a message"):
                self.backend.send_new({"phone": "+55 11 91234-5678"}, "  ")
        write.assert_not_called()

    def test_a_confirmed_number_receives_the_first_message(self) -> None:
        jid = "551191234567@s.whatsapp.net"
        with mock.patch.object(self.backend, "_mutate",
                               return_value=self._check_reply("5511912345678", jid)) as mutate:
            checked = self.backend.check_number("+55 (11) 91234-5678", "remote-read")
        self.assertEqual(mutate.call_args.args[0],
                         ["--json", "contacts", "check", "+5511912345678"])
        self.assertTrue(checked["registered"])
        self.assertEqual(checked["jid"], jid, "WhatsApp's canonical JID wins over the typed digits")
        self.assertFalse(checked["has_chat"])
        sent = subprocess.CompletedProcess([], 0, json.dumps({"success": True}), "")
        with mock.patch.object(self.backend, "_write", return_value=sent) as write:
            result = self.backend.send_new({"phone": "5511912345678"}, "  hello  ")
            self.backend.send_new({"jid": jid}, "again")
        command = write.call_args_list[0].args[0]
        self.assertEqual(command[command.index("--to") + 1], jid)
        self.assertEqual(command[command.index("--message") + 1], "hello")
        self.assertEqual(result["jid"], jid)
        self.assertEqual(write.call_count, 2)

    def test_whatsapp_answering_with_a_lid_still_confirms_the_number(self) -> None:
        # Found live: WhatsApp now answers a number check with the person's @lid.
        lid = "123456789012345@lid"
        with mock.patch.object(self.backend, "_mutate",
                               return_value=self._check_reply("5511912345678", lid)):
            checked = self.backend.check_number("+5511912345678", "remote-read")
        self.assertTrue(checked["registered"])
        self.assertEqual(checked["jid"], lid)
        self.assertFalse(checked["has_chat"])
        sent = subprocess.CompletedProcess([], 0, json.dumps(
            {"success": True, "data": {"id": "SYNTHETIC-SENT"}}), "")
        with mock.patch.object(self.backend, "_write", return_value=sent) as write:
            result = self.backend.send_new({"jid": lid}, "hello")
        command = write.call_args.args[0]
        self.assertEqual(command[command.index("--to") + 1], lid)
        self.assertEqual(result["chat_jid"], "5511912345678@s.whatsapp.net",
                         "without the stored row yet, the chat is expected under the phone JID")
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute(
                """INSERT INTO messages (chat_jid, chat_name, msg_id, sender_jid, sender_name,
                   ts, from_me, text, reaction_to_id, media_type, mime_type, local_path)
                   VALUES (?, '', 'SYNTHETIC-SENT', '', '', 90, 1, 'hello', '', '', '', '')""",
                ["5511987654321@s.whatsapp.net"])
        with mock.patch.object(self.backend, "_write", return_value=sent):
            again = self.backend.send_new({"jid": lid}, "hello")
        self.assertEqual(again["chat_jid"], "5511987654321@s.whatsapp.net",
                         "the stored message names the chat wacli really used")

    def test_a_lid_answer_for_someone_with_a_chat_opens_that_chat(self) -> None:
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute("INSERT INTO chats VALUES (?, 'dm', 'Known', 5, 0, 0, 0, 0, 0)",
                               ["5511912345678@s.whatsapp.net"])
        with mock.patch.object(self.backend, "_mutate", return_value=self._check_reply(
                "5511912345678", "123456789012345@lid")):
            checked = self.backend.check_number("+5511912345678", "remote-read")
        self.assertTrue(checked["has_chat"])
        self.assertEqual(checked["jid"], "5511912345678@s.whatsapp.net")
        self.assertEqual(checked["name"], "Known")

    def test_an_unregistered_number_is_never_remembered(self) -> None:
        with mock.patch.object(self.backend, "_mutate", return_value=self._check_reply(
                "5511900000000", "", registered=False)):
            checked = self.backend.check_number("+5511900000000", "remote-read")
        self.assertFalse(checked["registered"])
        self.assertEqual(checked["jid"], "")
        with mock.patch.object(self.backend, "_write") as write, \
             self.assertRaisesRegex(backend_module.OmaWhatsAppError, "Check that number"):
            self.backend.send_new({"phone": "+5511900000000"}, "hi")
        write.assert_not_called()

    def test_a_stale_check_must_be_repeated(self) -> None:
        jid = "5511912345678@s.whatsapp.net"
        with mock.patch.object(self.backend, "_mutate",
                               return_value=self._check_reply("5511912345678", jid)):
            self.backend.check_number("+5511912345678", "remote-read")
        later = time.time() + backend_module.NEW_CHAT_CHECK_TTL + 5
        with mock.patch.object(backend_module.time, "time", return_value=later), \
             mock.patch.object(self.backend, "_write") as write, \
             self.assertRaisesRegex(backend_module.OmaWhatsAppError, "Check that number"):
            self.backend.send_new({"phone": "+5511912345678"}, "hi")
        write.assert_not_called()

    def test_first_message_to_an_existing_chat_uses_the_normal_send(self) -> None:
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute("INSERT INTO chats VALUES (?, 'dm', 'Known', 5, 0, 0, 0, 0, 0)",
                               ["15550001111@s.whatsapp.net"])
            connection.execute("INSERT INTO contacts VALUES (?, ?, '', 'Only contact', '', '', '', 1)",
                               ["15550002222@s.whatsapp.net", "15550002222"])
        with mock.patch.object(self.backend, "send") as send, \
             mock.patch.object(self.backend, "_write") as write:
            self.backend.send_new({"jid": "15550001111@s.whatsapp.net"}, "hi")
            send.assert_called_once_with("15550001111@s.whatsapp.net", "hi")
            write.return_value = subprocess.CompletedProcess(
                [], 0, json.dumps({"success": True}), "")
            self.backend.send_new({"jid": "15550002222@s.whatsapp.net"}, "hi")
        command = write.call_args.args[0]
        self.assertEqual(command[command.index("--to") + 1], "15550002222@s.whatsapp.net")

    def test_save_media_copies_the_attachment_to_the_chosen_file(self) -> None:
        destination = self.root / "Downloads" / "saved.png"
        destination.parent.mkdir()
        result = self.backend.save_media("team@g.us", "t2", str(destination))
        self.assertEqual(result["path"], str(destination))
        self.assertEqual(destination.read_bytes(), self.preview.read_bytes())
        for bad in ("relative.png", str(self.root / "missing" / "x.png"), str(destination.parent)):
            with self.assertRaises(backend_module.OmaWhatsAppError):
                self.backend.save_media("team@g.us", "t2", bad)

    def test_save_media_replaces_a_file_only_when_the_dialog_asked(self) -> None:
        destination = self.root / "Downloads" / "saved.png"
        destination.parent.mkdir()
        destination.write_text("mine", encoding="utf-8")
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "already there"):
            self.backend.save_media("team@g.us", "t2", str(destination))
        self.assertEqual(destination.read_text(encoding="utf-8"), "mine")
        self.backend.save_media("team@g.us", "t2", str(destination), replace=True)
        self.assertEqual(destination.read_bytes(), self.preview.read_bytes())

    def test_unavailable_media_is_not_retried_forever(self) -> None:
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute(
                "UPDATE messages SET local_path = '', media_unavailable_at = 1 "
                "WHERE chat_jid = ? AND msg_id = ?",
                ["team@g.us", "t2"],
            )
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "no longer available"):
            self.backend.download_media("team@g.us", "t2")

    def test_unknown_chat_is_rejected_before_write(self) -> None:
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "not available"):
            self.backend.send("unknown@g.us", "hello")

    def test_send_targets_selected_local_chat(self) -> None:
        completed = subprocess.CompletedProcess([], 0, json.dumps(
            {"success": True, "data": {"id": "SYNTHETIC-ID"}}), "")
        with mock.patch.object(self.backend, "_write", return_value=completed) as write:
            result = self.backend.send("alex@s.whatsapp.net", "hello")
        self.assertEqual(result, {"ok": True, "message_id": "SYNTHETIC-ID"},
                         "the id lets the pending bubble give way to the stored row")
        command = write.call_args.args[0]
        self.assertEqual(command[command.index("--to") + 1], "alex@s.whatsapp.net")
        self.assertEqual(command[command.index("--message") + 1], "hello")

    def test_presence_goes_through_the_running_sync_and_never_pauses_it(self) -> None:
        # The owner asked for online, last seen and typing. Presence is only
        # meaningful on the sync's own connection, so the helper never yields
        # the sync for it: a paused sync loses whatever arrives meanwhile.
        answer = subprocess.CompletedProcess([], 0, json.dumps(
            {"success": True, "data": {"available": True, "until": "2026-09-25T12:01:30Z"}}), "")
        with mock.patch.object(self.backend, "_run", return_value=answer) as run, \
                mock.patch.object(self.backend, "_yield_active_sync") as yield_sync:
            result = self.backend.presence("available", lease=45)
        yield_sync.assert_not_called()
        self.assertEqual(result, {"ok": True, "action": "available", "until": "2026-09-25T12:01:30Z"})
        self.assertEqual(run.call_args.args[0], ["--json", "presence", "available", "--lease", "45s"])
        subscribed = subprocess.CompletedProcess([], 0, json.dumps(
            {"success": True, "data": {"subscribed": True, "sent_now": True}}), "")
        with mock.patch.object(self.backend, "_run", return_value=subscribed) as run:
            result = self.backend.presence("subscribe", "alex@s.whatsapp.net")
        self.assertEqual(run.call_args.args[0],
                         ["--json", "presence", "subscribe", "--to", "alex@s.whatsapp.net"])
        self.assertTrue(result["sent_now"])
        with self.assertRaises(backend_module.OmaWhatsAppError):
            self.backend.presence("subscribe", "team@g.us")
        official = subprocess.CompletedProcess([], 1, "", 'Error: unknown command "available" for "wacli presence"')
        with mock.patch.object(self.backend, "_run", return_value=official):
            self.assertEqual(self.backend.presence("unavailable")["supported"], False,
                             "official wacli lacks these commands; the app stops asking")
        with mock.patch.object(self.backend, "_run") as run, \
                mock.patch.object(self.backend, "online", return_value=False):
            self.assertEqual(self.backend.presence("available"), {"ok": True, "skipped": "offline"})
        run.assert_not_called()

    def test_chat_details_are_read_locally_for_a_group(self) -> None:
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute("""INSERT INTO groups (jid, name, owner_jid, created_ts, updated_at)
                                  VALUES ('team@g.us', 'Design team', 'admin@s.whatsapp.net', 100, 1)""")
            connection.execute("INSERT INTO starred VALUES ('team@g.us', 't1', '', 0, 5)")
        with mock.patch.object(self.backend, "_run") as run:
            details = self.backend.chat_details("team@g.us")
        run.assert_not_called()
        self.assertEqual(details["chat"]["name"], "Design team")
        self.assertEqual(details["counts"], {"total": 4, "media": 1, "documents": 0,
                                             "links": 0, "starred": 1, "missing": 0})
        self.assertEqual(details["since"], 20)
        self.assertEqual(details["group"], {"created_ts": 100, "left": False,
                                            "owner_name": "Alex Kim", "participant_count": 2,
                                            "my_role": ""})
        self.assertEqual([m["role"] for m in details["participants"]], ["admin", "member"])
        self.assertTrue(details["pinned"])
        self.assertNotIn("person", details)

    def test_chat_details_for_a_person_list_groups_in_common(self) -> None:
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute("INSERT INTO chats VALUES ('member@s.whatsapp.net', 'dm', '', 9, 0, 0, 0, 0, 0)")
            connection.execute("""INSERT INTO groups (jid, name, updated_at)
                                  VALUES ('team@g.us', 'Design team', 1)""")
            connection.execute("INSERT INTO contact_aliases VALUES ('member@s.whatsapp.net', 'Sammy', '', 1)")
        details = self.backend.chat_details("member@s.whatsapp.net")
        self.assertEqual(details["person"]["phone"], "15551234567")
        self.assertEqual(details["person"]["full_name"], "Sam Rivera")
        self.assertEqual(details["person"]["alias"], "Sammy")
        self.assertEqual(details["groups_in_common"], [{"jid": "team@g.us", "name": "Design team"}])
        self.assertNotIn("participants", details)
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "not available"):
            self.backend.chat_details("stranger@s.whatsapp.net")

    def _cache_own_jid(self, jid: str) -> None:
        key = hashlib.sha256(self.backend.account("").key.encode("utf-8")).hexdigest()[:24]
        state = self.root / "state"
        state.mkdir(mode=0o700, exist_ok=True)
        path = state / backend_module.DOCTOR_CACHE_FILE
        path.write_text(json.dumps({key: {"at": 0, "doctor": {"linked_jid": jid}}}), encoding="utf-8")
        path.chmod(0o600)

    def test_group_details_know_your_role_without_asking_wacli(self) -> None:
        self._cache_own_jid("admin@s.whatsapp.net")
        with mock.patch.object(self.backend, "_run") as run:
            details = self.backend.chat_details("team@g.us")
        run.assert_not_called()
        self.assertEqual(details["group"]["my_role"], "admin")

    def test_group_actions_build_exact_wacli_commands(self) -> None:
        sent = subprocess.CompletedProcess([], 0, json.dumps({"success": True, "data": {}}), "")
        cases = [
            ("rename", "  New   name ", ["groups", "rename", "--jid", "team@g.us", "--name", "New name"]),
            ("description", "About us", ["groups", "description", "--jid", "team@g.us", "--text", "About us"]),
            ("announce", True, ["groups", "announce-only", "--jid", "team@g.us", "--on"]),
            ("locked", False, ["groups", "locked", "--jid", "team@g.us", "--off"]),
            ("add", ["+1 555 000 1111"], ["groups", "participants", "add", "--jid", "team@g.us",
                                          "--user", "+15550001111"]),
            ("promote", "member@s.whatsapp.net", ["groups", "participants", "promote", "--jid",
                                                   "team@g.us", "--user", "member@s.whatsapp.net"]),
            ("remove", "member@s.whatsapp.net", ["groups", "participants", "remove", "--jid",
                                                  "team@g.us", "--user", "member@s.whatsapp.net"]),
            ("leave", None, ["groups", "leave", "--jid", "team@g.us"]),
        ]
        for action, value, expected in cases:
            with mock.patch.object(self.backend, "_write", return_value=sent) as write:
                self.backend.group_action("team@g.us", action, value)
            self.assertEqual(write.call_args.args[0], ["--json", *expected], action)

    def test_group_actions_refuse_what_they_cannot_tie_to_the_group(self) -> None:
        with mock.patch.object(self.backend, "_write") as write:
            for action, value, message in [
                ("remove", "stranger@s.whatsapp.net", "not indexed"),
                ("rename", "", "1 to 100"),
                ("announce", "yes", "on or off"),
                ("add", [], "1 to 10"),
                ("invite-get", None, "remote-read"),
                ("approve", "not a jid", "pending request"),
                ("explode", None, "not supported"),
            ]:
                with self.assertRaisesRegex(backend_module.OmaWhatsAppError, message):
                    self.backend.group_action("team@g.us", action, value)
            with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "not a group"):
                self.backend.group_action("alex@s.whatsapp.net", "leave")
        write.assert_not_called()

    def test_invite_links_and_requests_come_back_parsed(self) -> None:
        link = subprocess.CompletedProcess([], 0, json.dumps({"success": True, "data": {
            "jid": "team@g.us", "link": "https://chat.whatsapp.com/SyntheticCode"}}), "")
        with mock.patch.object(self.backend, "_write", return_value=link):
            self.assertEqual(self.backend.group_action("team@g.us", "invite-get", None, "remote-read")["link"],
                             "https://chat.whatsapp.com/SyntheticCode")
        requests = subprocess.CompletedProcess([], 0, json.dumps({"success": True, "data": [
            {"JID": "123456789012345@lid", "phone_number": "15550009999", "RequestedAt": "2026-09-24T12:00:00Z"}]}), "")
        with mock.patch.object(self.backend, "_write", return_value=requests):
            listed = self.backend.group_action("team@g.us", "requests", None, "remote-read")["requests"]
        self.assertEqual(listed[0]["jid"], "123456789012345@lid")

    def test_live_group_settings_name_your_role(self) -> None:
        self._cache_own_jid("admin@s.whatsapp.net")
        info = subprocess.CompletedProcess([], 0, json.dumps({"success": True, "data": {
            "Name": "Design team", "Topic": "About", "IsAnnounce": True, "IsLocked": False,
            "Participants": [{"JID": "admin@s.whatsapp.net", "IsAdmin": True, "IsSuperAdmin": False}]}}), "")
        with mock.patch.object(self.backend, "_mutate", return_value=info):
            settings = self.backend.group_info("team@g.us", "remote-read")
        self.assertEqual((settings["description"], settings["announce_only"], settings["locked"],
                          settings["my_role"]), ("About", True, False, "admin"))

    def test_group_members_are_named_and_admins_sort_first(self) -> None:
        members = self.backend.members("team@g.us")["members"]
        self.assertEqual([member["name"] for member in members], ["Alex Kim", "Sam Rivera"])
        self.assertEqual(members[0]["role"], "admin")
        self.assertEqual(self.backend.members("alex@s.whatsapp.net")["members"], [])

    def test_external_image_prefers_omasnap_when_installed(self) -> None:
        with mock.patch.object(backend_module.shutil, "which", return_value="/usr/bin/omasnap"), \
             mock.patch.object(backend_module.subprocess, "Popen") as popen:
            result = self.backend.open_media_external(self.preview.as_uri())
        self.assertEqual(result["opener"], "omasnap")
        self.assertEqual(popen.call_args.args[0],
                         ["/usr/bin/omasnap", "--file", str(self.preview)])

    def test_external_non_image_uses_system_opener(self) -> None:
        with mock.patch.object(backend_module.shutil, "which", return_value="/usr/bin/omasnap"), \
             mock.patch.object(backend_module.subprocess, "Popen") as popen:
            result = self.backend.open_media_external(self.document.as_uri())
        self.assertEqual(result["opener"], "system")
        self.assertEqual(popen.call_args.args[0],
                         [str(backend_module.XDG_OPEN), str(self.document)])

    def test_send_passes_real_group_mentions_to_wacli(self) -> None:
        completed = subprocess.CompletedProcess([], 0, json.dumps({"success": True}), "")
        with mock.patch.object(self.backend, "_write", return_value=completed) as write:
            self.backend.send("team@g.us", "hey @Sam Rivera", "", ["member@s.whatsapp.net"])
        command = write.call_args.args[0]
        self.assertEqual(command[command.index("--mention") + 1], "member@s.whatsapp.net")

    def test_send_rejects_mentions_outside_selected_group(self) -> None:
        with mock.patch.object(self.backend, "_write") as write, \
             self.assertRaisesRegex(backend_module.OmaWhatsAppError, "not a member"):
            self.backend.send("team@g.us", "hey @stranger", "", ["stranger@s.whatsapp.net"])
        write.assert_not_called()

    def test_clipboard_file_is_staged_without_sending(self) -> None:
        with mock.patch.object(self.backend, "_clipboard_types", return_value=["text/uri-list"]), \
             mock.patch.object(self.backend, "_clipboard", return_value=(self.document.as_uri() + "\n").encode()), \
             mock.patch.object(self.backend, "_write") as write:
            result = self.backend.paste("team@g.us")
        self.assertEqual(result["kind"], "file")
        self.assertEqual(result["path"], self.document.as_uri())
        write.assert_not_called()

    def test_clipboard_image_is_staged_for_preview_without_sending(self) -> None:
        runtime = self.root / "runtime"
        with mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": str(runtime)}), \
             mock.patch.object(self.backend, "_clipboard_types", return_value=["image/gif"]), \
             mock.patch.object(self.backend, "_clipboard", return_value=b"GIF89a"), \
             mock.patch.object(self.backend, "_write") as write:
            result = self.backend.paste("team@g.us")
        staged = Path(result["path"].removeprefix("file://"))
        self.assertEqual(result["kind"], "image")
        self.assertEqual(staged.suffix, ".gif")
        self.assertEqual(staged.read_bytes(), b"GIF89a")
        write.assert_not_called()

    def test_reply_is_scoped_and_carries_group_sender(self) -> None:
        completed = subprocess.CompletedProcess([], 0, '{"success":true}', "")
        with mock.patch.object(self.backend, "_write", return_value=completed) as write:
            self.backend.send("team@g.us", "reply", "t1")
        command = write.call_args.args[0]
        self.assertEqual(command[command.index("--reply-to") + 1], "t1")
        self.assertEqual(command[command.index("--reply-to-sender") + 1],
                         "member@s.whatsapp.net")

    def test_successful_reply_hint_restores_quote_before_the_index_links_it(self) -> None:
        completed = subprocess.CompletedProcess(
            [], 0, '{"success":true,"data":{"id":"sent-reply"}}', ""
        )
        with mock.patch.object(self.backend, "_write", return_value=completed):
            self.backend.send("team@g.us", "synthetic reply", "t1")
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute(
                """INSERT INTO messages
                (chat_jid, chat_name, msg_id, sender_jid, sender_name, ts,
                 from_me, text, reaction_to_id)
                VALUES (?, 'Design team', ?, 'me@s.whatsapp.net', '', ?, 1, ?, '')""",
                ["team@g.us", "sent-reply", 50, "synthetic reply"],
            )

        item = next(value for value in self.backend.messages("team@g.us")["messages"]
                    if value["id"] == "sent-reply")
        self.assertEqual(item["quoted_id"], "t1")
        self.assertEqual(item["quoted_sender"], "Sam")
        self.assertEqual(item["quoted_text"], "ship it")
        state = self.root / "state" / "sent-replies.json"
        self.assertEqual(state.stat().st_mode & 0o777, 0o600)
        hint_text = state.read_text(encoding="utf-8")
        self.assertNotIn("synthetic reply", hint_text)
        self.assertNotIn("ship it", hint_text)

    def test_reply_hint_bookkeeping_never_makes_a_delivered_send_retryable(self) -> None:
        completed = subprocess.CompletedProcess(
            [], 0, '{"success":true,"data":{"id":"sent-reply"}}', ""
        )
        with mock.patch.object(self.backend, "_write", return_value=completed), \
             mock.patch.object(
                 self.backend, "_remember_sent_reply",
                 side_effect=backend_module.OmaWhatsAppError("state is full"),
             ):
            result = self.backend.send("team@g.us", "synthetic reply", "t1")
        self.assertTrue(result["ok"])

    def test_attachment_reply_is_applied_only_to_first_file(self) -> None:
        completed = subprocess.CompletedProcess([], 0, '{"success":true}', "")
        with mock.patch.object(self.backend, "_write", return_value=completed) as write:
            self.backend.send_files("team@g.us", [self.preview.as_uri(), self.document.as_uri()],
                                    "caption", "t1")
        first, second = [call.args[0] for call in write.call_args_list]
        self.assertIn("--reply-to", first)
        self.assertIn("--caption", first)
        self.assertNotIn("--reply-to", second)
        self.assertNotIn("--caption", second)

    def test_sticker_requires_webp_and_supports_reply(self) -> None:
        completed = subprocess.CompletedProcess([], 0, '{"success":true}', "")
        with mock.patch.object(self.backend, "_write", return_value=completed) as write:
            self.backend.send_sticker("team@g.us", self.sticker.as_uri(), "t1")
        command = write.call_args.args[0]
        self.assertEqual(command[1:3], ["send", "sticker"])
        self.assertIn("--reply-to-sender", command)
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "WebP"):
            self.backend.send_sticker("team@g.us", self.preview.as_uri())

    def test_voice_drafts_are_private_and_require_ogg_opus(self) -> None:
        created = self.backend.voice_draft("create")
        draft = Path(created["path"])
        self.assertEqual(draft.parent.stat().st_mode & 0o777, 0o700)
        self.assertEqual(draft.stat().st_mode & 0o777, 0o600)
        self.assertEqual(draft.stat().st_size, 0)

        draft.write_bytes(b"not an opus recording")
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "OGG/Opus"):
            self.backend.voice_draft("finalize", draft)

        draft.write_bytes(b"OggS" + bytes(24) + b"OpusHead" + bytes(64))
        finalized = self.backend.voice_draft("finalize", draft.as_uri())
        self.assertEqual(finalized["path"], str(draft))
        self.assertEqual(finalized["size"], draft.stat().st_size)
        self.assertEqual(draft.stat().st_mode & 0o777, 0o600)

    def test_voice_send_is_exact_reply_aware_and_removes_confirmed_draft(self) -> None:
        draft = Path(self.backend.voice_draft("create")["path"])
        draft.write_bytes(b"OggS" + bytes(24) + b"OpusHead" + bytes(64))
        completed = subprocess.CompletedProcess([], 0, '{"success":true}', "")
        with mock.patch.object(self.backend, "_write", return_value=completed) as write:
            result = self.backend.send_voice("team@g.us", draft, "t1")
        command = write.call_args.args[0]
        self.assertEqual(command[1:3], ["send", "voice"])
        self.assertEqual(command[command.index("--to") + 1], "team@g.us")
        self.assertEqual(command[command.index("--file") + 1], str(draft))
        self.assertEqual(command[command.index("--mime") + 1], "audio/ogg")
        self.assertEqual(command[command.index("--reply-to") + 1], "t1")
        self.assertEqual(command[command.index("--reply-to-sender") + 1],
                         "member@s.whatsapp.net")
        self.assertTrue(result["draft_cleaned"])
        self.assertFalse(draft.exists())

    def test_failed_voice_send_preserves_review_draft(self) -> None:
        draft = Path(self.backend.voice_draft("create")["path"])
        draft.write_bytes(b"OggS" + bytes(24) + b"OpusHead" + bytes(64))
        rejected = subprocess.CompletedProcess(
            [], 1, '{"success":false,"error":{"message":"rejected"}}', ""
        )
        with mock.patch.object(self.backend, "_write", return_value=rejected), \
             self.assertRaisesRegex(backend_module.OmaWhatsAppError, "rejected"):
            self.backend.send_voice("team@g.us", draft)
        self.assertTrue(draft.exists())

    def test_voice_draft_commands_reject_paths_outside_private_store(self) -> None:
        external = self.root / "voice-deadbeefdeadbeefdeadbeefdeadbeef.ogg"
        external.write_bytes(b"OggS" + bytes(24) + b"OpusHead")
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "private voice draft"):
            self.backend.voice_draft("finalize", external)
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "private voice draft"):
            self.backend.send_voice("team@g.us", external)

    def test_poll_is_validated_and_transport_is_exact(self) -> None:
        completed = subprocess.CompletedProcess(
            [], 0, '{"success":true,"data":{"id":"POLL-ID"}}', "")
        with mock.patch.object(self.backend, "_write", return_value=completed) as write:
            result = self.backend.send_poll("team@g.us", "Ship it?", ["Yes", "No"], 1)
        self.assertEqual(result["message_id"], "POLL-ID",
                         "an agent needs the id to read the results or vote")
        command = write.call_args.args[0]
        self.assertEqual(command[1:3], ["send", "poll"])
        self.assertEqual(command.count("--option"), 2)
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "unique"):
            self.backend.send_poll("team@g.us", "Ship it?", ["Yes", "yes"], 1)

    def test_reaction_uses_stored_group_sender(self) -> None:
        completed = subprocess.CompletedProcess([], 0, '{"success":true}', "")
        with mock.patch.object(self.backend, "_write", return_value=completed) as write:
            self.backend.react("team@g.us", "t1", "🔥")
        command = write.call_args.args[0]
        self.assertEqual(command[command.index("--id") + 1], "t1")
        self.assertEqual(command[command.index("--sender") + 1],
                         "member@s.whatsapp.net")

    def test_edit_and_everyone_delete_require_own_message(self) -> None:
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "your own"):
            self.backend.edit_message("team@g.us", "t1", "changed")
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "your own"):
            self.backend.delete_message("team@g.us", "t1", False)

    def test_edit_delete_and_forward_commands_are_exact(self) -> None:
        completed = subprocess.CompletedProcess([], 0, '{"success":true}', "")
        with mock.patch.object(self.backend, "_write", return_value=completed) as write:
            self.backend.edit_message("alex@s.whatsapp.net", "a1", "changed")
            edit = write.call_args.args[0]
            self.backend.delete_message("alex@s.whatsapp.net", "a1", True)
            delete = write.call_args.args[0]
            self.backend.forward_message("team@g.us", "t1", "alex@s.whatsapp.net")
            forward = write.call_args.args[0]
        self.assertEqual(edit[1:3], ["messages", "edit"])
        self.assertIn("--for-me", delete)
        self.assertEqual(forward[forward.index("--to") + 1], "alex@s.whatsapp.net")

    def test_typing_goes_through_the_running_sync_or_not_at_all(self) -> None:
        completed = subprocess.CompletedProcess([], 0, '{"success":true}', "")
        with mock.patch.object(self.backend, "_sync_active", return_value=True), \
                mock.patch.object(self.backend, "_run", return_value=completed) as run:
            self.assertTrue(self.backend.chat_presence("team@g.us", "typing")["sent"])
            typing = run.call_args.args[0]
            self.backend.chat_presence("team@g.us", "recording")
            recording = run.call_args.args[0]
            self.backend.chat_presence("team@g.us", "paused")
            paused = run.call_args.args[0]
        self.assertEqual(typing, ["--json", "presence", "typing", "--to", "team@g.us"])
        self.assertEqual(recording[-2:], ["--media", "audio"])
        self.assertEqual(paused[1:3], ["presence", "paused"])
        # No sync running: skipped, never a second session or a paused sync.
        with mock.patch.object(self.backend, "_sync_active", return_value=False), \
                mock.patch.object(self.backend, "_run") as run, \
                mock.patch.object(self.backend, "_mutate") as mutate:
            self.assertFalse(self.backend.chat_presence("team@g.us", "typing")["sent"])
        run.assert_not_called()
        mutate.assert_not_called()
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "typing, recording, or paused"):
            self.backend.chat_presence("team@g.us", "dancing")

    def test_starring_goes_through_wacli_messages_star(self) -> None:
        completed = subprocess.CompletedProcess([], 0, json.dumps(
            {"success": True, "data": {"starred": True}}), "")
        with mock.patch.object(self.backend, "_write", return_value=completed) as write:
            self.assertTrue(self.backend.star_message("team@g.us", "t1", True)["starred"])
            star = write.call_args.args[0]
            self.backend.star_message("team@g.us", "t1", False)
            unstar = write.call_args.args[0]
        self.assertEqual(star[1:3], ["messages", "star"])
        self.assertEqual(star[star.index("--id") + 1], "t1")
        self.assertNotIn("--unstar", star)
        self.assertIn("--unstar", unstar)
        missing = subprocess.CompletedProcess([], 1, "", 'Error: unknown command "star" for "wacli messages"')
        with mock.patch.object(self.backend, "_write", return_value=missing):
            with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "cannot star"):
                self.backend.star_message("team@g.us", "t1", True)

    def test_forwarding_to_a_typed_number_needs_a_fresh_check(self) -> None:
        # L225: a number with no chat yet takes a forward once WhatsApp has
        # just confirmed it, as a first message does.
        completed = subprocess.CompletedProcess([], 0, json.dumps(
            {"success": True, "data": {"forwarded": True, "id": "FWD-9"}}), "")
        with mock.patch.object(self.backend, "_write", return_value=completed):
            with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "Check that number"):
                self.backend.forward_message("team@g.us", "t1", "", "+1 555 000 7777")
        self.backend._remember_new_chat_check("15550007777", "999000111@lid")
        with mock.patch.object(self.backend, "_write", return_value=completed) as write:
            result = self.backend.forward_message("team@g.us", "t1", "", "+1 555 000 7777")
        command = write.call_args.args[0]
        self.assertEqual(command[command.index("--to") + 1], "999000111@lid",
                         "sent to the person WhatsApp confirmed")
        self.assertEqual(result["target_jid"], "15550007777@s.whatsapp.net",
                         "the chat it lands in is the phone number's")
        self.assertEqual(result["target"], "+15550007777")
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "country code"):
            self.backend.forward_message("team@g.us", "t1", "", "12")

    def test_a_forwarded_photo_shows_the_file_already_here(self) -> None:
        # The owner's report: a forwarded photo offered a download in the
        # target chat although the file was on this computer.
        photo = self.root / "synthetic-photo.jpg"
        photo.write_bytes(b"\xff\xd8synthetic")
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute(
                """INSERT INTO messages (chat_jid, chat_name, msg_id, sender_jid, sender_name, ts,
                  from_me, text, display_text, reaction_to_id, media_type, mime_type, local_path)
                VALUES ('team@g.us', 'Design team', 'photo1', 'member@s.whatsapp.net', 'Sam', 90,
                  0, '', '', '', 'image', 'image/jpeg', ?)""", [str(photo)])
        answer = subprocess.CompletedProcess([], 0, json.dumps(
            {"success": True, "data": {"forwarded": True, "id": "FWD-1", "to": "alex@s.whatsapp.net"}}), "")
        with mock.patch.object(self.backend, "_write", return_value=answer):
            result = self.backend.forward_message("team@g.us", "photo1", "alex@s.whatsapp.net")
        self.assertEqual(result["message_id"], "FWD-1")
        self.assertEqual(result["target_jid"], "alex@s.whatsapp.net")
        hint = self.backend._sent_media_hints()[self.backend._sent_hint_key("alex@s.whatsapp.net", "FWD-1")]
        self.assertEqual(hint["local_path"], str(photo), "the copy points at the file already here")
        text_only = subprocess.CompletedProcess([], 0, json.dumps(
            {"success": True, "data": {"forwarded": True, "id": "FWD-2"}}), "")
        with mock.patch.object(self.backend, "_write", return_value=text_only):
            self.backend.forward_message("team@g.us", "t1", "alex@s.whatsapp.net")
        self.assertNotIn(self.backend._sent_hint_key("alex@s.whatsapp.net", "FWD-2"),
                         self.backend._sent_media_hints(), "text has no file to share")

    def test_chat_actions_are_allowlisted(self) -> None:
        completed = subprocess.CompletedProcess([], 0, '{"success":true}', "")
        with mock.patch.object(self.backend, "_write", return_value=completed) as write:
            self.backend.chat_action("team@g.us", "mute")
        command = write.call_args.args[0]
        self.assertEqual(command[1:3], ["chats", "mute"])
        self.assertEqual(command[command.index("--chat") + 1], "team@g.us")
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "not supported"):
            self.backend.chat_action("team@g.us", "leave")

    def test_chat_action_remove_local(self) -> None:
        completed = subprocess.CompletedProcess([], 0, '{"success":true,"data":{"deleted":true}}', "")
        with mock.patch.object(self.backend, "_mutate", return_value=completed) as mutate:
            result = self.backend.chat_action("team@g.us", "remove-local")
        self.assertTrue(result["ok"])
        self.assertEqual(result["action"], "remove-local")
        self.assertEqual(mutate.call_args.args[0], [
            "--json", "chats", "cleanup", "--jid", "team@g.us", "--confirm"
        ])
        self.assertFalse(mutate.call_args.kwargs.get("require_online", True))

    def test_mark_read_is_an_explicit_exact_receipt_command(self) -> None:
        completed = subprocess.CompletedProcess([], 0, '{"success":true}', "")
        with mock.patch.object(self.backend, "_write", return_value=completed) as write:
            self.backend.chat_action("team@g.us", "read")
        self.assertEqual(write.call_args.args[0], [
            "--json", "chats", "mark-read", "--chat", "team@g.us"
        ])

    def test_offline_mode_persists_and_blocks_whatsapp_writes(self) -> None:
        completed = subprocess.CompletedProcess([], 0, "", "")
        with mock.patch.object(backend_module, "run_bounded", return_value=completed) as run:
            result = self.backend.set_online(False)
        self.assertFalse(result["online"])
        self.assertFalse(self.backend.online())
        self.assertIn("disable", run.call_args.args[0])
        self.assertIn("--now", run.call_args.args[0])
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "Offline mode"):
            self.backend._write(["--json", "chats", "mark-read"], timeout=10)

        with mock.patch.object(backend_module, "run_bounded", return_value=completed) as run:
            result = self.backend.set_online(True)
        self.assertTrue(result["online"])
        self.assertTrue(self.backend.online())
        verbs = [call.args[0][2] for call in run.call_args_list]
        self.assertIn("enable", verbs, "back online it starts with the system again")
        self.assertEqual(verbs[-1], "start")

    def test_quit_stops_sync_until_launch_and_says_it_is_closed(self) -> None:
        # L233: quitting stops every account's sync for this session.
        completed = subprocess.CompletedProcess([], 0, "", "")
        with mock.patch.object(backend_module, "run_bounded", return_value=completed) as run:
            self.assertTrue(self.backend.quit_app()["closed"])
        verbs = [call.args[0][2] for call in run.call_args_list]
        self.assertEqual(verbs, ["stop"], "stopped, not disabled: it still starts at the next login")
        with mock.patch.object(self.backend, "_sync_active", return_value=False):
            self.assertTrue(self.backend.status()["closed"])
        with mock.patch.object(backend_module, "run_bounded", return_value=completed) as run:
            self.assertEqual(self.backend.launch_app()["started"], 1)
        self.assertEqual([call.args[0][2] for call in run.call_args_list], ["start"])
        with mock.patch.object(self.backend, "_sync_active", return_value=True):
            self.assertFalse(self.backend.status()["closed"])

    def test_starting_with_the_system_is_a_setting(self) -> None:
        # L234: on by default; off disables the unit without stopping it.
        self.assertTrue(self.backend.settings()["start_at_login"])
        completed = subprocess.CompletedProcess([], 0, "", "")
        with mock.patch.object(backend_module, "run_bounded", return_value=completed) as run:
            self.assertFalse(self.backend.settings({"start_at_login": False})["start_at_login"])
        self.assertEqual([call.args[0][2] for call in run.call_args_list], ["disable"])
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "on or off"):
            self.backend.settings({"start_at_login": "no"})
        # Not started at login: closed until opened, even with nothing quit.
        with mock.patch.object(self.backend, "_sync_active", return_value=False):
            self.assertTrue(self.backend.status()["closed"])
        with mock.patch.object(self.backend, "_sync_active", return_value=True):
            self.assertFalse(self.backend.status()["closed"], "running this session")
        with mock.patch.object(backend_module, "run_bounded", return_value=completed) as run:
            self.backend.set_online(True)
        verbs = [call.args[0][2] for call in run.call_args_list]
        self.assertNotIn("enable", verbs, "online again does not re-enable autostart")
        self.assertEqual(verbs[-1], "start")
        with mock.patch.object(backend_module, "run_bounded", return_value=completed) as run:
            self.backend.settings({"start_at_login": True})
        self.assertEqual([call.args[0][2] for call in run.call_args_list], ["enable"])

    def test_open_chat_preserves_private_reading_and_settings_are_bounded(self) -> None:
        defaults = self.backend.settings()
        self.assertFalse(defaults["send_read_receipts"])
        self.assertTrue(defaults["show_unread_count"])
        self.assertEqual(defaults["dropdown_rows"], 7)
        self.assertEqual(defaults["composer_max_lines"], 6)
        self.assertFalse(defaults["check_updates_on_launch"])
        self.backend.settings({"check_updates_on_launch": True})
        self.assertTrue(self.backend.settings()["check_updates_on_launch"])
        with self.assertRaises(backend_module.OmaWhatsAppError):
            self.backend.settings({"check_updates_on_launch": "yes"})

        updated = self.backend.settings({
            "send_read_receipts": False,
            "show_unread_count": False,
            "dropdown_rows": 9,
            "composer_max_lines": 8,
        })
        self.assertFalse(updated["send_read_receipts"])
        self.assertFalse(updated["show_unread_count"])
        self.assertEqual(updated["dropdown_rows"], 9)
        self.assertEqual(updated["composer_max_lines"], 8)
        self.assertFalse(self.backend.settings()["send_read_receipts"])
        preferences = self.root / "state" / "preferences.json"
        self.assertEqual(preferences.stat().st_mode & 0o777, 0o600)

        reloaded = backend_module.Backend(
            store_dir=self.store, state_dir=self.root / "state", wacli=self.wacli
        )
        persisted = reloaded.settings()
        self.assertFalse(persisted["send_read_receipts"],
                         "an explicit choice in version 3 survives a reload")
        self.assertFalse(persisted["show_unread_count"])
        self.assertEqual(persisted["dropdown_rows"], 9)
        self.assertEqual(persisted["composer_max_lines"], 8)

        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "5, 7, or 9"):
            self.backend.settings({"dropdown_rows": 8})
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "4, 6, 8, or 10"):
            self.backend.settings({"composer_max_lines": 7})
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "not supported"):
            self.backend.settings({"surprise": True})

    def test_the_signature_is_off_by_default_and_needs_a_name(self) -> None:
        self.assertEqual(self.backend.settings()["signature"],
                         {"enabled": False, "name": "", "position": "top"})
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "Type the name"):
            self.backend.settings({"signature": {"enabled": True, "name": "   "}})
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "without \\*"):
            self.backend.settings({"signature": {"enabled": True, "name": "At*os"}})
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "top or the bottom"):
            self.backend.settings({"signature": {"position": "left"}})
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "unsupported value"):
            self.backend.settings({"signature": {"color": "red"}})
        updated = self.backend.settings({"signature": {"enabled": True, "name": "  Atos  "}})
        self.assertEqual(updated["signature"], {"enabled": True, "name": "Atos", "position": "top"})
        # A later change keeps what it does not mention.
        moved = self.backend.settings({"signature": {"position": "bottom"}})
        self.assertEqual(moved["signature"], {"enabled": True, "name": "Atos", "position": "bottom"})
        self.assertEqual(self.backend.status()["signature"]["name"], "Atos")
        reloaded = backend_module.Backend(
            store_dir=self.store, state_dir=self.root / "state", wacli=self.wacli)
        self.assertEqual(reloaded.settings()["signature"]["position"], "bottom")

    def test_time_format_is_global_persisted_and_survives_other_settings(self) -> None:
        self.assertEqual(self.backend.settings()["time_format"], "auto")
        for choice in ("12h", "24h", "auto"):
            self.assertEqual(self.backend.settings({"time_format": choice})["time_format"], choice)
            self.backend.settings({"show_unread_count": False})
            reloaded = backend_module.Backend(
                store_dir=self.store, state_dir=self.root / "state", wacli=self.wacli
            )
            self.assertEqual(reloaded.settings()["time_format"], choice)
        preferences = json.loads((self.root / "state" / "preferences.json").read_text())
        self.assertEqual(preferences["time_format"], "auto")
        self.assertFalse(any("time_format" in state for state in preferences["stores"].values()))

    def test_time_format_rejects_invalid_values_without_changing_preferences(self) -> None:
        self.backend.settings({"time_format": "24h"})
        for choice in ("13h", "", 12, False, None, [], {}):
            with self.subTest(choice=choice):
                with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "auto, 12h, or 24h"):
                    self.backend.settings({"time_format": choice})
                self.assertEqual(self.backend.settings()["time_format"], "24h")

    def test_missing_or_invalid_stored_time_format_defaults_to_system(self) -> None:
        for preferences in ({}, {"time_format": "invalid"}, {"time_format": []}):
            with self.subTest(preferences=preferences):
                self.backend._write_preferences(preferences)
                self.assertEqual(self.backend.settings()["time_format"], "auto")

    def test_selectable_option_is_bounded(self) -> None:
        completed = subprocess.CompletedProcess([], 0, '{"success":true}', "")
        with mock.patch.object(self.backend, "_write", return_value=completed) as write:
            self.backend.select_option("team@g.us", "t1", 2)
        command = write.call_args.args[0]
        self.assertEqual(command[command.index("--index") + 1], "2")
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "valid option"):
            self.backend.select_option("team@g.us", "t1", "not-a-number")

    def test_multi_file_send_validates_then_sends_every_file(self) -> None:
        completed = subprocess.CompletedProcess([], 0,
            '{"success":true,"data":{"id":"sent-media-id",'
            '"file":{"mime_type":"image/png","media":"image"}}}', "")
        with mock.patch.object(self.backend, "_write", return_value=completed) as write:
            result = self.backend.send_files(
                "team@g.us", [self.preview.as_uri(), str(self.document)], "review"
            )
        self.assertEqual(result["count"], 2)
        commands = [call.args[0] for call in write.call_args_list]
        self.assertEqual(len(commands), 2)
        self.assertEqual(result["album_id"], "")
        self.assertEqual(commands[0][commands[0].index("--caption") + 1], "review")
        self.assertNotIn("--caption", commands[1])

    def test_visual_batch_keeps_one_private_album_identity(self) -> None:
        responses = [
            subprocess.CompletedProcess([], 0,
                '{"success":true,"data":{"id":"photo-1",'
                '"file":{"mime_type":"image/png","media":"image"}}}', ""),
            subprocess.CompletedProcess([], 0,
                '{"success":true,"data":{"id":"photo-2",'
                '"file":{"mime_type":"image/jpeg","media":"image"}}}', ""),
        ]
        with mock.patch.object(self.backend, "_write", side_effect=responses):
            result = self.backend.send_files(
                "team@g.us", [self.preview.as_uri(), self.preview_two.as_uri()], "album"
            )
        self.assertRegex(result["album_id"], r"^[0-9a-f]{24}$")
        self.assertEqual([item["album_index"] for item in result["items"]], [0, 1])
        self.assertEqual({item["album_id"] for item in result["items"]},
                         {result["album_id"]})

        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.executemany(
                """INSERT INTO messages
                (chat_jid, chat_name, msg_id, sender_jid, sender_name, ts, from_me,
                 text, reaction_to_id, media_type, mime_type, local_path)
                VALUES (?, 'Design team', ?, 'me@s.whatsapp.net', '', ?, 1,
                        '', '', 'image', ?, '')""",
                [
                    ("team@g.us", "photo-1", 50, "image/png"),
                    ("team@g.us", "photo-2", 49, "image/jpeg"),
                ],
            )
        messages = {item["id"]: item
                    for item in self.backend.messages("team@g.us")["messages"]}
        self.assertEqual(messages["photo-1"]["album_id"], result["album_id"])
        self.assertEqual(messages["photo-2"]["album_count"], 2)
        self.assertEqual(messages["photo-2"]["local_path"], str(self.preview_two))

    def test_fresh_sent_media_keeps_its_local_preview(self) -> None:
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute(
                "UPDATE messages SET local_path = '' WHERE chat_jid = ? AND msg_id = ?",
                ["team@g.us", "t2"],
            )
        completed = subprocess.CompletedProcess([], 0,
            '{"success":true,"data":{"sent":true,"id":"t2",'
            '"file":{"name":"mock.png","mime_type":"image/png","media":"image"}}}', "")
        with mock.patch.object(self.backend, "_write", return_value=completed):
            result = self.backend.send_file("team@g.us", self.preview, "image/png")
        self.assertEqual(result["id"], "t2")
        message = next(item for item in self.backend.messages("team@g.us")["messages"]
                       if item["id"] == "t2")
        self.assertEqual(message["local_path"], str(self.preview))
        index_path = self.root / "state" / "sent-media.json"
        self.assertEqual(index_path.stat().st_mode & 0o777, 0o600)
        hint_text = index_path.read_text(encoding="utf-8")
        self.assertNotIn("caption", hint_text)
        self.assertNotIn("mockup", hint_text)

    def test_sent_media_hints_are_scoped_by_chat(self) -> None:
        self.backend._remember_sent_media("alex@s.whatsapp.net", "t2", self.document,
                                         "application/pdf", "document")
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute(
                "UPDATE messages SET local_path = '' WHERE chat_jid = ? AND msg_id = ?",
                ["team@g.us", "t2"],
            )
        message = next(item for item in self.backend.messages("team@g.us")["messages"]
                       if item["id"] == "t2")
        self.assertEqual(message["local_path"], "")

    def test_sent_reply_hints_are_scoped_by_chat(self) -> None:
        self.backend._remember_sent_reply("alex@s.whatsapp.net", "t2", "a1")
        message = next(item for item in self.backend.messages("team@g.us")["messages"]
                       if item["id"] == "t2")
        self.assertEqual(message["quoted_id"], "")

    def test_multi_file_send_rejects_remote_and_oversized_batches(self) -> None:
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "Only local"):
            self.backend.send_files("team@g.us", ["https://example.com/file.png"])
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "no more than"):
            self.backend.send_files("team@g.us", [str(self.preview)] * 11)

    def test_live_delegate_path_does_not_stop_sync(self) -> None:
        completed = subprocess.CompletedProcess([], 0, '{"success":true}', "")
        with mock.patch.object(self.backend, "_run", return_value=completed), \
             mock.patch.object(backend_module.subprocess, "run") as systemctl:
            self.backend._write(["--json", "send"], timeout=10)
        systemctl.assert_not_called()

    def test_child_output_is_streamed_under_hard_caps(self) -> None:
        for stream in ("stdout", "stderr"):
            with self.subTest(stream=stream), \
                 self.assertRaises(backend_module.ProcessOutputLimitExceeded):
                backend_module.run_bounded(
                    [sys.executable, "-c",
                     f"import sys; sys.{stream}.write('x' * 4097)"],
                    timeout=5, stdout_limit=4096, stderr_limit=4096,
                )

        completed = backend_module.run_bounded(
            [sys.executable, "-c",
             "import sys; sys.stdout.write('ok'); sys.stderr.write('note')"],
            timeout=5, stdout_limit=16, stderr_limit=16,
        )
        self.assertEqual(completed.stdout, "ok")
        self.assertEqual(completed.stderr, "note")

    def test_state_json_never_follows_predictable_symlinks(self) -> None:
        state = self.root / "state"
        state.mkdir()
        victim = self.root / "victim.json"
        victim.write_text('{"online":false}', encoding="utf-8")
        (state / "preferences.json").symlink_to(victim)

        self.assertTrue(self.backend.online())
        self.backend._update_account_state(
            lambda account_state: account_state.update({"online": False}))
        self.assertFalse((state / "preferences.json").is_symlink())
        self.assertEqual(victim.read_text(encoding="utf-8"), '{"online":false}')
        self.assertFalse(self.backend.online())

        media_victim = self.root / "media-victim.json"
        media_victim.write_text('{"foreign":{"local_path":"/etc/passwd"}}',
                                encoding="utf-8")
        (state / "sent-media.json").symlink_to(media_victim)
        self.assertEqual(self.backend._sent_media_hints(), {})

        reply_victim = self.root / "reply-victim.json"
        reply_victim.write_text('{"foreign":{"quoted_id":"private"}}',
                                encoding="utf-8")
        (state / "sent-replies.json").symlink_to(reply_victim)
        self.assertEqual(self.backend._sent_reply_hints(), {})
        self.backend._remember_sent_reply("team@g.us", "sent", "quoted")
        self.assertEqual(
            reply_victim.read_text(encoding="utf-8"),
            '{"foreign":{"quoted_id":"private"}}',
        )
        self.assertFalse((state / "sent-replies.json").is_symlink())
        self.assertEqual((state / "sent-replies.json").stat().st_mode & 0o777, 0o600)

    def test_state_locks_never_follow_predictable_symlinks(self) -> None:
        state = self.root / "state"
        state.mkdir()
        victim = self.root / "lock-victim"
        victim.write_text("unchanged", encoding="utf-8")
        (state / "preferences.lock").symlink_to(victim)
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "unsafe state path"):
            self.backend._update_preferences(lambda value: value.update({"online": False}))
        self.assertEqual(victim.read_text(encoding="utf-8"), "unchanged")

    def test_state_directory_itself_must_not_be_a_symlink(self) -> None:
        actual = self.root / "redirected-state"
        actual.mkdir()
        (self.root / "state").symlink_to(actual, target_is_directory=True)
        self.assertTrue(self.backend.online())
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "unsafe state path"):
            self.backend._update_preferences(lambda value: value.update({"online": False}))
        self.assertEqual(list(actual.iterdir()), [])

    def test_every_qml_text_surface_is_explicitly_plain(self) -> None:
        plugin = SCRIPT.parent.parent / "plugins" / "omawhatsapp"
        missing = []
        for path in sorted(plugin.glob("*.qml")):
            lines = path.read_text(encoding="utf-8").splitlines()
            for index, line in enumerate(lines):
                if line.strip() != "Text {":
                    continue
                next_line = lines[index + 1].strip() if index + 1 < len(lines) else ""
                if next_line != "textFormat: Text.PlainText":
                    missing.append(f"{path.name}:{index + 1}")
        self.assertEqual(missing, [])

    def test_the_chat_list_width_is_a_bounded_whole_number(self) -> None:
        self.assertEqual(self.backend.settings({"rail_width": 420})["rail_width"], 420)
        self.assertEqual(self.backend.status()["rail_width"], 420)
        for bad in (-1, 641, 300.5, "300", True):
            with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "unsupported value"):
                self.backend.settings({"rail_width": bad})
        self.assertEqual(self.backend.settings({"rail_width": 0})["rail_width"], 0,
                         "zero goes back to the automatic width")

    def test_fork_interface_preferences_default_validate_and_persist(self) -> None:
        defaults = self.backend.settings()
        self.assertEqual(
            {name: defaults[name] for name in backend_module.UI_PREFERENCES},
            {"read_on_reply": False, "show_online": False, "notify_reply": True, "enter_sends": True,
             "show_avatars": True, "auto_refresh_avatars": False,
             "rail_density": "comfortable", "rail_width": 0},
        )
        updated = self.backend.settings({
            "read_on_reply": False, "enter_sends": False,
            "show_avatars": False, "auto_refresh_avatars": False,
            "rail_density": "compact",
        })
        self.assertFalse(updated["read_on_reply"])
        self.assertEqual(updated["rail_density"], "compact")
        status = self.backend.status()
        self.assertFalse(status["enter_sends"])
        self.assertFalse(status["show_avatars"])
        self.assertEqual(status["rail_density"], "compact")
        for bad in ({"read_on_reply": "yes"}, {"rail_density": "tiny"},
                    {"enter_sends": 1}):
            with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "unsupported value"):
                self.backend.settings(bad)
        self.assertFalse(self.backend.settings()["read_on_reply"],
                         "a rejected update must not change the saved value")

    def test_media_mode_writes_one_drop_in_per_sync_unit_and_restarts_running_sync(self) -> None:
        units = self.root / "units"
        backend = backend_module.Backend(
            store_dir=self.store, state_dir=self.root / "state",
            wacli=self.wacli, unit_dir=units,
        )
        calls: list[list[str]] = []

        def systemctl(command, **_kwargs):
            calls.append(list(command))
            code = 0 if command[-2:] == ["--quiet", "wacli-sync.service"] else 0
            return subprocess.CompletedProcess(command, code, "", "")

        self.assertTrue(backend.auto_download_media())
        with mock.patch.object(backend_module, "run_bounded", side_effect=systemctl):
            off = backend.media_mode(False)
        self.assertFalse(off["auto_download_media"])
        for unit in ("wacli-sync.service", "wacli-sync@.service"):
            dropin = units / f"{unit}.d" / "10-omawhatsapp-media.conf"
            self.assertEqual(dropin.read_text(encoding="utf-8"),
                             backend_module.stamped(backend_module.MEDIA_DROPIN_OFF))
            self.assertIn("Environment=OMAW_MEDIA_FLAGS=\n", dropin.read_text(encoding="utf-8"))
        verbs = [call[2] for call in calls]
        self.assertIn("daemon-reload", verbs)
        self.assertIn("restart", verbs, "a running sync picks the change up")
        self.assertFalse(backend.status()["auto_download_media"])

        calls.clear()
        with mock.patch.object(backend_module, "run_bounded", side_effect=systemctl):
            on = backend.media_mode(True)
        self.assertTrue(on["auto_download_media"])
        self.assertFalse(any((units / f"{unit}.d" / "10-omawhatsapp-media.conf").exists()
                             for unit in ("wacli-sync.service", "wacli-sync@.service")))
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "on or off"):
            backend.media_mode("no")

    def test_sync_units_route_media_download_through_the_drop_in_variable(self) -> None:
        source = SCRIPT.parent.parent / "systemd" / "user"
        for unit in ("wacli-sync.service", "wacli-sync@.service"):
            text = (source / unit).read_text(encoding="utf-8")
            self.assertIn("Environment=OMAW_MEDIA_FLAGS=--download-media", text)
            exec_start = next(line for line in text.splitlines() if line.startswith("ExecStart="))
            self.assertIn(" $OMAW_MEDIA_FLAGS ", exec_start)
            self.assertNotIn("--download-media", exec_start)

    def test_about_reports_versions_install_mode_and_disk_use(self) -> None:
        self.wacli.write_text("#!/bin/sh\necho 'wacli 0.18.3'\n", encoding="utf-8")
        plugin = self.root / "plugin"
        plugin.mkdir()
        (plugin / "manifest.json").write_text('{"version": "0.14.0"}', encoding="utf-8")
        # omarchy plugin add leaves a git checkout.
        (plugin / ".git").mkdir()
        media = self.store / "media" / "chat" / "message"
        media.mkdir(parents=True)
        (media / "photo.jpg").write_bytes(b"x" * 1000)
        (self.store / "media" / "loop").symlink_to(self.store)
        about = self.backend.about(plugin_dir=plugin)
        self.assertEqual(about["app_version"], "0.14.0")
        self.assertEqual(about["install_mode"], "git")
        self.assertEqual(about["wacli_version"], "0.18.3")
        self.assertEqual(about["wacli_minimum_version"], "0.17.1")
        store = about["stores"][0]
        self.assertEqual(store["media_bytes"], 1000, "symlinks are not followed")
        self.assertEqual(store["media_files"], 1)
        self.assertGreater(store["database_bytes"], 0)

    def test_oversized_message_is_rejected(self) -> None:
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "too long"):
            self.backend.send("alex@s.whatsapp.net", "x" * 4097)

    def test_wacli_parity_registry_covers_every_0183_leaf(self) -> None:
        policies = backend_module.WACLI_OPERATION_POLICIES
        self.assertEqual(len(policies), 108)
        # Presence and starring exist only in the wacli fork's builds; the
        # parity check accepts their absence on official releases.
        self.assertEqual(backend_module.WACLI_OPTIONAL_LEAVES, {
            ("messages", "star"),
            ("presence", "available"), ("presence", "subscribe"), ("presence", "unavailable")})
        self.assertTrue(backend_module.WACLI_OPTIONAL_LEAVES <= set(policies))
        self.assertEqual(policies[("presence", "subscribe")], "remote-read")
        self.assertEqual(policies[("groups", "participants", "list")], "local-read")
        self.assertIn(("groups", "participants", "list"),
                      backend_module.WACLI_GROUP_JID_OPERATIONS)
        leaf_minimums = backend_module.WACLI_LEAF_MINIMUM_VERSIONS
        self.assertEqual(leaf_minimums[("groups", "participants", "list")], "0.18.0")
        self.assertTrue(set(leaf_minimums) <= set(policies))
        self.assertEqual(len(set(policies)), len(policies))
        self.assertEqual(set(policies.values()), {
            "local-read", "remote-read", "local-write", "sync",
            "whatsapp-write", "destructive", "interactive",
        })
        capabilities = self.backend.capabilities()
        self.assertEqual(capabilities["wacli_parity_version"], "0.19.0")
        self.assertEqual(capabilities["wacli_minimum_version"], "0.17.1")
        self.assertEqual(capabilities["operation_count"], len(policies))
        self.assertEqual(len(capabilities["operations"]), len(policies))
        by_name = {item["operation"]: item for item in capabilities["operations"]}
        self.assertEqual(by_name["groups participants list"]["min_wacli"], "0.18.0")
        self.assertEqual(by_name["send text"]["min_wacli"], "0.17.1")

    def test_wacli_local_read_is_json_and_read_only(self) -> None:
        completed = subprocess.CompletedProcess(
            [], 0, '{"success":true,"data":{"version":"test"}}', ""
        )
        with mock.patch.object(self.backend, "_run", return_value=completed) as run:
            result = self.backend.transport({"args": ["version"]})
        command = run.call_args.args[0]
        self.assertIn("--read-only", command)
        self.assertIn("--json", command)
        self.assertEqual(command[-1], "version")
        self.assertEqual(result["data"], {"version": "test"})
        self.assertEqual(result["policy"], "local-read")

    def test_wacli_remote_read_requires_exact_authorization(self) -> None:
        completed = subprocess.CompletedProcess([], 0, '{"success":true,"data":[]}', "")
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "remote-read"):
            self.backend.transport({"args": ["channels", "list"]})
        with mock.patch.object(self.backend, "_mutate", return_value=completed) as mutate:
            result = self.backend.transport({
                "args": ["channels", "list"],
                "authorization": "remote-read",
            })
        self.assertEqual(result["policy"], "remote-read")
        self.assertTrue(mutate.call_args.kwargs["require_online"])

    def test_wacli_whatsapp_write_requires_exact_authorization(self) -> None:
        request = {"args": ["send", "location", "--to", "team@g.us",
                            "--latitude", "1", "--longitude", "2"]}
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "whatsapp-write"):
            self.backend.transport(request)
        completed = subprocess.CompletedProcess([], 0, '{"success":true,"data":{}}', "")
        with mock.patch.object(self.backend, "_mutate", return_value=completed) as mutate:
            request["authorization"] = "whatsapp-write"
            result = self.backend.transport(request)
        self.assertEqual(result["operation"], "send location")
        self.assertTrue(mutate.call_args.kwargs["require_online"])

    def test_wacli_chat_writes_reject_names_and_picks_before_transport(self) -> None:
        for args in (
            ["send", "text", "--to", "Design team", "--message", "hello"],
            ["send", "text", "--to", "team@g.us", "--pick", "1",
             "--message", "hello"],
        ):
            with self.subTest(args=args), mock.patch.object(self.backend, "_mutate") as mutate, \
                 self.assertRaises(backend_module.OmaWhatsAppError):
                self.backend.transport({
                    "args": args,
                    "authorization": "whatsapp-write",
                })
            mutate.assert_not_called()

    def test_wacli_local_destructive_operation_stays_offline_capable(self) -> None:
        completed = subprocess.CompletedProcess([], 0, '{"success":true,"data":{}}', "")
        with mock.patch.object(self.backend, "_mutate", return_value=completed) as mutate:
            result = self.backend.transport({
                "args": ["store", "cleanup", "--days", "365", "--confirm"],
                "authorization": "destructive",
            })
        self.assertEqual(result["policy"], "destructive")
        self.assertFalse(mutate.call_args.kwargs["require_online"])

    def test_wacli_dry_runs_are_downgraded_to_local_reads(self) -> None:
        completed = subprocess.CompletedProcess([], 0, '{"success":true,"data":{}}', "")
        cases = [
            ["history", "fill", "--dry-run"],
            ["messages", "purge", "--chat", "team@g.us", "--id", "t1", "--dry-run"],
            ["store", "cleanup", "--dry-run"],
        ]
        for args in cases:
            with self.subTest(args=args), \
                 mock.patch.object(self.backend, "_run", return_value=completed) as run:
                result = self.backend.transport({"args": args})
            self.assertEqual(result["policy"], "local-read")
            self.assertIn("--read-only", run.call_args.args[0])

    def test_false_boolean_flags_never_downgrade_authorization(self) -> None:
        cases = [
            (["accounts", "add", "secondary", "--no-auth=false"], "interactive"),
            (["doctor", "--connect=false"], "local-read"),
            (["history", "fill", "--chat", "team@g.us", "--dry-run=false"],
             "sync"),
            (["messages", "purge", "--chat", "team@g.us", "--id", "t1",
              "--dry-run=false"], "destructive"),
            (["store", "cleanup", "--dry-run=false"], "destructive"),
        ]
        for args, expected in cases:
            with self.subTest(args=args):
                self.assertEqual(self.backend._transport_policy(args), expected)

        with mock.patch.object(self.backend, "_mutate") as mutate, \
                self.assertRaisesRegex(
                    backend_module.OmaWhatsAppError, "needs a terminal"
                ):
            self.backend.transport({
                "args": ["accounts", "add", "secondary", "--no-auth=false"],
                "authorization": "local-write",
            })
        mutate.assert_not_called()
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "true or false"):
            self.backend._transport_policy([
                "accounts", "add", "secondary", "--no-auth=sometimes"
            ])

    def test_wacli_global_flags_cannot_bypass_request_contract(self) -> None:
        for args in (["--store", "/tmp/other", "version"],
                     ["version", "--read-only=false"],
                     ["send", "text", "--json"]):
            with self.subTest(args=args), \
                 self.assertRaisesRegex(backend_module.OmaWhatsAppError,
                                         "global options"):
                self.backend.transport({"args": args})

    def test_wacli_unknown_and_interactive_operations_fail_closed(self) -> None:
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "parity registry"):
            self.backend.transport({"args": ["future-command", "go"]})
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "needs a terminal"):
            self.backend.transport({"args": ["auth"], "authorization": "interactive"})

    def test_wacli_interactive_mode_is_limited_and_exact(self) -> None:
        completed = subprocess.CompletedProcess([], 0, "", "")

        def authenticate(*args, **kwargs):
            (self.store / "session.db").write_bytes(b"synthetic-session")
            return completed

        with mock.patch.object(self.backend, "_unit_active", return_value=False), \
             mock.patch.object(
                 self.backend, "_systemctl_user", return_value=completed
             ) as systemctl, \
             mock.patch.object(
                 backend_module.subprocess, "run", side_effect=authenticate
             ) as run:
            code = self.backend.transport_interactive(
                ["auth", "--qr-format", "terminal"], authorization="interactive"
            )
        self.assertEqual(code, 0)
        self.assertEqual(run.call_args.args[0], [
            str(self.wacli), "--store", str(self.store.resolve()),
            "auth", "--qr-format", "terminal"
        ])
        systemctl.assert_called_once_with([
            "enable", "--now", "wacli-sync.service"
        ])
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError,
                                    "only for linking"):
            self.backend.transport_interactive(
                ["send", "text"], authorization="whatsapp-write"
            )

    def test_one_off_store_auth_validates_session_without_managing_a_unit(self) -> None:
        one_off = self.root / "one-off"
        one_off.mkdir()
        completed = subprocess.CompletedProcess([], 0, "", "")

        def authenticate(*args, **kwargs):
            (one_off / "session.db").write_bytes(b"synthetic-session")
            return completed

        with mock.patch.object(backend_module, "HOME", self.root), \
                mock.patch.object(
                backend_module.subprocess, "run", side_effect=authenticate
        ) as run, mock.patch.object(
                self.backend, "_systemctl_user"
        ) as systemctl:
            result = self.backend.transport_interactive(
                ["auth"], authorization="interactive", store=str(one_off)
            )
        self.assertEqual(result, 0)
        self.assertEqual(run.call_args.args[0][:3], [
            str(self.wacli), "--store", str(one_off.resolve()),
        ])
        systemctl.assert_not_called()

    def test_wacli_interactive_cli_parser_preserves_command(self) -> None:
        args = backend_module.parser().parse_args([
            "wacli", "--interactive", "--authorize", "interactive", "--",
            "auth", "--qr-format", "terminal",
        ])
        self.assertTrue(args.interactive)
        self.assertEqual(args.authorize, "interactive")
        self.assertEqual(args.transport_args, [
            "--", "auth", "--qr-format", "terminal",
        ])

    def test_wacli_cli_gateway_runs_end_to_end_with_json(self) -> None:
        self.wacli.write_text(
            "#!/bin/sh\nprintf '%s\\n' "
            "'{\"success\":true,\"data\":{\"version\":\"fixture\"}}'\n",
            encoding="utf-8",
        )
        self.wacli.chmod(0o700)
        environment = dict(os.environ)
        environment.update({
            "WACLI_BIN": str(self.wacli),
            "WACLI_STORE_DIR": str(self.store),
            "XDG_STATE_HOME": str(self.root / "state-home"),
        })
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "wacli"],
            input=json.dumps({"args": ["version"]}),
            text=True,
            capture_output=True,
            env=environment,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        value = json.loads(result.stdout)
        self.assertTrue(value["ok"])
        self.assertEqual(value["operation"], "version")
        self.assertEqual(value["data"], {"version": "fixture"})

    def test_entrypoint_stays_usable_during_companion_module_recovery(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            helper = Path(temporary) / "omawhatsapp"
            helper.write_bytes(SCRIPT.with_name("omawhatsapp").read_bytes())
            helper.chmod(0o755)
            (Path(temporary) / SCRIPT.name).write_bytes(SCRIPT.read_bytes())
            result = subprocess.run(
                [str(helper), "capabilities"], text=True, capture_output=True,
                check=False, env=dict(os.environ, XDG_CACHE_HOME=str(Path(temporary) / "cache")),
            )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(json.loads(result.stdout)["ok"])

    def test_the_launcher_reuses_compiled_code_outside_the_bin_folder(self) -> None:
        # The owner found sending slow: every call recompiled the whole helper
        # (about 0.2 s) before doing anything. The launcher imports it as a
        # module so Python caches the bytecode, in the user cache folder.
        with tempfile.TemporaryDirectory() as temporary:
            bin_dir = Path(temporary) / "bin"
            bin_dir.mkdir()
            launcher = bin_dir / "omawhatsapp"
            launcher.write_bytes(SCRIPT.with_name("omawhatsapp").read_bytes())
            launcher.chmod(0o755)
            (bin_dir / SCRIPT.name).write_bytes(SCRIPT.read_bytes())
            cache = Path(temporary) / "cache"
            environment = dict(os.environ, XDG_CACHE_HOME=str(cache))
            environment.pop("PYTHONDONTWRITEBYTECODE", None)
            for _ in range(2):
                result = subprocess.run([str(launcher), "capabilities"], text=True,
                                        capture_output=True, check=False, env=environment)
                self.assertEqual(result.returncode, 0, result.stderr)
            compiled = list((cache / "omawhatsapp" / "pycache").rglob("omawhatsapp_core*.pyc"))
            self.assertEqual(len(compiled), 1, "the module's bytecode is cached once")
            self.assertFalse((bin_dir / "__pycache__").exists(), "nothing is written beside the helper")


    def test_a_person_chat_wacli_turned_unknown_stays_in_the_rail(self) -> None:
        # Found after sending a poll: wacli 0.18.3 filed it under the phone chat
        # but took kind and name from the @lid, so the chat became 'unknown',
        # got the push name instead of the saved one, and left the rail.
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute("INSERT INTO chats VALUES "
                               "('member@s.whatsapp.net', 'unknown', 'Sam push name', 60, 0, 0, 0, 0, 0)")
            connection.execute("INSERT INTO chats VALUES "
                               "('99887766@lid', 'unknown', 'Sam push name', 59, 0, 0, 0, 0, 0)")
        self._insert("member@s.whatsapp.net", "poll1", 60, from_me=1, text="Poll: Day?")
        rail = {chat["jid"]: chat for chat in self.backend.chats()["chats"]}
        self.assertIn("member@s.whatsapp.net", rail)
        self.assertEqual(rail["member@s.whatsapp.net"]["kind"], "dm")
        self.assertEqual(rail["member@s.whatsapp.net"]["name"], "Sam Rivera",
                         "the name saved on the phone, not the push name")
        self.assertNotIn("99887766@lid", rail, "a hidden @lid chat is still not a rail row")
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute("INSERT INTO chats VALUES "
                               "('bare@s.whatsapp.net', 'unknown', '', 0, 0, 0, 0, 0, 0)")
        self.assertNotIn("bare@s.whatsapp.net",
                         {chat["jid"] for chat in self.backend.chats()["chats"]},
                         "a bare row wacli left after a mark-read is not a conversation")
        self.assertNotIn("legacy@newsletter", rail)
        self.assertEqual(self.backend._chat("member@s.whatsapp.net")["kind"], "dm")
        self.assertEqual(self.backend._chat_any("member@s.whatsapp.net")["kind"], "dm")
        person = next(p for p in self.backend.contacts_search("Sam")["people"]
                      if p["jid"] == "member@s.whatsapp.net")
        self.assertTrue(person["has_chat"])
        self.assertEqual(person["name"], "Sam Rivera")

    def test_a_file_under_tmp_is_sent_from_a_copy_the_sync_service_sees(self) -> None:
        # Found sending a file from /tmp: the delegated send is opened by
        # wacli-sync.service, whose PrivateTmp hides the user's /tmp.
        seen: dict[str, object] = {}

        def write(command: list[str], *, timeout: float) -> subprocess.CompletedProcess[str]:
            sent = Path(command[command.index("--file") + 1])
            seen.update(path=sent, exists=sent.is_file(), content=sent.read_bytes())
            return subprocess.CompletedProcess([], 0, '{"success":true,"data":{"id":"F1"}}', "")

        self.assertTrue(str(self.document.resolve()).startswith(("/tmp/", "/var/tmp/")),
                        "the fixture lives in the system temporary directory")
        with mock.patch.object(self.backend, "_write", side_effect=write) as call:
            result = self.backend.send_file("alex@s.whatsapp.net", self.document,
                                            "application/pdf")
        command = call.call_args.args[0]
        sent = seen["path"]
        self.assertTrue(seen["exists"])
        self.assertEqual(seen["content"], b"pdf")
        self.assertNotEqual(sent, self.document)
        self.assertEqual(sent.parent, self.backend.state_dir / "outgoing",
                         "the helper's own folder, which the service can read")
        self.assertEqual(command[command.index("--filename") + 1], "notes.pdf",
                         "the contact still sees the original name")
        self.assertFalse(sent.exists(), "the private copy is removed after the send")
        self.assertEqual(result["local_path"], str(self.document))

    def test_a_file_outside_tmp_is_sent_as_it_is(self) -> None:
        home_file = Path(self.backend.state_dir) / "home-file.pdf"
        home_file.parent.mkdir(parents=True, exist_ok=True)
        home_file.write_bytes(b"pdf")
        with mock.patch.object(self.backend, "PRIVATE_TMP_ROOTS", (Path("/nonexistent"),)), \
                mock.patch.object(self.backend, "_write", return_value=subprocess.CompletedProcess(
                    [], 0, '{"success":true,"data":{"id":"F2"}}', "")) as call:
            self.backend.send_file("alex@s.whatsapp.net", home_file, "application/pdf")
        command = call.call_args.args[0]
        self.assertEqual(command[command.index("--file") + 1], str(home_file))

    def _add_poll_tables(self) -> None:
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.executescript("""
                CREATE TABLE polls (chat_jid TEXT NOT NULL, msg_id TEXT NOT NULL, sender_jid TEXT,
                  question TEXT NOT NULL, options_json TEXT NOT NULL,
                  selectable_count INTEGER NOT NULL DEFAULT 1, created_ts INTEGER NOT NULL,
                  PRIMARY KEY (chat_jid, msg_id));
                CREATE TABLE poll_votes (chat_jid TEXT NOT NULL, poll_msg_id TEXT NOT NULL,
                  voter_jid TEXT NOT NULL, vote_msg_id TEXT NOT NULL,
                  selected_options_json TEXT NOT NULL, ts INTEGER NOT NULL,
                  PRIMARY KEY (chat_jid, poll_msg_id, voter_jid));""")

    def test_a_poll_carries_its_options_votes_and_voters(self) -> None:
        # The owner saw a poll as the text "Poll: …" and his vote as a bubble.
        self._add_poll_tables()
        self._insert("team@g.us", "poll1", 50, from_me=1, text="Poll: Which day?")
        self._insert("team@g.us", "vote1", 51, from_me=1, text="Voted: Monday")
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute("INSERT INTO polls VALUES ('team@g.us', 'poll1', '', 'Which day?', "
                               "'[\"Monday\", \"Tuesday\"]', 1, 50)")
            connection.executemany("INSERT INTO poll_votes VALUES ('team@g.us', 'poll1', ?, ?, ?, ?)", [
                ("me@s.whatsapp.net", "vote1", '["Monday"]', 51),
                ("member@s.whatsapp.net", "v2", '["Monday"]', 52),
                ("admin@s.whatsapp.net", "v3", '["Tuesday"]', 53)])
        with mock.patch.object(self.backend, "_own_jid", return_value="me@s.whatsapp.net"):
            rows = {row["id"]: row for row in self.backend.messages("team@g.us")["messages"]}
        self.assertNotIn("vote1", rows, "a vote shows inside its poll, not as a bubble")
        poll = rows["poll1"]["poll"]
        self.assertEqual(rows["poll1"]["text"], "")
        self.assertEqual(poll["question"], "Which day?")
        self.assertEqual(poll["voters"], 3)
        monday, tuesday = poll["options"]
        self.assertEqual((monday["text"], monday["votes"], monday["mine"]), ("Monday", 2, True))
        self.assertEqual(monday["voters"], ["You", "Sam Rivera"])
        self.assertEqual((tuesday["votes"], tuesday["voters"]), (1, ["Alex Kim"]))
        rail = {chat["jid"]: chat for chat in self.backend.chats()["chats"]}
        self.assertEqual(rail["team@g.us"]["preview"], "Poll: Which day?",
                         "the rail preview skips the vote row")

    def test_a_message_deleted_for_everyone_stays_as_a_placeholder(self) -> None:
        self._insert("alex@s.whatsapp.net", "gone", 50, from_me=1, text="secret words")
        self._insert("alex@s.whatsapp.net", "mine-only", 49, from_me=0, text="local delete")
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute("UPDATE messages SET revoked = 1, deleted_at = 60, "
                               "deletion_reason = 'whatsapp-revoke' WHERE msg_id = 'gone'")
            connection.execute("UPDATE messages SET deleted_for_me = 1, deleted_at = 60, "
                               "deletion_reason = 'whatsapp-delete-for-me' WHERE msg_id = 'mine-only'")
        rows = {row["id"]: row for row in self.backend.messages("alex@s.whatsapp.net")["messages"]}
        self.assertTrue(rows["gone"]["revoked"])
        self.assertEqual(rows["gone"]["text"], "", "the old words never reach the app")
        self.assertNotIn("mine-only", rows, "deleted on your devices is gone")
        searched = self.backend.messages("alex@s.whatsapp.net", "secret")["messages"]
        self.assertEqual(searched, [], "a search never finds what was deleted")
        rail = {chat["jid"]: chat for chat in self.backend.chats()["chats"]}
        self.assertEqual(rail["alex@s.whatsapp.net"]["preview"], "You deleted this message")

    def test_a_poll_vote_checks_the_options_and_sends_them_exactly(self) -> None:
        self._add_poll_tables()
        self._insert("team@g.us", "poll1", 50, from_me=0, text="Poll: Which day?")
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute("INSERT INTO polls VALUES ('team@g.us', 'poll1', '', 'Which day?', "
                               "'[\"Monday\", \"Tuesday\"]', 1, 50)")
        completed = subprocess.CompletedProcess([], 0, '{"success":true}', "")
        with mock.patch.object(self.backend, "_write", return_value=completed) as write:
            self.assertEqual(self.backend.vote_poll("team@g.us", "poll1", ["Tuesday"])["options"],
                             ["Tuesday"])
        command = write.call_args.args[0]
        self.assertEqual(command[1:3], ["poll", "vote"])
        self.assertEqual(command[command.index("--option") + 1], "Tuesday")
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "not in this poll"):
            self.backend.vote_poll("team@g.us", "poll1", ["Friday"])
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "fewer choices"):
            self.backend.vote_poll("team@g.us", "poll1", ["Monday", "Tuesday"])
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "not a poll"):
            self.backend.vote_poll("team@g.us", "t1", ["Monday"])

    def _add_status_table(self) -> None:
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute("""CREATE TABLE status_messages (
                rowid INTEGER PRIMARY KEY AUTOINCREMENT, msg_id TEXT NOT NULL UNIQUE,
                ts INTEGER NOT NULL, from_me INTEGER NOT NULL, sender_jid TEXT, sender_name TEXT,
                text TEXT, media_type TEXT, media_caption TEXT, filename TEXT, mime_type TEXT,
                direct_path TEXT, media_key BLOB, file_sha256 BLOB, file_enc_sha256 BLOB,
                file_length INTEGER, background_color TEXT, font INTEGER)""")
            now = int(time.time())
            connection.executemany(
                "INSERT INTO status_messages (msg_id, ts, from_me, sender_jid, sender_name, text) "
                "VALUES (?, ?, ?, ?, ?, ?)", [
                    ("mine", now - 60, 1, "", "", "On holiday until the 10th"),
                    ("sam", now - 120, 0, "member@s.whatsapp.net", "sam push", "New tools"),
                    ("old", now - 2 * 86400, 0, "member@s.whatsapp.net", "", "Expired")])

    def test_statuses_of_the_last_day_with_saved_names(self) -> None:
        self._add_status_table()
        statuses = self.backend.statuses()["statuses"]
        self.assertEqual([item["id"] for item in statuses], ["mine", "sam"],
                         "newest first, and a status older than a day is gone")
        self.assertEqual(statuses[1]["sender"], "Sam Rivera", "the name saved on the phone")
        self.assertEqual(statuses[0]["sender"], "You")
        self.assertEqual([item["id"] for item in self.backend.statuses(True)["statuses"]], ["mine"])

    def test_only_your_own_status_can_be_deleted_and_by_id(self) -> None:
        self._add_status_table()
        completed = subprocess.CompletedProcess([], 0, '{"success":true,"data":{"revoked":true}}', "")
        with mock.patch.object(self.backend, "_write", return_value=completed) as write:
            self.assertEqual(self.backend.delete_status("mine")["id"], "mine")
        command = write.call_args.args[0]
        self.assertEqual(command[1:3], ["messages", "revoke"])
        self.assertEqual(command[command.index("--chat") + 1], "status@broadcast")
        self.assertEqual(command[command.index("--id") + 1], "mine")
        for other in ("sam", "unknown"):
            with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "your own"):
                self.backend.delete_status(other)

    def test_statuses_on_a_mirror_without_them(self) -> None:
        self.assertEqual(self.backend.statuses()["statuses"], [])
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "your own"):
            self.backend.delete_status("mine")

    def test_a_shared_contact_becomes_a_card_with_the_known_person(self) -> None:
        # The owner shared a contact and saw "Contact: Name (+55 ...)" as text.
        self._insert("alex@s.whatsapp.net", "c1", 50, from_me=1,
                     display="Contact: Sam Rivera (+1 555 123-4567)")
        self._insert("alex@s.whatsapp.net", "c2", 51, from_me=0,
                     display="Contacts:\nContact: Ana (+55 16 99999-0000)\nContact: Bo")
        self._insert("alex@s.whatsapp.net", "t9", 52, from_me=0, text="Contact: me later, ok?")
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute("UPDATE contacts SET phone = '15551234567' "
                               "WHERE jid = 'member@s.whatsapp.net'")
            connection.execute("INSERT INTO contacts (jid, phone) VALUES "
                               "('15551234567@s.whatsapp.net', '15551234567')")
        rows = {row["id"]: row for row in self.backend.messages("alex@s.whatsapp.net")["messages"]}
        card = rows["c1"]["contacts"][0]
        self.assertEqual((card["name"], card["phone"], card["digits"]),
                         ("Sam Rivera", "+1 555 123-4567", "15551234567"))
        self.assertEqual(card["jid"], "15551234567@s.whatsapp.net")
        self.assertEqual([item["name"] for item in rows["c2"]["contacts"]], ["Ana", "Bo"])
        self.assertEqual(rows["c2"]["contacts"][1]["phone"], "")
        self.assertNotIn("contacts", rows["t9"], "ordinary words are not a card")
        rail = {chat["jid"]: chat for chat in self.backend.chats()["chats"]}
        self.assertEqual(rail["alex@s.whatsapp.net"]["preview"], "Contact: me later, ok?")
        self._insert("alex@s.whatsapp.net", "c3", 53, from_me=1, display="Contact: Sam (+1 555 1234567)")
        rail = {chat["jid"]: chat for chat in self.backend.chats()["chats"]}
        self.assertEqual(rail["alex@s.whatsapp.net"]["preview"], "👤 Sam")

    def test_a_group_is_created_only_with_known_people(self) -> None:
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute("INSERT INTO contacts (jid, phone) VALUES "
                               "('15551234567@s.whatsapp.net', '15551234567')")
        completed = subprocess.CompletedProcess(
            [], 0, '{"success":true,"data":{"JID":"new@g.us"}}', "")
        with mock.patch.object(self.backend, "_write", return_value=completed) as write:
            result = self.backend.create_group("  Obra   Sorriso ", ["15551234567@s.whatsapp.net"])
        self.assertEqual(result["jid"], "new@g.us")
        command = write.call_args.args[0]
        self.assertEqual(command[command.index("--name") + 1], "Obra Sorriso")
        self.assertEqual(command[command.index("--user") + 1], "15551234567@s.whatsapp.net")
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "your WhatsApp contacts"):
            self.backend.create_group("Obra", ["19990000000@s.whatsapp.net"])
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "1 to 256"):
            self.backend.create_group("Obra", [])
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "1 to 100"):
            self.backend.create_group("   ", ["15551234567@s.whatsapp.net"])

    def test_joining_a_group_takes_a_link_or_a_code(self) -> None:
        completed = subprocess.CompletedProcess(
            [], 0, '{"success":true,"data":{"jid":"g@g.us","joined":true}}', "")
        for invite in ("https://chat.whatsapp.com/AbCdEfGhIjKlMnOpQr12",
                       "chat.whatsapp.com/invite/AbCdEfGhIjKlMnOpQr12/", "AbCdEfGhIjKlMnOpQr12"):
            with mock.patch.object(self.backend, "_write", return_value=completed) as write:
                self.assertEqual(self.backend.join_group(invite)["jid"], "g@g.us")
            command = write.call_args.args[0]
            self.assertEqual(command[command.index("--code") + 1], "AbCdEfGhIjKlMnOpQr12")
        for bad in ("hello", "https://evil.example/AbCdEfGhIjKlMnOpQr12", ""):
            with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "invite link"):
                self.backend.join_group(bad)

    def test_a_chat_exports_as_readable_text_like_the_phone(self) -> None:
        self._insert("alex@s.whatsapp.net", "a2", 41, from_me=0, text="*see* you")
        self._insert("alex@s.whatsapp.net", "a3", 42, from_me=1, text="gone")
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute("UPDATE messages SET revoked = 1, deleted_at = 50, "
                               "deletion_reason = 'whatsapp-revoke' WHERE msg_id = 'a3'")
        home = self.root / "home"
        (home / "Documents").mkdir(parents=True)
        destination = home / "Documents" / "alex.txt"
        with mock.patch.object(backend_module, "HOME", home):
            result = self.backend.export_chat("alex@s.whatsapp.net", str(destination))
            self.assertEqual(result["messages"], 3)
            lines = destination.read_text(encoding="utf-8").splitlines()
            self.assertEqual(lines[0], "WhatsApp chat with Alex")
            self.assertTrue(lines[1].endswith(" - You: hello"))
            self.assertTrue(lines[2].endswith(": *see* you"), "markers stay, as the phone exports them")
            self.assertTrue(lines[3].endswith(" - You: This message was deleted"))
            self.assertEqual(destination.stat().st_mode & 0o777, 0o600)
            (home / "code" / ".git").mkdir(parents=True)
            with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "code repository"):
                self.backend.export_chat("alex@s.whatsapp.net", str(home / "code" / "x.txt"))
            with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "home folder"):
                self.backend.export_chat("alex@s.whatsapp.net", str(self.root / "outside.txt"))
            destination.write_text("mine", encoding="utf-8")
            with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "already there"):
                self.backend.export_chat("alex@s.whatsapp.net", str(destination))
            self.assertEqual(destination.read_text(encoding="utf-8"), "mine")
            self.backend.export_chat("alex@s.whatsapp.net", str(destination), replace=True)
            self.assertTrue(destination.read_text(encoding="utf-8").startswith("WhatsApp chat with"))

    def test_pending_attachments_download_beside_sync_and_count_expired(self) -> None:
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.executemany(
                """INSERT INTO messages (chat_jid, chat_name, msg_id, sender_jid, sender_name, ts,
                   from_me, text, media_type, mime_type, filename, local_path, media_unavailable_at)
                   VALUES ('alex@s.whatsapp.net', 'Alex', ?, 'alex@s.whatsapp.net', 'Alex', ?, 0,
                   '', 'document', 'application/pdf', ?, '', ?)""",
                [("d1", 50, "a.pdf", None), ("d2", 51, "b.pdf", None), ("d3", 52, "c.pdf", 60)])
        def fake(jid: str, message_id: str) -> dict:
            if message_id == "d2":
                raise backend_module.OmaWhatsAppError("download failed with status code 403")
            return {"ok": True, "local_path": "/private/a.pdf"}
        with mock.patch.object(self.backend, "download_media", side_effect=fake) as download:
            result = self.backend.download_pending("alex@s.whatsapp.net")
        self.assertEqual((result["downloaded"], result["expired"], result["failed"]), (1, 2, 0))
        self.assertEqual(sorted(call.args[1] for call in download.call_args_list), ["d1", "d2"])
        details = self.backend.chat_details("alex@s.whatsapp.net")
        self.assertEqual(details["counts"]["missing"], 2, "d3 expired on the server is not pending")

    def test_an_attachment_expired_on_the_server_is_remembered(self) -> None:
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute(
                """INSERT INTO messages (chat_jid, chat_name, msg_id, sender_jid, sender_name, ts,
                   from_me, text, media_type, mime_type, filename, local_path)
                   VALUES ('alex@s.whatsapp.net', 'Alex', 'old1', 'alex@s.whatsapp.net', 'Alex', 50,
                   0, '', 'image', 'image/jpeg', 'x.jpg', '')""")
        self.assertEqual(self.backend.chat_details("alex@s.whatsapp.net")["counts"]["missing"], 1)
        with mock.patch.object(self.backend, "_fetch_media_file", side_effect=backend_module.OmaWhatsAppError(
                "download failed with status code 403")) as fetch:
            with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "no longer available"):
                self.backend.download_media("alex@s.whatsapp.net", "old1")
            with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "no longer available"):
                self.backend.download_media("alex@s.whatsapp.net", "old1")
        self.assertEqual(fetch.call_count, 1, "a known expired file is not asked for again")
        self.assertEqual(self.backend.chat_details("alex@s.whatsapp.net")["counts"]["missing"], 0)
        row = next(m for m in self.backend.messages("alex@s.whatsapp.net")["messages"] if m["id"] == "old1")
        self.assertTrue(row["media_unavailable"], "the bubble says it is gone")

    def test_contact_alias_and_tags_are_local_writes_for_known_people(self) -> None:
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute("INSERT INTO contacts (jid, phone) VALUES "
                               "('15551234567@s.whatsapp.net', '15551234567')")
        completed = subprocess.CompletedProcess([], 0, '{"success":true}', "")
        person = "15551234567@s.whatsapp.net"
        with mock.patch.object(self.backend, "_mutate", return_value=completed) as mutate:
            self.backend.contact_alias(person, "  Mechanic   Joao ")
            self.backend.contact_alias(person, "")
            self.backend.contact_tag(person, " suppliers ")
            self.backend.contact_tag(person, "suppliers", remove=True)
        commands = [call.args[0] for call in mutate.call_args_list]
        self.assertEqual(commands[0][-2:], ["--alias", "Mechanic Joao"])
        self.assertEqual(commands[1][1:4], ["contacts", "alias", "rm"])
        self.assertEqual(commands[2][1:4], ["contacts", "tags", "add"])
        self.assertEqual(commands[3][1:4], ["contacts", "tags", "rm"])
        self.assertTrue(all(call.kwargs["require_online"] is False for call in mutate.call_args_list),
                        "local metadata works offline")
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "your WhatsApp contacts"):
            self.backend.contact_alias("19990000000@s.whatsapp.net", "x")

    def test_a_contact_profile_is_an_explicit_remote_read(self) -> None:
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute("INSERT INTO contacts (jid, phone) VALUES "
                               "('15551234567@s.whatsapp.net', '15551234567')")
        person = "15551234567@s.whatsapp.net"
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "remote-read"):
            self.backend.contact_profile(person)
        answers = iter([
            subprocess.CompletedProcess([], 0, '{"success":true,"data":{"about":"Busy"}}', ""),
            subprocess.CompletedProcess([], 0, '{"success":true,"data":{"jid":"x","address":"Main st",'
                                               '"email":"","website":["https://x.example"]}}', "")])
        with mock.patch.object(self.backend, "_mutate", side_effect=lambda *a, **k: next(answers)):
            profile = self.backend.contact_profile(person, "remote-read")
        self.assertEqual(profile["about"], "Busy")
        self.assertEqual(profile["business"], {"address": "Main st", "website": ["https://x.example"]})

    def test_attachments_list_every_rail_chat_newest_first(self) -> None:
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.executemany(
                """INSERT INTO messages (chat_jid, chat_name, msg_id, sender_jid, sender_name,
                   ts, from_me, text, media_type, mime_type, filename, local_path)
                   VALUES (?, '', ?, ?, ?, ?, ?, '', ?, ?, ?, ?)""",
                [("alex@s.whatsapp.net", "d1", "alex@s.whatsapp.net", "Alex", 45, 0,
                  "document", "application/pdf", "quote.pdf", str(self.document)),
                 ("team@g.us", "d2", "member@s.whatsapp.net", "Sam", 46, 0,
                  "document", "application/pdf", "plan.pdf", ""),
                 ("news@newsletter", "n1", "", "", 47, 0, "image", "image/png", "", "")])
        everything = self.backend.attachments()["attachments"]
        self.assertEqual([item["id"] for item in everything], ["d2", "d1", "t2"],
                         "newest first, and a channel outside the rail is left out")
        self.assertEqual(everything[1]["local_path"], str(self.document))
        self.assertEqual(everything[0]["chat_name"], "Design team")
        documents = self.backend.attachments(kinds=["document"], direction="received")
        self.assertEqual([item["id"] for item in documents["attachments"]], ["d2", "d1"])
        from_sam = self.backend.attachments(sender="member@s.whatsapp.net")
        self.assertEqual([item["id"] for item in from_sam["attachments"]], ["d2"])
        in_team = self.backend.attachments(jid="team@g.us", after=21)
        self.assertEqual([item["id"] for item in in_team["attachments"]], ["d2"])
        missing = self.backend.attachments(missing_only=True)
        self.assertEqual([item["id"] for item in missing["attachments"]], ["d2"],
                         "files already on this computer are not pending")
        with self.assertRaises(backend_module.OmaWhatsAppError):
            self.backend.attachments(kinds=["spreadsheet"])

    def test_contact_search_reports_alias_and_tags_and_filters_by_tag(self) -> None:
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute("""CREATE TABLE contact_tags (
                jid TEXT NOT NULL, tag TEXT NOT NULL, updated_at INTEGER NOT NULL,
                PRIMARY KEY (jid, tag))""")
            connection.executemany("INSERT INTO contact_tags VALUES (?, ?, 1)", [
                ("member@s.whatsapp.net", "suppliers"), ("member@s.whatsapp.net", "team"),
                ("admin@s.whatsapp.net", "Suppliers")])
            connection.execute(
                "INSERT INTO contact_aliases VALUES ('member@s.whatsapp.net', 'Sammy', '', 1)")
        people = {person["jid"]: person for person in self.backend.contacts_search()["people"]}
        self.assertEqual(people["member@s.whatsapp.net"]["alias"], "Sammy")
        self.assertEqual(people["member@s.whatsapp.net"]["name"], "Sammy",
                         "your own name for someone wins")
        self.assertEqual(people["member@s.whatsapp.net"]["tags"], ["suppliers", "team"])
        tagged = self.backend.contacts_search(tag="SUPPLIERS")["people"]
        self.assertEqual(sorted(person["jid"] for person in tagged),
                         ["admin@s.whatsapp.net", "member@s.whatsapp.net"],
                         "tags match without regard to case")
        self.assertEqual(self.backend.contact_tags()["tags"],
                         [{"tag": "Suppliers", "people": 2}, {"tag": "team", "people": 1}],
                         "one row per tag whatever its case, with a stable spelling")

    def test_contact_search_works_on_a_mirror_without_tags(self) -> None:
        self.assertEqual(self.backend.contact_tags(), {"ok": True, "tags": []})
        self.assertEqual(self.backend.contacts_search(tag="suppliers")["people"], [])
        self.assertTrue(all(person["tags"] == []
                            for person in self.backend.contacts_search()["people"]))


class MultiAccountTests(unittest.TestCase):
    """Two linked accounts, two stores, one rail."""

    FAKE_WACLI = """#!/usr/bin/env python3
import pathlib
import sys

args = sys.argv[1:]
if "accounts" in args and "list" in args:
    sys.stdout.write(pathlib.Path(PAYLOAD).read_text(encoding="utf-8"))
sys.exit(0)
"""

    WORK_CHATS = [
        ("team@g.us", "group", "Design team", 30, 1, 3),
        ("shared@s.whatsapp.net", "dm", "Robin", 20, 0, 2),
    ]
    HOME_CHATS = [
        ("family@g.us", "group", "Family", 40, 0, 1),
        ("shared@s.whatsapp.net", "dm", "Robin", 10, 0, 5),
    ]

    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        # Session markers (quit, launch) live in the runtime directory; keep
        # them in the test's own tree, never the desktop session's.
        runtime = self.root / "runtime"
        runtime.mkdir(mode=0o700, exist_ok=True)
        environment = mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": str(runtime)})
        environment.start()
        self.addCleanup(environment.stop)
        self.work = self.root / "stores" / "work"
        self.home = self.root / "stores" / "home"
        for store, chats in ((self.work, self.WORK_CHATS), (self.home, self.HOME_CHATS)):
            store.mkdir(parents=True)
            self._build(store, chats)
        self.config = self.root / "config.yaml"
        self.config.write_text("accounts: {}\n", encoding="utf-8")
        payload = self.root / "accounts.json"
        payload.write_text(json.dumps({"success": True, "error": None, "data": {
            "accounts": [
                {"name": "work", "configured_store": "stores/work",
                 "store_dir": str(self.work), "default": True},
                {"name": "home", "configured_store": "stores/home",
                 "store_dir": str(self.home), "default": False},
            ],
            "config_path": str(self.config),
            "default_account": "work",
        }}), encoding="utf-8")
        self.wacli = self.root / "wacli-bin"
        self.wacli.write_text(
            self.FAKE_WACLI.replace("PAYLOAD", repr(str(payload))), encoding="utf-8")
        self.wacli.chmod(0o700)
        self.backend = backend_module.Backend(
            store_dir=self.work, state_dir=self.root / "state", wacli=self.wacli,
            account_config=self.config, unit_dir=installed_units(self.root),
        )

    def tearDown(self) -> None:
        self.temporary.cleanup()

    @staticmethod
    def _build(store: Path, chats: list) -> None:
        with closing(sqlite3.connect(store / "wacli.db")) as connection, connection:
            connection.executescript(SCHEMA)
            connection.executemany(
                "INSERT INTO chats VALUES (?, ?, ?, ?, 0, ?, 0, 0, ?)", chats)
            connection.executemany(
                """INSERT INTO messages
                (chat_jid, chat_name, msg_id, sender_jid, sender_name, ts, from_me,
                 text, reaction_to_id, media_type, mime_type, local_path)
                VALUES (?, '', ?, 'member@s.whatsapp.net', 'Sam', ?, 0, ?, '', '', '', '')""",
                [(chat[0], f"m-{chat[0]}", chat[3], "hello") for chat in chats])

    def test_accounts_come_from_wacli_with_the_default_resolved_first(self) -> None:
        self.assertEqual([account.name for account in self.backend.accounts()],
                         ["work", "home"])
        self.assertEqual(self.backend.account("").name, "work")
        self.assertEqual(self.backend.account("home").store_dir, self.home)
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "not configured"):
            self.backend.account("missing")
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "valid named"):
            self.backend.account("../escape")

    def test_a_machine_without_an_account_config_stays_single_account(self) -> None:
        backend = backend_module.Backend(
            store_dir=self.work, state_dir=self.root / "state", wacli=self.wacli,
            account_config=self.root / "absent.yaml",
        )
        accounts = backend.accounts()
        self.assertEqual([account.name for account in accounts], ["primary"])
        self.assertEqual(accounts[0].store_dir, self.work)
        self.assertEqual(accounts[0].unit, "wacli-sync.service")
        self.assertEqual(accounts[0].cli_args, ["--store", str(self.work.resolve())])

    def test_existing_root_session_stays_primary_without_rewriting_wacli_config(self) -> None:
        legacy = self.root / "legacy-root"
        legacy.mkdir()
        (legacy / "session.db").write_bytes(b"synthetic-session")
        original_config = self.config.read_bytes()
        backend = backend_module.Backend(
            store_dir=legacy,
            state_dir=self.root / "legacy-state",
            wacli=self.wacli,
            account_config=self.config,
        )
        accounts = backend.accounts()
        self.assertEqual([account.name for account in accounts],
                         ["primary", "work", "home"])
        primary = backend.account("primary")
        self.assertEqual(primary.unit, "wacli-sync.service")
        self.assertEqual(primary.cli_args, ["--store", str(legacy.resolve())])
        self.assertEqual(self.config.read_bytes(), original_config)

        completed = subprocess.CompletedProcess([], 0, "{}", "")
        with mock.patch.object(
                backend_module, "run_bounded", return_value=completed) as run:
            backend._run(["--json", "doctor"], account=primary)
        self.assertEqual(run.call_args.args[0][:3],
                         [str(self.wacli), "--store", str(legacy.resolve())])

        completed = subprocess.CompletedProcess(
            [], 0, '{"success":true,"data":{"version":"synthetic"}}', ""
        )
        with mock.patch.object(backend, "_run", return_value=completed) as run:
            result = backend.transport({"account": "primary", "args": ["version"]})
        self.assertTrue(result["ok"])
        command = run.call_args.args[0]
        self.assertEqual(command[:2], ["--store", str(legacy.resolve())])
        self.assertNotIn("--account", command)

    def test_root_account_reference_stays_stable_across_the_first_link(self) -> None:
        legacy = self.root / "transition-root"
        legacy.mkdir()
        self._build(legacy, [self.WORK_CHATS[1]])
        (legacy / "session.db").write_bytes(b"synthetic-session")
        transition_config = self.root / "transition.yaml"
        backend = backend_module.Backend(
            store_dir=legacy, state_dir=self.root / "transition-state",
            wacli=self.wacli, account_config=transition_config,
        )
        captured = backend.account("").name
        self.assertEqual(captured, "primary")

        transition_config.write_text("accounts: {}\n", encoding="utf-8")
        backend._refresh_account_registry()
        self.assertEqual(backend.account("").name, captured)
        backend.use_account(captured)
        completed = subprocess.CompletedProcess(
            [], 0, '{"success":true,"data":{}}', ""
        )
        with mock.patch.object(
                backend_module, "run_bounded", return_value=completed) as run:
            backend.send("shared@s.whatsapp.net", "synthetic")
            backend.chat_action("shared@s.whatsapp.net", "read")
        for invocation in run.call_args_list:
            self.assertEqual(invocation.args[0][:3], [
                str(self.wacli), "--store", str(legacy.resolve())
            ])

    def test_rail_merges_every_account_and_tags_each_row(self) -> None:
        result = self.backend.chats()
        self.assertEqual(
            [(chat["name"], chat["account"]) for chat in result["chats"]],
            [("Design team", "work"), ("Family", "home"),
             ("Robin", "work"), ("Robin", "home")],
        )
        self.assertEqual(result["accounts"],
                         [{"account": "work", "ready": True, "error": ""},
                          {"account": "home", "ready": True, "error": ""}])

    def test_an_unreadable_account_never_empties_the_rail(self) -> None:
        (self.home / "wacli.db").unlink()
        result = self.backend.chats()
        self.assertEqual({chat["account"] for chat in result["chats"]}, {"work"})
        report = {row["account"]: row for row in result["accounts"]}
        self.assertFalse(report["home"]["ready"])
        self.assertTrue(report["home"]["error"])

    def test_the_same_chat_in_two_accounts_keeps_separate_state(self) -> None:
        self.backend.use_account("work")
        self.backend.acknowledge_notifications("shared@s.whatsapp.net")
        rail = {(chat["account"], chat["jid"]): chat
                for chat in self.backend.chats()["chats"]}
        self.assertEqual(rail[("work", "shared@s.whatsapp.net")]["notification_unread"], 0)
        self.assertEqual(rail[("home", "shared@s.whatsapp.net")]["notification_unread"], 5)
        stored = json.loads(
            (self.root / "state" / "preferences.json").read_text(encoding="utf-8"))
        self.assertEqual(list(stored["stores"]), [str(self.work)])

    def test_each_account_signs_with_its_own_name(self) -> None:
        self.backend.use_account("work")
        self.backend.settings({"signature": {"enabled": True, "name": "Atos · DLX"}})
        self.backend.use_account("home")
        self.assertFalse(self.backend.settings()["signature"]["enabled"],
                         "the other account is untouched")
        self.backend.settings({"signature": {"enabled": True, "name": "Atos"}})
        reports = {report["account"]: report for report in self.backend.status()["accounts"]}
        self.assertEqual(reports["work"]["signature"]["name"], "Atos · DLX")
        self.assertEqual(reports["home"]["signature"]["name"], "Atos")

    def test_avatar_cache_is_isolated_for_identical_jids_across_accounts(self) -> None:
        work = self.backend.account("work")
        home = self.backend.account("home")
        work_key = self.backend._avatar_key(work, "shared@s.whatsapp.net")
        home_key = self.backend._avatar_key(home, "shared@s.whatsapp.net")
        self.assertNotEqual(work_key, home_key)
        self.backend.avatar_cache.update([{
            "key": work_key, "picture_id": "work-picture", "checked_at": 1,
            "missing": False, "data": b"\xff\xd8\xffwork",
        }])
        rail = {(chat["account"], chat["jid"]): chat
                for chat in self.backend.chats()["chats"]}
        self.assertTrue(rail[("work", "shared@s.whatsapp.net")]["avatar_path"])
        self.assertEqual(
            rail[("home", "shared@s.whatsapp.net")]["avatar_path"], ""
        )

    def test_dismissing_the_bar_badge_covers_every_account(self) -> None:
        self.backend.acknowledge_notifications("")
        rail = self.backend.chats()["chats"]
        self.assertEqual(sum(chat["notification_unread"] for chat in rail), 0)
        self.assertEqual(sum(chat["unread"] for chat in rail), 11)

    def test_every_wacli_command_carries_its_account(self) -> None:
        completed = subprocess.CompletedProcess([], 0, '{"success":true,"data":{}}', "")
        self.backend.use_account("home")
        with mock.patch.object(backend_module, "run_bounded", return_value=completed) as run:
            self.backend.send("family@g.us", "hello")
        command = run.call_args.args[0]
        self.assertEqual(command[:3], [str(self.wacli), "--account", "home"])
        self.assertIn("--to", command)

    def test_sync_is_one_unit_per_account(self) -> None:
        self.assertEqual(self.backend.account("work").unit, "wacli-sync@work.service")
        self.assertEqual(self.backend.account("home").unit, "wacli-sync@home.service")
        completed = subprocess.CompletedProcess([], 0, "", "")
        self.backend.use_account("home")
        with mock.patch.object(backend_module, "run_bounded", return_value=completed) as run:
            self.backend.set_online(False)
        self.assertEqual(run.call_args.args[0][-1], "wacli-sync@home.service")
        self.assertFalse(self.backend.online())
        self.backend.use_account("work")
        self.assertTrue(self.backend.online())

    def test_account_link_resumes_unfinished_names_and_starts_new_sync(self) -> None:
        def finish_home(*args, **kwargs):
            (self.home / "session.db").write_bytes(b"synthetic-session")
            return 0, self.backend.account("home"), ("auth",)

        with mock.patch.object(
                self.backend, "_transport_interactive", side_effect=finish_home) as interactive, \
                mock.patch.object(self.backend, "_systemctl_user") as systemctl:
            self.assertEqual(self.backend.link_account("home", "interactive"), 0)
        interactive.assert_called_once_with(
            ["auth"], authorization="interactive", account="home"
        )
        systemctl.assert_called_once_with(
            ["enable", "--now", "wacli-sync@home.service"]
        )

        travel_store = self.root / "stores" / "travel"
        travel_store.mkdir(parents=True)
        (travel_store / "session.db").write_bytes(b"synthetic-session")
        new = backend_module.Account(
            "travel", travel_store, default=False
        )
        current = [self.backend.account("work"), self.backend.account("home")]
        known = [*current, new]
        with mock.patch.object(
                self.backend, "accounts", side_effect=[current, known]), \
                mock.patch.object(
                    self.backend, "_transport_interactive",
                    return_value=(0, current[0], ("accounts", "add")),
                ) as interactive, \
                mock.patch.object(self.backend, "_systemctl_user") as systemctl:
            self.assertEqual(self.backend.link_account("travel", "interactive"), 0)
        interactive.assert_called_once_with(
            ["accounts", "add", "travel"], authorization="interactive"
        )
        systemctl.assert_called_once_with(
            ["enable", "--now", "wacli-sync@travel.service"]
        )

    def test_account_link_reconciles_a_committed_nonzero_terminal_exit(self) -> None:
        travel_store = self.root / "stores" / "travel"
        travel_store.mkdir(parents=True)
        new = backend_module.Account("travel", travel_store)
        current = [self.backend.account("work"), self.backend.account("home")]

        def committed(*args, **kwargs):
            (travel_store / "session.db").write_bytes(b"synthetic-session")
            return 1, current[0], ("accounts", "add")

        with mock.patch.object(self.backend, "accounts", side_effect=[current, [*current, new]]), \
                mock.patch.object(
                    self.backend, "_transport_interactive", side_effect=committed), \
                mock.patch.object(self.backend, "_systemctl_user") as systemctl:
            with self.assertRaisesRegex(
                    backend_module.OmaWhatsAppPartialError, "terminal exited") as raised:
                self.backend.link_account("travel", "interactive")
        self.assertTrue(raised.exception.partial["committed"])
        systemctl.assert_called_once_with(
            ["enable", "--now", "wacli-sync@travel.service"]
        )

    def test_account_link_rejects_success_without_a_linked_session(self) -> None:
        travel_store = self.root / "stores" / "travel"
        travel_store.mkdir(parents=True)
        new = backend_module.Account("travel", travel_store)
        current = [self.backend.account("work"), self.backend.account("home")]
        with mock.patch.object(
                self.backend, "accounts", side_effect=[current, [*current, new]]), \
                mock.patch.object(
                    self.backend, "_transport_interactive",
                    return_value=(0, current[0], ("accounts", "add")),
                ), mock.patch.object(
                    self.backend, "_systemctl_user"
                ) as systemctl, self.assertRaisesRegex(
                    backend_module.OmaWhatsAppError, "no linked session"
                ):
            self.backend.link_account("travel", "interactive")
        systemctl.assert_not_called()

    def test_account_link_rejects_invalid_or_already_linked_names(self) -> None:
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "1-64"):
            self.backend.link_account(".hidden", "interactive")
        (self.home / "session.db").write_bytes(b"synthetic-session")
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "already linked"):
            self.backend.link_account("home", "interactive")
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "authorize interactive"):
            self.backend.link_account("work", "")

        full = [backend_module.Account(f"account-{index}", self.root / str(index))
                for index in range(backend_module.MAX_ACCOUNTS)]
        with mock.patch.object(self.backend, "accounts", return_value=full), \
                mock.patch.object(self.backend, "_transport_interactive") as interactive, \
                self.assertRaisesRegex(backend_module.OmaWhatsAppError, "maximum"):
            self.backend.link_account("overflow", "interactive")
        interactive.assert_not_called()

    def test_status_separates_what_is_aggregated_from_what_is_selected(self) -> None:
        probes = threading.Barrier(2)
        self.backend.settings({"time_format": "24h"})

        def unit_active(unit: str) -> bool:
            return unit == "wacli-sync@work.service"

        def doctor(account: backend_module.Account) -> dict[str, bool]:
            probes.wait(timeout=2)
            return {"authenticated": account.name == "work"}

        with mock.patch.object(self.backend, "_unit_active", side_effect=unit_active), \
                mock.patch.object(self.backend, "_doctor", side_effect=doctor):
            self.backend.use_account("home")
            (self.home / "wacli.db").unlink()
            status = self.backend.status()
        # The rail is ready when one complete account can serve it, but the
        # selected account cannot borrow that readiness for writes/receipts.
        self.assertTrue(status["rail_ready"])
        self.assertEqual(status["time_format"], "24h")
        self.assertTrue(status["any_authenticated"])
        self.assertTrue(status["any_database_ready"])
        self.assertFalse(status["authenticated"])
        self.assertFalse(status["database_ready"])
        self.assertEqual(status["account"], "home")
        self.assertFalse(status["sync_active"])
        self.assertEqual({row["account"]: row["sync_active"] for row in status["accounts"]},
                         {"work": True, "home": False})

    def test_one_failed_account_probe_does_not_empty_the_ready_rail(self) -> None:
        def doctor(account: backend_module.Account) -> dict[str, bool]:
            if account.name == "home":
                raise backend_module.OmaWhatsAppError("synthetic doctor timeout")
            return {"authenticated": True}

        with mock.patch.object(self.backend, "_unit_active", return_value=False), \
                mock.patch.object(self.backend, "_doctor", side_effect=doctor):
            status = self.backend.status()
        reports = {row["account"]: row for row in status["accounts"]}
        self.assertTrue(status["rail_ready"])
        self.assertTrue(reports["work"]["authenticated"])
        self.assertFalse(reports["home"]["authenticated"])
        self.assertIn("synthetic doctor timeout", reports["home"]["error"])

    def test_gateway_validates_the_target_inside_the_named_account(self) -> None:
        completed = subprocess.CompletedProcess([], 0, '{"success":true,"data":{}}', "")
        request = {
            "args": ["send", "text", "--to", "family@g.us", "--text", "hi"],
            "authorization": "whatsapp-write",
        }
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "not an exact chat"):
            self.backend.transport(dict(request, account="work"))
        with mock.patch.object(backend_module, "run_bounded", return_value=completed) as run:
            self.backend.transport(dict(request, account="home"))
        command = run.call_args.args[0]
        self.assertEqual(command.count("--account"), 1)
        self.assertEqual(command[command.index("--account") + 1], "home")

    def test_notify_sweeps_every_account_and_names_it(self) -> None:
        with mock.patch.object(self.backend, "_notify_send_ready", return_value=True):
            self.backend.set_notifications(True, True)
        with closing(sqlite3.connect(self.home / "wacli.db")) as connection, connection:
            connection.execute(
                "UPDATE chats SET last_message_ts = 41, unread_count = 3 WHERE jid = ?",
                ["family@g.us"])
            # A popup needs a new last message, not just a moved chat time.
            connection.execute(
                """INSERT INTO messages
                (chat_jid, chat_name, msg_id, sender_jid, sender_name, ts, from_me,
                 text, reaction_to_id, media_type, mime_type, local_path)
                VALUES ('family@g.us', '', 'f-new', 'kin@s.whatsapp.net', 'Kin', 41, 0,
                        'dinner?', '', '', '', '')""")
        with mock.patch.object(self.backend, "_notify_send_ready", return_value=True), \
                mock.patch.object(self.backend, "_deliver_notification",
                                  return_value=True) as deliver:
            result = self.backend.notify()
        self.assertEqual(result["sent"], 1)
        self.assertEqual(deliver.call_args.args[0], "Family (home) · 2 new")
        stored = json.loads(
            (self.root / "state" / "preferences.json").read_text(encoding="utf-8"))
        self.assertEqual(sorted(stored["stores"]), sorted([str(self.work), str(self.home)]))

    def test_one_account_can_be_muted_without_replaying_it_later(self) -> None:
        # L236: popups per account; muted, what arrives is marked seen.
        with mock.patch.object(self.backend, "_notify_send_ready", return_value=True):
            self.backend.set_notifications(True, True)
            self.backend.notify()  # adopt both accounts' archives
        self.backend.use_account("home")
        self.assertFalse(self.backend.settings({"account_notifications": False})["account_notifications"])
        reports = {report["account"]: report for report in self.backend.status()["accounts"]}
        self.assertTrue(reports["home"]["notifications_muted"])
        self.assertFalse(reports["work"]["notifications_muted"])
        self.assertFalse(reports["home"]["main"], "a named account is removed on unlink")

    def test_status_reports_the_helper_version_of_the_manifest(self) -> None:
        manifest = json.loads((Path(__file__).resolve().parents[1] / "manifest.json").read_text())
        self.assertEqual(self.backend.status()["helper_version"], manifest["version"],
                         "the app compares the two to catch an update that replaced only the plugin")

        def arrive(message_id: str, ts: int) -> None:
            with closing(sqlite3.connect(self.home / "wacli.db")) as connection, connection:
                connection.execute(
                    "UPDATE chats SET last_message_ts = ?, unread_count = 3 WHERE jid = ?",
                    [ts, "family@g.us"])
                connection.execute(
                    """INSERT INTO messages
                    (chat_jid, chat_name, msg_id, sender_jid, sender_name, ts, from_me,
                     text, reaction_to_id, media_type, mime_type, local_path)
                    VALUES ('family@g.us', '', ?, 'kin@s.whatsapp.net', 'Kin', ?, 0,
                            'dinner?', '', '', '', '')""", [message_id, ts])
        arrive("f-muted", 41)
        with mock.patch.object(self.backend, "_notify_send_ready", return_value=True), \
                mock.patch.object(self.backend, "_deliver_notification", return_value=True) as deliver:
            self.assertEqual(self.backend.notify()["sent"], 0, "muted account: no popup")
        deliver.assert_not_called()
        self.backend.settings({"account_notifications": True})
        with mock.patch.object(self.backend, "_notify_send_ready", return_value=True), \
                mock.patch.object(self.backend, "_deliver_notification", return_value=True) as deliver:
            self.assertEqual(self.backend.notify()["sent"], 0, "unmuting does not replay it")
        arrive("f-after", 42)
        with mock.patch.object(self.backend, "_notify_send_ready", return_value=True), \
                mock.patch.object(self.backend, "_deliver_notification", return_value=True) as deliver:
            self.assertEqual(self.backend.notify()["sent"], 1, "new messages pop up again")

    def test_unlinking_an_account_needs_its_name_and_keeps_the_archive(self) -> None:
        completed = subprocess.CompletedProcess([], 0, '{"success":true}', "")
        real_run = self.backend._run
        mutations: list[list[str]] = []

        def run(answer):
            def fake(args, **kwargs):
                if args[1:3] in (["auth", "logout"], ["accounts", "remove"]):
                    mutations.append(args[1:3])
                    return answer
                return real_run(args, **kwargs)
            return fake
        with mock.patch.object(self.backend, "_run", side_effect=run(completed)), \
                mock.patch.object(self.backend, "_systemctl_user", return_value=completed) as systemctl:
            with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "Confirm by naming"):
                self.backend.unlink_account("home", "")
            self.assertEqual(mutations, [], "nothing happens without the name")
            result = self.backend.unlink_account("home", "home")
        self.assertTrue(result["archive_kept"])
        self.assertTrue(result["removed"])
        self.assertEqual(systemctl.call_args_list[0].args[0], ["disable", "--now", "wacli-sync@home.service"])
        self.assertEqual(mutations, [["auth", "logout"], ["accounts", "remove"]])
        self.assertTrue((self.home / "wacli.db").is_file(), "the local archive stays")
        mutations.clear()
        refused = subprocess.CompletedProcess([], 1, "", "not connected")
        with mock.patch.object(self.backend, "_run", side_effect=run(refused)), \
                mock.patch.object(self.backend, "_systemctl_user", return_value=completed):
            with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "not connected|did not accept"):
                self.backend.unlink_account("work", "work")
        self.assertEqual(mutations, [["auth", "logout"]], "no removal after a refused logout")

    def test_version_2_preserves_private_reading(self) -> None:
        state = self.root / "state"
        state.mkdir(mode=0o700)
        key = str(self.backend.account("").key)
        target = state / "preferences.json"
        target.write_text(json.dumps({
            "version": 2,
            "stores": {key: {"online": True, "send_read_receipts": False}},
        }), encoding="utf-8")
        target.chmod(0o600)
        self.assertFalse(self.backend.settings()["send_read_receipts"])
        self.backend.settings({"send_read_receipts": False})
        self.assertEqual(json.loads(target.read_text(encoding="utf-8"))["version"], 4)
        self.assertFalse(self.backend.settings()["send_read_receipts"])

    def test_upgrade_preserves_each_accounts_reading_and_notification_choices(self) -> None:
        state = self.root / "state"
        state.mkdir(mode=0o700)
        target = state / "preferences.json"
        for version in (1, 2, 3, 4):
            for enabled in (False, True):
                with self.subTest(version=version, enabled=enabled):
                    target.write_text(json.dumps({
                        "version": version,
                        "notifications": {"enabled": enabled},
                        "read_on_reply": enabled,
                        "show_online": enabled,
                        "stores": {
                            str(self.work): {"send_read_receipts": enabled},
                            str(self.home): {"send_read_receipts": not enabled},
                        },
                    }), encoding="utf-8")
                    target.chmod(0o600)
                    preferences = self.backend._preferences()
                    self.assertEqual(preferences["notifications"]["enabled"], enabled)
                    self.assertEqual(preferences["read_on_reply"], enabled)
                    self.assertEqual(preferences["show_online"], enabled)
                    self.assertEqual(preferences["stores"][str(self.work)]["send_read_receipts"], enabled)
                    self.assertEqual(preferences["stores"][str(self.home)]["send_read_receipts"], not enabled)

    def test_version_1_state_migrates_to_the_default_account(self) -> None:
        state = self.root / "state"
        state.mkdir(mode=0o700)
        legacy = {
            "version": 1,
            "online": False,
            "send_read_receipts": True,
            "acknowledged_unread": {"team@g.us": {"unread": 3, "timestamp": 30}},
            "notified": {"team@g.us": {"unread": 3, "timestamp": 30}},
            "show_unread_count": False,
            "dropdown_rows": 9,
        }
        target = state / "preferences.json"
        target.write_text(json.dumps(legacy), encoding="utf-8")
        target.chmod(0o600)

        preferences = self.backend._preferences()
        self.assertEqual(list(preferences["stores"]), [str(self.work)])
        self.assertFalse(preferences["show_unread_count"])
        self.assertEqual(preferences["dropdown_rows"], 9)
        migrated = preferences["stores"][str(self.work)]
        self.assertFalse(migrated["online"])
        self.assertTrue(migrated["send_read_receipts"])
        self.assertIn("team@g.us", migrated["acknowledged_unread"])
        # Version 4 restarts the popup watermark so the archive is adopted.
        self.assertEqual(migrated["notified"], {})

        # The second account starts clean instead of inheriting that history.
        self.backend.use_account("home")
        self.assertTrue(self.backend.online())
        self.assertEqual(self.backend._account_state()["acknowledged_unread"], {})


if __name__ == "__main__":
    unittest.main()
