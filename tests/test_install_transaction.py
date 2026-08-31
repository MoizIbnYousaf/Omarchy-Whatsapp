from __future__ import annotations

import json
import hashlib
import importlib.util
import os
from pathlib import Path
import stat
import subprocess
import shutil
import tempfile
import textwrap
from types import SimpleNamespace
import unittest
from unittest import mock


SOURCE = Path(__file__).resolve().parent.parent
HELPER = SOURCE / "scripts" / "install-transaction.py"
UNINSTALL = SOURCE / "scripts" / "uninstall"
PLUGIN_ID = "io.github.moizibnyousaf.omawhatsapp"


def load_transaction_module() -> object:
    spec = importlib.util.spec_from_file_location("omaw_install_transaction", HELPER)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class TransactionFixture:
    def __init__(self, root: Path) -> None:
        self.root = root
        self.state = root / "state"
        self.stage = self.state / "stage.test"
        self.live = root / "live"
        self.state.mkdir()
        self.stage.mkdir()
        self.live.mkdir()

        self.old_directory = self.live / "plugin"
        self.old_directory.mkdir()
        (self.old_directory / "value").write_text("old directory\n", encoding="utf-8")
        self.new_directory = self.stage / "plugin"
        self.new_directory.mkdir()
        (self.new_directory / "value").write_text("new directory\n", encoding="utf-8")

        self.new_file = self.stage / "helper"
        self.new_file.write_text("new helper\n", encoding="utf-8")
        self.new_file.chmod(0o755)
        self.absent_file = self.live / "helper"

        self.legacy = self.live / "legacy"
        self.legacy.write_text("legacy\n", encoding="utf-8")
        self.journal = self.state / "transaction.json"
        self.plan = self.root / "plan.json"
        self.plan.write_text(
            json.dumps(
                {
                    "mode": "install",
                    "staging_root": str(self.stage),
                    "units": [
                        {"name": "wacli-sync.service", "enabled": True, "active": False}
                    ],
                    "targets": [
                        {
                            "operation": "replace",
                            "staged": str(self.new_directory),
                            "target": str(self.old_directory),
                        },
                        {
                            "operation": "replace",
                            "staged": str(self.new_file),
                            "target": str(self.absent_file),
                        },
                        {"operation": "remove", "target": str(self.legacy)},
                    ],
                }
            ),
            encoding="utf-8",
        )

    def run(self, command: str, *, kill_at: str | None = None) -> subprocess.CompletedProcess[str]:
        environment = os.environ.copy()
        if kill_at is not None:
            environment["OMAW_INSTALL_TEST_KILL_AT"] = kill_at
        return subprocess.run(
            ["python3", str(HELPER), command, "--journal", str(self.journal)],
            text=True,
            capture_output=True,
            env=environment,
            check=False,
        )

    def begin(self, *, kill_at: str | None = None) -> subprocess.CompletedProcess[str]:
        environment = os.environ.copy()
        if kill_at is not None:
            environment["OMAW_INSTALL_TEST_KILL_AT"] = kill_at
        return subprocess.run(
            [
                "python3",
                str(HELPER),
                "begin",
                "--journal",
                str(self.journal),
                "--plan",
                str(self.plan),
            ],
            text=True,
            capture_output=True,
            env=environment,
            check=False,
        )

    def start(self) -> None:
        begin = self.begin()
        if begin.returncode != 0:
            raise AssertionError(begin.stderr)
        prepare = self.run("prepare")
        if prepare.returncode != 0:
            raise AssertionError(prepare.stderr)

    def assert_original(self, case: unittest.TestCase) -> None:
        case.assertEqual(
            (self.old_directory / "value").read_text(encoding="utf-8"),
            "old directory\n",
        )
        case.assertFalse(self.absent_file.exists())
        case.assertEqual(self.legacy.read_text(encoding="utf-8"), "legacy\n")
        case.assertFalse(self.journal.exists())
        artifacts = [path.name for path in self.live.iterdir() if ".omawhatsapp-" in path.name]
        case.assertEqual(artifacts, [])


