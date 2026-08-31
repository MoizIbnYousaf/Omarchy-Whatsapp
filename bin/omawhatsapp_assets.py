"""Private, bounded local cache primitives for WhatsApp chat avatars."""

from __future__ import annotations

from contextlib import contextmanager
import hashlib
from http.client import HTTPException, HTTPSConnection
import ipaddress
import json
import os
from pathlib import Path
import re
import secrets
import socket
import ssl
import stat
from typing import Any, Iterator
from urllib.parse import urljoin, urlparse


MAX_AVATAR_BYTES = 1024 * 1024
MAX_AVATAR_FILES = 128
MAX_AVATAR_INDEX = 512 * 1024
AVATAR_DIRECTORY = "avatars"
AVATAR_INDEX = "avatars.json"
AVATAR_FILE = re.compile(r"[0-9a-f]{64}\.(?:jpg|png|webp)\Z")
AVATAR_TEMP_FILE = re.compile(
    r"\.[0-9a-f]{64}\.(?:jpg|png|webp)\.[0-9a-f]{24}\.tmp\Z"
)


class AvatarCacheError(RuntimeError):
    pass


def _public_https_target(value: str) -> tuple[str, str, list[str]]:
    parsed = urlparse(str(value or "").strip())
    try:
        port = parsed.port
    except ValueError as exc:
        raise AvatarCacheError("WhatsApp returned an unsafe profile-photo URL.") from exc
    if (parsed.scheme != "https" or not parsed.hostname or parsed.username
            or parsed.password or port not in (None, 443)):
        raise AvatarCacheError("WhatsApp returned an unsafe profile-photo URL.")
    try:
        addresses = socket.getaddrinfo(
            parsed.hostname, 443, type=socket.SOCK_STREAM
        )
    except OSError as exc:
        raise AvatarCacheError("The profile-photo host could not be resolved.") from exc
    if not addresses:
        raise AvatarCacheError("The profile-photo host could not be resolved.")
    public_addresses: list[str] = []
    for address in addresses:
        try:
            candidate = ipaddress.ip_address(address[4][0])
        except ValueError as exc:
            raise AvatarCacheError("The profile-photo host returned an invalid address.") from exc
        if not candidate.is_global:
            raise AvatarCacheError("The profile-photo host is not public.")
        normalized = str(candidate)
        if normalized not in public_addresses:
            public_addresses.append(normalized)
    return parsed.geturl(), parsed.hostname, public_addresses


def _validate_public_https_url(value: str) -> str:
    return _public_https_target(value)[0]


class _PinnedHTTPSConnection(HTTPSConnection):
    """Use the validated address while retaining hostname TLS verification."""

    def __init__(self, hostname: str, address: str, timeout: float) -> None:
        super().__init__(
            hostname, port=443, timeout=timeout, context=ssl.create_default_context()
        )
        self.address = address

    def connect(self) -> None:
        raw = socket.create_connection(
            (self.address, self.port), self.timeout, self.source_address
        )
        try:
            self.sock = self._context.wrap_socket(raw, server_hostname=self.host)
        except BaseException:
            raw.close()
            raise


def _image_extension(data: bytes) -> str:
    if data.startswith(b"\xff\xd8\xff"):
        return "jpg"
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "png"
    if len(data) >= 12 and data.startswith(b"RIFF") and data[8:12] == b"WEBP":
        return "webp"
    raise AvatarCacheError("WhatsApp returned an unsupported profile-photo format.")


def _nonnegative_int(value: Any) -> int:
    try:
        return max(0, int(value or 0))
    except (TypeError, ValueError):
        return 0


def fetch_https_image(url: str, timeout: float = 20) -> bytes:
    """Fetch one small image with DNS-pinned, hostname-verified HTTPS."""
    current = str(url or "")
    for _ in range(4):
        safe_url, hostname, addresses = _public_https_target(current)
        parsed = urlparse(safe_url)
        target = parsed.path or "/"
        if parsed.query:
            target += "?" + parsed.query
        response = None
        connection = None
        last_error: BaseException | None = None
        for address in addresses:
            candidate = _PinnedHTTPSConnection(hostname, address, timeout)
            try:
                candidate.request("GET", target, headers={
                    "Accept": "image/jpeg,image/png,image/webp",
                    "User-Agent": "OmaWhatsApp/1",
                })
                response = candidate.getresponse()
                connection = candidate
                break
            except (HTTPException, OSError, ssl.SSLError) as exc:
                last_error = exc
                candidate.close()
        if response is None or connection is None:
            raise AvatarCacheError(
                "That profile photo could not be downloaded."
            ) from last_error
        try:
            if response.status in {301, 302, 303, 307, 308}:
                location = str(response.getheader("Location") or "")
                if not location:
                    raise AvatarCacheError("The profile-photo redirect was invalid.")
                current = urljoin(safe_url, location)
                continue
            if response.status != 200:
                raise AvatarCacheError("That profile photo could not be downloaded.")
            content_type = str(response.headers.get_content_type() or "").lower()
            if content_type not in {"image/jpeg", "image/png", "image/webp"}:
                raise AvatarCacheError("WhatsApp returned a non-image profile photo.")
            length = response.getheader("Content-Length")
            if length and int(length) > MAX_AVATAR_BYTES:
                raise AvatarCacheError("That profile photo is too large to cache safely.")
            data = response.read(MAX_AVATAR_BYTES + 1)
        except (HTTPException, OSError, ValueError) as exc:
            raise AvatarCacheError(
                "That profile photo could not be downloaded."
            ) from exc
        finally:
            response.close()
            connection.close()
        if not data or len(data) > MAX_AVATAR_BYTES:
            raise AvatarCacheError("That profile photo is empty or too large.")
        _image_extension(data)
        return data
    raise AvatarCacheError("The profile photo redirected too many times.")


