#!/usr/bin/env python3
"""Crash-safe filesystem transaction support for install and uninstall.

The shell entry points own product-specific validation and systemd policy. This
helper owns the smaller, security-sensitive primitive: durable target swaps and
their exact rollback. Its journal deliberately contains paths and public unit
names only; it never reads or records application data.
"""

from __future__ import annotations

import argparse
import ctypes
import errno
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import stat
import sys
import uuid
from typing import Any, NoReturn


SCHEMA = 1
KIND = "io.github.moizibnyousaf.omawhatsapp.install-transaction"
UNIT_RE = re.compile(r"^wacli-sync(?:@[A-Za-z0-9._-]{1,64})?\.service$")
RENAME_NOREPLACE = 1
AT_FDCWD = -100


class TransactionError(RuntimeError):
    """A transaction invariant failed without intentionally clobbering data."""


def fail(message: str) -> NoReturn:
    raise TransactionError(message)


def absolute_path(value: object, label: str, *, allow_root: bool = False) -> Path:
    if not isinstance(value, str) or not value or not os.path.isabs(value):
        fail(f"{label} must be an absolute path")
    path = Path(value)
    if not allow_root and path == Path("/"):
        fail(f"{label} must not be the filesystem root")
    return path


def path_exists(path: Path) -> bool:
    try:
        path.lstat()
        return True
    except FileNotFoundError:
        return False


