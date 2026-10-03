from __future__ import annotations

import hashlib
import importlib.util
from importlib.machinery import SourceFileLoader
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
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
        self.checkout = self.root / "plugins" / "io.github.moizibnyousaf.omawhatsapp"
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

    def test_managed_launcher_uses_the_same_package_and_preserves_arguments(self) -> None:
        config = self.root / "config with spaces"
        helper = config / "omarchy/plugins/io.github.moizibnyousaf.omawhatsapp/bin/omawhatsapp"
        helper.parent.mkdir(parents=True)
        helper.write_text('#!/bin/sh\nprintf "%s\\n" "$@"\n', encoding="utf-8")
        helper.chmod(0o755)
        arguments = ["status", "--account", "synthetic account; ignored"]
        environment = dict(os.environ, XDG_CONFIG_HOME=str(config))
        result = subprocess.run(["sh", str(REPOSITORY / "managed/omawhatsapp"), *arguments],
                                env=environment, capture_output=True, text=True, check=True)
        self.assertEqual(result.stdout.splitlines(), arguments)

    def test_managed_install_defers_setup_and_teardown_without_mutating(self) -> None:
        (self.checkout / "managed-install.json").write_text(
            '{"manager":"my-omarchy-plugin"}', encoding="utf-8")
        state = self.backend._setup_state()
        self.assertTrue(state["complete"])
        self.assertEqual(state["manager"], "my-omarchy-plugin")
        for operation in (lambda: self.backend.setup(True, True),
                          lambda: self.backend.teardown("remove")):
            with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "managed by My Plugins"):
                operation()
        self.assertFalse(self.home_bin.exists())
        self.assertFalse(self.units.exists())

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
        self.assertIn("ExecCondition=%h/.local/bin/omawhatsapp session-ready", unit)
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

    # Stand-ins for what the old installers copied; known_copies() makes them
    # count as shipped versions the way bin/earlier-copies.json lists the real ones.
    OLD_COPIES = {
        "omawhatsapp": "#!/usr/bin/python3\n\"\"\"Local bridge to wacli.\"\"\"\nfrom omawhatsapp_core import main\n",
        "omawhatsapp-mcp": "#!/usr/bin/python3\n# omawhatsapp MCP server; the helper talks to wacli\n",
        "omawhatsapp_core.py": "# omawhatsapp helper core over wacli\n",
        "omawhatsapp_assets.py": "class AvatarCacheError(RuntimeError):\n    pass\n",
    }
    OLD_SKILL = {
        "SKILL.md": "---\nname: omawhatsapp\n---\nUse the helper over wacli.\n",
        "references/wacli-parity.md": "# wacli parity\n",
    }

    def known_copies(self) -> None:
        files = {name: frozenset({hashlib.sha256(text.encode("utf-8")).hexdigest()})
                 for name, text in self.OLD_COPIES.items()}
        skill = backend_module.tree_digest(
            [(path, text.encode("utf-8")) for path, text in self.OLD_SKILL.items()])
        patch = mock.patch.object(backend_module, "earlier_copies",
                                  return_value=(files, frozenset({skill})))
        patch.start()
        self.addCleanup(patch.stop)

    def write_skill(self, files: dict[str, str]) -> None:
        for path, text in files.items():
            (self.skill_link / path).parent.mkdir(parents=True, exist_ok=True)
            (self.skill_link / path).write_text(text, encoding="utf-8")

    def allow_agents(self) -> None:
        """The user said yes to agent access; only then is the skill path set up."""
        self.backend._update_preferences(lambda value: value.__setitem__(
            "setup", {"consented": False, "agents": True}))

    def write_old_copies(self) -> None:
        """What the old installer left, byte for byte a version it shipped."""
        self.known_copies()
        self.home_bin.mkdir(parents=True, exist_ok=True)
        for name, text in self.OLD_COPIES.items():
            (self.home_bin / name).write_text(text, encoding="utf-8")
        self.write_skill(self.OLD_SKILL)

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
        self.known_copies()
        self.backend.setup(True, False)
        self.backend._update_preferences(lambda value: value.__setitem__(
            "setup", {"consented": False, "agents": True}))
        (self.home_bin / "omawhatsapp").unlink()
        (self.home_bin / "omawhatsapp").write_text(self.OLD_COPIES["omawhatsapp"], encoding="utf-8")
        self.assertTrue(self.backend._setup_state()["previous_install"])

    def test_a_look_alike_wrapper_module_or_skill_is_left_alone(self) -> None:
        # Someone's own wrapper around wacli, a module and a skill that use the
        # app's names, but are not what the old installers shipped.
        self.known_copies()
        self.home_bin.mkdir(parents=True)
        mine = {
            "omawhatsapp": "#!/bin/sh\n# my omawhatsapp wrapper\nexec wacli \"$@\"\n",
            "omawhatsapp-mcp": "#!/bin/sh\n# omawhatsapp MCP of my own, over wacli\n",
            "omawhatsapp_core.py": "# notes: omawhatsapp, wacli, AvatarCacheError\n",
        }
        for name, text in mine.items():
            (self.home_bin / name).write_text(text, encoding="utf-8")
        own_skill = {"SKILL.md": "---\nname: omawhatsapp\n---\nMy own skill over wacli.\n"}
        self.write_skill(own_skill)
        self.allow_agents()
        state = self.backend._setup_state()
        self.assertEqual(state["links"][str(self.home_bin / "omawhatsapp")], "foreign")
        self.assertEqual(state["links"][str(self.skill_link)], "foreign")
        self.assertFalse(state["legacy_copies"])
        self.assertFalse(state["previous_install"])
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "belongs to something else"):
            self.backend.setup(True, False)
        for name, text in mine.items():
            self.assertEqual((self.home_bin / name).read_text(encoding="utf-8"), text)
        self.assertEqual((self.skill_link / "SKILL.md").read_text(encoding="utf-8"),
                         own_skill["SKILL.md"])
        self.assertFalse((self.root / "state" / "setup-backup").exists(), "not even moved aside")

    def test_a_copy_changed_by_one_byte_is_not_the_apps(self) -> None:
        self.write_old_copies()
        helper = self.home_bin / "omawhatsapp"
        helper.write_text(self.OLD_COPIES["omawhatsapp"] + "\n", encoding="utf-8")
        self.assertEqual(self.backend._setup_state()["links"][str(helper)], "foreign")
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "belongs to something else"):
            self.backend.setup(True, False)
        self.assertEqual(helper.read_text(encoding="utf-8"), self.OLD_COPIES["omawhatsapp"] + "\n")

    def test_a_shipped_skill_with_anything_added_is_not_the_apps(self) -> None:
        self.write_old_copies()
        self.allow_agents()
        self.assertEqual(self.backend._setup_state()["links"][str(self.skill_link)], "ours")
        (self.skill_link / "notes.md").write_text("mine\n", encoding="utf-8")
        self.assertEqual(self.backend._setup_state()["links"][str(self.skill_link)], "foreign")
        (self.skill_link / "notes.md").unlink()
        (self.skill_link / "linked.md").symlink_to(self.skill_link / "SKILL.md")
        self.assertEqual(self.backend._setup_state()["links"][str(self.skill_link)], "foreign")

    def test_a_copy_with_another_files_name_is_not_the_apps(self) -> None:
        # The module's shipped text at the helper's path was never copied there.
        self.known_copies()
        self.home_bin.mkdir(parents=True)
        (self.home_bin / "omawhatsapp").write_text(self.OLD_COPIES["omawhatsapp_core.py"],
                                                    encoding="utf-8")
        self.assertEqual(self.backend._setup_state()["links"][str(self.home_bin / "omawhatsapp")],
                         "foreign")

    def test_turning_agents_off_removes_their_links_only(self) -> None:
        self.backend.setup(True, False)
        result = self.backend.setup(False, False)
        self.assertFalse((self.home_bin / "omawhatsapp-mcp").exists())
        self.assertFalse(self.skill_link.exists())
        self.assertTrue((self.home_bin / "omawhatsapp").is_symlink(), "the command stays")
        self.assertFalse(result["setup"]["agents"])
        self.assertTrue(result["setup"]["complete"])

    def test_agent_access_is_off_until_the_user_turns_it_on(self) -> None:
        self.assertFalse(self.backend._setup_state()["agents"], "no answer is not a yes")
        result = self.backend.setup(None, False)
        self.assertTrue((self.home_bin / "omawhatsapp").is_symlink(), "the command is set up")
        self.assertFalse(os.path.lexists(self.home_bin / "omawhatsapp-mcp"))
        self.assertFalse(os.path.lexists(self.skill_link), "no agent instructions without a yes")
        self.assertFalse(result["setup"]["agents"])
        self.assertTrue(result["setup"]["complete"])
        self.assertFalse(self.backend._preferences()["setup"]["agents"])
        self.backend.setup(True, False)
        self.assertTrue(self.skill_link.is_symlink())
        self.assertTrue((self.home_bin / "omawhatsapp-mcp").is_symlink())

    def test_a_yes_already_given_keeps_agent_access(self) -> None:
        self.backend._update_preferences(lambda value: value.__setitem__(
            "setup", {"consented": True, "agents": True}))
        self.assertTrue(self.backend._setup_state()["agents"])
        self.backend.setup(None, False)
        self.assertTrue(self.skill_link.is_symlink())

    def test_an_old_install_moves_on_without_agent_access(self) -> None:
        # The old script placed the skill without asking; moving to links is
        # not a yes, so its skill and MCP copies go aside until the user opts in.
        self.write_old_copies()
        self.backend.setup(None, False)
        self.assertTrue((self.home_bin / "omawhatsapp").is_symlink())
        self.assertFalse(os.path.lexists(self.skill_link))
        self.assertFalse(os.path.lexists(self.home_bin / "omawhatsapp-mcp"))
        self.assertEqual(len(list((self.root / "state" / "setup-backup").iterdir())), 5,
                         "the copies are kept aside, not deleted")
        self.assertFalse(self.backend._preferences()["setup"]["agents"])

    def test_a_unit_that_is_not_ours_is_never_replaced(self) -> None:
        self.units.mkdir(parents=True)
        (self.units / "wacli-sync.service").write_text("[Service]\nExecStart=/bin/true\n", encoding="utf-8")
        self.assertEqual(self.backend._setup_state()["units"], "foreign")
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "belongs to something else"):
            self.backend.setup(True, False)
        self.assertEqual((self.units / "wacli-sync.service").read_text(encoding="utf-8"),
                         "[Service]\nExecStart=/bin/true\n")
        self.assertFalse(self.home_bin.exists(), "it stops before changing anything")

    def test_the_fork_is_replaced_only_when_allowed(self) -> None:
        (self.root / "plugins" / backend_module.ORIGINAL_PLUGIN_ID).mkdir(parents=True)
        self.shell.write_text(json.dumps({"plugins": [], "bar": {"layout": {"right": [
            {"id": backend_module.ORIGINAL_PLUGIN_ID}]}}}), encoding="utf-8")
        self.assertEqual(self.backend._setup_state()["original_plugin"],
                         {"installed": True, "enabled": True})
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, "The fork is still turned on"):
            self.backend.setup(True, False)
        self.assertFalse(self.home_bin.exists())
        with mock.patch.object(self.backend, "_run_omarchy") as omarchy:
            self.backend.setup(True, True)
        omarchy.assert_called_once_with(["plugin", "disable", backend_module.ORIGINAL_PLUGIN_ID])

    def test_teardown_undoes_the_setup_and_keeps_the_archive(self) -> None:
        self.backend.setup(True, False)
        self.backend.media_mode(False)
        (self.root / "store" / "wacli.db").write_text("archive", encoding="utf-8")
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError, 'Confirm by sending "remove"'):
            self.backend.teardown("yes")
        self.calls.clear()
        result = self.backend.teardown("remove")
        self.assertIn("disable --now wacli-sync.service", self.verbs())
        for gone in (self.units / "wacli-sync.service", self.units / "wacli-sync@.service",
                     self.home_bin / "omawhatsapp", self.home_bin / "omawhatsapp-mcp", self.skill_link,
                     self.units / "wacli-sync.service.d", self.units / "wacli-sync@.service.d"):
            self.assertFalse(gone.exists() or gone.is_symlink(), gone)
        self.assertEqual(result["kept"], [])
        self.assertTrue((self.root / "store" / "wacli.db").is_file(), "the archive stays")
        self.assertFalse(self.backend._preferences()["setup"]["consented"])
        self.assertEqual(result["remove_command"], "omarchy plugin remove io.github.moizibnyousaf.omawhatsapp")

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

    # Store review, 2026-09-27 (second): a sync unit or media drop-in that
    # someone edited, or wrote, is never replaced or removed. Only a file
    # exactly as the app wrote it is the app's to change.
    def dropin(self, unit: str = "wacli-sync.service") -> Path:
        return self.units / f"{unit}.d" / backend_module.MEDIA_DROPIN

    def test_an_edited_unit_stops_the_setup_and_stays_as_it_is(self) -> None:
        self.backend.setup(True, False)
        unit = self.units / "wacli-sync@.service"
        edited = unit.read_text(encoding="utf-8") + "Environment=MINE=1\n"
        unit.write_text(edited, encoding="utf-8")
        (self.home_bin / "omawhatsapp-mcp").unlink()
        state = self.backend._setup_state()
        self.assertEqual(state["units"], "foreign")
        self.assertIn(str(unit), state["conflicts"])
        self.assertFalse(state["complete"])
        with self.assertRaisesRegex(backend_module.OmaWhatsAppError,
                                    "was changed after the app wrote it.*systemctl --user edit"):
            self.backend.setup(True, False)
        self.assertEqual(unit.read_text(encoding="utf-8"), edited)
        self.assertFalse(os.path.lexists(self.home_bin / "omawhatsapp-mcp"),
                         "it stops before changing anything")

    def test_units_an_earlier_version_wrote_are_still_its_own(self) -> None:
        self.units.mkdir(parents=True)
        earlier = "[Unit]\nDescription=OmaWhatsApp sync from an earlier version\n"
        for name in backend_module.SETUP_UNITS:
            (self.units / name).write_text(earlier, encoding="utf-8")
        digest = backend_module.hashlib.sha256(earlier.encode("utf-8")).hexdigest()
        with mock.patch.object(backend_module, "EARLIER_WRITTEN_SHA256", frozenset({digest})):
            self.assertEqual(self.backend._setup_state()["units"], "stale")
            self.assertTrue(self.backend.setup(True, False)["setup"]["complete"])
        text = (self.units / "wacli-sync.service").read_text(encoding="utf-8")
        self.assertTrue(text.startswith("# Written by OmaWhatsApp (sha256 "), text[:80])
        self.assertTrue(backend_module.written_unchanged(text.encode("utf-8")))

    def test_the_media_setting_changes_only_its_own_dropins(self) -> None:
        self.backend.setup(True, False)
        self.backend.media_mode(False)
        for unit in backend_module.MEDIA_UNITS:
            self.assertTrue(backend_module.written_unchanged(self.dropin(unit).read_bytes()))
        self.assertFalse(self.backend.auto_download_media())
        self.backend.media_mode(False)
        self.backend.media_mode(True)
        self.assertFalse(any(self.dropin(unit).exists() for unit in backend_module.MEDIA_UNITS))
        self.assertTrue(self.backend.auto_download_media())
        self.backend.media_mode(False)
        edited = self.dropin().read_text(encoding="utf-8") + "Environment=MINE=1\n"
        self.dropin().write_text(edited, encoding="utf-8")
        for enabled in (True, False):
            with self.assertRaisesRegex(backend_module.OmaWhatsAppError,
                                        "was changed after the app wrote it; it was left as it is"):
                self.backend.media_mode(enabled)
        self.assertEqual(self.dropin().read_text(encoding="utf-8"), edited)
        self.assertTrue(self.dropin("wacli-sync@.service").exists(),
                        "both are checked before either changes")

    def test_a_dropin_that_is_not_the_apps_is_never_replaced(self) -> None:
        for content in ("[Service]\nEnvironment=OMAW_MEDIA_FLAGS=--mine\n", ""):
            self.dropin().parent.mkdir(parents=True, exist_ok=True)
            self.dropin().write_text(content, encoding="utf-8")
            for enabled in (True, False):
                with self.assertRaisesRegex(backend_module.OmaWhatsAppError,
                                            "belongs to something else; it was left as it is"):
                    self.backend.media_mode(enabled)
                self.assertEqual(self.dropin().read_text(encoding="utf-8"), content)
            self.assertFalse(self.dropin("wacli-sync@.service").exists())

    def test_a_dropin_an_earlier_version_wrote_is_still_its_own(self) -> None:
        for earlier in (
            "# Written by OmaWhatsApp: received media is downloaded only on request.\n"
            "[Service]\nEnvironment=OMAW_MEDIA_FLAGS=\n",
            "# Written by OmaWhatsApp: received media is downloaded only on request.\n"
            "[Service]\nEnvironment=OMAW_MEDIA_FLAGS=\n",
        ):
            self.dropin().parent.mkdir(parents=True, exist_ok=True)
            self.dropin().write_text(earlier, encoding="utf-8")
            self.backend.media_mode(True)
            self.assertFalse(self.dropin().exists())

    def test_teardown_keeps_what_was_edited_and_its_running_sync(self) -> None:
        listing = subprocess.CompletedProcess(
            [], 0, "wacli-sync@work.service loaded active running x\n", "")

        def systemctl(arguments, require_success=True):
            self.calls.append(list(arguments))
            if arguments[:1] == ["list-units"]:
                return listing
            return subprocess.CompletedProcess(arguments, 0, "", "")

        self.backend.setup(True, False)
        self.backend.media_mode(False)
        template = self.units / "wacli-sync@.service"
        template.write_text(template.read_text(encoding="utf-8") + "Nice=5\n", encoding="utf-8")
        self.dropin().write_text(self.dropin().read_text(encoding="utf-8") + "# mine\n",
                                 encoding="utf-8")
        override = self.units / "wacli-sync@.service.d" / "override.conf"
        override.write_text("[Service]\nNice=5\n", encoding="utf-8")
        self.calls.clear()
        with mock.patch.object(self.backend, "_systemctl_user", side_effect=systemctl):
            self.assertIn("wacli-sync@work.service", self.backend._sync_instances())
            result = self.backend.teardown("remove")
        self.assertEqual(sorted(result["kept"]), sorted([str(template), str(self.dropin())]))
        self.assertIn(str(self.units / "wacli-sync.service"), result["removed"])
        self.assertIn(str(self.dropin("wacli-sync@.service")), result["removed"])
        self.assertTrue(template.is_file() and self.dropin().is_file())
        self.assertEqual(override.read_text(encoding="utf-8"), "[Service]\nNice=5\n")
        self.assertIn("disable --now wacli-sync.service", self.verbs())
        self.assertNotIn("disable --now wacli-sync@work.service", self.verbs(),
                         "a unit it keeps keeps running")

    @mock.patch.object(backend_module.Backend, "_doctor", return_value={"authenticated": True})
    def test_linking_before_setup_does_not_touch_missing_units(self, doctor) -> None:
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


