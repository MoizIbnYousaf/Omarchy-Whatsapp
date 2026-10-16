"""Synthetic clipboard producers; no desktop clipboard or account access."""
import importlib.util
import os
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location("account_clipboard_backend", os.environ["OMAW_SCRIPT"])
backend = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = backend
spec.loader.exec_module(backend)

class AccountClipboardTests(unittest.TestCase):
    def offer(self, body):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        script = Path(temp.name) / "wl-paste"
        script.write_text("#!" + sys.executable + "\n" + body)
        script.chmod(0o700)
        return mock.patch.object(backend, "WL_PASTE", script)

    def test_valid_name(self):
        with self.offer('print("work.one_2-test")'):
            self.assertEqual(backend.Backend.paste_account_name()["text"], "work.one_2-test")

    def test_invalid_and_failed_offers(self):
        for body in ['print("a" * 65)', 'print("invalid name")', 'print("é")', 'raise SystemExit(1)']:
            with self.subTest(body=body), self.offer(body):
                with self.assertRaises(backend.OmaWhatsAppError):
                    backend.Backend.paste_account_name()

    def test_unbounded_offer_is_stopped_at_byte_limit(self):
        with self.offer('import os\nwhile True: os.write(1, b"x" * 4096)'):
            before = time.monotonic()
            with self.assertRaises(backend.OmaWhatsAppError):
                backend.Backend.paste_account_name()
            self.assertLess(time.monotonic() - before, 4)

    def test_slow_offer_has_total_deadline(self):
        with self.offer('import os, time\nos.write(1, b"a")\ntime.sleep(30)'):
            before = time.monotonic()
            with self.assertRaises(backend.OmaWhatsAppError):
                backend.Backend.paste_account_name()
            self.assertLess(time.monotonic() - before, 4.5)