def fsync_directory(path: Path) -> None:
    descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def fsync_file(path: Path) -> None:
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def atomic_write_json(path: Path, payload: dict[str, Any]) -> None:
    encoded = (json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n").encode()
    temporary = path.parent / f".{path.name}.{uuid.uuid4().hex}.tmp"
    descriptor = os.open(
        temporary,
        os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
        0o600,
    )
    try:
        with os.fdopen(descriptor, "wb", closefd=True) as stream:
            stream.write(encoded)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        fsync_directory(path.parent)
    except BaseException:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass
        raise


def unlink_durable(path: Path) -> None:
    path.unlink()
    fsync_directory(path.parent)


def remove_exact(path: Path) -> None:
    if not path_exists(path):
        return
    mode = path.lstat().st_mode
    if stat.S_ISDIR(mode) and not stat.S_ISLNK(mode):
        shutil.rmtree(path)
    else:
        path.unlink()
    fsync_directory(path.parent)


def copy_durable(source: Path, target: Path) -> None:
    if path_exists(target):
        fail(f"transaction staging target already exists: {target}")
    mode = source.lstat().st_mode
    if stat.S_ISDIR(mode) and not stat.S_ISLNK(mode):
        shutil.copytree(source, target, symlinks=True, copy_function=shutil.copy2)
    elif stat.S_ISREG(mode):
        shutil.copy2(source, target, follow_symlinks=False)
    elif stat.S_ISLNK(mode):
        target.symlink_to(os.readlink(source))
    else:
        fail(f"unsupported transaction source type: {source}")

    def sync_tree(current: Path) -> None:
        current_mode = current.lstat().st_mode
        if stat.S_ISREG(current_mode):
            fsync_file(current)
        elif stat.S_ISDIR(current_mode) and not stat.S_ISLNK(current_mode):
            with os.scandir(current) as entries:
                children = [current / entry.name for entry in entries]
            for child in children:
                sync_tree(child)
            fsync_directory(current)

    sync_tree(target)
    fsync_directory(target.parent)


def rename_noreplace(source: Path, target: Path) -> None:
    if not path_exists(source):
        fail(f"transaction source disappeared: {source}")
    if path_exists(target):
        fail(f"transaction target appeared unexpectedly: {target}")

    libc = ctypes.CDLL(None, use_errno=True)
    renameat2 = getattr(libc, "renameat2", None)
    if renameat2 is None:
        fail("renameat2(RENAME_NOREPLACE) is unavailable on this system")
    renameat2.argtypes = [
        ctypes.c_int,
        ctypes.c_char_p,
        ctypes.c_int,
        ctypes.c_char_p,
        ctypes.c_uint,
    ]
    renameat2.restype = ctypes.c_int
    result = renameat2(
        AT_FDCWD,
        os.fsencode(source),
        AT_FDCWD,
        os.fsencode(target),
        RENAME_NOREPLACE,
    )
    if result != 0:
        error = ctypes.get_errno()
        if error == errno.EEXIST:
            fail(f"transaction target appeared unexpectedly: {target}")
        if error == errno.EXDEV:
            fail(f"transaction paths cross filesystems: {source} -> {target}")
        raise OSError(error, os.strerror(error), str(source), str(target))
    fsync_directory(source.parent)
    if target.parent != source.parent:
        fsync_directory(target.parent)


def identity(path: Path) -> list[int]:
    info = path.lstat()
    return [info.st_dev, info.st_ino, stat.S_IFMT(info.st_mode)]


def fingerprint(path: Path) -> str:
    digest = hashlib.sha256()

    def visit(current: Path, relative: str) -> None:
        info = current.lstat()
        file_type = stat.S_IFMT(info.st_mode)
        digest.update(relative.encode("utf-8", "surrogateescape"))
        digest.update(b"\0")
        digest.update(str(file_type).encode())
        digest.update(b"\0")
        digest.update(str(stat.S_IMODE(info.st_mode)).encode())
        digest.update(b"\0")
        if stat.S_ISLNK(info.st_mode):
            digest.update(os.fsencode(os.readlink(current)))
        elif stat.S_ISREG(info.st_mode):
            with current.open("rb") as stream:
                while chunk := stream.read(1024 * 1024):
                    digest.update(chunk)
        elif stat.S_ISDIR(info.st_mode):
            with os.scandir(current) as entries:
                names = sorted(entry.name for entry in entries)
            for name in names:
                child_relative = f"{relative}/{name}" if relative else name
                visit(current / name, child_relative)
        else:
            fail(f"unsupported transaction target type: {current}")
        digest.update(b"\0")

    visit(path, "")
    return digest.hexdigest()


def sha256_regular_file(path: Path) -> str:
    if not path_exists(path) or not stat.S_ISREG(path.lstat().st_mode):
        fail(f"expected a regular file: {path}")
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def matches(path: Path, expected_identity: object, expected_fingerprint: object) -> bool:
    if not path_exists(path):
        return False
    if not isinstance(expected_identity, list) or len(expected_identity) != 3:
        return False
    if not isinstance(expected_fingerprint, str):
        return False
    return identity(path) == expected_identity and fingerprint(path) == expected_fingerprint


def validate_journal_path(raw: str) -> Path:
    path = absolute_path(raw, "journal")
    if path.name != "transaction.json":
        fail("journal must be named transaction.json")
    if not path.parent.is_dir():
        fail(f"journal directory does not exist: {path.parent}")
    return path


def load_json_file(path: Path, label: str) -> Any:
    try:
        with path.open("r", encoding="utf-8") as stream:
            return json.load(stream)
    except (OSError, json.JSONDecodeError) as error:
        fail(f"could not read {label}: {error}")


def validate_entry(entry: object, index: int, journal: Path, token: str) -> dict[str, Any]:
    if not isinstance(entry, dict):
        fail(f"journal target {index} is not an object")
    operation = entry.get("operation")
    if operation not in {"replace", "remove"}:
        fail(f"journal target {index} has an invalid operation")
    target = absolute_path(entry.get("target"), f"journal target {index}")
    artifact_parent = absolute_path(
        entry.get("artifact_parent"), f"journal artifact parent {index}"
    )
    staged_raw = entry.get("staged")
    source_staged_raw = entry.get("source_staged")
    staged = None
    source_staged = None
    if operation == "replace":
        staged = absolute_path(staged_raw, f"journal staged target {index}")
        source_staged = absolute_path(
            source_staged_raw, f"journal source staging target {index}"
        )
    elif staged_raw is not None or source_staged_raw is not None:
        fail(f"remove target {index} must not have a staging path")
    backup = absolute_path(entry.get("backup"), f"journal backup {index}")
    expected_backup = artifact_parent / f".{target.name}.omawhatsapp-backup-{token}-{index}"
    if backup != expected_backup:
        fail(f"journal backup {index} is not the target's exact adjacent backup")
    if operation == "replace":
        expected_staged = artifact_parent / f".{target.name}.omawhatsapp-stage-{token}-{index}"
        if staged != expected_staged:
            fail(f"journal staging target {index} is not the target's exact adjacent stage")
    state = entry.get("state")
    if state not in {
        "planned",
        "prepare_pending",
        "prepared",
        "backup_pending",
        "backed_up",
        "publish_pending",
        "published",
        "removed",
        "restored",
    }:
        fail(f"journal target {index} has an invalid state")
    expected_sha256 = entry.get("expected_sha256")
    if expected_sha256 is not None \
            and (not isinstance(expected_sha256, str) \
                 or not re.fullmatch(r"[0-9a-f]{64}", expected_sha256)):
        fail(f"journal target {index} has an invalid expected digest")
    return {
        **entry,
        "operation": operation,
        "target": str(target),
        "artifact_parent": str(artifact_parent),
        "staged": str(staged) if staged is not None else None,
        "source_staged": str(source_staged) if source_staged is not None else None,
        "backup": str(backup),
        "expected_sha256": expected_sha256,
    }


def validate_journal(payload: object, journal: Path) -> dict[str, Any]:
    if not isinstance(payload, dict):
        fail("transaction journal is not an object")
    if payload.get("schema") != SCHEMA or payload.get("kind") != KIND:
        fail("transaction journal has an unsupported schema")
    if payload.get("mode") not in {"install", "uninstall"}:
        fail("transaction journal has an invalid mode")
    token = payload.get("token")
    if not isinstance(token, str) or not re.fullmatch(r"[0-9a-f]{32}", token):
        fail("transaction journal has an invalid token")
    phase = payload.get("phase")
    if phase not in {
        "initializing",
        "prepared",
        "applying",
        "targets_applied",
        "units",
        "validated",
        "rolling_back",
        "files_restored",
        "rolled_back",
        "committed",
    }:
        fail("transaction journal has an invalid phase")
    staging_root = absolute_path(payload.get("staging_root"), "journal staging root")
    if staging_root.parent != journal.parent or not staging_root.name.startswith("stage."):
        fail("journal staging root is outside the transaction directory")
    targets_raw = payload.get("targets")
    if not isinstance(targets_raw, list):
        fail("transaction journal targets are invalid")
    targets = [validate_entry(item, index, journal, token) for index, item in enumerate(targets_raw)]
    if len({entry["target"] for entry in targets}) != len(targets):
        fail("transaction journal contains duplicate targets")
    for index, entry in enumerate(targets):
        if entry["source_staged"] is None:
            continue
        try:
            Path(entry["source_staged"]).relative_to(staging_root)
        except ValueError:
            fail(f"journal source staging target {index} is outside its staging root")
    units = payload.get("units")
    if not isinstance(units, list):
        fail("transaction journal units are invalid")
    seen_units: set[str] = set()
    for index, unit in enumerate(units):
        if not isinstance(unit, dict) or not UNIT_RE.fullmatch(str(unit.get("name", ""))):
            fail(f"transaction unit {index} is invalid")
        if not isinstance(unit.get("enabled"), bool) or not isinstance(unit.get("active"), bool):
            fail(f"transaction unit {index} state is invalid")
        if unit["name"] in seen_units:
            fail(f"transaction unit is duplicated: {unit['name']}")
        seen_units.add(unit["name"])
    if not isinstance(payload.get("units_started"), bool):
        fail("transaction unit phase is invalid")
    if not isinstance(payload.get("shell_restart_required"), bool):
        fail("transaction shell lifecycle state is invalid")
    return {**payload, "targets": targets}


def read_journal(path: Path) -> dict[str, Any]:
    try:
        info = path.lstat()
    except FileNotFoundError:
        fail(f"transaction journal does not exist: {path}")
    if not stat.S_ISREG(info.st_mode) or stat.S_ISLNK(info.st_mode):
        fail("transaction journal is not a regular file")
    if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) & 0o077:
        fail("transaction journal ownership or permissions are unsafe")
    return validate_journal(load_json_file(path, "transaction journal"), path)


