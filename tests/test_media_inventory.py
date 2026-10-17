"""Every untrusted image/container must cross the resource-limited worker."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]

class MediaInventory(unittest.TestCase):
    def test_no_direct_image_or_media_decoder(self):
        for path in (ROOT / 'plugins/omawhatsapp').rglob('*.qml'):
            text = path.read_text()
            for match in re.finditer(r'(?m)^\s*(?:(\w+)\.)?(Image|BorderImage|AnimatedImage|AnimatedSprite|SpriteSequence|MediaPlayer)\s*\{', text):
                with self.subTest(file=path.name, primitive=match.group(2)):
                    allowed = (path.name in {'SafeImage.qml', 'SafeAnimatedImage.qml'} and match.groups() == ('Native', 'AnimatedImage')) or (path.name == 'SafeMediaPlayer.qml' and match.groups() == (None, 'MediaPlayer'))
                    self.assertTrue(allowed, 'Route external media through the bounded worker')
    def test_shell_native_code_contains_no_file_decoder(self):
        for name in ('inputs.cpp', 'media_items.h'):
            text = (ROOT/'native'/name).read_text()
            self.assertNotRegex(text, r'QImageReader|QMovie|QPixmap|QImage::fromData|\.load\(')
    def test_notification_icon_is_only_a_public_constant(self):
        text = (ROOT/'bin/omawhatsapp_core.py').read_text()
        start=text.index('    def _notification_command(')
        body=text[start:text.index('\n    @staticmethod',start)]
        self.assertIn('NOTIFY_APP_ICON',body)
        self.assertNotIn('avatar',body)
