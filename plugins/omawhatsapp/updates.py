#!/usr/bin/python3
"""Release discovery and explicitly confirmed, full-app standalone upgrades.

No WhatsApp state is read here. Managed installs never run this installer.
"""
import argparse
import io
import json
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import tempfile
import time
import urllib.request
import zipfile

REPOSITORY = "MoizIbnYousaf/Omarchy-Whatsapp"
API = "https://api.github.com/repos/" + REPOSITORY
RELEASES = "https://github.com/" + REPOSITORY + "/releases"
VERSION = re.compile(r"v?(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})\Z")
SHA = re.compile(r"[0-9a-f]{40}\Z")


def version(value):
    match = VERSION.fullmatch(str(value))
    if not match:
        raise ValueError("The release version is not supported.")
    return tuple(map(int, match.groups()))


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError("Unexpected update redirect; no files were installed.")


def download(url, limit):
    # All callers construct fixed-host URLs from validated versions/SHAs.
    request = urllib.request.Request(url, headers={"User-Agent": "OmaWhatsApp-updates"})
    deadline = time.monotonic() + 30
    with urllib.request.build_opener(NoRedirect).open(request, timeout=10) as response:
        chunks = []
        size = 0
        while True:
            chunk = response.read(min(65536, limit + 1 - size))
            size += len(chunk)
            if size > limit or time.monotonic() > deadline:
                raise ValueError("Update download exceeded its size or time limit.")
            if not chunk:
                return b"".join(chunks)
            chunks.append(chunk)


def api(path):
    result = json.loads(download(API + path, 1024 * 1024))
    if not isinstance(result, dict):
        raise ValueError("Invalid release response.")
    return result


def standalone(directory):
    marker = directory / "install-mode"
    return (not marker.is_symlink() and marker.is_file()
            and marker.stat().st_size == 11
            and marker.read_text() == "standalone\n")


def check(directory):
    current = json.loads((directory / "manifest.json").read_text())["version"]
    release = api("/releases/latest")
    tag = release.get("tag_name", "")
    newer = version(tag) > version(current)
    if release.get("draft") is not False or release.get("prerelease") is not False:
        raise ValueError("No stable release is available.")
    commit = api("/commits/" + tag).get("sha", "")
    if not isinstance(commit, str) or not SHA.fullmatch(commit):
        raise ValueError("The release could not be pinned to a commit.")
    return {"ok": True, "current": current, "version": tag, "commit": commit,
            "available": newer, "standalone": standalone(directory)}


def extract(data, destination):
    """Extract only regular files/directories under one root, with hard limits."""
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        entries = archive.infolist()
        if not entries or len(entries) > 4096:
            raise ValueError("Invalid update archive size.")
        first = PurePosixPath(entries[0].filename).parts
        if not first:
            raise ValueError("Empty update archive root.")
        root = first[0]
        total = 0
        seen = set()
        for item in entries:
            path = PurePosixPath(item.filename)
            mode = item.external_attr >> 16
            total += item.file_size
            if (not path.parts or path.is_absolute() or ".." in path.parts or path.parts[0] != root
                    or "\\" in item.filename or item.filename in seen
                    or total > 128 * 1024 * 1024
                    or (stat.S_IFMT(mode) not in (0, stat.S_IFREG, stat.S_IFDIR))):
                raise ValueError("Unsafe update archive; no files were installed.")
            seen.add(item.filename)
        for item in entries:
            target = destination.joinpath(*PurePosixPath(item.filename).parts)
            if item.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with archive.open(item) as source, target.open("xb") as output:
                    # Declared uncompressed sizes were bounded above; zipfile
                    # enforces those lengths and verifies each file's CRC.
                    output.write(source.read())
                target.chmod(0o700 if item.external_attr >> 16 & 0o111 else 0o600)
    return destination / root


def install(directory, tag, commit):
    version(tag)
    if not SHA.fullmatch(commit) or not standalone(directory):
        raise ValueError("Use your plugin manager to update this managed installation.")
    if version(tag) <= version(json.loads((directory / "manifest.json").read_text())["version"]):
        raise ValueError("This release is already installed or older.")
    print(f"Install OmaWhatsApp {tag} ({commit})?\n"
          "This installs upstream release code, not a marketplace verification.\n"
          "The full app will be upgraded and the Omarchy shell restarted.\n"
          "Finish any voice recording and save your drafts first.")
    if input("Type INSTALL to continue: ").strip() != "INSTALL":
        print("Cancelled. Nothing was changed.")
        return
    with tempfile.TemporaryDirectory(prefix="omawhatsapp-update-") as temporary:
        root = extract(download("https://codeload.github.com/" + REPOSITORY
                                + "/zip/" + commit, 32 * 1024 * 1024), Path(temporary))
        manifest = json.loads((root / "manifest.json").read_text())
        if (manifest.get("id") != "io.github.moizibnyousaf.omawhatsapp"
                or version(manifest.get("version")) != version(tag)):
            raise ValueError("The pinned release manifest does not match the update.")
        subprocess.run(["bash", str(root / "scripts/install")], check=True, timeout=600)
    print("OmaWhatsApp updated. You can close this terminal.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("check", "install"))
    parser.add_argument("--version", default="")
    parser.add_argument("--commit", default="")
    args = parser.parse_args()
    directory = Path(__file__).resolve().parent
    try:
        if args.action == "check":
            print(json.dumps(check(directory)))
        else:
            install(directory, args.version, args.commit)
        return 0
    except (OSError, ValueError, KeyError, EOFError, zipfile.BadZipFile,
            subprocess.SubprocessError):
        # Network/installer exceptions can contain local paths. Keep UI output
        # generic; installer diagnostics remain in the user's own terminal.
        message = "Update failed. Check your connection or use the documented installer."
        print(json.dumps({"ok": False, "error": message}))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