def save_journal(path: Path, payload: dict[str, Any]) -> None:
    atomic_write_json(path, validate_journal(payload, path))


def maybe_kill(point: str) -> None:
    if os.environ.get("OMAW_INSTALL_TEST_KILL_AT") == point:
        os.kill(os.getpid(), signal.SIGKILL)


def command_begin(args: argparse.Namespace) -> None:
    journal = validate_journal_path(args.journal)
    if path_exists(journal):
        fail(f"an unfinished transaction already exists: {journal}")
    plan = load_json_file(absolute_path(args.plan, "transaction plan"), "transaction plan")
    if not isinstance(plan, dict):
        fail("transaction plan is not an object")
    mode = plan.get("mode")
    if mode not in {"install", "uninstall"}:
        fail("transaction plan has an invalid mode")
    staging_root = absolute_path(plan.get("staging_root"), "transaction staging root")
    if staging_root.parent != journal.parent or not staging_root.name.startswith("stage."):
        fail("transaction staging root must be a stage.* child of the journal directory")
    if not staging_root.is_dir():
        fail(f"transaction staging root does not exist: {staging_root}")

    raw_targets = plan.get("targets")
    if not isinstance(raw_targets, list) or not raw_targets:
        fail("transaction plan must contain at least one target")
    token = uuid.uuid4().hex
    targets: list[dict[str, Any]] = []
    seen_targets: set[str] = set()
    for index, raw in enumerate(raw_targets):
        if not isinstance(raw, dict):
            fail(f"transaction target {index} is not an object")
        operation = raw.get("operation")
        if operation not in {"replace", "remove"}:
            fail(f"transaction target {index} has an invalid operation")
        target = absolute_path(raw.get("target"), f"transaction target {index}")
        if str(target) in seen_targets:
            fail(f"transaction target is duplicated: {target}")
        seen_targets.add(str(target))
        artifact_parent = absolute_path(
            raw.get("artifact_parent", str(target.parent)),
            f"transaction artifact parent {index}",
        )
        if not artifact_parent.is_dir():
            fail(f"transaction artifact parent does not exist: {artifact_parent}")
        try:
            artifact_parent.relative_to(target)
        except ValueError:
            pass
        else:
            fail(f"transaction artifacts must not be placed inside their target: {target}")
        if target.parent.is_dir() \
                and target.parent.stat().st_dev != artifact_parent.stat().st_dev:
            fail(f"transaction artifact directory crosses filesystems for target: {target}")
        expected_sha256 = raw.get("expected_sha256")
        if expected_sha256 is not None \
                and (not isinstance(expected_sha256, str) \
                     or not re.fullmatch(r"[0-9a-f]{64}", expected_sha256)):
            fail(f"transaction target {index} has an invalid expected digest")
        source_staged: Path | None = None
        prepared_staged: Path | None = None
        if operation == "replace":
            source_staged = absolute_path(
                raw.get("staged"), f"transaction staged target {index}"
            )
            try:
                source_staged.relative_to(staging_root)
            except ValueError:
                fail(f"transaction staged target {index} is outside its staging root")
            if not path_exists(source_staged):
                fail(f"transaction staged target does not exist: {source_staged}")
            if not target.parent.is_dir():
                fail(f"transaction target parent does not exist: {target.parent}")
            prepared_staged = artifact_parent / (
                f".{target.name}.omawhatsapp-stage-{token}-{index}"
            )
        elif raw.get("staged") is not None:
            fail(f"remove target {index} must not have a staged path")
        backup = artifact_parent / f".{target.name}.omawhatsapp-backup-{token}-{index}"
        if path_exists(backup) or (prepared_staged is not None and path_exists(prepared_staged)):
            fail(f"transaction artifact already exists beside target: {target}")
        targets.append(
            {
                "operation": operation,
                "target": str(target),
                "artifact_parent": str(artifact_parent),
                "staged": str(prepared_staged) if prepared_staged is not None else None,
                "source_staged": str(source_staged) if source_staged is not None else None,
                "backup": str(backup),
                "state": "planned",
                "had_target": None,
                "original_identity": None,
                "original_fingerprint": None,
                "published_identity": None,
                "published_fingerprint": None,
                "expected_sha256": expected_sha256,
            }
        )

    raw_units = plan.get("units", [])
    if not isinstance(raw_units, list):
        fail("transaction plan units are invalid")
    units: list[dict[str, Any]] = []
    seen_units: set[str] = set()
    for index, raw in enumerate(raw_units):
        if not isinstance(raw, dict):
            fail(f"transaction unit {index} is not an object")
        name = raw.get("name")
        if not isinstance(name, str) or not UNIT_RE.fullmatch(name):
            fail(f"transaction unit {index} has an invalid name")
        if name in seen_units:
            fail(f"transaction unit is duplicated: {name}")
        seen_units.add(name)
        enabled = raw.get("enabled")
        active = raw.get("active")
        if not isinstance(enabled, bool) or not isinstance(active, bool):
            fail(f"transaction unit {index} has an invalid state")
        units.append({"name": name, "enabled": enabled, "active": active})

    payload = {
        "schema": SCHEMA,
        "kind": KIND,
        "token": token,
        "mode": mode,
        "phase": "initializing",
        "staging_root": str(staging_root),
        "targets": targets,
        "units": units,
        "units_started": False,
        "shell_restart_required": False,
    }
    save_journal(journal, payload)
    maybe_kill("after-initial-journal")
    maybe_kill("after-begin")