class EarlierCopiesTests(unittest.TestCase):
    """bin/earlier-copies.json decides what the setup may take for a copy an
    old install script left; it has to be exactly what those scripts shipped."""

    SOURCE = "dd09400f17d293ccc40ee6ea7c602b1b9fac5796"
    NAMES = ("omawhatsapp", "omawhatsapp-mcp", "omawhatsapp_core.py", "omawhatsapp_assets.py")

    def git(self, *arguments: str) -> bytes:
        return subprocess.run(["git", "-C", str(REPOSITORY), *arguments],
                              check=True, capture_output=True).stdout

    def needs_history(self) -> None:
        found = subprocess.run(["git", "-C", str(REPOSITORY), "cat-file", "-e", self.SOURCE + "^{commit}"],
                               capture_output=True)
        if found.returncode != 0:
            self.skipTest("needs the git history up to the last commit with the installer")

    def test_the_shipped_list_is_well_formed(self) -> None:
        data = json.loads((REPOSITORY / "bin" / "earlier-copies.json").read_text(encoding="utf-8"))
        self.assertEqual(sorted(data["files"]), sorted(self.NAMES))
        self.assertTrue(all(data["files"].values()) and data["skill"])
        for digest in [d for digests in data["files"].values() for d in digests] + data["skill"]:
            self.assertRegex(digest, r"^[0-9a-f]{64}$")
        files, skills = backend_module.earlier_copies()
        self.assertEqual(files["omawhatsapp"], frozenset(data["files"]["omawhatsapp"]))
        self.assertEqual(skills, frozenset(data["skill"]))

    def test_without_the_list_nothing_counts_as_a_copy(self) -> None:
        with mock.patch.object(backend_module, "EARLIER_COPIES", Path("/nonexistent/earlier-copies.json")), \
                mock.patch.object(backend_module, "_earlier_copies", None):
            self.assertEqual(backend_module.earlier_copies(), ({}, frozenset()))

    def test_the_list_is_exactly_what_the_history_shipped(self) -> None:
        self.needs_history()
        result = subprocess.run([sys.executable, "-B", str(REPOSITORY / "scripts" / "earlier-copies"),
                                 "--check"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_copies_the_last_installer_made_are_the_apps(self) -> None:
        self.needs_history()
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            for name in self.NAMES:
                (home / name).write_bytes(self.git("show", f"{self.SOURCE}:bin/{name}"))
                self.assertTrue(backend_module.Backend._is_earlier_copy(home / name), name)
            skill = home / "skills" / "omawhatsapp"
            listing = self.git("ls-tree", "-r", "--name-only", self.SOURCE, "skills/omawhatsapp/")
            for path in listing.decode("utf-8").split():
                copy = skill / path.removeprefix("skills/omawhatsapp/")
                copy.parent.mkdir(parents=True, exist_ok=True)
                copy.write_bytes(self.git("show", f"{self.SOURCE}:{path}"))
            self.assertTrue(backend_module.Backend._is_earlier_copy(skill))


if __name__ == "__main__":
    unittest.main()
