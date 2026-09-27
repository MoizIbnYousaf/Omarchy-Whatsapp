from __future__ import annotations

import importlib.util
from importlib.machinery import SourceFileLoader
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock


SCRIPT = Path(os.environ["OMAW_SCRIPT"])
SPEC = importlib.util.spec_from_loader(
    "omawhatsapp_setup_backend", SourceFileLoader("omawhatsapp_setup_backend", str(SCRIPT))
)
assert SPEC and SPEC.loader
backend_module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(backend_module)
REPOSITORY = Path(__file__).resolve().parents[1]


class SetupTests(unittest.TestCase):
    """The first run sets up what `omarchy plugin add` cannot: sync units,
    command links and the agent skill, all pointing into the checkout."""

    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        runtime = self.root / "runtime"
        runtime.mkdir(mode=0o700)
        environment = mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": str(runtime)})
        environment.start()
        self.addCleanup(environment.stop)
        # A checkout as omarchy plugin add leaves it.
        self.checkout = self.root / "plugins" / "io.github.atoslins.whatsapp"
        (self.checkout / "bin").mkdir(parents=True)
        for name in ("omawhatsapp", "omawhatsapp-mcp"):
            (self.checkout / "bin" / name).write_text("#!/bin/sh\n", encoding="utf-8")
        (self.checkout / "skills" / "omawhatsapp").mkdir(parents=True)
        (self.checkout / "skills" / "omawhatsapp" / "SKILL.md").write_text(
            "---\nname: omawhatsapp\n---\n", encoding="utf-8")
        shutil.copytree(REPOSITORY / "systemd", self.checkout / "systemd")
        (self.checkout / "manifest.json").write_text('{"version": "9.9.9"}', encoding="utf-8")
        self.home_bin = self.root / "home" / ".local" / "bin"
        self.skill_link = self.root / "home" / ".agents" / "skills" / "omawhatsapp"
        self.units = self.root / "home" / ".config" / "systemd" / "user"
        self.shell = self.root / "home" / ".config" / "omarchy" / "shell.json"
        self.shell.parent.mkdir(parents=True)
        self.shell.write_text('{"plugins": [], "bar": {"layout": {"right": []}}}', encoding="utf-8")
        self.wacli = self.root / "usr" / "bin" / "wacli"
        self.wacli.parent.mkdir(parents=True)
        self.wacli.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        self.wacli.chmod(0o755)
        (self.root / "store").mkdir()
        self.backend = backend_module.Backend(
            store_dir=self.root / "store", state_dir=self.root / "state", wacli=self.wacli,
            unit_dir=self.units, plugin_root=self.checkout, local_bin=self.home_bin,
            skill_link=self.skill_link, plugins_dir=self.root / "plugins",
            shell_config=self.shell,
        )
        self.calls: list[list[str]] = []
        self.active: set[str] = set()

        def systemctl(arguments, require_success=True):
            self.calls.append(list(arguments))
            return subprocess.CompletedProcess(arguments, 0, "", "")

        patch = mock.patch.object(self.backend, "_systemctl_user", side_effect=systemctl)
        patch.start()
        self.addCleanup(patch.stop)
        active = mock.patch.object(self.backend, "_unit_active",
                                   side_effect=lambda unit: unit in self.active)
        active.start()
        self.addCleanup(active.stop)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def verbs(self) -> list[str]:
        return [" ".join(call) for call in self.calls]

    def test_the_first_setup_links_writes_units_and_starts_sync(self) -> None:
        before = self.backend._setup_state()
        self.assertFalse(before["consented"])
        self.assertEqual(before["units"], "missing")
        result = self.backend.setup(True, False)
        self.assertTrue(result["setup"]["complete"], result["setup"])
        for link, target in ((self.home_bin / "omawhatsapp", "bin/omawhatsapp"),
                             (self.home_bin / "omawhatsapp-mcp", "bin/omawhatsapp-mcp"),
                             (self.skill_link, "skills/omawhatsapp")):
            self.assertTrue(link.is_symlink(), link)
            self.assertEqual(link.resolve(), (self.checkout / target).resolve())
        unit = (self.units / "wacli-sync.service").read_text(encoding="utf-8")
        self.assertIn(f"ExecStart={self.wacli} --store", unit,
                      "a wacli outside ~/.local/bin is written into the unit")
        template = (self.units / "wacli-sync@.service").read_text(encoding="utf-8")
        self.assertIn("ExecCondition=%h/.local/bin/omawhatsapp session-ready", template,
                      "per-account units ask the linked helper")
        self.assertIn(f"ExecStart={self.wacli} --account %i", template)
        self.assertIn("ProtectSystem=strict", unit, "the sandbox comes along")
        self.assertIn("daemon-reload", self.verbs())
        self.assertIn("enable wacli-sync.service", self.verbs())
        self.assertIn("start wacli-sync.service", self.verbs(), "the first setup starts sync")
        self.assertTrue(self.backend._preferences()["setup"]["consented"])

    def test_setup_again_changes_nothing(self) -> None:
        self.backend.setup(True, False)
        self.active.add("wacli-sync.service")
        self.calls.clear()
        result = self.backend.setup(None, False)
        self.assertFalse(result["changed"])
        self.assertNotIn("daemon-reload", self.verbs())
        self.assertFalse(any(verb.startswith(("restart", "start")) for verb in self.verbs()),
                         "an unchanged setup never restarts a running sync")

    def test_a_changed_template_is_rewritten_and_restarts_running_sync(self) -> None:
        self.backend.setup(True, False)
        self.active.add("wacli-sync.service")
        template = self.checkout / "systemd" / "user" / "wacli-sync.service"
        template.write_text(template.read_text(encoding="utf-8").replace("RestartSec=10", "RestartSec=15"),
                            encoding="utf-8")
        self.assertEqual(self.backend._setup_state()["units"], "stale")
        self.calls.clear()
        self.backend.setup(None, False)
        self.assertIn("RestartSec=15", (self.units / "wacli-sync.service").read_text(encoding="utf-8"))
        self.assertIn("daemon-reload", self.verbs())
        self.assertIn("restart wacli-sync.service", self.verbs())

    def test_a_changed_setup_retires_instances_no_account_owns(self) -> None:
        orphan = subprocess.CompletedProcess([], 0,
                                             "wacli-sync@gone.service loaded active running x\n", "")

        def systemctl(arguments, require_success=True):
            self.calls.append(list(arguments))
            if arguments[:1] == ["list-units"]:
                return orphan
            return subprocess.CompletedProcess(arguments, 0, "", "")

        with mock.patch.object(self.backend, "_systemctl_user", side_effect=systemctl):
            self.backend.setup(True, False)
        self.assertIn("disable --now wacli-sync@gone.service", self.verbs())

    def test_wacli_in_local_bin_keeps_the_portable_unit(self) -> None:
        local = self.home_bin / "wacli"
        local.parent.mkdir(parents=True)
        local.write_text("#!/bin/sh\n", encoding="utf-8")
        local.chmod(0o755)
        self.backend.wacli = local
        self.backend.setup(True, False)
        self.assertIn("ExecStart=%h/.local/bin/wacli", (self.units / "wacli-sync.service").read_text(
            encoding="utf-8"))

    def test_setup_needs_wacli(self) -> None:
        self.wacli.unlink()
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "omarchy pkg aur add wacli-bin"):
            self.backend.setup(True, False)
        self.assertFalse(self.home_bin.exists(), "nothing is written without wacli")

    def write_old_copies(self) -> None:
        """What the old installer left: each file says whose it is."""
        self.home_bin.mkdir(parents=True, exist_ok=True)
        copies = {
            "omawhatsapp": "#!/usr/bin/python3\n\"\"\"Local bridge to wacli.\"\"\"\nfrom omawhatsapp_core import main\n",
            "omawhatsapp-mcp": "#!/usr/bin/python3\n# omawhatsapp MCP server; the helper talks to wacli\n",
            "omawhatsapp_core.py": "# omawhatsapp helper core over wacli\n",
            "omawhatsapp_assets.py": "class AvatarCacheError(RuntimeError):\n    pass\n",
        }
        for name, text in copies.items():
            (self.home_bin / name).write_text(text, encoding="utf-8")
        self.skill_link.mkdir(parents=True, exist_ok=True)
        (self.skill_link / "SKILL.md").write_text("---\nname: omawhatsapp\n---\n", encoding="utf-8")

    def test_old_installer_copies_move_aside_for_links(self) -> None:
        self.write_old_copies()
        state = self.backend._setup_state()
        self.assertTrue(state["legacy_copies"])
        self.backend.setup(True, False)
        self.assertTrue((self.home_bin / "omawhatsapp").is_symlink())
        self.assertTrue(self.skill_link.is_symlink())
        self.assertFalse((self.home_bin / "omawhatsapp_core.py").exists())
        self.assertEqual(len(list((self.root / "state" / "setup-backup").iterdir())), 5,
                         "four copies and the skill folder are kept aside, not deleted")

    def test_an_install_by_the_old_script_counts_as_consent(self) -> None:
        self.backend.setup(True, False)
        self.backend._update_preferences(lambda value: value.__setitem__(
            "setup", {"consented": False, "agents": True}))
        (self.home_bin / "omawhatsapp").unlink()
        (self.home_bin / "omawhatsapp").write_text(
            "#!/usr/bin/python3\nfrom omawhatsapp_core import main  # wacli\n", encoding="utf-8")
        self.assertTrue(self.backend._setup_state()["previous_install"])

    def test_turning_agents_off_removes_their_links_only(self) -> None:
        self.backend.setup(True, False)
        result = self.backend.setup(False, False)
        self.assertFalse((self.home_bin / "omawhatsapp-mcp").exists())
        self.assertFalse(self.skill_link.exists())
        self.assertTrue((self.home_bin / "omawhatsapp").is_symlink(), "the command stays")
        self.assertFalse(result["setup"]["agents"])
        self.assertTrue(result["setup"]["complete"])

    def test_a_unit_that_is_not_ours_is_never_replaced(self) -> None:
        self.units.mkdir(parents=True)
        (self.units / "wacli-sync.service").write_text("[Service]\nExecStart=/bin/true\n", encoding="utf-8")
        self.assertEqual(self.backend._setup_state()["units"], "foreign")
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "belongs to something else"):
            self.backend.setup(True, False)

    def test_the_original_omawhatsapp_is_replaced_only_when_allowed(self) -> None:
        (self.root / "plugins" / backend_module.ORIGINAL_PLUGIN_ID).mkdir(parents=True)
        self.shell.write_text(json.dumps({"plugins": [], "bar": {"layout": {"right": [
            {"id": backend_module.ORIGINAL_PLUGIN_ID}]}}}), encoding="utf-8")
        self.assertEqual(self.backend._setup_state()["original_plugin"],
                         {"installed": True, "enabled": True})
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "OmaWhatsApp is still turned on"):
            self.backend.setup(True, False)
        self.assertFalse(self.home_bin.exists())
        with mock.patch.object(self.backend, "_run_omarchy") as omarchy:
            self.backend.setup(True, True)
        omarchy.assert_called_once_with(["plugin", "disable", backend_module.ORIGINAL_PLUGIN_ID])

    def test_teardown_undoes_the_setup_and_keeps_the_archive(self) -> None:
        self.backend.setup(True, False)
        (self.units / "wacli-sync.service.d").mkdir()
        (self.units / "wacli-sync.service.d" / backend_module.MEDIA_DROPIN).write_text("x", encoding="utf-8")
        (self.root / "store" / "wacli.db").write_text("archive", encoding="utf-8")
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, 'Confirm by sending "remove"'):
            self.backend.teardown("yes")
        self.calls.clear()
        result = self.backend.teardown("remove")
        self.assertIn("disable --now wacli-sync.service", self.verbs())
        for gone in (self.units / "wacli-sync.service", self.units / "wacli-sync@.service",
                     self.home_bin / "omawhatsapp", self.home_bin / "omawhatsapp-mcp", self.skill_link,
                     self.units / "wacli-sync.service.d"):
            self.assertFalse(gone.exists() or gone.is_symlink(), gone)
        self.assertTrue((self.root / "store" / "wacli.db").is_file(), "the archive stays")
        self.assertFalse(self.backend._preferences()["setup"]["consented"])
        self.assertEqual(result["remove_command"], "omarchy plugin remove io.github.atoslins.whatsapp")

    # Store review, 2026-09-27: the setup must never replace a path that
    # belongs to something else, and neither may teardown or turning agents off.
    def test_a_link_owned_by_something_else_stops_the_setup_untouched(self) -> None:
        other = self.root / "other-tool"
        other.write_text("#!/bin/sh\n", encoding="utf-8")
        self.home_bin.mkdir(parents=True)
        (self.home_bin / "omawhatsapp").symlink_to(other)
        state = self.backend._setup_state()
        self.assertEqual(state["conflicts"], [str(self.home_bin / "omawhatsapp")])
        self.assertFalse(state["previous_install"])
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError,
                                    "Setup stopped before changing anything: .*a link to .*other-tool"):
            self.backend.setup(True, False)
        self.assertEqual(os.readlink(self.home_bin / "omawhatsapp"), str(other))
        self.assertFalse((self.home_bin / "omawhatsapp-mcp").exists())
        self.assertFalse(os.path.lexists(self.skill_link))
        self.assertFalse(self.units.exists(), "no unit is written either")
        self.assertFalse(self.backend._preferences()["setup"]["consented"])

    def test_a_broken_link_owned_by_something_else_is_left_alone(self) -> None:
        self.home_bin.mkdir(parents=True)
        (self.home_bin / "omawhatsapp-mcp").symlink_to("/nonexistent/elsewhere/mcp")
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "belongs to something else"):
            self.backend.setup(True, False)
        self.backend.teardown("remove")
        self.assertTrue(os.path.lexists(self.home_bin / "omawhatsapp-mcp"),
                        "teardown never removes a broken link that is not this app's")

    def test_a_file_that_is_not_this_apps_stops_the_setup(self) -> None:
        self.home_bin.mkdir(parents=True)
        (self.home_bin / "omawhatsapp").write_text("#!/bin/sh\necho another tool\n", encoding="utf-8")
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, r"omawhatsapp \(a file\) belongs"):
            self.backend.setup(True, False)
        self.assertEqual((self.home_bin / "omawhatsapp").read_text(encoding="utf-8"),
                         "#!/bin/sh\necho another tool\n")
        self.assertFalse((self.root / "state" / "setup-backup").exists(), "not even moved aside")

    def test_a_skill_folder_of_something_else_is_left_alone(self) -> None:
        self.skill_link.mkdir(parents=True)
        (self.skill_link / "SKILL.md").write_text("---\nname: another-skill\n---\n", encoding="utf-8")
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "belongs to something else"):
            self.backend.setup(True, False)
        # Without agents the skill path is not needed, so the setup goes on
        # and still leaves that folder as it is.
        self.backend.setup(False, False)
        self.assertTrue((self.home_bin / "omawhatsapp").is_symlink())
        self.assertEqual((self.skill_link / "SKILL.md").read_text(encoding="utf-8"),
                         "---\nname: another-skill\n---\n")

    def test_a_link_into_this_apps_folder_is_its_own(self) -> None:
        self.home_bin.mkdir(parents=True)
        (self.home_bin / "omawhatsapp").symlink_to(self.checkout / "bin" / "old-name")
        self.assertEqual(self.backend._setup_state()["links"][str(self.home_bin / "omawhatsapp")], "ours")
        self.backend.setup(True, False)
        self.assertEqual((self.home_bin / "omawhatsapp").resolve(),
                         (self.checkout / "bin" / "omawhatsapp").resolve())

    def test_turning_agents_off_and_teardown_leave_links_of_something_else(self) -> None:
        self.backend.setup(True, False)
        other = self.root / "other-mcp"
        other.write_text("#!/bin/sh\n", encoding="utf-8")
        (self.home_bin / "omawhatsapp-mcp").unlink()
        (self.home_bin / "omawhatsapp-mcp").symlink_to(other)
        self.backend.setup(False, False)
        self.assertEqual(os.readlink(self.home_bin / "omawhatsapp-mcp"), str(other))
        self.assertFalse(os.path.lexists(self.skill_link), "its own skill link goes")
        self.backend.teardown("remove")
        self.assertEqual(os.readlink(self.home_bin / "omawhatsapp-mcp"), str(other))
        self.assertFalse(os.path.lexists(self.home_bin / "omawhatsapp"), "its own link goes")

    def test_teardown_leaves_what_it_did_not_create(self) -> None:
        self.home_bin.mkdir(parents=True)
        (self.home_bin / "omawhatsapp").write_text("someone else's\n", encoding="utf-8")
        self.backend.teardown("remove")
        self.assertTrue((self.home_bin / "omawhatsapp").is_file())

    def test_linking_before_setup_does_not_touch_missing_units(self) -> None:
        self.assertEqual(self.backend._units_state(), "missing")
        account = self.backend.account("")
        (account.store_dir / "session.db").write_text("", encoding="utf-8")
        self.assertEqual(self.backend._finalize_link(account, 0), 0)
        self.assertEqual(self.calls, [], "no unit to enable before the setup")

    def test_about_reports_the_checkout_version_and_mode(self) -> None:
        about = self.backend.about()
        self.assertEqual(about["app_version"], "9.9.9")
        self.assertEqual(about["install_mode"], "copy")
        (self.checkout / ".git").mkdir()
        self.assertEqual(self.backend.about()["install_mode"], "git")