def command_prepare(args: argparse.Namespace) -> None:
    journal = validate_journal_path(args.journal)
    payload = read_journal(journal)
    if payload["phase"] != "initializing":
        fail(f"transaction cannot be prepared from phase {payload['phase']}")
    for index, entry in enumerate(payload["targets"]):
        if entry["operation"] == "remove":
            entry["state"] = "prepared"
            save_journal(journal, payload)
            continue
        source_staged = Path(entry["source_staged"])
        prepared_staged = Path(entry["staged"])
        source_fingerprint = fingerprint(source_staged)
        entry["state"] = "prepare_pending"
        save_journal(journal, payload)
        maybe_kill(f"after-prepare-intent:{index}")
        copy_durable(source_staged, prepared_staged)
        maybe_kill(f"after-prepare-copy:{index}")
        if fingerprint(prepared_staged) != source_fingerprint:
            fail(f"adjacent staged copy failed verification: {prepared_staged}")
        entry["published_identity"] = identity(prepared_staged)
        entry["published_fingerprint"] = source_fingerprint
        entry["state"] = "prepared"
        save_journal(journal, payload)
    payload["phase"] = "prepared"
    save_journal(journal, payload)
    maybe_kill("after-prepare")


def command_mark_shell_stop(args: argparse.Namespace) -> None:
    journal = validate_journal_path(args.journal)
    payload = read_journal(journal)
    if payload["phase"] != "initializing":
        fail(f"shell stop cannot be journaled from phase {payload['phase']}")
    payload["shell_restart_required"] = True
    save_journal(journal, payload)
    maybe_kill("after-mark-shell-stop")