class InstallTransactionTests(unittest.TestCase):
    def test_every_begin_kill_point_recovers_exact_originals(self) -> None:
        points = {
            "begin": ["after-initial-journal", "after-begin"],
            "mark-shell-stop": ["after-mark-shell-stop"],
            "prepare": [
                "after-prepare-intent:0",
                "after-prepare-copy:0",
                "after-prepare-intent:1",
                "after-prepare-copy:1",
                "after-prepare",
            ],
        }
        for command, command_points in points.items():
            for point in command_points:
                with self.subTest(command=command, point=point), tempfile.TemporaryDirectory() as temporary:
                    fixture = TransactionFixture(Path(temporary))
                    if command == "begin":
                        result = fixture.begin(kill_at=point)
                    else:
                        self.assertEqual(fixture.begin().returncode, 0)
                        result = fixture.run(command, kill_at=point)
                    self.assertEqual(result.returncode, -signal_number("KILL"))
                    self.assertEqual(fixture.run("rollback-files").returncode, 0)
                    self.assertEqual(fixture.run("finish-rollback").returncode, 0)
                    fixture.assert_original(self)

    def test_every_apply_kill_point_recovers_exact_originals(self) -> None:
        points = [
            "after-backup-intent:0",
            "after-backup:0",
            "after-publish-intent:0",
            "after-publish:0",
            "after-backup-intent:1",
            "after-backup:1",
            "after-publish-intent:1",
            "after-publish:1",
            "after-backup-intent:2",
            "after-backup:2",
            "after-apply",
        ]
        for point in points:
            with self.subTest(point=point), tempfile.TemporaryDirectory() as temporary:
                fixture = TransactionFixture(Path(temporary))
                fixture.start()
                result = fixture.run("apply", kill_at=point)
                self.assertEqual(result.returncode, -signal_number("KILL"))
                self.assertEqual(fixture.run("rollback-files").returncode, 0)
                self.assertEqual(fixture.run("finish-rollback").returncode, 0)
                fixture.assert_original(self)

    def test_rollback_and_cleanup_are_restartable_after_kill(self) -> None:
        for command, point in (
            ("rollback-files", "after-files-restored"),
            ("finish-rollback", "after-rollback"),
        ):
            with self.subTest(point=point), tempfile.TemporaryDirectory() as temporary:
                fixture = TransactionFixture(Path(temporary))
                fixture.start()
                self.assertEqual(fixture.run("apply").returncode, 0)
                if command == "finish-rollback":
                    self.assertEqual(fixture.run("rollback-files").returncode, 0)
                result = fixture.run(command, kill_at=point)
                self.assertEqual(result.returncode, -signal_number("KILL"))
                self.assertEqual(fixture.run("rollback-files").returncode, 0)
                self.assertEqual(fixture.run("finish-rollback").returncode, 0)
                fixture.assert_original(self)

    def test_committed_cleanup_recovery_preserves_new_version(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = TransactionFixture(Path(temporary))
            fixture.start()
            self.assertEqual(fixture.run("apply").returncode, 0)
            self.assertEqual(fixture.run("mark-units").returncode, 0)
            self.assertEqual(fixture.run("mark-validated").returncode, 0)
            result = fixture.run("commit", kill_at="after-commit")
            self.assertEqual(result.returncode, -signal_number("KILL"))
            metadata = json.loads(fixture.run("metadata").stdout)
            self.assertEqual(metadata["phase"], "committed")
            self.assertEqual(fixture.run("commit").returncode, 0)
            self.assertEqual(
                (fixture.old_directory / "value").read_text(encoding="utf-8"),
                "new directory\n",
            )
            self.assertEqual(fixture.absent_file.read_text(encoding="utf-8"), "new helper\n")
            self.assertEqual(stat.S_IMODE(fixture.absent_file.stat().st_mode), 0o755)
            self.assertFalse(fixture.legacy.exists())
            self.assertFalse(fixture.journal.exists())

    def test_recovery_refuses_to_clobber_a_changed_live_target(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = TransactionFixture(Path(temporary))
            fixture.start()
            result = fixture.run("apply", kill_at="after-publish:0")
            self.assertEqual(result.returncode, -signal_number("KILL"))
            (fixture.old_directory / "value").write_text("changed elsewhere\n", encoding="utf-8")
            recovery = fixture.run("rollback-files")
            self.assertNotEqual(recovery.returncode, 0)
            self.assertIn("refusing to clobber", recovery.stderr)
            self.assertTrue(fixture.journal.exists())

    def test_expected_merge_source_rejects_changes_before_and_during_rename(self) -> None:
        for race in ("before-apply", "during-rename"):
            with self.subTest(race=race), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                state = root / "state"
                stage = state / "stage.test"
                live = root / "live"
                stage.mkdir(parents=True)
                live.mkdir()
                shell = live / "shell.json"
                shell.write_text("old merge source\n", encoding="utf-8")
                staged = stage / "shell.json"
                staged.write_text("stale merged output\n", encoding="utf-8")
                expected = hashlib.sha256(shell.read_bytes()).hexdigest()
                plan = root / "plan.json"
                plan.write_text(
                    json.dumps(
                        {
                            "mode": "install",
                            "staging_root": str(stage),
                            "targets": [
                                {
                                    "operation": "replace",
                                    "staged": str(staged),
                                    "target": str(shell),
                                    "expected_sha256": expected,
                                }
                            ],
                        }
                    ),
                    encoding="utf-8",
                )
                journal = state / "transaction.json"
                begin = subprocess.run(
                    [
                        "python3",
                        str(HELPER),
                        "begin",
                        "--journal",
                        str(journal),
                        "--plan",
                        str(plan),
                    ],
                    text=True,
                    capture_output=True,
                    check=False,
                )
                self.assertEqual(begin.returncode, 0, begin.stderr)
                prepare = subprocess.run(
                    ["python3", str(HELPER), "prepare", "--journal", str(journal)],
                    text=True,
                    capture_output=True,
                    check=False,
                )
                self.assertEqual(prepare.returncode, 0, prepare.stderr)

                if race == "before-apply":
                    shell.write_text("concurrent value\n", encoding="utf-8")
                    apply = subprocess.run(
                        ["python3", str(HELPER), "apply", "--journal", str(journal)],
                        text=True,
                        capture_output=True,
                        check=False,
                    )
                    self.assertNotEqual(apply.returncode, 0)
                    self.assertIn("merge source changed before publication", apply.stderr)
                else:
                    module = load_transaction_module()
                    original_rename = module.rename_noreplace

                    def race_rename(source: Path, target: Path) -> None:
                        if source == shell:
                            replacement = live / "concurrent.json"
                            replacement.write_text("concurrent value\n", encoding="utf-8")
                            os.replace(replacement, shell)
                        original_rename(source, target)

                    with mock.patch.object(module, "rename_noreplace", new=race_rename):
                        with self.assertRaisesRegex(
                            module.TransactionError, "changed during publication"
                        ):
                            module.command_apply(SimpleNamespace(journal=str(journal)))

                for command in ("rollback-files", "finish-rollback"):
                    result = subprocess.run(
                        ["python3", str(HELPER), command, "--journal", str(journal)],
                        text=True,
                        capture_output=True,
                        check=False,
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(shell.read_text(encoding="utf-8"), "concurrent value\n")

    def test_relative_journal_and_root_target_are_rejected_without_writes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            relative = subprocess.run(
                ["python3", str(HELPER), "metadata", "--journal", "relative/transaction.json"],
                cwd=root,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertNotEqual(relative.returncode, 0)
            self.assertFalse((root / "relative").exists())

            state = root / "state"
            stage = state / "stage.test"
            stage.mkdir(parents=True)
            staged = stage / "payload"
            staged.write_text("safe\n", encoding="utf-8")
            plan = root / "root-plan.json"
            plan.write_text(
                json.dumps(
                    {
                        "mode": "uninstall",
                        "staging_root": str(stage),
                        "targets": [
                            {"operation": "replace", "staged": str(staged), "target": "/"}
                        ],
                    }
                ),
                encoding="utf-8",
            )
            result = subprocess.run(
                [
                    "python3",
                    str(HELPER),
                    "begin",
                    "--journal",
                    str(state / "transaction.json"),
                    "--plan",
                    str(plan),
                ],
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((state / "transaction.json").exists())

    def test_journal_can_live_on_a_different_filesystem(self) -> None:
        shared_memory = Path("/dev/shm")
        if not shared_memory.is_dir() or os.stat(shared_memory).st_dev == os.stat("/tmp").st_dev:
            self.skipTest("no writable second filesystem is available")
        with tempfile.TemporaryDirectory(dir=shared_memory) as state_temporary, \
                tempfile.TemporaryDirectory(dir="/tmp") as live_temporary:
            state_root = Path(state_temporary)
            stage = state_root / "stage.test"
            stage.mkdir()
            staged = stage / "helper"
            staged.write_text("new\n", encoding="utf-8")
            target = Path(live_temporary) / "helper"
            target.write_text("old\n", encoding="utf-8")
            plan = state_root / "plan.json"
            plan.write_text(
                json.dumps(
                    {
                        "mode": "install",
                        "staging_root": str(stage),
                        "targets": [
                            {"operation": "replace", "staged": str(staged), "target": str(target)}
                        ],
                    }
                ),
                encoding="utf-8",
            )
            journal = state_root / "transaction.json"
            commands = (
                ["begin", "--plan", str(plan)],
                ["prepare"],
                ["apply"],
                ["mark-validated"],
                ["commit"],
            )
            for command in commands:
                result = subprocess.run(
                    ["python3", str(HELPER), command[0], "--journal", str(journal), *command[1:]],
                    text=True,
                    capture_output=True,
                    check=False,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(target.read_text(encoding="utf-8"), "new\n")


def signal_number(name: str) -> int:
    import signal

    return int(getattr(signal, f"SIG{name}"))


class UninstallEnvironmentTests(unittest.TestCase):
    def test_lifecycle_order_is_journal_stop_prepare_apply_units_commit(self) -> None:
        for script in (SOURCE / "scripts" / "install", UNINSTALL):
            with self.subTest(script=script.name):
                source = script.read_text(encoding="utf-8")
                positions = [
                    source.index('begin --journal "$transaction_journal"'),
                    source.index('mark-shell-stop --journal "$transaction_journal"'),
                    source.index("omaw_stop_shell"),
                    source.index('prepare --journal "$transaction_journal"'),
                    source.index('apply --journal "$transaction_journal"'),
                    source.index('mark-units --journal "$transaction_journal"'),
                    source.index("systemctl --user daemon-reload"),
                    source.index('commit --journal "$transaction_journal"'),
                ]
                self.assertEqual(positions, sorted(positions))
                self.assertIn("omarchy-restart-shell 9>&-", source)
        install_source = (SOURCE / "scripts" / "install").read_text(encoding="utf-8")
        self.assertIn(
            "if ! $check_only && [[ -e $transaction_journal || -L $transaction_journal ]]",
            install_source,
        )

    def make_fake_commands(self, root: Path) -> tuple[Path, Path]:
        fake_bin = root / "fake-bin"
        fake_state = root / "fake-systemctl"
        fake_bin.mkdir()
        (fake_state / "enabled").mkdir(parents=True)
        (fake_state / "active").mkdir()
        for unit in ("wacli-sync.service", "wacli-sync@work.service"):
            (fake_state / "enabled" / unit).touch()
            (fake_state / "active" / unit).touch()
        systemctl = fake_bin / "systemctl"
        systemctl.write_text(
            textwrap.dedent(
                """\
                #!/usr/bin/env python3
                import os
                from pathlib import Path
                import sys

                args = sys.argv[1:]
                if args and args[0] == "--user":
                    args = args[1:]
                command = args[0]
                state = Path(os.environ["FAKE_SYSTEMCTL_STATE"])
                if command == "list-unit-files":
                    print("wacli-sync@work.service enabled")
                elif command == "list-units":
                    print("wacli-sync@work.service loaded active running")
                elif command in {"is-enabled", "is-active"}:
                    unit = args[-1]
                    category = "enabled" if command == "is-enabled" else "active"
                    raise SystemExit(0 if (state / category / unit).exists() else 1)
                elif command in {"enable", "disable", "start", "stop", "restart"}:
                    unit = args[-1]
                    categories = []
                    if command == "enable": categories = ["enabled"]
                    if command == "disable": categories = ["enabled"]
                    if command == "start": categories = ["active"]
                    if command == "stop": categories = ["active"]
                    if command == "restart": categories = ["active"]
                    if "--now" in args:
                        categories = ["enabled", "active"]
                    for category in categories:
                        marker = state / category / unit
                        if command in {"disable", "stop"}:
                            marker.unlink(missing_ok=True)
                        else:
                            marker.touch()
                elif command != "daemon-reload":
                    raise SystemExit(f"unexpected systemctl command: {args}")
                """
            ),
            encoding="utf-8",
        )
        systemctl.chmod(0o755)
        for name, body in (
            (
                "quickshell",
                "#!/bin/sh\n"
                "if [ \"${FAKE_QUICKSHELL_TIMEOUT:-0}\" = 1 ]; then exit 124; fi\n"
                "if [ \"${1:-}\" = list ]; then printf '[]\\n'; exit 0; fi\n"
                "printf down > \"$FAKE_SHELL_STATE\"\nexit 1\n",
            ),
            (
                "omarchy-restart-shell",
                "#!/bin/sh\n[ ! -e /proc/$$/fd/9 ] || exit 91\nprintf up > \"$FAKE_SHELL_STATE\"\nexit 0\n",
            ),
        ):
            command = fake_bin / name
            command.write_text(body, encoding="utf-8")
            command.chmod(0o755)
        return fake_bin, fake_state

    def populate_install(self, home: Path, service_root: Path, runtime: Path) -> None:
        plugin = home / ".config" / "omarchy" / "plugins" / PLUGIN_ID
        plugin.mkdir(parents=True)
        (plugin / "manifest.json").write_text("{}\n", encoding="utf-8")
        skill = home / ".agents" / "skills" / "omawhatsapp"
        skill.mkdir(parents=True)
        (skill / "SKILL.md").write_text("synthetic\n", encoding="utf-8")
        helper = home / ".local" / "bin" / "omawhatsapp"
        helper.parent.mkdir(parents=True)
        helper.write_text("synthetic\n", encoding="utf-8")
        service_root.mkdir(parents=True)
        for name in ("wacli-sync.service", "wacli-sync@.service"):
            (service_root / name).write_text("synthetic\n", encoding="utf-8")
        shell = home / ".config" / "omarchy" / "shell.json"
        shell.parent.mkdir(parents=True, exist_ok=True)
        shell.write_text(
            json.dumps(
                {
                    "plugins": [{"id": PLUGIN_ID}],
                    "bar": {"layout": {"left": [], "center": [], "right": [{"id": PLUGIN_ID}]}},
                }
            ),
            encoding="utf-8",
        )
        runtime.mkdir(parents=True)
        (runtime / "synthetic-state").write_text("state\n", encoding="utf-8")
        wacli = runtime.parent / "wacli"
        wacli.mkdir(exist_ok=True)
        (wacli / "preserve").write_text("linked device\n", encoding="utf-8")

    def run_uninstall(
        self,
        root: Path,
        home: Path,
        service_root: Path,
        runtime: Path,
        *,
        xdg_config: str,
        xdg_state: str,
    ) -> subprocess.CompletedProcess[str]:
        fake_bin, fake_state = self.make_fake_commands(root)
        self.populate_install(home, service_root, runtime)
        work = root / "work"
        work.mkdir()
        environment = os.environ.copy()
        environment.update(
            {
                "HOME": str(home),
                "XDG_CONFIG_HOME": xdg_config,
                "XDG_STATE_HOME": xdg_state,
                "PATH": f"{fake_bin}:{environment['PATH']}",
                "FAKE_SYSTEMCTL_STATE": str(fake_state),
                "FAKE_SHELL_STATE": str(root / "fake-shell-state"),
            }
        )
        return subprocess.run(
            [str(UNINSTALL), "--purge-runtime"],
            cwd=work,
            text=True,
            capture_output=True,
            env=environment,
            check=False,
        )

    def test_relative_xdg_falls_back_without_writing_into_cwd(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            home = root / "home"
            service_root = home / ".config" / "systemd" / "user"
            runtime = home / ".local" / "state" / "omawhatsapp"
            result = self.run_uninstall(
                root,
                home,
                service_root,
                runtime,
                xdg_config="relative-config",
                xdg_state="relative-state",
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse((root / "work" / "relative-config").exists())
            self.assertFalse((root / "work" / "relative-state").exists())
            self.assertFalse(runtime.exists())
            self.assertTrue((home / ".local" / "state" / "wacli" / "preserve").exists())
            self.assertFalse((service_root / "wacli-sync.service").exists())

    def test_absolute_custom_xdg_and_cross_device_state_are_honored(self) -> None:
        shared_memory = Path("/dev/shm")
        if not shared_memory.is_dir() or os.stat(shared_memory).st_dev == os.stat("/tmp").st_dev:
            self.skipTest("no writable second filesystem is available")
        with tempfile.TemporaryDirectory(dir="/tmp") as temporary, \
                tempfile.TemporaryDirectory(dir=shared_memory) as state_temporary:
            root = Path(temporary)
            home = root / "home"
            custom_config = root / "custom-config"
            custom_state = Path(state_temporary) / "custom-state"
            service_root = custom_config / "systemd" / "user"
            runtime = custom_state / "omawhatsapp"
            default_service = home / ".config" / "systemd" / "user" / "preserve.service"
            default_service.parent.mkdir(parents=True)
            default_service.write_text("preserve\n", encoding="utf-8")
            result = self.run_uninstall(
                root,
                home,
                service_root,
                runtime,
                xdg_config=str(custom_config),
                xdg_state=str(custom_state),
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(runtime.exists())
            self.assertTrue((custom_state / "wacli" / "preserve").exists())
            self.assertFalse((service_root / "wacli-sync.service").exists())
            self.assertTrue(default_service.exists())

    def test_kill_after_shell_stop_is_recovered_on_the_next_invocation(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            home = root / "home"
            service_root = home / ".config" / "systemd" / "user"
            runtime = home / ".local" / "state" / "omawhatsapp"
            fake_bin, fake_state = self.make_fake_commands(root)
            self.populate_install(home, service_root, runtime)
            work = root / "work"
            work.mkdir()
            shell_state = root / "fake-shell-state"
            environment = os.environ.copy()
            environment.update(
                {
                    "HOME": str(home),
                    "XDG_CONFIG_HOME": str(home / ".config"),
                    "XDG_STATE_HOME": str(home / ".local" / "state"),
                    "PATH": f"{fake_bin}:/usr/bin:/bin",
                    "FAKE_SYSTEMCTL_STATE": str(fake_state),
                    "FAKE_SHELL_STATE": str(shell_state),
                    "OMAW_INSTALL_TEST_KILL_AFTER_SHELL_STOP": "1",
                }
            )
            interrupted = subprocess.run(
                [str(UNINSTALL)],
                cwd=work,
                text=True,
                capture_output=True,
                env=environment,
                check=False,
            )
            self.assertEqual(interrupted.returncode, -signal_number("KILL"))
            self.assertEqual(shell_state.read_text(encoding="utf-8"), "down")
            journal = home / ".local" / "state" / "omawhatsapp-installer" / "transaction.json"
            self.assertTrue(journal.exists())

            environment.pop("OMAW_INSTALL_TEST_KILL_AFTER_SHELL_STOP")
            recovered = subprocess.run(
                [str(UNINSTALL)],
                cwd=work,
                text=True,
                capture_output=True,
                env=environment,
                check=False,
            )
            self.assertEqual(recovered.returncode, 0, recovered.stderr)
            self.assertIn("Recovered and rolled back", recovered.stderr)
            self.assertEqual(shell_state.read_text(encoding="utf-8"), "up")
            self.assertFalse(journal.exists())

    def test_shell_timeout_fails_closed_and_restores_the_shell(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            home = root / "home"
            service_root = home / ".config" / "systemd" / "user"
            runtime = home / ".local" / "state" / "omawhatsapp"
            fake_bin, fake_state = self.make_fake_commands(root)
            self.populate_install(home, service_root, runtime)
            work = root / "work"
            work.mkdir()
            shell_state = root / "fake-shell-state"
            environment = os.environ.copy()
            environment.update(
                {
                    "HOME": str(home),
                    "XDG_CONFIG_HOME": str(home / ".config"),
                    "XDG_STATE_HOME": str(home / ".local" / "state"),
                    "PATH": f"{fake_bin}:{environment['PATH']}",
                    "FAKE_SYSTEMCTL_STATE": str(fake_state),
                    "FAKE_SHELL_STATE": str(shell_state),
                    "FAKE_QUICKSHELL_TIMEOUT": "1",
                }
            )
            result = subprocess.run(
                [str(UNINSTALL)],
                cwd=work,
                text=True,
                capture_output=True,
                env=environment,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Timed out while stopping", result.stderr)
            self.assertEqual(shell_state.read_text(encoding="utf-8"), "up")
            self.assertTrue(
                (home / ".config" / "omarchy" / "plugins" / PLUGIN_ID).exists()
            )
            self.assertFalse(
                (home / ".local" / "state" / "omawhatsapp-installer" / "transaction.json").exists()
            )

    def test_mutation_refuses_to_stop_shell_without_a_restarter(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            home = root / "home"
            service_root = home / ".config" / "systemd" / "user"
            runtime = home / ".local" / "state" / "omawhatsapp"
            fake_bin, fake_state = self.make_fake_commands(root)
            (fake_bin / "omarchy-restart-shell").unlink()
            for command_name in (
                "dirname",
                "flock",
                "jq",
                "python3",
                "realpath",
                "sha256sum",
                "timeout",
            ):
                command_path = shutil.which(command_name)
                assert command_path is not None
                (fake_bin / command_name).symlink_to(command_path)
            self.populate_install(home, service_root, runtime)
            environment = os.environ.copy()
            environment.update(
                {
                    "HOME": str(home),
                    "XDG_CONFIG_HOME": str(home / ".config"),
                    "XDG_STATE_HOME": str(home / ".local" / "state"),
                    "PATH": str(fake_bin),
                    "FAKE_SYSTEMCTL_STATE": str(fake_state),
                    "FAKE_SHELL_STATE": str(root / "fake-shell-state"),
                }
            )
            result = subprocess.run(
                ["/bin/bash", str(UNINSTALL)],
                text=True,
                capture_output=True,
                env=environment,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("without omarchy-restart-shell", result.stderr)
            self.assertTrue(
                (home / ".config" / "omarchy" / "plugins" / PLUGIN_ID).exists()
            )
            self.assertFalse((home / ".local" / "state" / "omawhatsapp-installer").exists())

    def test_scripts_reject_root_home_and_root_xdg_bases(self) -> None:
        for script in (SOURCE / "scripts" / "install", UNINSTALL):
            with self.subTest(script=script.name, environment="root-home"):
                environment = os.environ.copy()
                environment["HOME"] = "/"
                result = subprocess.run(
                    [str(script), "--check"] if script.name == "install" else [str(script)],
                    text=True,
                    capture_output=True,
                    env=environment,
                    check=False,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("must not be the filesystem root", result.stderr)
            with self.subTest(script=script.name, environment="root-xdg"):
                with tempfile.TemporaryDirectory() as temporary:
                    environment = os.environ.copy()
                    environment.update(
                        {"HOME": temporary, "XDG_CONFIG_HOME": "/", "XDG_STATE_HOME": "/"}
                    )
                    result = subprocess.run(
                        [str(script), "--check"] if script.name == "install" else [str(script)],
                        text=True,
                        capture_output=True,
                        env=environment,
                        check=False,
                    )
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("must not be the filesystem root", result.stderr)


if __name__ == "__main__":
    unittest.main()
