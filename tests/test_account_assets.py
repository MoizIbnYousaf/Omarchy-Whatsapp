from __future__ import annotations

import json
import os
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from unittest import mock


BIN = Path(__file__).resolve().parents[1] / "bin"
sys.path.insert(0, str(BIN))

from omawhatsapp_assets import (  # noqa: E402
    AvatarCache,
    AvatarCacheError,
    _validate_public_https_url,
    fetch_https_image,
)


class AvatarCacheTests(unittest.TestCase):
    class _Headers:
        def get_content_type(self) -> str:
            return "image/jpeg"

    class _Response:
        def __init__(self, status: int, location: str = "") -> None:
            self.status = status
            self.location = location
            self.headers = AvatarCacheTests._Headers()

        def getheader(self, name: str):
            return self.location if name == "Location" else None

        def read(self, limit: int) -> bytes:
            return b"\xff\xd8\xffsynthetic"

        def close(self) -> None:
            pass

    def test_download_connects_only_to_each_validated_redirect_address(self) -> None:
        responses = [self._Response(302, "https://next.example/avatar"),
                     self._Response(200)]
        connections = []

        class Connection:
            def __init__(self, hostname, address, timeout):
                connections.append((hostname, address))
                self.response = responses.pop(0)

            def request(self, method, target, headers):
                pass

            def getresponse(self):
                return self.response

            def close(self):
                pass

        targets = [
            ("https://first.example/avatar", "first.example", ["93.184.216.34"]),
            ("https://next.example/avatar", "next.example", ["8.8.8.8"]),
        ]
        with mock.patch(
                "omawhatsapp_assets._public_https_target", side_effect=targets), \
                mock.patch(
                    "omawhatsapp_assets._PinnedHTTPSConnection", Connection):
            self.assertTrue(fetch_https_image("https://first.example/avatar"))
        self.assertEqual(connections, [
            ("first.example", "93.184.216.34"),
            ("next.example", "8.8.8.8"),
        ])

    def test_avatar_urls_must_be_plain_https_on_public_addresses(self) -> None:
        public = [(None, None, None, None, ("93.184.216.34", 443))]
        private = [(None, None, None, None, ("127.0.0.1", 443))]
        with mock.patch("omawhatsapp_assets.socket.getaddrinfo", return_value=public):
            self.assertEqual(
                _validate_public_https_url("https://cdn.example.test/avatar.jpg"),
                "https://cdn.example.test/avatar.jpg",
            )
            for unsafe in (
                "http://cdn.example.test/avatar.jpg",
                "https://user:secret@cdn.example.test/avatar.jpg",
                "https://cdn.example.test:8443/avatar.jpg",
                "https://cdn.example.test:bad/avatar.jpg",
            ):
                with self.subTest(unsafe=unsafe), self.assertRaises(AvatarCacheError):
                    _validate_public_https_url(unsafe)
        with mock.patch("omawhatsapp_assets.socket.getaddrinfo", return_value=private):
            with self.assertRaisesRegex(AvatarCacheError, "not public"):
                _validate_public_https_url("https://localhost/avatar.jpg")

    def test_cache_is_private_bounded_and_uses_opaque_file_names(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            state = Path(temporary) / "state"
            cache = AvatarCache(state)
            private_key = "opaque-account-and-chat"
            cache.update([{
                "key": private_key, "picture_id": "picture-one", "checked_at": 10,
                "missing": False, "data": b"\xff\xd8\xffsynthetic",
            }])
            path = Path(cache.paths([private_key])[private_key])
            self.assertTrue(path.is_file())
            self.assertNotIn("opaque", path.name)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertEqual(path.parent.stat().st_mode & 0o777, 0o700)
            self.assertEqual(state.stat().st_mode & 0o777, 0o700)
            self.assertEqual((state / "avatars.json").stat().st_mode & 0o777, 0o600)

            path.write_bytes(b"partial")
            cache.update([{
                "key": private_key, "picture_id": "picture-one", "checked_at": 11,
                "missing": False, "data": b"\xff\xd8\xffsynthetic",
            }])
            self.assertEqual(path.read_bytes(), b"\xff\xd8\xffsynthetic")

    def test_cache_prunes_overflow_and_crash_orphans(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            state = Path(temporary) / "state"
            cache = AvatarCache(state)
            cache.update([{
                "key": f"key-{index}", "picture_id": f"picture-{index}",
                "checked_at": index + 1, "missing": False,
                "data": b"\xff\xd8\xffsynthetic" + bytes([index % 256]),
            } for index in range(129)])
            avatars = state / "avatars"
            self.assertEqual(len(list(avatars.iterdir())), 128)
            index = json.loads((state / "avatars.json").read_text(encoding="utf-8"))
            self.assertEqual(len(index), 128)

            orphan = avatars / ("f" * 64 + ".jpg")
            orphan.write_bytes(b"\xff\xd8\xfforphan")
            temporary = avatars / ("." + "e" * 64 + ".jpg." + "d" * 24 + ".tmp")
            temporary.write_bytes(b"partial")
            cache.paths([])
            self.assertTrue(orphan.exists())
            self.assertTrue(temporary.exists())
            cache.prune()
            self.assertFalse(orphan.exists())
            self.assertFalse(temporary.exists())

    def test_full_cache_keeps_new_failure_backoff_records(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            cache = AvatarCache(Path(temporary) / "state")
            cache.update([{
                "key": f"cached-{index}", "picture_id": "",
                "checked_at": index + 1, "missing": True,
            } for index in range(128)])
            cache.update([{
                "key": "retry-later", "picture_id": "", "checked_at": 0,
                "retry_after": 10_000, "missing": False,
            }])
            entries = cache.entries([
                "retry-later", "cached-0", "cached-127"
            ])
            self.assertIn("retry-later", entries)
            self.assertNotIn("cached-0", entries)
            self.assertIn("cached-127", entries)

    def test_reader_never_prunes_an_inflight_atomic_write(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            cache = AvatarCache(Path(temporary) / "state")
            cache.update([{
                "key": "old", "picture_id": "old", "checked_at": 1,
                "missing": False, "data": b"\xff\xd8\xffold",
            }])
            entered = threading.Event()
            release = threading.Event()
            original = cache._write_index
            failures = []

            def blocked(index):
                entered.set()
                release.wait(timeout=2)
                original(index)

            def update():
                try:
                    cache.update([{
                        "key": "new", "picture_id": "new", "checked_at": 2,
                        "missing": False, "data": b"\xff\xd8\xffnew",
                    }])
                except BaseException as exc:
                    failures.append(exc)

            with mock.patch.object(cache, "_write_index", side_effect=blocked):
                worker = threading.Thread(target=update)
                worker.start()
                self.assertTrue(entered.wait(timeout=2))
                inflight = set((cache.state_dir / "avatars").iterdir())
                cache.paths([])
                self.assertEqual(set((cache.state_dir / "avatars").iterdir()), inflight)
                release.set()
                worker.join(timeout=2)
            self.assertFalse(worker.is_alive())
            self.assertEqual(failures, [])
            self.assertEqual(set(cache.paths(["old", "new"])), {"old", "new"})

    def test_post_publish_fsync_failure_preserves_both_generations(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            cache = AvatarCache(Path(temporary) / "state")
            cache.update([{
                "key": "old", "picture_id": "old", "checked_at": 1,
                "missing": False, "data": b"\xff\xd8\xffold",
            }])
            real_replace = os.replace
            real_fsync = os.fsync
            published = {"index": False}

            def replace(source, target, **kwargs):
                result = real_replace(source, target, **kwargs)
                if target == "avatars.json":
                    published["index"] = True
                return result

            def fsync(descriptor):
                if published["index"]:
                    published["index"] = False
                    raise OSError("synthetic post-publication fsync failure")
                return real_fsync(descriptor)

            with mock.patch("omawhatsapp_assets.os.replace", side_effect=replace), \
                    mock.patch("omawhatsapp_assets.os.fsync", side_effect=fsync), \
                    self.assertRaises(AvatarCacheError):
                cache.update([{
                    "key": "new", "picture_id": "new", "checked_at": 2,
                    "missing": False, "data": b"\xff\xd8\xffnew",
                }])
            self.assertEqual(set(cache.paths(["old", "new"])), {"old", "new"})

    def test_symlinked_avatar_is_never_returned_to_qml(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            state = Path(temporary) / "state"
            avatars = state / "avatars"
            avatars.mkdir(parents=True, mode=0o700)
            filename = "a" * 64 + ".jpg"
            (avatars / filename).symlink_to("/etc/passwd")
            (state / "avatars.json").write_text(json.dumps({
                "opaque": {
                    "picture_id": "one", "filename": filename,
                    "checked_at": 1, "missing": False,
                }
            }), encoding="utf-8")
            os.chmod(state / "avatars.json", 0o600)
            self.assertEqual(AvatarCache(state).paths(["opaque"]), {})


if __name__ == "__main__":
    unittest.main()