def command_apply(args: argparse.Namespace) -> None:
    journal = validate_journal_path(args.journal)
    payload = read_journal(journal)
    if payload["phase"] != "prepared":
        fail(f"transaction cannot be applied from phase {payload['phase']}")
    payload["phase"] = "applying"
    save_journal(journal, payload)

    for index, entry in enumerate(payload["targets"]):
        if entry["state"] != "prepared":
            fail(f"transaction target {index} was not completely staged")
        target = Path(entry["target"])
        backup = Path(entry["backup"])
        staged = Path(entry["staged"]) if entry["staged"] is not None else None
        had_target = path_exists(target)
        if entry["expected_sha256"] is not None:
            if not had_target \
                    or sha256_regular_file(target) != entry["expected_sha256"]:
                fail(f"merge source changed before publication: {target}")
        entry["had_target"] = had_target
        if had_target:
            entry["original_identity"] = identity(target)
            entry["original_fingerprint"] = fingerprint(target)
        entry["state"] = "backup_pending"
        save_journal(journal, payload)
        maybe_kill(f"after-backup-intent:{index}")

        if had_target:
            rename_noreplace(target, backup)
        maybe_kill(f"after-backup:{index}")
        if had_target:
            if not matches(
                backup, entry["original_identity"], entry["original_fingerprint"]
            ):
                fail(f"original target changed during publication: {target}")
            if entry["expected_sha256"] is not None \
                    and sha256_regular_file(backup) != entry["expected_sha256"]:
                fail(f"merge source changed during publication: {target}")
        entry["state"] = "backed_up"
        save_journal(journal, payload)

        if entry["operation"] == "replace":
            assert staged is not None
            if not matches(staged, entry["published_identity"], entry["published_fingerprint"]):
                fail(f"staged target changed during transaction: {staged}")
            entry["state"] = "publish_pending"
            save_journal(journal, payload)
            maybe_kill(f"after-publish-intent:{index}")
            rename_noreplace(staged, target)
            maybe_kill(f"after-publish:{index}")
            if not matches(target, entry["published_identity"], entry["published_fingerprint"]):
                fail(f"published target failed verification: {target}")
            entry["state"] = "published"
        else:
            entry["state"] = "removed"
        save_journal(journal, payload)

    payload["phase"] = "targets_applied"
    save_journal(journal, payload)
    maybe_kill("after-apply")


