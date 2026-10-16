from pathlib import Path
import re
import unittest
class AnimationInventory(unittest.TestCase):
 def test_no_unguarded_qt_movie_inputs(self):
  root=Path(__file__).resolve().parents[1]/"plugins/omawhatsapp"
  for path in root.glob("*.qml"):
   with self.subTest(path=path.name):
    self.assertFalse(re.search(r"(?<![\w.])AnimatedImage\s*\{",path.read_text()),"Use SafeAnimatedImage to avoid recursive QMovie playback")
