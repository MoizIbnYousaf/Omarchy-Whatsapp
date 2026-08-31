from __future__ import annotations

import importlib.util
from importlib.machinery import SourceFileLoader
from contextlib import closing
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
            store_dir=self.store, state_dir=self.root / "state", wacli=self.wacli
        )

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_chat_rail_contains_every_local_chat(self) -> None:
        result = self.backend.chats()
        self.assertEqual({chat["name"] for chat in result["chats"]}, {"Design team", "Alex", "Archive"})
        self.assertEqual(result["chats"][0]["name"], "Design team")  # pinned first
        self.assertEqual(result["chats"][0]["unread"], 3)

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
        self.assertEqual(result["refreshed"], 3)
        self.assertEqual(fetch.call_count, 3)
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
        rows = [{"account": account.name, "jid": f"synthetic-{index}@example"}
                for index in range(15)]
        batches = []

        def fail(selected, candidates):
            batches.append([item["jid"] for item in candidates])
            return [], [item["key"] for item in candidates]

        with mock.patch.object(self.backend, "chats", return_value={"chats": rows}), \
                mock.patch.object(
                    self.backend, "_profile_picture_metadata", side_effect=fail):
            first = self.backend.refresh_avatars("remote-read")
            second = self.backend.refresh_avatars("remote-read")
        self.assertEqual((first["checked"], first["failed"]), (12, 12))
        self.assertEqual((second["checked"], second["failed"]), (3, 3))
        self.assertEqual(batches[1], [row["jid"] for row in rows[12:]])

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
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute(
                "UPDATE chats SET last_message_ts = ?, unread_count = ? WHERE jid = ?",
                [timestamp, unread, jid],
            )
            connection.execute(
                """INSERT INTO messages
                (chat_jid, chat_name, msg_id, sender_jid, sender_name, ts, from_me,
                 text, reaction_to_id, media_type, mime_type, local_path)
                VALUES (?, '', ?, 'member@s.whatsapp.net', ?, ?, 0, ?, '', '', '', '')""",
                [jid, msg_id, sender, timestamp, text],
            )

    def _notify(self, skip_jid: str = "") -> tuple[dict, list]:
        with mock.patch.object(self.backend, "_notify_send_ready", return_value=True), \
                mock.patch.object(self.backend, "_deliver_notification",
                                  return_value=True) as deliver:
            result = self.backend.notify(skip_jid)
        return result, [call.args for call in deliver.call_args_list]

    def test_desktop_notifications_are_off_until_notify_send_exists(self) -> None:
        self.assertEqual(self.backend._preferences()["notifications"],
                         {"enabled": False, "preview": True})
        with mock.patch.object(self.backend, "_notify_send_ready", return_value=False):
            with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "notify-send"):
                self.backend.set_notifications(True, None)
        result, sent = self._notify()
        self.assertFalse(result["enabled"])
        self.assertEqual(sent, [])

    def test_enabling_notifications_adopts_the_archive_instead_of_replaying_it(self) -> None:
        self.backend._update_preferences(
            lambda value: value["notifications"].update({"enabled": True}))
        result, sent = self._notify()
        self.assertTrue(result["seeded"])
        self.assertEqual(sent, [])

        self._enable_notifications()
        stored = json.loads((self.root / "state" / "preferences.json").read_text(encoding="utf-8"))
        self.assertEqual(stored["notifications"], {"enabled": True, "preview": True})
        self.assertIn("team@g.us", stored["stores"][str(self.store)]["notified"])

        self._arrive("team@g.us", "t3", 31, 4)
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

    def test_chat_surface_is_only_dms_and_standalone_groups(self) -> None:
        visible = {chat["jid"] for chat in self.backend.chats()["chats"]}
        self.assertEqual(visible, {"team@g.us", "alex@s.whatsapp.net", "archive@g.us"})
        for hidden in ("news@newsletter", "legacy@newsletter", "community@g.us",
                       "subgroup@g.us"):
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

    def test_messages_never_cross_chat_boundary(self) -> None:
        values = self.backend.messages("team@g.us")["messages"]
        self.assertEqual([value["id"] for value in values], ["t1", "t2"])
        self.assertNotIn("a1", [value["id"] for value in values])

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
        completed = subprocess.CompletedProcess([], 0, '{"success":true}', "")
        with mock.patch.object(self.backend, "_write", return_value=completed) as write:
            result = self.backend.download_media("team@g.us", "t2")
        self.assertTrue(result["ok"])
        command = write.call_args.args[0]
        self.assertEqual(command[command.index("--chat") + 1], "team@g.us")
        self.assertEqual(command[command.index("--id") + 1], "t2")

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
        completed = subprocess.CompletedProcess([], 0, json.dumps({"success": True}), "")
        with mock.patch.object(self.backend, "_write", return_value=completed) as write:
            self.backend.send("alex@s.whatsapp.net", "hello")
        command = write.call_args.args[0]
        self.assertEqual(command[command.index("--to") + 1], "alex@s.whatsapp.net")
        self.assertEqual(command[command.index("--message") + 1], "hello")

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
        completed = subprocess.CompletedProcess([], 0, '{"success":true}', "")
        with mock.patch.object(self.backend, "_write", return_value=completed) as write:
            self.backend.send_poll("team@g.us", "Ship it?", ["Yes", "No"], 1)
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

    def test_chat_actions_are_allowlisted(self) -> None:
        completed = subprocess.CompletedProcess([], 0, '{"success":true}', "")
        with mock.patch.object(self.backend, "_write", return_value=completed) as write:
            self.backend.chat_action("team@g.us", "mute")
        command = write.call_args.args[0]
        self.assertEqual(command[1:3], ["chats", "mute"])
        self.assertEqual(command[command.index("--chat") + 1], "team@g.us")
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "not supported"):
            self.backend.chat_action("team@g.us", "leave")

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
        self.assertIn("enable", run.call_args.args[0])

    def test_private_reading_is_default_and_settings_are_bounded(self) -> None:
        defaults = self.backend.settings()
        self.assertFalse(defaults["send_read_receipts"])
        self.assertTrue(defaults["show_unread_count"])
        self.assertEqual(defaults["dropdown_rows"], 7)

        updated = self.backend.settings({
            "send_read_receipts": True,
            "show_unread_count": False,
            "dropdown_rows": 9,
        })
        self.assertTrue(updated["send_read_receipts"])
        self.assertFalse(updated["show_unread_count"])
        self.assertEqual(updated["dropdown_rows"], 9)
        self.assertTrue(self.backend.settings()["send_read_receipts"])
        preferences = self.root / "state" / "preferences.json"
        self.assertEqual(preferences.stat().st_mode & 0o777, 0o600)

        reloaded = backend_module.Backend(
            store_dir=self.store, state_dir=self.root / "state", wacli=self.wacli
        )
        persisted = reloaded.settings()
        self.assertTrue(persisted["send_read_receipts"])
        self.assertFalse(persisted["show_unread_count"])
        self.assertEqual(persisted["dropdown_rows"], 9)

        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "5, 7, or 9"):
            self.backend.settings({"dropdown_rows": 8})
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "not supported"):
            self.backend.settings({"surprise": True})

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

    def test_oversized_message_is_rejected(self) -> None:
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "too long"):
            self.backend.send("alex@s.whatsapp.net", "x" * 4097)

    def test_wacli_parity_registry_covers_every_0171_leaf(self) -> None:
        policies = backend_module.WACLI_OPERATION_POLICIES
        self.assertEqual(len(policies), 103)
        self.assertEqual(len(set(policies)), len(policies))
        self.assertEqual(set(policies.values()), {
            "local-read", "remote-read", "local-write", "sync",
            "whatsapp-write", "destructive", "interactive",
        })
        capabilities = self.backend.capabilities()
        self.assertEqual(capabilities["wacli_parity_version"], "0.17.1")
        self.assertEqual(capabilities["operation_count"], len(policies))
        self.assertEqual(len(capabilities["operations"]), len(policies))

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
            helper.write_bytes(SCRIPT.read_bytes())
            helper.chmod(0o755)
            result = subprocess.run(
                [str(helper), "capabilities"], text=True, capture_output=True,
                check=False,
            )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(json.loads(result.stdout)["ok"])


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
            account_config=self.config,
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
        with mock.patch.object(self.backend, "_notify_send_ready", return_value=True), \
                mock.patch.object(self.backend, "_deliver_notification",
                                  return_value=True) as deliver:
            result = self.backend.notify()
        self.assertEqual(result["sent"], 1)
        self.assertEqual(deliver.call_args.args[0], "Family (home) · 2 new")
        stored = json.loads(
            (self.root / "state" / "preferences.json").read_text(encoding="utf-8"))
        self.assertEqual(sorted(stored["stores"]), sorted([str(self.work), str(self.home)]))

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
        self.assertIn("team@g.us", migrated["notified"])

        # The second account starts clean instead of inheriting that history.
        self.backend.use_account("home")
        self.assertTrue(self.backend.online())
        self.assertEqual(self.backend._account_state()["acknowledged_unread"], {})


if __name__ == "__main__":
    unittest.main()