def command_mark_units(args: argparse.Namespace) -> None:
    journal = validate_journal_path(args.journal)
    payload = read_journal(journal)
    if payload["phase"] != "targets_applied":
        fail(f"unit mutations cannot start from phase {payload['phase']}")
    payload["units_started"] = True
    payload["phase"] = "units"
    save_journal(journal, payload)
    maybe_kill("after-mark-units")


def command_mark_validated(args: argparse.Namespace) -> None:
    journal = validate_journal_path(args.journal)
    payload = read_journal(journal)
    if payload["phase"] not in {"targets_applied", "units"}:
        fail(f"transaction cannot be validated from phase {payload['phase']}")
    payload["phase"] = "validated"
    save_journal(journal, payload)


def cleanup_transaction_paths(journal: Path, payload: dict[str, Any]) -> None:
    for entry in payload["targets"]:
        backup = Path(entry["backup"])
        if path_exists(backup):
            if payload["phase"] != "committed":
                fail(f"rollback left an original backup in place: {backup}")
            remove_exact(backup)
        if entry["staged"] is not None:
            remove_exact(Path(entry["staged"]))
    remove_exact(Path(payload["staging_root"]))


def command_commit(args: argparse.Namespace) -> None:
    journal = validate_journal_path(args.journal)
    payload = read_journal(journal)
    if payload["phase"] not in {"targets_applied", "units", "validated", "committed"}:
        fail(f"transaction cannot commit from phase {payload['phase']}")
    if payload["phase"] != "committed":
        for entry in payload["targets"]:
            backup = Path(entry["backup"])
            if entry["had_target"]:
                if not matches(
                    backup, entry["original_identity"], entry["original_fingerprint"]
                ):
                    fail(f"original backup changed before commit: {backup}")
            elif path_exists(backup):
                fail(f"unexpected backup appeared before commit: {backup}")
        payload["phase"] = "committed"
        save_journal(journal, payload)
        maybe_kill("after-commit")
    cleanup_transaction_paths(journal, payload)
    unlink_durable(journal)


