import importlib.util
import io
import json
import os
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch
import zipfile

SCRIPT = Path(__file__).resolve().parents[1] / "plugins/omawhatsapp/updates.py"
spec = importlib.util.spec_from_file_location("updates", SCRIPT)
updates = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updates)
SHA = "a" * 40


class UpdateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "manifest.json").write_text(json.dumps({"version": "0.11.2"}))

    def release(self, tag="v0.12.0", **values):
        return {"tag_name": tag, "draft": False, "prerelease": False, **values}

    def archive(self, entries):
        stream = io.BytesIO()
        with zipfile.ZipFile(stream, "w") as archive:
            for name, data in entries:
                archive.writestr(name, data)
        return stream.getvalue()

    def test_semantic_versions(self):
        self.assertGreater(updates.version("v0.12.0"), updates.version("0.9.9"))
        for invalid in ("latest", "v1.0.0/evil", "1.0", "1.0.0-beta", "01.0.0"):
            with self.assertRaises(ValueError):
                updates.version(invalid)

    def test_check_new_current_and_older(self):
        for tag, available in (("v0.12.0", True), ("v0.11.2", False), ("v0.9.0", False)):
            with patch.object(updates, "api", side_effect=[self.release(tag), {"sha": SHA}]) as api:
                result = updates.check(self.root)
            self.assertEqual(result["available"], available)
            self.assertFalse(result["standalone"])
            self.assertEqual(api.call_args_list[1].args, ("/commits/" + tag,))

    def test_unstable_and_invalid_release_fail_closed(self):
        for release in (self.release(prerelease=True), self.release(draft=True), self.release("../main")):
            with patch.object(updates, "api", return_value=release) as api:
                with self.assertRaises(ValueError):
                    updates.check(self.root)
                self.assertEqual(api.call_count, 1)

    def test_managed_install_never_downloads_or_prompts(self):
        with patch.object(updates, "download") as download, patch("builtins.input") as prompt:
            with self.assertRaises(ValueError):
                updates.install(self.root, "v0.12.0", SHA)
            download.assert_not_called()
            prompt.assert_not_called()

    def test_marker_and_cancel(self):
        marker = self.root / "install-mode"
        marker.write_text("standalone\n")
        self.assertTrue(updates.standalone(self.root))
        with patch("builtins.input", return_value="no"), patch.object(updates, "download") as download:
            updates.install(self.root, "v0.12.0", SHA)
            download.assert_not_called()
        marker.unlink()
        target = self.root / "elsewhere"
        target.write_text("standalone\n")
        marker.symlink_to(target)
        self.assertFalse(updates.standalone(self.root))

    def test_archive_rejects_escapes_links_and_multiple_roots(self):
        link = zipfile.ZipInfo("root/link")
        link.external_attr = (stat.S_IFLNK | 0o777) << 16
        for entries in ([("../escape", "bad")], [("/absolute", "bad")],
                        [("root/a", "ok"), ("other/a", "bad")],
                        [(link, "/etc/passwd")], [("root/a", "a"), ("root/a", "b")]):
            with self.assertRaises(ValueError):
                updates.extract(self.archive(entries), self.root / "extract")
        self.assertFalse((self.root / "extract").exists())

    def test_confirmed_update_uses_pinned_full_installer(self):
        (self.root / "install-mode").write_text("standalone\n")
        archive = self.archive([
            ("release/manifest.json", json.dumps({"id": "io.github.moizibnyousaf.omawhatsapp", "version": "0.12.0"})),
            ("release/scripts/install", "#!/bin/bash\nexit 0\n")])
        with patch("builtins.input", return_value="INSTALL"), patch.object(updates, "download", return_value=archive) as download, patch.object(updates.subprocess, "run") as run:
            updates.install(self.root, "v0.12.0", SHA)
        self.assertTrue(download.call_args.args[0].endswith("/zip/" + SHA))
        self.assertEqual(run.call_args.args[0][0], "bash")
        self.assertTrue(run.call_args.args[0][1].endswith("/scripts/install"))
        self.assertEqual(run.call_args.kwargs, {"check": True, "timeout": 600})

    def test_redirect_is_never_followed(self):
        with self.assertRaises(ValueError):
            updates.NoRedirect().redirect_request(None, None, 302, "", {}, "http://localhost")

    def test_download_size_and_time_limits(self):
        class Response(io.BytesIO):
            pass
        for body, limit, times in ((b"12345", 4, [0, 1]), (b"ok", 10, [0, 31])):
            with patch.object(updates.urllib.request, "build_opener") as opener, patch.object(updates.time, "monotonic", side_effect=times):
                opener.return_value.open.return_value = Response(body)
                with self.assertRaises(ValueError):
                    updates.download(updates.API, limit)

    def test_mismatched_release_never_executes_installer(self):
        (self.root / "install-mode").write_text("standalone\n")
        archive = self.archive([("release/manifest.json", json.dumps({"id": "wrong", "version": "0.12.0"}))])
        with patch("builtins.input", return_value="INSTALL"), patch.object(updates, "download", return_value=archive), patch.object(updates.subprocess, "run") as run:
            with self.assertRaises(ValueError):
                updates.install(self.root, "v0.12.0", SHA)
            run.assert_not_called()

    def test_real_subprocess_handoff_with_offline_synthetic_installer(self):
        (self.root / "install-mode").write_text("standalone\n")
        proof = self.root / "proof"
        archive = self.archive([
            ("release/manifest.json", json.dumps({"id": "io.github.moizibnyousaf.omawhatsapp", "version": "0.12.0"})),
            ("release/scripts/install", '#!/bin/bash\nprintf installed > "$OMAW_TEST_PROOF"\n')])
        with patch("builtins.input", return_value="INSTALL"), patch.object(updates, "download", return_value=archive), patch.dict(os.environ, {"OMAW_TEST_PROOF": str(proof)}):
            updates.install(self.root, "v0.12.0", SHA)
        self.assertEqual(proof.read_text(), "installed")


if __name__ == "__main__":
    unittest.main()
