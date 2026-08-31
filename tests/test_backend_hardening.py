from __future__ import annotations

from contextlib import closing
from concurrent.futures import ThreadPoolExecutor
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

from test_backend import SCHEMA, SCRIPT, backend_module


class BackendHardeningTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.store = self.root / "store"
        self.store.mkdir()
        self.wacli = self.root / "wacli"
        self.wacli.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        self.wacli.chmod(0o700)
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.executescript(SCHEMA)
            connection.executemany(
                "INSERT INTO chats VALUES (?, ?, ?, ?, 0, 0, 0, 0, ?)",
                [
                    ("team@g.us", "group", "Team", 10, 1),
                    ("alex@s.whatsapp.net", "dm", "Alex", 9, 0),
                    ("news@newsletter", "newsletter", "News", 8, 0),
                ],
            )
            connection.execute(
                "INSERT INTO groups (jid, name, updated_at) VALUES (?, ?, 1)",
                ["team@g.us", "Team"],
            )
            connection.execute(
                "INSERT INTO contacts VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                ["member@s.whatsapp.net", "15551234567", "Sam", "Sam", "Sam", "", "", 1],
            )
            connection.execute(
                "INSERT INTO group_participants VALUES (?, ?, ?, ?)",
                ["team@g.us", "member@s.whatsapp.net", "member", 1],
            )
            connection.executemany(
                """INSERT INTO messages
                (chat_jid, chat_name, msg_id, sender_jid, sender_name, ts,
                 from_me, text, reaction_to_id)
                VALUES (?, '', ?, 'member@s.whatsapp.net', 'Sam', ?, 0, ?, '')""",
                [
                    ("team@g.us", "team-message", 10, "hello"),
                    ("alex@s.whatsapp.net", "alex-message", 9, "hello"),
                    ("news@newsletter", "news-message", 8, "hello"),
                ],
            )
        self.backend = backend_module.Backend(
            store_dir=self.store,
            state_dir=self.root / "state",
            wacli=self.wacli,
            account_config=self.root / "absent.yaml",
        )

    def tearDown(self) -> None:
        self.temporary.cleanup()

    @staticmethod
    def completed(data: object | None = None) -> subprocess.CompletedProcess[str]:
        return subprocess.CompletedProcess(
            [], 0, json.dumps({"success": True, "data": data}), ""
        )

    def test_existing_account_config_fails_closed_on_discovery_errors(self) -> None:
        config = self.root / "config.yaml"
        config.write_text("accounts: {}\n", encoding="utf-8")
        cases = [
            subprocess.CompletedProcess([], 1, "", "failed"),
            subprocess.CompletedProcess([], 0, "not-json", ""),
            self.completed({"accounts": []}),
            self.completed({
                "accounts": [
                    {"name": "work", "store_dir": str(self.store), "default": False},
                ]
            }),
        ]
        for result in cases:
            backend = backend_module.Backend(
                store_dir=self.store,
                state_dir=self.root / "state",
                wacli=self.wacli,
                account_config=config,
            )
            with self.subTest(stdout=result.stdout), \
                    mock.patch.object(backend, "_run", return_value=result), \
                    self.assertRaises(backend_module.OmaWhatsAppError):
                backend.accounts()

    def test_relative_xdg_state_is_ignored_outside_the_checkout(self) -> None:
        checkout = self.root / "public-checkout"
        checkout.mkdir()
        isolated_home = self.root / "home"
        isolated_home.mkdir()
        environment = dict(os.environ)
        environment.update({
            "HOME": str(isolated_home),
            "XDG_STATE_HOME": "relative-state",
            "WACLI_STORE_DIR": "relative-store",
            "WACLI_BIN": str(self.wacli),
        })
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "settings"],
            input=json.dumps({"settings": {"show_unread_count": False}}),
            text=True,
            capture_output=True,
            cwd=checkout,
            env=environment,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((checkout / "relative-state").exists())
        self.assertFalse((checkout / "relative-store").exists())
        self.assertTrue(
            (isolated_home / ".local/state/omawhatsapp/preferences.json").is_file()
        )

    def test_online_mode_restores_service_and_preference_after_state_failure(self) -> None:
        completed = subprocess.CompletedProcess([], 0, "", "")
        with mock.patch.object(
            backend_module, "run_bounded", return_value=completed
        ) as run, mock.patch.object(
            self.backend,
            "_update_account_state",
            side_effect=[backend_module.OmaWhatsAppError("disk full"), {}],
        ) as update, self.assertRaisesRegex(
            backend_module.OmaWhatsAppError, "previous sync mode was restored"
        ):
            self.backend.set_online(False)
        self.assertEqual(update.call_count, 2)
        commands = [call.args[0][2] for call in run.call_args_list]
        self.assertEqual(commands, [
            "is-enabled", "is-active", "disable", "enable", "start"
        ])

    def test_online_mode_does_not_write_state_when_systemd_rejects_change(self) -> None:
        success = subprocess.CompletedProcess([], 0, "", "")
        failure = subprocess.CompletedProcess([], 1, "", "synthetic rejection")
        with mock.patch.object(
            backend_module, "run_bounded", side_effect=[success, success, failure]
        ), mock.patch.object(self.backend, "_update_account_state") as update, \
                self.assertRaisesRegex(
                    backend_module.OmaWhatsAppError, "synthetic rejection"
                ):
            self.backend.set_online(False)
        update.assert_not_called()

    def test_interrupted_foreground_intent_is_recovered_by_the_next_helper(self) -> None:
        account = self.backend.account("")
        unit = account.unit
        self.backend._record_lifecycle_recovery(account)
        recovery = json.loads(
            (self.root / "state" / "lifecycle-recovery.json").read_text(
                encoding="utf-8"
            )
        )
        self.assertEqual([item["unit"] for item in recovery["records"]], [unit])

        next_helper = backend_module.Backend(
            store_dir=self.store, state_dir=self.root / "state",
            wacli=self.wacli, account_config=self.root / "absent.yaml",
        )
        with mock.patch.object(next_helper, "_systemctl_user") as systemctl:
            next_helper.recover_lifecycle()
        systemctl.assert_called_once_with(["start", unit])
        recovered = json.loads(
            (self.root / "state" / "lifecycle-recovery.json").read_text(
                encoding="utf-8"
            )
        )
        self.assertEqual(recovered["records"], [])

    def test_failed_lifecycle_recovery_remains_durable_and_fails_closed(self) -> None:
        account = self.backend.account("")
        unit = account.unit
        self.backend._record_lifecycle_recovery(account)
        with mock.patch.object(
                self.backend, "_systemctl_user",
                side_effect=backend_module.OmaWhatsAppError("service failed")), \
                self.assertRaisesRegex(
                    backend_module.OmaWhatsAppError, "recovery is still pending"
                ):
            self.backend.recover_lifecycle()
        self.assertEqual(self.backend._lifecycle_recovery_units(), [unit])

    def test_recovery_waits_for_an_active_account_operation(self) -> None:
        account = self.backend.account("")
        self.backend._record_lifecycle_recovery(account)
        next_helper = backend_module.Backend(
            store_dir=self.store, state_dir=self.root / "state",
            wacli=self.wacli, account_config=self.root / "absent.yaml",
        )
        snapshotted = threading.Event()
        failures = []
        original_records = next_helper._lifecycle_recovery_records

        def records():
            value = original_records()
            snapshotted.set()
            return value

        def recover():
            try:
                next_helper.recover_lifecycle()
            except BaseException as exc:
                failures.append(exc)

        with self.backend._state_lock(
                self.backend._lifecycle_lock_name(account)), \
                mock.patch.object(
                    next_helper, "_lifecycle_recovery_records",
                    side_effect=records,
                ), mock.patch.object(
                    next_helper, "_systemctl_user"
                ) as systemctl:
            worker = threading.Thread(target=recover)
            worker.start()
            self.assertTrue(snapshotted.wait(timeout=2))
            time.sleep(0.05)
            systemctl.assert_not_called()
            self.backend._clear_lifecycle_recovery(account.unit)
        worker.join(timeout=2)
        self.assertFalse(worker.is_alive())
        self.assertEqual(failures, [])
        systemctl.assert_not_called()

    def test_gateway_resolves_chat_group_contact_and_message_targets(self) -> None:
        cases = [
            ({"args": ["chats", "archive", "--chat", "Team"],
              "authorization": "whatsapp-write"}, "exact"),
            ({"args": ["groups", "leave", "--jid", "alex@s.whatsapp.net"],
              "authorization": "destructive"}, "group"),
            ({"args": ["contacts", "alias", "set", "--jid", "15551234567",
                       "--alias", "Sam"], "authorization": "local-write"}, "contact"),
            ({"args": ["messages", "edit", "--chat", "team@g.us",
                       "--id", "alex-message", "--message", "changed"],
              "authorization": "whatsapp-write"}, "message"),
        ]
        for request, error in cases:
            with self.subTest(args=request["args"]), \
                    mock.patch.object(self.backend, "_mutate") as mutate, \
                    self.assertRaisesRegex(backend_module.OmaWhatsAppError, error):
                self.backend.transport(request)
            mutate.assert_not_called()

        with mock.patch.object(
            self.backend, "_mutate", return_value=self.completed({})
        ) as mutate:
            result = self.backend.transport({
                "args": ["messages", "edit", "--chat", "team@g.us",
                         "--id", "team-message", "--message", "changed"],
                "authorization": "whatsapp-write",
            })
        self.assertEqual(result["operation"], "messages edit")
        self.assertTrue(mutate.call_args.kwargs["require_online"])

    def test_gateway_validates_every_pinned_optional_chat_and_profile_target(self) -> None:
        optional_cases = [
            ["calls", "list", "--chat", "missing@s.whatsapp.net"],
            ["history", "coverage", "--chat", "team@g.us",
             "--chat", "missing@s.whatsapp.net"],
            ["polls", "list", "--chat", "missing@s.whatsapp.net"],
        ]
        for args in optional_cases:
            with self.subTest(args=args), mock.patch.object(self.backend, "_run") as run, \
                    self.assertRaisesRegex(backend_module.OmaWhatsAppError, "exact"):
                self.backend.transport({"args": args})
            run.assert_not_called()

        for operation in ("business", "get-about", "picture-info"):
            request = {
                "args": ["profile", operation, "--jid", "15551234567"],
                "authorization": "remote-read",
            }
            with self.subTest(operation=operation), \
                    mock.patch.object(self.backend, "_mutate") as mutate, \
                    self.assertRaisesRegex(backend_module.OmaWhatsAppError, "contact JID"):
                self.backend.transport(request)
            mutate.assert_not_called()

    def test_gateway_redacts_webhook_urls_queries_and_secrets_from_all_output(self) -> None:
        webhook = "https://events.example.test/hook?token=query-secret"
        secret = "header-secret"
        args = ["sync", "--once", "--webhook", webhook,
                "--webhook-secret", secret]
        request = {
            "args": args,
            "authorization": "sync",
            "external_stream_authorization": f"external-stream:{webhook}",
        }
        diagnostic = f"failed command {webhook} {secret} query-secret"
        failed = subprocess.CompletedProcess([], 1, "", diagnostic)
        with mock.patch.object(self.backend, "_mutate", return_value=failed), \
                self.assertRaises(backend_module.OmaWhatsAppError) as raised:
            self.backend.transport(request)
        error = str(raised.exception)
        self.assertNotIn(webhook, error)
        self.assertNotIn(secret, error)
        self.assertNotIn("query-secret", error)
        self.assertIn("[redacted]", error)

        completed = subprocess.CompletedProcess(
            [], 0,
            json.dumps({"success": True, "data": {"diagnostic": diagnostic}}),
            json.dumps({"event": diagnostic}),
        )
        event_request = dict(request)
        event_request["events"] = True
        event_request["external_stream_authorization"] = [
            f"external-stream:{webhook}", "external-stream:response"
        ]
        with mock.patch.object(self.backend, "_mutate", return_value=completed):
            response = self.backend.transport(event_request)
        serialized = json.dumps(response)
        self.assertNotIn(webhook, serialized)
        self.assertNotIn(secret, serialized)
        self.assertNotIn("query-secret", serialized)
        self.assertIn("[redacted]", serialized)

    def test_existing_participant_mutations_require_an_indexed_jid(self) -> None:
        valid = {
            "args": ["groups", "participants", "remove", "--jid", "team@g.us",
                     "--user", "member@s.whatsapp.net"],
            "authorization": "destructive",
        }
        with mock.patch.object(
            self.backend, "_mutate", return_value=self.completed({})
        ) as mutate:
            self.backend.transport(valid)
        mutate.assert_called_once()

        for user in ("15551234567", "missing@s.whatsapp.net"):
            request = dict(valid)
            request["args"] = [*valid["args"][:-1], user]
            with mock.patch.object(self.backend, "_mutate") as mutate, \
                    self.assertRaises(backend_module.OmaWhatsAppError):
                self.backend.transport(request)
            mutate.assert_not_called()

    def test_participant_add_and_group_create_reject_phone_selectors(self) -> None:
        requests = [
            ["groups", "participants", "add", "--jid", "team@g.us",
             "--user", "+1 555 123 4567"],
            ["groups", "create", "--name", "Exact group",
             "--user", "+1 555 123 4567"],
        ]
        for args in requests:
            with self.subTest(args=args), \
                    mock.patch.object(self.backend, "_mutate") as mutate, \
                    self.assertRaisesRegex(backend_module.OmaWhatsAppError, "contact JID"):
                self.backend.transport({
                    "args": args,
                    "authorization": "whatsapp-write",
                })
            mutate.assert_not_called()

        with mock.patch.object(
            self.backend, "_mutate", return_value=self.completed({})
        ) as mutate:
            self.backend.transport({
                "args": ["groups", "participants", "add", "--jid", "team@g.us",
                         "--user", "member@s.whatsapp.net"],
                "authorization": "whatsapp-write",
            })
        mutate.assert_called_once()

    def test_private_export_authorization_is_path_bound_and_repo_aware(self) -> None:
        export_dir = self.root / "exports"
        export_dir.mkdir()
        destination = export_dir / "messages.json"
        args = ["messages", "export", "--chat", "team@g.us",
                "--output", str(destination)]
        with mock.patch.object(backend_module, "HOME", self.root):
            with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "private-export"):
                self.backend.transport({"args": args, "authorization": "local-write"})
            with mock.patch.object(
                self.backend, "_mutate", return_value=self.completed({})
            ) as mutate:
                result = self.backend.transport({
                    "args": args,
                    "authorization": f"private-export:{destination}",
                })
            self.assertEqual(result["policy"], "private-export")
            self.assertFalse(mutate.call_args.kwargs["require_online"])

            repository = self.root / "repository"
            (repository / ".git").mkdir(parents=True)
            repository_destination = repository / "messages.json"
            repository_args = ["messages", "export", "--output",
                               str(repository_destination)]
            authorization = f"private-export:{repository_destination}"
            with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "repository"):
                self.backend.transport({
                    "args": repository_args,
                    "authorization": authorization,
                })
            with mock.patch.object(
                self.backend, "_mutate", return_value=self.completed({})
            ):
                result = self.backend.transport({
                    "args": repository_args,
                    "authorization": authorization,
                    "repository_export_authorization":
                        f"allow-repository-export:{repository_destination}",
                })
            self.assertTrue(result["ok"])

    def test_media_download_output_requires_a_private_destination_token(self) -> None:
        destination = self.root / "downloaded-media"
        destination.mkdir()
        args = ["media", "download", "--chat", "team@g.us",
                "--id", "team-message", "--output", str(destination)]
        with mock.patch.object(backend_module, "HOME", self.root):
            with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "private-export"):
                self.backend.transport({"args": args, "authorization": "sync"})
            with mock.patch.object(
                self.backend, "_mutate", return_value=self.completed({})
            ) as mutate:
                result = self.backend.transport({
                    "args": args,
                    "authorization": "sync",
                    "private_export_authorization":
                        f"private-export:{destination}",
                })
            self.assertTrue(result["ok"])
            mutate.assert_called_once()

            repository = self.root / "repository-media"
            (repository / ".git").mkdir(parents=True)
            repository_args = [*args[:-1], str(repository)]
            request = {
                "args": repository_args,
                "authorization": "sync",
                "private_export_authorization": f"private-export:{repository}",
            }
            with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "repository"):
                self.backend.transport(request)
            request["repository_export_authorization"] = \
                f"allow-repository-export:{repository}"
            with mock.patch.object(
                self.backend, "_mutate", return_value=self.completed({})
            ):
                self.assertTrue(self.backend.transport(request)["ok"])

    def test_private_event_egress_has_a_separate_destination_token(self) -> None:
        with mock.patch.object(
            self.backend, "_run", return_value=self.completed({"version": "fixture"})
        ):
            self.assertTrue(self.backend.transport({
                "args": ["version"], "external_stream_authorization": ""
            })["ok"])
        webhook = "https://events.example.test/wacli"
        request = {
            "args": ["sync", "--once", "--webhook", webhook],
            "authorization": "sync",
        }
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "external-stream"):
            self.backend.transport(request)
        request["external_stream_authorization"] = f"external-stream:{webhook}"
        with mock.patch.object(
            self.backend, "_mutate", return_value=self.completed({})
        ) as mutate:
            result = self.backend.transport(request)
        self.assertEqual(result["policy"], "sync")
        self.assertTrue(mutate.call_args.kwargs["require_online"])

        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "external-stream"):
            self.backend.transport({"args": ["version"], "events": True})
        with mock.patch.object(
            self.backend, "_run", return_value=self.completed({"version": "fixture"})
        ):
            result = self.backend.transport({
                "args": ["version"],
                "events": True,
                "external_stream_authorization": "external-stream:response",
            })
        self.assertTrue(result["ok"])

    def test_interactive_sync_cannot_bypass_stream_authorization(self) -> None:
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "cannot export"):
            self.backend.transport_interactive(
                ["sync", "--once", "--webhook", "https://events.example.test/hook"],
                authorization="sync",
            )

    def test_failed_notification_delivery_keeps_the_previous_watermark(self) -> None:
        with mock.patch.object(self.backend, "_notify_send_ready", return_value=True):
            self.backend.set_notifications(True, True)
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute(
                "UPDATE chats SET last_message_ts = 11, unread_count = 2 WHERE jid = ?",
                ["team@g.us"],
            )
            connection.execute(
                """INSERT INTO messages
                (chat_jid, chat_name, msg_id, sender_jid, sender_name, ts,
                 from_me, text, reaction_to_id)
                VALUES ('team@g.us', '', 'new-message', 'member@s.whatsapp.net',
                        'Sam', 11, 0, 'new', '')"""
            )
        with mock.patch.object(self.backend, "_notify_send_ready", return_value=True), \
                mock.patch.object(self.backend, "_deliver_notification", return_value=False):
            result = self.backend.notify()
        self.assertEqual(result["failed"], 1)
        state = self.backend._account_state()
        self.assertEqual(state["notified"]["team@g.us"]["timestamp"], 10)

        with mock.patch.object(self.backend, "_notify_send_ready", return_value=True), \
                mock.patch.object(self.backend, "_deliver_notification", return_value=True):
            result = self.backend.notify()
        self.assertEqual(result["sent"], 1)
        self.assertEqual(self.backend._account_state()["notified"]["team@g.us"]["timestamp"], 11)

    def test_notification_detects_a_second_message_in_the_same_second(self) -> None:
        with mock.patch.object(self.backend, "_notify_send_ready", return_value=True):
            self.backend.set_notifications(True, True)
        with closing(sqlite3.connect(self.store / "wacli.db")) as connection, connection:
            connection.execute(
                "UPDATE chats SET unread_count = 2 WHERE jid = ?", ["team@g.us"]
            )
            connection.execute(
                """INSERT INTO messages
                (chat_jid, chat_name, msg_id, sender_jid, sender_name, ts,
                 from_me, text, reaction_to_id)
                VALUES ('team@g.us', '', 'same-second-message',
                        'member@s.whatsapp.net', 'Sam', 10, 0, 'new', '')"""
            )
        with mock.patch.object(self.backend, "_notify_send_ready", return_value=True), \
                mock.patch.object(self.backend, "_deliver_notification", return_value=True):
            result = self.backend.notify()
        self.assertEqual(result["sent"], 1)
        snapshot = self.backend._account_state()["notified"]["team@g.us"]
        self.assertEqual(snapshot["message_id"], "same-second-message")

    def test_clipboard_stage_is_private_and_promoted_only_after_send(self) -> None:
        runtime = self.root / "runtime"
        with mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": str(runtime)}), \
                mock.patch.object(self.backend, "_clipboard_types", return_value=["image/gif"]), \
                mock.patch.object(self.backend, "_clipboard", return_value=b"GIF89a"):
            staged_result = self.backend.paste("team@g.us")
            staged = Path(staged_result["path"].removeprefix("file://"))
            self.assertEqual(staged.parent.stat().st_mode & 0o777, 0o700)
            self.assertEqual(staged.stat().st_mode & 0o777, 0o600)
            with mock.patch.object(
                self.backend,
                "send_file",
                return_value={"ok": True, "kind": "image", "local_path": str(staged)},
            ):
                result = self.backend.send_files("team@g.us", [str(staged)])
            self.assertFalse(staged.exists())
            promoted = Path(result["items"][0]["local_path"])
            self.assertTrue(promoted.exists())
            self.assertRegex(promoted.name, backend_module.CLIPBOARD_SENT_PATTERN)
            self.assertTrue(result["items"][0]["staged_promoted"])

            with mock.patch.object(self.backend, "_clipboard", return_value=b"GIF89a"):
                abandoned = Path(
                    self.backend.paste("team@g.us")["path"].removeprefix("file://")
                )
            discarded = self.backend.discard_clipboard_stage(abandoned.as_uri())
            self.assertTrue(discarded["discarded"])
            self.assertFalse(abandoned.exists())
            self.assertFalse(
                self.backend.discard_clipboard_stage(str(promoted))["discarded"]
            )
            self.assertTrue(promoted.exists())

            with mock.patch.object(self.backend, "_clipboard", return_value=b"GIF89a"):
                retry = Path(self.backend.paste("team@g.us")["path"].removeprefix("file://"))
            with mock.patch.object(
                self.backend,
                "send_file",
                side_effect=backend_module.OmaWhatsAppError("rejected"),
            ), self.assertRaisesRegex(backend_module.OmaWhatsAppError, "rejected"):
                self.backend.send_files("team@g.us", [str(retry)])
            self.assertTrue(retry.exists())

        # A paste may sit in the composer longer than the existing cache. Its
        # successful promotion must refresh recency instead of immediately
        # evicting the attachment whose hint is about to be returned.
        bounded_runtime = self.root / "bounded-runtime"
        with mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": str(bounded_runtime)}), \
                mock.patch.object(backend_module, "MAX_CLIPBOARD_SENT_FILES", 2):
            pending = self.backend._stage_clipboard_image(b"new", ".png")
            stage = pending.parent
            first = stage / ("sent-" + "1" * 32 + ".png")
            second = stage / ("sent-" + "2" * 32 + ".png")
            first.write_bytes(b"first")
            second.write_bytes(b"second")
            os.utime(pending, ns=(1, 1))
            os.utime(first, ns=(2, 2))
            os.utime(second, ns=(3, 3))
            promoted = self.backend._promote_clipboard_stage(pending)
            self.assertIsNotNone(promoted)
            self.assertTrue(promoted.is_file())
            self.assertEqual(
                len([path for path in stage.iterdir()
                     if backend_module.CLIPBOARD_SENT_PATTERN.fullmatch(path.name)]),
                2,
            )
            self.assertFalse(first.exists())
            self.assertTrue(second.exists())

        unsafe_runtime = self.root / "unsafe-runtime"
        unsafe_runtime.mkdir()
        victim = self.root / "victim"
        victim.mkdir()
        (unsafe_runtime / "omawhatsapp").symlink_to(victim, target_is_directory=True)
        with mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": str(unsafe_runtime)}), \
                mock.patch.object(self.backend, "_clipboard_types", return_value=["image/png"]), \
                mock.patch.object(self.backend, "_clipboard", return_value=b"png"), \
                self.assertRaisesRegex(backend_module.OmaWhatsAppError, "staging directory"):
            self.backend.paste("team@g.us")
        self.assertEqual(list(victim.iterdir()), [])

    def test_clipboard_promotion_cleanup_failures_keep_a_live_sent_preview(self) -> None:
        runtime = self.root / "promotion-runtime"
        for failing_call in ("utime", "listdir"):
            with self.subTest(failing_call=failing_call), \
                    mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": str(runtime)}):
                pending = self.backend._stage_clipboard_image(b"preview", ".png")
                delivered = {
                    "ok": True,
                    "kind": "image",
                    "id": f"delivered-{failing_call}",
                    "local_path": str(pending),
                    "mime_type": "image/png",
                    "media_type": "image",
                }
                cleanup = mock.patch.object(
                    backend_module.os, failing_call,
                    side_effect=OSError("synthetic housekeeping failure"),
                )
                with cleanup, \
                        mock.patch.object(
                            self.backend, "send_file", return_value=delivered
                        ), \
                        mock.patch.object(
                            self.backend, "_remember_sent_media_best_effort",
                            return_value=True,
                        ) as remember:
                    result = self.backend.send_files("team@g.us", [str(pending)])
                promoted = Path(result["items"][0]["local_path"])
                self.assertTrue(result["items"][0]["staged_promoted"])
                self.assertTrue(promoted.is_file())
                self.assertFalse(pending.exists())
                self.assertTrue(
                    backend_module.CLIPBOARD_SENT_PATTERN.fullmatch(promoted.name)
                )
                self.assertEqual(remember.call_args.args[2], promoted)

    def test_partial_mixed_send_reports_only_safe_retry_paths(self) -> None:
        runtime = self.root / "partial-runtime"
        external = self.root / "external.pdf"
        remaining = self.root / "remaining.pdf"
        external.write_bytes(b"external")
        remaining.write_bytes(b"remaining")
        calls = 0

        def send_file(_jid: str, path: Path, mime: str, *_args: object) -> dict:
            nonlocal calls
            calls += 1
            if calls == 3:
                raise backend_module.OmaWhatsAppError("fixture rejection")
            return {
                "ok": True,
                "kind": "image" if path.suffix == ".png" else "file",
                "id": f"sent-{calls}",
                "local_path": str(path),
                "mime_type": mime,
                "media_type": "image" if path.suffix == ".png" else "document",
            }

        with mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": str(runtime)}):
            staged = self.backend._stage_clipboard_image(b"png", ".png")
            with mock.patch.object(self.backend, "send_file", side_effect=send_file), \
                    self.assertRaises(backend_module.OmaWhatsAppPartialError) as raised:
                self.backend.send_files(
                    "team@g.us", [str(external), str(staged), str(remaining)]
                )

        error = raised.exception
        self.assertIn("Do not retry", str(error))
        self.assertEqual(error.partial["sent_count"], 2)
        self.assertEqual(error.partial["sent_paths"], [str(external), str(staged)])
        self.assertEqual(error.partial["remaining_paths"], [str(remaining)])
        self.assertFalse(staged.exists())
        promoted = Path(error.partial["items"][1]["local_path"])
        self.assertRegex(promoted.name, backend_module.CLIPBOARD_SENT_PATTERN)
        self.assertTrue(promoted.exists())

    def test_preview_bookkeeping_never_makes_a_delivered_file_retryable(self) -> None:
        delivered = self.root / "delivered.pdf"
        delivered.write_bytes(b"delivered")
        with mock.patch.object(
            self.backend, "_write", return_value=self.completed({
                "id": "delivered-id",
                "file": {"name": delivered.name,
                         "mime_type": "application/pdf", "media": "document"},
            })
        ), mock.patch.object(
            self.backend, "_remember_sent_media",
            side_effect=backend_module.OmaWhatsAppError("state is full"),
        ):
            result = self.backend.send_files("team@g.us", [str(delivered)])
        self.assertTrue(result["ok"])
        self.assertEqual(result["count"], 1)
        self.assertEqual(result["items"][0]["id"], "delivered-id")

    def test_corrupt_hint_timestamps_never_turn_delivery_into_a_retry(self) -> None:
        delivered = self.root / "delivered-corrupt-state.pdf"
        delivered.write_bytes(b"delivered")
        hints = {
            self.backend._sent_hint_key("team@g.us", f"old-{index}"): {
                "local_path": str(delivered),
                "saved_at": {"not": "an integer"} if index == 0 else index,
            }
            for index in range(backend_module.MAX_SENT_MEDIA_HINTS + 1)
        }
        self.backend._write_state_json(
            "sent-media.json", hints, backend_module.MAX_SENT_MEDIA_STATE
        )
        with mock.patch.object(
            self.backend, "_write", return_value=self.completed({
                "id": "delivered-corrupt-state",
                "file": {"name": delivered.name,
                         "mime_type": "application/pdf", "media": "document"},
            })
        ):
            result = self.backend.send_file(
                "team@g.us", delivered, "application/pdf"
            )
        self.assertTrue(result["ok"])
        self.assertEqual(result["id"], "delivered-corrupt-state")

    def test_concurrent_sent_media_updates_never_drop_each_other(self) -> None:
        second = backend_module.Backend(
            store_dir=self.store,
            state_dir=self.root / "state",
            wacli=self.wacli,
            account_config=self.root / "absent.yaml",
        )
        first_file = self.root / "first.png"
        second_file = self.root / "second.png"
        first_file.write_bytes(b"first")
        second_file.write_bytes(b"second")
        barrier = threading.Barrier(2)
        original_write = backend_module.Backend._write_state_json

        def delayed_write(instance: object, *args: object) -> None:
            time.sleep(0.001)
            original_write(instance, *args)

        def remember(instance: object, prefix: str, path: Path) -> None:
            barrier.wait()
            for index in range(20):
                instance._remember_sent_media(
                    "team@g.us", f"{prefix}-{index}", path, "image/png", "image"
                )

        with mock.patch.object(
            backend_module.Backend, "_write_state_json", new=delayed_write
        ), ThreadPoolExecutor(max_workers=2) as pool:
            futures = [
                pool.submit(remember, self.backend, "first", first_file),
                pool.submit(remember, second, "second", second_file),
            ]
            for future in futures:
                future.result(timeout=10)

        hints = json.loads(
            (self.root / "state" / "sent-media.json").read_text(encoding="utf-8")
        )
        self.assertEqual(len(hints), 40)

    def test_release_scripts_pin_version_and_reconcile_stale_instances(self) -> None:
        source = SCRIPT.parent.parent
        installer = (source / "scripts" / "install").read_text(encoding="utf-8")
        parity = (source / "scripts" / "check-wacli-parity").read_text(encoding="utf-8")
        self.assertIn("[[ $wacli_version != 0.17.1 ]]", installer)
        self.assertIn("list-unit-files", installer)
        self.assertIn("list-units --all", installer)
        self.assertIn("requires exactly wacli", parity)


class AccountLifecycleTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.wacli = self.root / "wacli"
        self.wacli.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        self.wacli.chmod(0o700)
        self.work_store = self.root / "work"
        self.home_store = self.root / "home"
        for store in (self.work_store, self.home_store):
            store.mkdir()
            with closing(sqlite3.connect(store / "wacli.db")) as connection, connection:
                connection.executescript(SCHEMA)
        self.work = backend_module.Account("work", self.work_store, True)
        self.home = backend_module.Account("home", self.home_store, False)
        self.backend = backend_module.Backend(
            store_dir=self.work_store,
            state_dir=self.root / "state",
            wacli=self.wacli,
            account_config=self.root / "absent.yaml",
        )
        self.backend._accounts = [self.work, self.home]
        self.backend._active = self.work

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def _online(self, account: object, value: bool) -> None:
        self.backend._update_account_state(
            lambda state: state.update({"online": value}), account
        )

    def test_foreground_sync_checks_and_restarts_only_the_selected_account(self) -> None:
        self._online(self.work, True)
        self._online(self.home, False)
        with mock.patch.object(backend_module.subprocess, "run") as run, \
                self.assertRaisesRegex(backend_module.OmaWhatsAppError, "Offline mode"):
            self.backend.transport_interactive(
                ["sync", "--once"], authorization="sync", account="home"
            )
        run.assert_not_called()

        self._online(self.work, False)
        self._online(self.home, True)
        completed = subprocess.CompletedProcess([], 0, "", "")
        with mock.patch.object(self.backend, "_unit_active", return_value=True), \
                mock.patch.object(
                    self.backend, "_systemctl_user", return_value=completed
                ) as systemctl, \
                mock.patch.object(
                    backend_module.subprocess, "run", return_value=completed
                ) as run:
            code = self.backend.transport_interactive(
                ["sync", "--once"], authorization="sync", account="home"
            )
        self.assertEqual(code, 0)
        self.assertEqual(run.call_args.args[0], [
            str(self.wacli), "--account", "home", "sync", "--once"
        ])
        commands = [call.args[0] for call in systemctl.call_args_list]
        self.assertEqual(commands, [
            ["stop", "wacli-sync@home.service"],
            ["start", "wacli-sync@home.service"],
        ])

    def test_linking_an_inactive_named_account_starts_only_its_unit(self) -> None:
        self._online(self.home, True)
        (self.home_store / "session.db").write_bytes(b"synthetic-session")
        completed = subprocess.CompletedProcess([], 0, "", "")
        with mock.patch.object(self.backend, "_unit_active", return_value=False), \
                mock.patch.object(
                    self.backend, "_systemctl_user", return_value=completed
                ) as systemctl, mock.patch.object(
                    backend_module.subprocess, "run", return_value=completed
                ) as run:
            code = self.backend.transport_interactive(
                ["auth"], authorization="interactive", account="home"
            )
        self.assertEqual(code, 0)
        self.assertEqual(run.call_args.args[0], [
            str(self.wacli), "--account", "home", "auth"
        ])
        systemctl.assert_called_once_with([
            "enable", "--now", "wacli-sync@home.service"
        ])

    def test_link_success_reports_partial_when_background_sync_cannot_start(self) -> None:
        self._online(self.home, True)
        completed = subprocess.CompletedProcess([], 0, "", "")
        with mock.patch.object(self.backend, "_unit_active", return_value=True), \
                mock.patch.object(
                    self.backend, "_systemctl_user",
                    side_effect=[completed, backend_module.OmaWhatsAppError("start failed")],
                ), mock.patch.object(
                    backend_module.subprocess, "run", return_value=completed
                ), self.assertRaises(backend_module.OmaWhatsAppPartialError) as raised:
            self.backend.transport_interactive(
                ["auth"], authorization="interactive", account="home"
            )
        self.assertTrue(raised.exception.partial["committed"])
        self.assertEqual(raised.exception.partial["account"], "home")

    def test_interrupted_terminal_link_always_restores_active_sync(self) -> None:
        self._online(self.home, True)
        completed = subprocess.CompletedProcess([], 0, "", "")
        observed_intent = []

        def interrupt(*args, **kwargs):
            observed_intent.extend(self.backend._lifecycle_recovery_units())
            raise KeyboardInterrupt

        with mock.patch.object(self.backend, "_unit_active", return_value=True), \
                mock.patch.object(
                    self.backend, "_systemctl_user", return_value=completed
                ) as systemctl, mock.patch.object(
                    backend_module.subprocess, "run", side_effect=interrupt
                ), self.assertRaises(KeyboardInterrupt):
            self.backend.transport_interactive(
                ["auth"], authorization="interactive", account="home"
            )
        self.assertEqual(
            [call.args[0] for call in systemctl.call_args_list],
            [["stop", "wacli-sync@home.service"],
             ["start", "wacli-sync@home.service"]],
        )
        self.assertEqual(observed_intent, ["wacli-sync@home.service"])
        self.assertEqual(self.backend._lifecycle_recovery_units(), [])

    def test_lock_contention_recovery_is_serialized_per_account(self) -> None:
        self._online(self.home, True)
        self.backend.use_account("home")
        locked = subprocess.CompletedProcess([], 1, "", "store is locked")
        success = subprocess.CompletedProcess([], 0, '{"success":true}', "")
        systemctl_result = subprocess.CompletedProcess([], 0, "", "")
        with mock.patch.object(
            self.backend, "_run", side_effect=[locked, locked, success]
        ), mock.patch.object(self.backend, "_sync_active", return_value=True), \
                mock.patch.object(backend_module.time, "sleep"), \
                mock.patch.object(
                    self.backend, "_systemctl_user", return_value=systemctl_result
                ) as systemctl:
            result = self.backend._write(["--json", "send", "text"], timeout=10)
        self.assertEqual(result.returncode, 0)
        commands = [call.args[0] for call in systemctl.call_args_list]
        self.assertEqual(commands, [
            ["stop", "wacli-sync@home.service"],
            ["start", "wacli-sync@home.service"],
        ])
        self.assertNotEqual(
            self.backend._lifecycle_lock_name(self.work),
            self.backend._lifecycle_lock_name(self.home),
        )

    def test_ambiguous_stop_failure_keeps_durable_recovery_intent(self) -> None:
        self._online(self.home, True)
        self.backend.use_account("home")
        locked = subprocess.CompletedProcess([], 1, "", "store is locked")
        with mock.patch.object(
                self.backend, "_run", side_effect=[locked, locked]), \
                mock.patch.object(self.backend, "_sync_active", return_value=True), \
                mock.patch.object(self.backend, "_unit_active", return_value=False), \
                mock.patch.object(
                    self.backend, "_systemctl_user",
                    side_effect=backend_module.OmaWhatsAppError("stop uncertain"),
                ), self.assertRaisesRegex(
                    backend_module.OmaWhatsAppError, "stop uncertain"
                ):
            self.backend._write(["--json", "send", "text"], timeout=10)
        self.assertEqual(
            self.backend._lifecycle_recovery_units(),
            ["wacli-sync@home.service"],
        )

    def test_committed_mutation_reports_partial_when_sync_restart_fails(self) -> None:
        self._online(self.home, True)
        self.backend.use_account("home")
        locked = subprocess.CompletedProcess([], 1, "", "store is locked")
        success = subprocess.CompletedProcess([], 0, '{"success":true}', "")
        systemctl_result = subprocess.CompletedProcess([], 0, "", "")
        with mock.patch.object(
            self.backend, "_run", side_effect=[locked, locked, success]
        ), mock.patch.object(self.backend, "_sync_active", return_value=True), \
                mock.patch.object(
                    self.backend, "_systemctl_user",
                    side_effect=[systemctl_result,
                                 backend_module.OmaWhatsAppError("restart rejected")],
                ), self.assertRaises(backend_module.OmaWhatsAppPartialError) as raised:
            self.backend._write(["--json", "send", "text"], timeout=10)
        self.assertTrue(raised.exception.partial["committed"])
        self.assertEqual(raised.exception.partial["account"], "home")

    def test_systemctl_timeout_is_always_a_domain_error(self) -> None:
        with mock.patch.object(
            backend_module, "run_bounded",
            side_effect=subprocess.TimeoutExpired(["systemctl"], 20),
        ), self.assertRaisesRegex(
            backend_module.OmaWhatsAppError, "too long"
        ):
            self.backend._systemctl_user(["stop", self.home.unit])

    def test_one_off_store_never_stops_the_default_sync_service(self) -> None:
        locked = subprocess.CompletedProcess([], 1, "", "store is locked")
        success = subprocess.CompletedProcess([], 0, '{"success":true}', "")
        with mock.patch.object(backend_module, "HOME", self.root), \
                mock.patch.object(
                    self.backend, "_run", side_effect=[locked, locked, success]
                ), mock.patch.object(self.backend, "_unit_active") as unit_active, \
                mock.patch.object(backend_module.time, "sleep"):
            result = self.backend.transport({
                "args": ["sync", "--once"],
                "authorization": "sync",
                "store": str(self.home_store),
            })
        self.assertTrue(result["ok"])
        unit_active.assert_not_called()


if __name__ == "__main__":
    unittest.main()