def restore_entry(entry: dict[str, Any]) -> None:
    target = Path(entry["target"])
    backup = Path(entry["backup"])
    had_target = entry["had_target"]
    if had_target is None:
        if path_exists(backup):
            fail(f"unplanned backup exists during recovery: {backup}")
        return

    target_exists = path_exists(target)
    backup_exists = path_exists(backup)
    if had_target:
        if backup_exists:
            if not target_exists and entry["state"] in {
                "backup_pending",
                "backed_up",
                "publish_pending",
            }:
                # Publication never completed. Whatever inode our no-replace
                # rename captured is the newest original-path value, including
                # a writer that won the narrow check-to-rename race.
                rename_noreplace(backup, target)
                return
            if identity(backup) != entry["original_identity"]:
                fail(f"original backup was replaced; refusing recovery: {backup}")
            if target_exists:
                if not matches(target, entry["published_identity"], entry["published_fingerprint"]):
                    fail(f"live target changed; refusing to clobber it: {target}")
                remove_exact(target)
            rename_noreplace(backup, target)
            return
        if target_exists and matches(
            target, entry["original_identity"], entry["original_fingerprint"]
        ):
            return
        fail(f"original backup is missing; recovery stopped: {backup}")

    if backup_exists:
        fail(f"unexpected backup exists for an originally absent target: {backup}")
    if not target_exists:
        return
    if entry["operation"] == "replace" and matches(
        target, entry["published_identity"], entry["published_fingerprint"]
    ):
        remove_exact(target)
        return
    fail(f"an unrecognized target appeared; refusing to clobber it: {target}")


def command_rollback_files(args: argparse.Namespace) -> None:
    journal = validate_journal_path(args.journal)
    payload = read_journal(journal)
    if payload["phase"] == "committed":
        fail("a committed transaction must be finalized, not rolled back")
    if payload["phase"] in {"files_restored", "rolled_back"}:
        return
    payload["phase"] = "rolling_back"
    save_journal(journal, payload)
    for index in range(len(payload["targets"]) - 1, -1, -1):
        entry = payload["targets"][index]
        if entry["state"] != "restored":
            restore_entry(entry)
            entry["state"] = "restored"
            save_journal(journal, payload)
    payload["phase"] = "files_restored"
    save_journal(journal, payload)
    maybe_kill("after-files-restored")


def command_finish_rollback(args: argparse.Namespace) -> None:
    journal = validate_journal_path(args.journal)
    payload = read_journal(journal)
    if payload["phase"] not in {"files_restored", "rolled_back"}:
        fail(f"rollback cannot finish from phase {payload['phase']}")
    if payload["phase"] != "rolled_back":
        payload["phase"] = "rolled_back"
        save_journal(journal, payload)
        maybe_kill("after-rollback")
    cleanup_transaction_paths(journal, payload)
    unlink_durable(journal)


def command_metadata(args: argparse.Namespace) -> None:
    journal = validate_journal_path(args.journal)
    payload = read_journal(journal)
    json.dump(
        {
            "mode": payload["mode"],
            "phase": payload["phase"],
            "units_started": payload["units_started"],
            "units": payload["units"],
            "shell_restart_required": payload["shell_restart_required"],
        },
        sys.stdout,
        sort_keys=True,
        separators=(",", ":"),
    )
    sys.stdout.write("\n")


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    commands = result.add_subparsers(dest="command", required=True)
    begin = commands.add_parser("begin")
    begin.add_argument("--journal", required=True)
    begin.add_argument("--plan", required=True)
    begin.set_defaults(function=command_begin)
    for name, function in (
        ("mark-shell-stop", command_mark_shell_stop),
        ("prepare", command_prepare),
        ("apply", command_apply),
        ("mark-units", command_mark_units),
        ("mark-validated", command_mark_validated),
        ("commit", command_commit),
        ("rollback-files", command_rollback_files),
        ("finish-rollback", command_finish_rollback),
        ("metadata", command_metadata),
    ):
        command = commands.add_parser(name)
        command.add_argument("--journal", required=True)
        command.set_defaults(function=function)
    return result


def main() -> int:
    args = parser().parse_args()
    try:
        args.function(args)
    except (OSError, TransactionError) as error:
        print(f"install-transaction: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
