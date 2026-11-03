"""Private native picker boundary; synthetic names, no filesystem export."""
import importlib.machinery
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "bin/omawhatsapp-save-picker"
spec = importlib.util.spec_from_loader("save_picker", importlib.machinery.SourceFileLoader("save_picker", str(SCRIPT)))
picker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(picker)


class SavePickerTests(unittest.TestCase):
    def test_private_unicode_name_arrives_through_bounded_stdin(self):
        name = "Rapport été.pdf"
        self.assertEqual(picker.request(io.BytesIO(json.dumps({"name": name}).encode())), name)

    def test_bad_requests_fail_before_opening_dialog(self):
        for value in ({}, [], {"name": "../private.pdf"}, {"name": "C:\\private.pdf"},
                      {"name": "bad\nname"}, {"name": "\u0000"}, {"name": "界" * 81},
                      {"name": ".."}, {"name": "\ud800"}):
            with self.subTest(value=value), self.assertRaises((ValueError, UnicodeError)):
                picker.request(io.BytesIO(json.dumps(value).encode()))
        with self.assertRaises(ValueError):
            picker.request(io.BytesIO(b" " * 4097))

    def test_missing_display_fails_closed_without_echoing_private_input(self):
        import os
        name = "synthetic-private-attachment.pdf"
        env = dict(os.environ, DISPLAY="", WAYLAND_DISPLAY="/nonexistent/save-picker")
        result = subprocess.run([sys.executable, "-B", str(SCRIPT)],
                                input=json.dumps({"name": name}), env=env,
                                text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")
        self.assertNotIn(name, result.stderr)
        self.assertNotIn(name, " ".join(result.args))
        self.assertNotIn(name, str(env))

    def test_actual_process_receives_name_without_argv_or_environment(self):
        # Stop at the native UI boundary, after the real entry point reads its
        # stdin. Inspect the running process, not a constructed command list.
        import os
        name = "synthetic-private-été.pdf"
        code = ('import runpy,time; m=runpy.run_path(__import__("sys").argv[1]); '
                'm["main"].__globals__["choose"]=lambda name: '
                '(print("READY",flush=True),time.sleep(5),None)[2]; '
                'raise SystemExit(m["main"]())')
        proc = subprocess.Popen([sys.executable, "-B", "-c", code, str(SCRIPT)],
                                stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, text=True)
        try:
            proc.stdin.write(json.dumps({"name": name}))
            proc.stdin.close()
            self.assertEqual(proc.stdout.readline().strip(), "READY")
            for filename in ("cmdline", "environ"):
                self.assertNotIn(name.encode(), Path(f"/proc/{proc.pid}/{filename}").read_bytes())
        finally:
            proc.terminate()
            proc.wait(timeout=5)
            proc.stdout.close()
            proc.stderr.close()