class AvatarCache:
    """A private cache keyed by opaque account-and-chat identities."""

    def __init__(self, state_dir: Path) -> None:
        self.state_dir = state_dir

    @contextmanager
    def _directory(self, name: str = "", *, create: bool) -> Iterator[int]:
        try:
            if create:
                self.state_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
            root_flags = os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC
            if hasattr(os, "O_NOFOLLOW"):
                root_flags |= os.O_NOFOLLOW
            root = os.open(self.state_dir, root_flags)
            try:
                metadata = os.fstat(root)
                if not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid != os.getuid():
                    raise OSError("unsafe state directory")
                if create:
                    os.fchmod(root, 0o700)
                if not name:
                    yield root
                    return
                if create:
                    try:
                        os.mkdir(name, mode=0o700, dir_fd=root)
                    except FileExistsError:
                        pass
                child = os.open(name, root_flags, dir_fd=root)
                try:
                    child_metadata = os.fstat(child)
                    if (not stat.S_ISDIR(child_metadata.st_mode)
                            or child_metadata.st_uid != os.getuid()):
                        raise OSError("unsafe avatar directory")
                    if create:
                        os.fchmod(child, 0o700)
                    yield child
                finally:
                    os.close(child)
            finally:
                os.close(root)
        except OSError as exc:
            raise AvatarCacheError("The private profile-photo cache is unsafe.") from exc

    def _load(self) -> dict[str, dict[str, Any]]:
        descriptor = -1
        flags = os.O_RDONLY | os.O_CLOEXEC
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        try:
            with self._directory(create=False) as directory:
                descriptor = os.open(AVATAR_INDEX, flags, dir_fd=directory)
                metadata = os.fstat(descriptor)
                if (not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != os.getuid()
                        or metadata.st_nlink != 1 or metadata.st_size > MAX_AVATAR_INDEX):
                    return {}
                data = os.read(descriptor, MAX_AVATAR_INDEX + 1)
        except (AvatarCacheError, FileNotFoundError, OSError):
            return {}
        finally:
            if descriptor >= 0:
                os.close(descriptor)
        try:
            value = json.loads(data.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            return {}
        if not isinstance(value, dict):
            return {}
        clean: dict[str, dict[str, Any]] = {}
        for key, item in list(value.items())[:MAX_AVATAR_FILES]:
            if not isinstance(key, str) or not key or not isinstance(item, dict):
                continue
            filename = str(item.get("filename") or "")
            if filename and not AVATAR_FILE.fullmatch(filename):
                continue
            clean[key[:8192]] = {
                "picture_id": str(item.get("picture_id") or "")[:256],
                "filename": filename,
                "checked_at": _nonnegative_int(item.get("checked_at")),
                "retry_after": _nonnegative_int(item.get("retry_after")),
                "missing": item.get("missing") is True,
            }
        return clean

    def entries(self, keys: list[str]) -> dict[str, dict[str, Any]]:
        wanted = set(keys)
        return {key: value for key, value in self._load().items() if key in wanted}

    def _valid_path(self, filename: str) -> str:
        if not AVATAR_FILE.fullmatch(filename):
            return ""
        descriptor = -1
        flags = os.O_RDONLY | os.O_CLOEXEC
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        try:
            with self._directory(AVATAR_DIRECTORY, create=False) as directory:
                descriptor = os.open(filename, flags, dir_fd=directory)
                metadata = os.fstat(descriptor)
                if (not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != os.getuid()
                        or metadata.st_nlink != 1 or metadata.st_size <= 0
                        or metadata.st_size > MAX_AVATAR_BYTES):
                    return ""
        except (AvatarCacheError, FileNotFoundError, OSError):
            return ""
        finally:
            if descriptor >= 0:
                os.close(descriptor)
        return str(self.state_dir / AVATAR_DIRECTORY / filename)

    def paths(self, keys: list[str]) -> dict[str, str]:
        index = self._load()
        wanted = set(keys)
        entries = {key: item for key, item in index.items() if key in wanted}
        return {
            key: path for key, item in entries.items()
            if (path := self._valid_path(str(item.get("filename") or "")))
        }

    def prune(self) -> None:
        """Remove crash orphans while the caller holds the refresh lock."""
        self._prune_files({
            str(item.get("filename") or "") for item in self._load().values()
        })

    def _write_file(self, key: str, picture_id: str, data: bytes) -> str:
        extension = _image_extension(data)
        digest = hashlib.sha256(
            key.encode("utf-8") + b"\0" + picture_id.encode("utf-8")
            + b"\0" + hashlib.sha256(data).digest()
        ).hexdigest()
        filename = f"{digest}.{extension}"
        temporary = f".{filename}.{secrets.token_hex(12)}.tmp"
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        descriptor = -1
        try:
            with self._directory(AVATAR_DIRECTORY, create=True) as directory:
                descriptor = os.open(temporary, flags, 0o600, dir_fd=directory)
                os.fchmod(descriptor, 0o600)
                view = memoryview(data)
                while view:
                    view = view[os.write(descriptor, view):]
                os.fsync(descriptor)
                os.close(descriptor)
                descriptor = -1
                os.replace(temporary, filename, src_dir_fd=directory,
                           dst_dir_fd=directory)
                os.fsync(directory)
        except OSError as exc:
            raise AvatarCacheError("The profile photo could not be cached privately.") from exc
        finally:
            if descriptor >= 0:
                os.close(descriptor)
            try:
                with self._directory(AVATAR_DIRECTORY, create=False) as directory:
                    os.unlink(temporary, dir_fd=directory)
            except (AvatarCacheError, FileNotFoundError, OSError):
                pass
        return filename

    def _prune_files(self, keep: set[str]) -> None:
        try:
            with self._directory(AVATAR_DIRECTORY, create=False) as directory:
                for filename in os.listdir(directory):
                    if filename in keep:
                        continue
                    if (not AVATAR_FILE.fullmatch(filename)
                            and not AVATAR_TEMP_FILE.fullmatch(filename)):
                        continue
                    try:
                        os.unlink(filename, dir_fd=directory)
                    except FileNotFoundError:
                        pass
        except (AvatarCacheError, FileNotFoundError, OSError):
            pass

    def _write_index(self, value: dict[str, dict[str, Any]]) -> None:
        encoded = json.dumps(value, separators=(",", ":")).encode("utf-8")
        if len(encoded) > MAX_AVATAR_INDEX:
            raise AvatarCacheError("The profile-photo index exceeded its safe limit.")
        temporary = f".{AVATAR_INDEX}.{secrets.token_hex(12)}.tmp"
        descriptor = -1
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        with self._directory(create=True) as directory:
            try:
                descriptor = os.open(temporary, flags, 0o600, dir_fd=directory)
                os.fchmod(descriptor, 0o600)
                view = memoryview(encoded)
                while view:
                    view = view[os.write(descriptor, view):]
                os.fsync(descriptor)
                os.close(descriptor)
                descriptor = -1
                os.replace(temporary, AVATAR_INDEX, src_dir_fd=directory,
                           dst_dir_fd=directory)
                os.fsync(directory)
            except OSError as exc:
                raise AvatarCacheError("The profile-photo index could not be saved.") from exc
            finally:
                if descriptor >= 0:
                    os.close(descriptor)
                try:
                    os.unlink(temporary, dir_fd=directory)
                except FileNotFoundError:
                    pass

    def update(self, values: list[dict[str, Any]]) -> None:
        index = self._load()
        for value in values:
            key = str(value.get("key") or "")[:8192]
            if not key:
                continue
            previous = index.get(key, {})
            filename = str(previous.get("filename") or "")
            data = value.get("data")
            if isinstance(data, bytes) and data:
                filename = self._write_file(
                    key, str(value.get("picture_id") or "")[:256], data
                )
            elif value.get("missing") is True:
                filename = ""
            index[key] = {
                "picture_id": str(value.get("picture_id") or "")[:256],
                "filename": filename,
                "checked_at": _nonnegative_int(value.get("checked_at")),
                "retry_after": _nonnegative_int(value.get("retry_after")),
                "missing": value.get("missing") is True,
            }
        ordered = sorted(
            index.items(), key=lambda pair: max(
                _nonnegative_int(pair[1].get("checked_at")),
                _nonnegative_int(pair[1].get("retry_after")),
            )
        )
        index = dict(ordered[-MAX_AVATAR_FILES:])
        try:
            self._write_index(index)
        except AvatarCacheError:
            # Publication may already have happened if the final directory
            # fsync failed. Preserve both generations; the next serialized
            # refresh reads the live index before pruning crash orphans.
            raise
        keep = {str(item.get("filename") or "") for item in index.values()}
        self._prune_files(keep)
