"""Keep every product editor inside the tested native clipboard boundary."""
import os
from pathlib import Path
import re
import unittest

class EditorInventoryTests(unittest.TestCase):
    def test_no_product_control_bypasses_the_native_boundary(self):
        folder = Path(os.environ["OMAW_SCRIPT"]).resolve().parent.parent / "plugins" / "omawhatsapp"
        allowed = {"SafeTextField.qml", "SafeTextArea.qml", "SafeTextEdit.qml"}
        failures = []
        for file in folder.glob("*.qml"):
            for match in re.finditer(r"(?m)^\s*(?:(\w+)\.)?(TextField|TextArea|TextInput|TextEdit)\s*\{", file.read_text()):
                if file.name not in allowed or match.group(1) != "Native":
                    failures.append(file.name)
        self.assertEqual(failures, [])