class WacliLocationTests(unittest.TestCase):
    def test_local_bin_comes_first_then_system_paths(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            local, system = root / "local" / "wacli", root / "usr" / "wacli"
            system.parent.mkdir(parents=True)
            system.write_text("#!/bin/sh\n", encoding="utf-8")
            system.chmod(0o755)
            with mock.patch.object(backend_module, "WACLI_CANDIDATES", (local, system)), \
                    mock.patch.dict(os.environ, {"WACLI_BIN": ""}):
                self.assertEqual(backend_module.locate_wacli(), system)
                local.parent.mkdir(parents=True)
                local.write_text("#!/bin/sh\n", encoding="utf-8")
                local.chmod(0o755)
                self.assertEqual(backend_module.locate_wacli(), local)
            with mock.patch.dict(os.environ, {"WACLI_BIN": str(system)}):
                self.assertEqual(backend_module.locate_wacli(), system, "an explicit path wins")
            with mock.patch.dict(os.environ, {"WACLI_BIN": "relative/wacli"}), \
                    mock.patch.object(backend_module, "WACLI_CANDIDATES", (local, system)):
                self.assertEqual(backend_module.locate_wacli(), local, "a relative path is ignored")


class UpdateCheckTests(unittest.TestCase):
    def git(self, *arguments: str, cwd: Path) -> str:
        environment = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t",
                           GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")
        return subprocess.run(["git", *arguments], cwd=cwd, check=True, capture_output=True,
                              text=True, env=environment).stdout.strip()

    def test_a_newer_commit_upstream_is_an_update(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            upstream = root / "upstream"
            upstream.mkdir()
            self.git("init", "-q", "-b", "main", cwd=upstream)
            (upstream / "manifest.json").write_text('{"version": "1.0.0"}', encoding="utf-8")
            self.git("add", ".", cwd=upstream)
            self.git("commit", "-q", "-m", "first", cwd=upstream)
            self.git("clone", "-q", str(upstream), str(root / "checkout"), cwd=root)
            backend = backend_module.Backend(store_dir=root / "store", state_dir=root / "state",
                                             wacli=root / "wacli", plugin_root=root / "checkout")
            result = backend.update_check()
            self.assertEqual((result["managed"], result["available"], result["current"]),
                             (True, False, "1.0.0"))
            (upstream / "manifest.json").write_text('{"version": "1.1.0"}', encoding="utf-8")
            self.git("commit", "-q", "-am", "second", cwd=upstream)
            self.assertTrue(backend.update_check()["available"])
            # A copy ahead of the repository (a development checkout) has
            # nothing to update.
            self.git("pull", "-q", cwd=root / "checkout")
            (root / "checkout" / "manifest.json").write_text('{"version": "1.2.0"}', encoding="utf-8")
            self.git("commit", "-q", "-am", "local", cwd=root / "checkout")
            self.assertFalse(backend.update_check()["available"])

    def test_a_copy_that_is_not_a_checkout_says_so(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "copy").mkdir()
            backend = backend_module.Backend(store_dir=root / "store", state_dir=root / "state",
                                             wacli=root / "wacli", plugin_root=root / "copy")
            self.assertEqual(backend.update_check()["managed"], False)


if __name__ == "__main__":
    unittest.main()
