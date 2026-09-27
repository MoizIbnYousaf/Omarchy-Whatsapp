#!/usr/bin/python3
"""Local, bounded bridge between WhatsApp for Omarchy and wacli."""

from __future__ import annotations

import argparse
from contextlib import closing, contextmanager
import fcntl
import hashlib
import json
import mimetypes
import os
from pathlib import Path
import re
import selectors
import secrets
import shutil
import sqlite3
import stat
import subprocess
import sys
import time
from typing import Any, Iterator, Sequence
from urllib.parse import parse_qsl, quote, unquote, urlparse

# Delivery states of a sent message, indexed by the code wacli builds with
# receipts store (the WhatsApp WebMessageInfo status order).
DELIVERY_STATES = ("error", "pending", "sent", "delivered", "read", "played")

MODULE_DIRECTORY = str(Path(__file__).resolve().parent)
if MODULE_DIRECTORY not in sys.path:
    sys.path.insert(0, MODULE_DIRECTORY)
try:
    from omawhatsapp_assets import AvatarCache, AvatarCacheError, fetch_https_image
except ModuleNotFoundError as exc:
    if exc.name != "omawhatsapp_assets":
        raise
    AvatarCache = None
    fetch_https_image = None

    class AvatarCacheError(RuntimeError):
        pass


HOME = Path.home()


def absolute_environment_path(name: str, fallback: Path) -> Path:
    """Use an environment path only when it is absolute.

    The XDG base-directory specification says relative values are invalid and
    must be ignored. Applying the rule centrally also prevents malformed launch
    environments from writing WhatsApp for Omarchy state into a public checkout.
    """
    raw = os.environ.get(name, "").strip()
    candidate = Path(raw).expanduser() if raw else fallback
    return candidate if candidate.is_absolute() else fallback


STATE_HOME = absolute_environment_path("XDG_STATE_HOME", HOME / ".local/state")
STATE_DIR = STATE_HOME / "omawhatsapp"
STORE_DIR = absolute_environment_path("WACLI_STORE_DIR", STATE_HOME / "wacli")
# The checkout this helper runs from. `omarchy plugin add` clones the whole
# repository into the plugins folder, so the helper, the QML, the unit
# templates and the agent skill always come from the same commit.
PLUGIN_ROOT = Path(__file__).resolve().parent.parent
LOCAL_BIN = HOME / ".local" / "bin"
# wacli is looked up in fixed places, never on PATH: ~/.local/bin first (a build
# the user placed there, such as one with extra features), then a system
# package (AUR wacli-bin installs /usr/bin/wacli).
WACLI_CANDIDATES = (LOCAL_BIN / "wacli", Path("/usr/local/bin/wacli"), Path("/usr/bin/wacli"))


def locate_wacli() -> Path:
    raw = os.environ.get("WACLI_BIN", "").strip()
    if raw:
        chosen = Path(raw).expanduser()
        if chosen.is_absolute():
            return chosen
    for candidate in WACLI_CANDIDATES:
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return candidate
    return WACLI_CANDIDATES[0]


WACLI = locate_wacli()


def version_tuple(text: str) -> tuple[int, ...]:
    return tuple(int(part) for part in re.findall(r"[0-9]+", text)[:3])
# wacli keeps the account config in the XDG state directory even when
# --store or WACLI_STORE_DIR points somewhere else.
ACCOUNT_CONFIG = STATE_HOME / "wacli" / "config.yaml"
SYSTEMCTL = Path("/usr/bin/systemctl")
PLUGIN_ID = "io.github.atoslins.whatsapp"
PLUGINS_DIR = absolute_environment_path(
    "XDG_CONFIG_HOME", HOME / ".config") / "omarchy" / "plugins"
PLUGIN_DIR = PLUGINS_DIR / PLUGIN_ID
SHELL_CONFIG = absolute_environment_path(
    "XDG_CONFIG_HOME", HOME / ".config") / "omarchy" / "shell.json"
# What the first run sets up, with the user's consent: the background sync
# units, the `omawhatsapp` command, and the agent skill with the MCP server.
SETUP_UNITS = ("wacli-sync.service", "wacli-sync@.service")
UNIT_WACLI = "%h/.local/bin/wacli"
UNIT_MARKERS = ("WhatsApp for Omarchy", "OmaWhatsApp")
SKILL_LINK = HOME / ".agents" / "skills" / "omawhatsapp"
# Copies the old installer left beside the helper in ~/.local/bin.
LEGACY_HELPER_COPIES = ("omawhatsapp_core.py", "omawhatsapp_assets.py")
# The original OmaWhatsApp shares the helper name, the units and the state, so
# only one of the two can run.
ORIGINAL_PLUGIN_ID = "io.github.moizibnyousaf.omawhatsapp"
OMARCHY = Path("/usr/bin/omarchy")
GIT = Path("/usr/bin/git")
ZENITY = Path("/usr/bin/zenity")
MAX_ABOUT_FILES = 200_000
USER_UNIT_DIR = absolute_environment_path(
    "XDG_CONFIG_HOME", HOME / ".config") / "systemd" / "user"
# The sync units pass --download-media through $OMAW_MEDIA_FLAGS. A drop-in
# that empties it turns automatic media download off for every account; the
# drop-in's presence is the setting, so it cannot drift from what runs.
MEDIA_UNITS = ("wacli-sync.service", "wacli-sync@.service")
MEDIA_DROPIN = "10-omawhatsapp-media.conf"
MEDIA_DROPIN_OFF = (
    "# Written by WhatsApp for Omarchy: received media is downloaded only on request.\n"
    "[Service]\nEnvironment=OMAW_MEDIA_FLAGS=\n"
)
# Every file the app writes outside its plugin folder (the sync units and the
# media drop-in) starts with this line, holding the sha256 of the rest. The
# app replaces or removes such a file only while that checksum still matches,
# so a file someone edited, or wrote, is left as it is.
WRITTEN_STAMP = re.compile(
    rb"# Written by WhatsApp for Omarchy \(sha256 ([0-9a-f]{64}) of the lines below\)\.[^\n]*\n")
MAX_WRITTEN_FILE = 64 * 1024
# The exact texts that versions before the stamp wrote at those paths, the
# original OmaWhatsApp's included; unchanged, they are the app's own too.
EARLIER_WRITTEN_SHA256 = frozenset({
    "2eeedb0520b5028e524a9ef9c5544667a20e4d0a9de02f0529915e12e4e24fc2",  # wacli-sync.service
    "2fe91f485643e9647a51b221d64f6b9446c9797648b0b57f767a6f69d0c5d144",
    "b46ddc584cbd50b6a881d21d902b29f0aa4a34e7ae027d009a8ef85cc00531ea",
    "cc37bde81c110e40aa57325d1a7a5754c75ebe62a990185365ef147dddb0c9bb",
    "dc6f6c09d2b69aaba800b3695806375f840de7d28ef0b1cb704c1fec9cb75278",
    "a074a2d36287a39f57cceedfddc92d11fb803681294bc5f922a4b0f1dd743be0",  # 0.16, /usr/local/bin/wacli
    "2b4827dc04774b0f2a6b31c56710a87beca293300cab20c86702d3217d50fd0f",  # 0.16, /usr/bin/wacli
    "26453a707470e7b67a4532d88051641762a5afb11fde012192daa30d249ef537",  # wacli-sync@.service
    "6c92d7997e99a832b50a419ea5fcb92690cef1327f9398363b5a7c8f66fbeb5f",
    "974006e3f7f15ed0de47fc0a3c32e386c4b0fd58ed54f7c53e67915f0bc8a4e6",
    "e077e74b384fa729229ecaf779d254b2bcce23e4769c2bd380526fd5a4d93ad8",
    "d747a639a0b16f42a287df0ce55501fba40894e39e48f8e446fc4308151fb660",  # 0.16, /usr/local/bin/wacli
    "a8bfdc333df6b88577b15f9c4d232be8cd954dde1a9471518848663d7fa3bc87",  # 0.16, /usr/bin/wacli
    "ab14985bb533a59151e513958bc9dca2686b4815694d0de053db332423e955a5",  # media drop-in, OmaWhatsApp
    "3e108b9e74b49994c15f355af938ad98c1d7e102b9a5c2701861caca308743f3",  # media drop-in, 0.16
})


def stamped(body: str) -> str:
    """A file the app writes, led by the line that lets it recognize the file later."""
    digest = hashlib.sha256(body.encode("utf-8")).hexdigest()
    return (f"# Written by WhatsApp for Omarchy (sha256 {digest} of the lines below). "
            "Once edited, the app leaves it as it is.\n" + body)


def written_unchanged(data: bytes) -> bool:
    """Whether a file is exactly what this app, or the original OmaWhatsApp, wrote."""
    match = WRITTEN_STAMP.match(data)
    if match:
        return hashlib.sha256(data[match.end():]).hexdigest() == match.group(1).decode("ascii")
    return hashlib.sha256(data).hexdigest() in EARLIER_WRITTEN_SHA256
WL_PASTE = Path("/usr/bin/wl-paste")
XDG_OPEN = Path("/usr/bin/xdg-open")
NOTIFY_SEND = Path("/usr/bin/notify-send")
NOTIFY_APP_ICON = "whatsapp"
NOTIFY_SOUND = Path("/usr/share/sounds/freedesktop/stereo/message-new-instant.oga")
SOUND_PLAYER = Path("/usr/bin/pw-play")
# Omarchy's notification service keeps its do-not-disturb flag here.
OMARCHY_NOTIFICATION_STATE = STATE_HOME / "omarchy" / "notifications.json"
# What a notification says for media when there is no caption.
NOTIFY_MEDIA_LABELS = {
    "image": "📷 Photo", "video": "🎥 Video", "gif": "GIF", "sticker": "Sticker",
    "document": "📄 Document", "audio": "🎵 Audio", "location": "📍 Location",
    "contact": "👤 Contact", "poll": "📊 Poll", "album": "📷 Photos",
}
OMARCHY_SHELL = Path("/usr/share/omarchy/bin/omarchy-shell")
MAX_MESSAGE = 4096
# A new chat only goes to a user JID the mirror already knows or that WhatsApp
# confirmed moments ago; a typo never becomes a recipient. WhatsApp now answers
# a number check with the person's @lid, which wacli can send to directly.
NEW_CHAT_JID = re.compile(r"^[0-9]{5,20}@(?:s\.whatsapp\.net|lid)$")
NEW_CHAT_CHECK_TTL = 15 * 60
NEW_CHAT_CHECKS_FILE = "new-chat-checks.json"
MAX_NEW_CHAT_CHECKS = 32
MAX_NEW_CHAT_STATE = 16 * 1024
MAX_FILE = 100 * 1024 * 1024
MAX_ATTACHMENTS = 10
MAX_SENT_MEDIA_HINTS = 2000
MAX_SENT_REPLY_HINTS = 2000
MAX_WACLI_OUTPUT = 1024 * 1024
MAX_PROCESS_ERROR = 64 * 1024
MAX_CLIPBOARD_TYPES = 64 * 1024
MAX_CLIPBOARD_TEXT = MAX_MESSAGE * 4
MAX_PREFERENCES = 1024 * 1024
MAX_SENT_MEDIA_STATE = 2 * 1024 * 1024
MAX_SENT_REPLY_STATE = 2 * 1024 * 1024
# 3: opening a chat marks it read by default (the owner's decision; wacli's
# mark-read syncs the user's own devices and sends no read receipt).
PREFERENCES_VERSION = 4
MAX_NOTIFY_BURST = 5
MAX_NOTIFY_SUMMARY = 96
MAX_NOTIFY_SENDER = 48
# A name to sign messages with, per account: one line, no formatting marks.
MAX_SIGNATURE_NAME = 40
SIGNATURE_POSITIONS = ("top", "bottom")
MAX_NOTIFY_BODY = 180
MAX_NOTIFY_WATERMARKS = 500
NOTIFY_EXPIRE_MS = 8000
# The popup id of each chat's last notification, so the next message in that
# chat updates it instead of stacking another one.
# wacli files a delegated file send under the @lid WhatsApp answers with,
# away from the contact's phone-number chat, until its next sync start
# migrates it. The helper folds those rows back in, resolving each @lid once
# through `wacli --read-only contacts show` (it never reads session.db).
LID_ALIASES_FILE = "lid-aliases.json"
MAX_LID_ALIASES = 256
MAX_LID_ALIASES_STATE = 64 * 1024
# The sticker picker: recent distinct stickers, and how many missing files one
# open may fetch (media download --read-only runs beside the live sync).
MAX_STICKER_CHOICES = 60
MAX_STICKER_FETCH = 24
STICKER_FETCH_SECONDS = 25.0
# Stickers WhatsApp answered 403/404/410 for: expired on the server, not retried.
STICKERS_GONE_FILE = "stickers-gone.json"
# Attachments WhatsApp's server answered 403/404/410 for: expired there, so
# they are shown as no longer available instead of offered for download.
MEDIA_GONE_FILE = "media-gone.json"
MAX_MEDIA_GONE = 5000
MAX_STICKERS_GONE = 512
DOCTOR_CACHE_FILE = "doctor-cache.json"
DOCTOR_CACHE_TTL = 60
MAX_DOCTOR_CACHE = 16 * 1024
NOTIFY_IDS_FILE = "notify-ids.json"
MAX_NOTIFY_IDS = 64
NOTIFY_ID_TTL = 60 * 60
MAX_NOTIFY_IDS_STATE = 16 * 1024
SYNC_UNIT = "wacli-sync.service"
SYNC_UNIT_TEMPLATE = "wacli-sync@{name}.service"
SYNC_UNIT_NAME = re.compile(
    r"wacli-sync(?:@[A-Za-z0-9][A-Za-z0-9._-]{0,63})?\.service\Z"
)
LIFECYCLE_LOCK_NAME = re.compile(r"lifecycle-[0-9a-f]{24}\.lock\Z")
MAX_ACCOUNTS = 16
MAX_LIFECYCLE_RECOVERY = 4096
# Sentinel: run against whichever account this request selected.
ACTIVE_ACCOUNT: Any = object()
ACCOUNT_NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}")
LEGACY_ACCOUNT_NAME = "primary"
# Chats checked per explicit refresh. Each refresh yields the sync unit
# while it runs, so a larger batch means fewer restarts for the same work.
AVATAR_REFRESH_LIMIT = 64
# Each photo lookup is its own wacli connection holding the store lock, so a
# batch stops starting lookups after this long; the rest stay due.
AVATAR_BATCH_SECONDS = 20.0
AVATAR_REFRESH_TTL = 7 * 24 * 60 * 60
AVATAR_MISSING_TTL = 24 * 60 * 60
AVATAR_FAILURE_BACKOFF = 60 * 60
VOICE_DRAFT_DIRECTORY = "voice-drafts"
VOICE_DRAFT_PATTERN = re.compile(r"voice-[0-9a-f]{32}\.ogg\Z")
CLIPBOARD_STAGE_DIRECTORY = "omawhatsapp"
CLIPBOARD_STAGE_PATTERN = re.compile(
    r"paste-[0-9a-f]{32}\.(?:png|jpg|webp|gif|bmp)\Z"
)
CLIPBOARD_SENT_PATTERN = re.compile(
    r"sent-[0-9a-f]{32}\.(?:png|jpg|webp|gif|bmp)\Z"
)
MAX_CLIPBOARD_SENT_FILES = 64
MAX_CLIPBOARD_SENT_BYTES = 256 * 1024 * 1024
# Rows wacli stores with synthetic text instead of content: "(message)" for
# payloads it could not decode (protocol and placeholder messages) and the
# "[Album: N images]" header that precedes an album's real media messages.
# They are never shown as bubbles or used as a chat preview.
CONTACT_LINE = re.compile(r"^Contact: (.+?)(?: \((\+?[0-9][0-9 ()\-.]{4,30})\))?$")


def contact_cards(text: str) -> list[dict[str, str]]:
    """The people in a shared contact, from wacli's text for it.

    wacli stores one card as "Contact: Name (+55 16 99999-9999)" and several
    as "Contacts:" followed by one such line each. Anything else is text.
    """
    lines = [line.strip() for line in str(text or "").strip().split("\n")]
    several = bool(lines) and lines[0] == "Contacts:"
    if several:
        lines = lines[1:]
    cards: list[dict[str, str]] = []
    for line in lines:
        match = CONTACT_LINE.match(line)
        if not match or not line:
            return []
        cards.append({"name": match.group(1).strip()[:128],
                      "phone": (match.group(2) or "").strip()[:40]})
    # A lone card always carries its number; words someone typed after
    # "Contact:" do not.
    if not several and (len(cards) != 1 or not cards[0]["phone"]):
        return []
    return cards[:20]


def contact_preview(text: str) -> str:
    cards = contact_cards(text)
    if not cards:
        return text
    return "👤 " + (cards[0]["name"] if len(cards) == 1 else f"{len(cards)} contacts")


def revoked_sql(table: str) -> str:
    """A message deleted for everyone: the phone keeps a placeholder for it."""
    return f"(COALESCE({table}.revoked, 0) = 1 AND COALESCE({table}.deleted_for_me, 0) = 0)"


def poll_vote_sql(table: str) -> str:
    """The row wacli stores for a vote cast from this computer.

    Only ``wacli poll vote`` writes "Voted: …" rows; other people's votes go
    straight to poll_votes. The phone shows a vote only inside its poll.
    """
    return f"""({table}.from_me = 1 AND COALESCE({table}.media_type, '') = ''
      AND {table}.text GLOB 'Voted: *'
      AND EXISTS (SELECT 1 FROM polls WHERE polls.chat_jid = {table}.chat_jid))"""


def synthetic_message_sql(table: str) -> str:
    return f"""(COALESCE({table}.media_type, '') = ''
      AND COALESCE({table}.media_caption, '') = ''
      AND COALESCE({table}.filename, '') = ''
      AND ((COALESCE({table}.text, '') = ''
            AND COALESCE({table}.display_text, '') IN ('', '(message)'))
        OR {table}.text = '[Album]'
        OR {table}.text GLOB '[[]Album: [0-9]*]'))"""


# wacli writes "[Audio]" into the text of every audio message without a
# caption; the voice bubble already says what it is.
SYNTHETIC_AUDIO_TEXT = "[Audio]"

# Global interface preferences added by the fork. Each entry is
# (allowed values, default); a bool entry accepts True or False. Older keys
# keep their own validation and error messages below.
UI_PREFERENCES: dict[str, tuple[Any, Any]] = {
    "read_on_reply": (bool, True),
    # Online while the window has focus: WhatsApp only sends others' online
    # state and typing to a device that shows itself online.
    "show_online": (bool, True),
    # Clicking a message popup opens a small reply view by the bar; off, it
    # opens the full app on that chat.
    "notify_reply": (bool, True),
    "enter_sends": (bool, True),
    "show_avatars": (bool, True),
    # Off by default: every photo batch pauses sync, and whatever arrives in
    # that window is acknowledged by the short wacli connection and lost.
    "auto_refresh_avatars": (bool, False),
    "rail_density": (("comfortable", "compact"), "comfortable"),
    # Chat list width in pixels, set by dragging its edge; 0 means automatic.
    "rail_width": (("int", 0, 640), 0),
}


def _int_range(allowed: Any) -> tuple[int, int] | None:
    if isinstance(allowed, tuple) and len(allowed) == 3 and allowed[0] == "int":
        return int(allowed[1]), int(allowed[2])
    return None


def ui_preference(value: dict[str, Any], name: str) -> Any:
    allowed, default = UI_PREFERENCES[name]
    raw = value.get(name, default)
    if allowed is bool:
        return raw if isinstance(raw, bool) else default
    bounds = _int_range(allowed)
    if bounds is not None:
        valid = isinstance(raw, int) and not isinstance(raw, bool) \
            and bounds[0] <= raw <= bounds[1]
        return raw if valid else default
    return raw if isinstance(raw, str) and raw in allowed else default


def valid_ui_preference(name: str, setting: Any) -> bool:
    allowed, _ = UI_PREFERENCES[name]
    if allowed is bool:
        return isinstance(setting, bool)
    bounds = _int_range(allowed)
    if bounds is not None:
        return isinstance(setting, int) and not isinstance(setting, bool) \
            and bounds[0] <= setting <= bounds[1]
    return isinstance(setting, str) and setting in allowed


def chat_kind_sql(table: str = "chats") -> str:
    """A chat's kind, repairing the one wacli 0.18.3 and 0.19.0 break.

    wacli files an outgoing poll or poll vote under the person's phone chat
    but takes the kind and the name from the @lid WhatsApp answered with, so
    the chat turns 'unknown' and drops out of the rail. A phone JID is always
    a person.
    """
    # Only a chat with messages: wacli also leaves bare 'unknown' rows behind
    # when it marks a chat read, and those are not conversations.
    return (f"(CASE WHEN {table}.kind = 'unknown' AND {table}.jid GLOB '*@s.whatsapp.net' "
            f"AND EXISTS (SELECT 1 FROM messages WHERE messages.chat_jid = {table}.jid) "
            f"THEN 'dm' ELSE {table}.kind END)")


# People, and every group you chat in: a group inside a Community is an
# ordinary chat on the phone. The Community itself is not a chat.
SUPPORTED_CHAT_WHERE = f"""({chat_kind_sql()} = 'dm' OR (
  chats.kind = 'group'
  AND COALESCE(groups.is_parent, 0) = 0
))"""

# Oldest wacli whose CLI contract the helper relies on, and the newest release
# the registry, tests, and CI were verified against. Any version in between
# (or newer) is accepted; leaves unknown to the registry keep failing closed.
# Bumped with manifest.json (scripts/test checks it). The app compares it with
# the plugin it loaded: an update that replaced only the plugin says so.
HELPER_VERSION = "0.16.2"  # x-release-please-version
WACLI_MINIMUM_VERSION = "0.17.1"
WACLI_PARITY_VERSION = "0.19.0"
# Leaves that only exist from a given wacli release. The parity check accepts
# their absence on an older accepted release; there the gateway still
# demands the exact target flags, so wacli itself rejects the call.
WACLI_LEAF_MINIMUM_VERSIONS: dict[tuple[str, ...], str] = {
    ("groups", "participants", "list"): "0.18.0",
}
# Leaves only wacli builds that follow presence have (fork branch
# oma-presence-receipts). Official releases lack them; either is accepted.
WACLI_OPTIONAL_LEAVES = frozenset({
    # Fork-only as well: starring through app state.
    ("messages", "star"),
    ("presence", "available"),
    ("presence", "subscribe"),
    ("presence", "unavailable"),
})
WACLI_GLOBAL_FLAGS = frozenset({
    "--account", "--events", "--full", "--json", "--lock-wait",
    "--read-only", "--store", "--timeout",
})
WACLI_CHAT_TO_OPERATIONS = frozenset({
    ("messages", "forward"),
    ("poll", "show"),
    ("poll", "vote"),
    ("presence", "paused"),
    ("presence", "subscribe"),
    ("presence", "typing"),
    ("send", "file"),
    ("send", "location"),
    ("send", "poll"),
    ("send", "react"),
    ("send", "select"),
    ("send", "sticker"),
    ("send", "text"),
    ("send", "voice"),
})

# Existing-target selectors accepted by wacli 0.19.0. The gateway resolves
# these against the selected account's local mirror so names, phone numbers,
# and --pick can never choose a recipient or destructive target implicitly.
WACLI_REQUIRED_CHAT_FLAGS: dict[tuple[str, ...], tuple[str, ...]] = {
    ("chats", "archive"): ("--chat",),
    ("chats", "mark-read"): ("--chat",),
    ("chats", "mark-unread"): ("--chat",),
    ("chats", "mute"): ("--chat",),
    ("chats", "pin"): ("--chat",),
    ("chats", "show"): ("--jid",),
    ("chats", "unarchive"): ("--chat",),
    ("chats", "unmute"): ("--chat",),
    ("chats", "unpin"): ("--chat",),
    ("history", "backfill"): ("--chat",),
    ("messages", "context"): ("--chat",),
    ("messages", "delete"): ("--chat",),
    ("messages", "edit"): ("--chat",),
    ("messages", "forward"): ("--chat", "--to"),
    ("messages", "purge"): ("--chat",),
    ("messages", "revoke"): ("--chat",),
    ("messages", "show"): ("--chat",),
    ("messages", "star"): ("--chat",),
}
WACLI_OPTIONAL_CHAT_FLAGS: dict[tuple[str, ...], tuple[str, ...]] = {
    ("calls", "list"): ("--chat",),
    ("chats", "cleanup"): ("--jid",),
    ("history", "coverage"): ("--chat",),
    ("history", "fill"): ("--chat",),
    ("media", "backfill"): ("--chat",),
    ("media", "retry"): ("--chat",),
    ("messages", "export"): ("--chat",),
    ("messages", "list"): ("--chat",),
    ("messages", "search"): ("--chat",),
    ("messages", "starred"): ("--chat",),
    ("polls", "list"): ("--chat",),
}
WACLI_GROUP_JID_OPERATIONS = frozenset({
    ("groups", "announce-only"),
    ("groups", "description"),
    ("groups", "info"),
    ("groups", "invite", "link", "get"),
    ("groups", "invite", "link", "revoke"),
    ("groups", "leave"),
    ("groups", "locked"),
    ("groups", "participants", "add"),
    ("groups", "participants", "demote"),
    ("groups", "participants", "list"),
    ("groups", "participants", "promote"),
    ("groups", "participants", "remove"),
    ("groups", "rename"),
    ("groups", "requests", "approve"),
    ("groups", "requests", "list"),
    ("groups", "requests", "reject"),
    ("groups", "topic"),
})
WACLI_CHANNEL_JID_OPERATIONS = frozenset({
    ("channels", "info"),
    ("channels", "leave"),
})
WACLI_CONTACT_JID_OPERATIONS = frozenset({
    ("contacts", "alias", "rm"),
    ("contacts", "alias", "set"),
    ("contacts", "show"),
    ("contacts", "tags", "add"),
    ("contacts", "tags", "rm"),
    ("profile", "business"),
    ("profile", "get-about"),
    ("profile", "picture-info"),
})
WACLI_SENSITIVE_FLAGS = frozenset({"--webhook", "--webhook-secret"})
WACLI_MESSAGE_TARGETS: dict[tuple[str, ...], tuple[str, str]] = {
    ("media", "download"): ("--chat", "--id"),
    ("messages", "context"): ("--chat", "--id"),
    ("messages", "delete"): ("--chat", "--id"),
    ("messages", "edit"): ("--chat", "--id"),
    ("messages", "forward"): ("--chat", "--id"),
    ("messages", "purge"): ("--chat", "--id"),
    ("messages", "revoke"): ("--chat", "--id"),
    ("messages", "show"): ("--chat", "--id"),
    ("messages", "star"): ("--chat", "--id"),
    ("poll", "show"): ("--to", "--id"),
    ("poll", "vote"): ("--to", "--id"),
    ("send", "react"): ("--to", "--id"),
    ("send", "select"): ("--to", "--id"),
}

# Every user-facing leaf in wacli 0.19.0 is classified here (the same 104
# leaves as 0.18.3; 0.19.0 adds only `chats mark-read --receipts`, which stays
# a WhatsApp write). Unknown leaves
# fail closed; a future wacli release can therefore never silently broaden an
# agent's mutation surface. A few flag-dependent operations are narrowed by
# _transport_policy (for example, cleanup --dry-run is a local read).
WACLI_OPERATION_POLICIES: dict[tuple[str, ...], str] = {
    ("accounts", "add"): "interactive",
    ("accounts", "list"): "local-read",
    ("accounts", "remove"): "destructive",
    ("accounts", "show"): "local-read",
    ("accounts", "use"): "local-write",
    ("auth",): "interactive",
    ("auth", "logout"): "destructive",
    ("auth", "status"): "local-read",
    ("calls", "list"): "local-read",
    ("channels", "info"): "remote-read",
    ("channels", "join"): "whatsapp-write",
    ("channels", "leave"): "destructive",
    ("channels", "list"): "remote-read",
    ("chats", "archive"): "whatsapp-write",
    ("chats", "cleanup"): "local-write",
    ("chats", "list"): "local-read",
    ("chats", "mark-read"): "whatsapp-write",
    ("chats", "mark-unread"): "whatsapp-write",
    ("chats", "mute"): "whatsapp-write",
    ("chats", "pin"): "whatsapp-write",
    ("chats", "show"): "local-read",
    ("chats", "unarchive"): "whatsapp-write",
    ("chats", "unmute"): "whatsapp-write",
    ("chats", "unpin"): "whatsapp-write",
    ("completion", "bash"): "local-read",
    ("completion", "fish"): "local-read",
    ("completion", "powershell"): "local-read",
    ("completion", "zsh"): "local-read",
    ("contacts", "alias", "rm"): "local-write",
    ("contacts", "alias", "set"): "local-write",
    ("contacts", "check"): "remote-read",
    ("contacts", "import-system"): "local-write",
    ("contacts", "refresh"): "local-write",
    ("contacts", "search"): "local-read",
    ("contacts", "show"): "local-read",
    ("contacts", "tags", "add"): "local-write",
    ("contacts", "tags", "rm"): "local-write",
    ("docs",): "local-read",
    ("doctor",): "local-read",
    ("groups", "announce-only"): "whatsapp-write",
    ("groups", "create"): "whatsapp-write",
    ("groups", "description"): "whatsapp-write",
    ("groups", "info"): "remote-read",
    ("groups", "invite", "link", "get"): "remote-read",
    ("groups", "invite", "link", "revoke"): "destructive",
    ("groups", "join"): "whatsapp-write",
    ("groups", "leave"): "destructive",
    ("groups", "list"): "local-read",
    ("groups", "locked"): "whatsapp-write",
    ("groups", "participants", "add"): "whatsapp-write",
    ("groups", "participants", "demote"): "destructive",
    ("groups", "participants", "list"): "local-read",
    ("groups", "participants", "promote"): "whatsapp-write",
    ("groups", "participants", "remove"): "destructive",
    ("groups", "prune"): "local-write",
    ("groups", "refresh"): "remote-read",
    ("groups", "rename"): "whatsapp-write",
    ("groups", "requests", "approve"): "whatsapp-write",
    ("groups", "requests", "list"): "remote-read",
    ("groups", "requests", "reject"): "destructive",
    ("groups", "topic"): "whatsapp-write",
    ("help",): "local-read",
    ("history", "backfill"): "sync",
    ("history", "coverage"): "local-read",
    ("history", "fill"): "sync",
    ("media", "backfill"): "sync",
    ("media", "download"): "sync",
    ("media", "retry"): "sync",
    ("messages", "context"): "local-read",
    ("messages", "delete"): "destructive",
    ("messages", "edit"): "whatsapp-write",
    ("messages", "export"): "local-read",
    ("messages", "forward"): "whatsapp-write",
    ("messages", "list"): "local-read",
    ("messages", "purge"): "destructive",
    ("messages", "revoke"): "destructive",
    ("messages", "search"): "local-read",
    ("messages", "show"): "local-read",
    ("messages", "star"): "whatsapp-write",
    ("messages", "starred"): "local-read",
    ("poll", "show"): "local-read",
    ("poll", "vote"): "whatsapp-write",
    ("polls", "list"): "local-read",
    ("presence", "paused"): "whatsapp-write",
    ("presence", "typing"): "whatsapp-write",
    ("presence", "available"): "whatsapp-write",
    ("presence", "unavailable"): "whatsapp-write",
    ("presence", "subscribe"): "remote-read",
    ("profile", "business"): "remote-read",
    ("profile", "get-about"): "remote-read",
    ("profile", "picture-info"): "remote-read",
    ("profile", "remove-picture"): "destructive",
    ("profile", "set-about"): "whatsapp-write",
    ("profile", "set-name"): "whatsapp-write",
    ("profile", "set-picture"): "whatsapp-write",
    ("send", "file"): "whatsapp-write",
    ("send", "location"): "whatsapp-write",
    ("send", "poll"): "whatsapp-write",
    ("send", "react"): "whatsapp-write",
    ("send", "select"): "whatsapp-write",
    ("send", "status"): "whatsapp-write",
    ("send", "sticker"): "whatsapp-write",
    ("send", "text"): "whatsapp-write",
    ("send", "voice"): "whatsapp-write",
    ("store", "cleanup"): "destructive",
    ("store", "stats"): "local-read",
    ("sync",): "sync",
    ("version",): "local-read",
}
class Account:
    """One wacli account: a name, the store it owns, and its sync unit.

    An empty name is the implicit account of a machine that never ran
    `wacli accounts add`. It addresses the root store and keeps the original
    single-instance sync unit, so nothing changes until accounts are named.
    """

    __slots__ = ("name", "store_dir", "default", "managed_unit", "selector")

    def __init__(
        self, name: str, store_dir: Path, default: bool = False,
        managed_unit: bool = True, selector: str = "",
    ) -> None:
        self.name = name
        self.store_dir = store_dir
        self.default = default
        self.managed_unit = managed_unit
        self.selector = selector or ("account" if name else "implicit")
        if self.selector not in {"implicit", "account", "store"}:
            raise ValueError("invalid account selector")

    @property
    def key(self) -> str:
        # State is keyed by store, not by name: a rename keeps the mirror, and
        # registering the legacy session with `store: .` keeps its history.
        return str(self.store_dir)

    @property
    def label(self) -> str:
        return self.name or "default"

    @property
    def unit(self) -> str:
        if not self.managed_unit:
            return ""
        return SYNC_UNIT_TEMPLATE.format(name=self.name) \
            if self.selector == "account" else SYNC_UNIT

    @property
    def cli_args(self) -> list[str]:
        if self.selector == "account":
            return ["--account", self.name]
        if self.selector == "store":
            return ["--store", str(self.store_dir)]
        return []

    def __repr__(self) -> str:  # pragma: no cover - debugging aid
        return f"Account({self.name!r}, {str(self.store_dir)!r})"


class OmaWhatsAppError(RuntimeError):
    pass


class OmaWhatsAppPartialError(OmaWhatsAppError):
    """A multi-step mutation delivered some items and must not be retried whole."""

    def __init__(self, message: str, partial: dict[str, Any]) -> None:
        super().__init__(message)
        self.partial = partial


class ProcessOutputLimitExceeded(RuntimeError):
    pass


def emit(value: dict[str, Any], code: int = 0) -> int:
    print(json.dumps(value, ensure_ascii=False, separators=(",", ":")))
    return code


def clean_error(value: Any, fallback: str) -> str:
    text = " ".join(str(value or "").split())
    return (text or fallback)[:512]


def bounded_int(value: Any, fallback: int, minimum: int, maximum: int) -> int:
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        return fallback
    return max(minimum, min(parsed, maximum))


def muted_until_active(value: Any, now: float | None = None) -> bool:
    """Normalize WhatsApp's forever, seconds, and milliseconds mute values."""
    try:
        muted_until = int(value or 0)
    except (TypeError, ValueError):
        return False
    if muted_until == -1:
        return True
    if muted_until <= 0:
        return False
    current = time.time() if now is None else now
    if muted_until >= 10_000_000_000:
        return muted_until > int(current * 1000)
    return muted_until > int(current)


def request() -> dict[str, Any]:
    raw = sys.stdin.buffer.read(65_537)
    if len(raw) > 65_536:
        raise OmaWhatsAppError("Request is too large.")
    try:
        value = json.loads(raw.decode("utf-8") or "{}")
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise OmaWhatsAppError("Request must be valid JSON.") from exc
    if not isinstance(value, dict):
        raise OmaWhatsAppError("Request must be a JSON object.")
    return value


def run_bounded(
    command: Sequence[str],
    *,
    timeout: float,
    stdout_limit: int,
    stderr_limit: int = MAX_PROCESS_ERROR,
    text: bool = True,
) -> subprocess.CompletedProcess[Any]:
    """Run a child while draining both pipes under hard in-memory byte caps."""
    process = subprocess.Popen(
        list(command),
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        close_fds=True,
    )
    if process.stdout is None or process.stderr is None:
        process.kill()
        process.wait()
        raise OmaWhatsAppError("The helper process could not be started safely.")

    stdout_descriptor = process.stdout.fileno()
    stderr_descriptor = process.stderr.fileno()
    streams = {stdout_descriptor: (process.stdout, stdout_limit, bytearray()),
               stderr_descriptor: (process.stderr, stderr_limit, bytearray())}
    selector = selectors.DefaultSelector()
    deadline = time.monotonic() + timeout
    try:
        for descriptor in streams:
            os.set_blocking(descriptor, False)
            selector.register(descriptor, selectors.EVENT_READ)
        while selector.get_map():
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise subprocess.TimeoutExpired(list(command), timeout)
            events = selector.select(remaining)
            if not events:
                raise subprocess.TimeoutExpired(list(command), timeout)
            for key, _ in events:
                descriptor = int(key.fd)
                stream, limit, output = streams[descriptor]
                try:
                    chunk = os.read(descriptor, min(65_536, limit - len(output) + 1))
                except BlockingIOError:
                    continue
                if not chunk:
                    selector.unregister(descriptor)
                    stream.close()
                    continue
                output.extend(chunk)
                if len(output) > limit:
                    raise ProcessOutputLimitExceeded(
                        f"Child output exceeded its {limit}-byte limit"
                    )
        returncode = process.wait(timeout=max(0.01, deadline - time.monotonic()))
    except (ProcessOutputLimitExceeded, subprocess.TimeoutExpired):
        process.kill()
        process.wait()
        raise
    finally:
        selector.close()
        for stream, _, _ in streams.values():
            if not stream.closed:
                stream.close()

    stdout_bytes = bytes(streams[stdout_descriptor][2])
    stderr_bytes = bytes(streams[stderr_descriptor][2])
    stdout: Any = stdout_bytes.decode("utf-8", "replace") if text else stdout_bytes
    stderr: Any = stderr_bytes.decode("utf-8", "replace") if text else stderr_bytes
    return subprocess.CompletedProcess(list(command), returncode, stdout, stderr)


class Backend:
    def __init__(
        self,
        store_dir: Path = STORE_DIR,
        state_dir: Path = STATE_DIR,
        wacli: Path = WACLI,
        account_config: Path | None = None,
        unit_dir: Path | None = None,
        plugin_root: Path = PLUGIN_ROOT,
        local_bin: Path = LOCAL_BIN,
        skill_link: Path = SKILL_LINK,
        plugins_dir: Path = PLUGINS_DIR,
        shell_config: Path = SHELL_CONFIG,
    ) -> None:
        self.unit_dir = unit_dir or USER_UNIT_DIR
        self.plugin_root = plugin_root
        self.local_bin = local_bin
        self.skill_link = skill_link
        self.plugins_dir = plugins_dir
        self.shell_config = shell_config
        self.store_dir = store_dir
        self.state_dir = state_dir
        self.wacli = wacli
        self.account_config = account_config or ACCOUNT_CONFIG
        self._accounts: list[Account] | None = None
        self._active: Account | None = None
        self.avatar_cache = AvatarCache(state_dir) if AvatarCache is not None else None

    def accounts(self) -> list[Account]:
        if self._accounts is None:
            self._accounts = self._discover_accounts()
        return self._accounts

    def _discover_accounts(self) -> list[Account]:
        implicit = [Account(
            LEGACY_ACCOUNT_NAME, self.store_dir.resolve(strict=False), True,
            selector="store",
        )]
        # No account config means no named accounts, and no reason to pay for a
        # wacli invocation on every request.
        if not self.account_config.exists() and not self.account_config.is_symlink():
            return implicit
        if not self.account_config.is_file():
            raise OmaWhatsAppError("The wacli account configuration is not a regular file.")
        try:
            # account=None: the account list itself must never be account scoped.
            result = self._run(
                ["--read-only", "--json", "accounts", "list"], timeout=15, account=None
            )
            envelope = json.loads(result.stdout or "{}")
        except (OmaWhatsAppError, json.JSONDecodeError) as exc:
            raise OmaWhatsAppError(
                "Named wacli accounts could not be discovered safely."
            ) from exc
        if result.returncode != 0 or not isinstance(envelope, dict) \
                or envelope.get("success") is not True:
            raise OmaWhatsAppError("Named wacli accounts could not be discovered safely.")
        data = envelope.get("data") if isinstance(envelope, dict) else None
        rows = data.get("accounts") if isinstance(data, dict) else None
        if not isinstance(rows, list) or not rows or len(rows) > MAX_ACCOUNTS:
            raise OmaWhatsAppError("The wacli account list is invalid or empty.")
        accounts: list[Account] = []
        for row in rows:
            if not isinstance(row, dict):
                raise OmaWhatsAppError("The wacli account list contains an invalid entry.")
            name = str(row.get("name") or "")
            store = str(row.get("store_dir") or "")
            if not ACCOUNT_NAME.fullmatch(name) or not store:
                raise OmaWhatsAppError("The wacli account list contains an invalid entry.")
            unresolved = Path(store).expanduser()
            if not unresolved.is_absolute():
                raise OmaWhatsAppError("A named wacli account has an invalid store path.")
            try:
                resolved = unresolved.resolve(strict=False)
            except OSError as exc:
                raise OmaWhatsAppError(
                    "A named wacli account store could not be resolved safely."
                ) from exc
            accounts.append(Account(name, resolved, row.get("default") is True))
        if len({account.name for account in accounts}) != len(accounts) \
                or len({account.key for account in accounts}) != len(accounts):
            raise OmaWhatsAppError("The wacli account list contains duplicate identities.")
        if sum(account.default for account in accounts) != 1:
            raise OmaWhatsAppError("The wacli account list must identify exactly one default.")
        root_store = self.store_dir.resolve(strict=False)
        root_session = root_store / "session.db"
        if root_session.is_file() and all(account.store_dir != root_store for account in accounts):
            if any(account.name == LEGACY_ACCOUNT_NAME for account in accounts):
                raise OmaWhatsAppError(
                    f"The account name {LEGACY_ACCOUNT_NAME!r} is reserved for the existing root session."
                )
            if len(accounts) >= MAX_ACCOUNTS:
                raise OmaWhatsAppError("The wacli account list contains too many accounts.")
            accounts.insert(0, Account(
                LEGACY_ACCOUNT_NAME, root_store, False, selector="store"
            ))
        return accounts

    def account(self, name: Any = "") -> Account:
        """Resolve a requested account; empty keeps a root session stable."""
        requested = str(name or "").strip()
        accounts = self.accounts()
        if not requested:
            for candidate in accounts:
                if candidate.name == LEGACY_ACCOUNT_NAME \
                        and candidate.selector == "store":
                    return candidate
            for candidate in accounts:
                if candidate.default:
                    return candidate
            return accounts[0]
        if not ACCOUNT_NAME.fullmatch(requested):
            raise OmaWhatsAppError("Choose a valid named wacli account.")
        for candidate in accounts:
            if candidate.name == requested:
                return candidate
        raise OmaWhatsAppError("That wacli account is not configured.")

    def use_account(self, name: Any = "") -> Account:
        self._active = self.account(name)
        return self._active

    def _refresh_account_registry(self) -> None:
        self._accounts = None
        self._active = None

    def link_account(self, value: Any, authorization: Any) -> int:
        """Interactively add or resume one named account in a terminal."""
        if str(authorization or "") != "interactive":
            raise OmaWhatsAppError(
                "Linking an account requires --authorize interactive."
            )
        name = str(value or "").strip()
        if not ACCOUNT_NAME.fullmatch(name):
            raise OmaWhatsAppError(
                "Use 1-64 letters, digits, dots, underscores, or hyphens, "
                "starting with a letter or digit."
            )
        accounts = self.accounts()
        if name == LEGACY_ACCOUNT_NAME and any(
                account.selector in {"implicit", "store"} for account in accounts):
            raise OmaWhatsAppError(
                f"{LEGACY_ACCOUNT_NAME!r} is reserved for your existing account."
            )
        existing = next(
            (candidate for candidate in accounts if candidate.name == name), None
        )
        if existing is not None:
            if (existing.store_dir / "session.db").is_file():
                raise OmaWhatsAppError(f"Account {name!r} is already linked.")
            result, _, _ = self._transport_interactive(
                ["auth"], authorization="interactive", account=name
            )
        else:
            if len(accounts) >= MAX_ACCOUNTS:
                raise OmaWhatsAppError("WhatsApp for Omarchy already has the maximum number of accounts.")
            result, _, _ = self._transport_interactive(
                ["accounts", "add", name], authorization="interactive"
            )
        self._refresh_account_registry()
        try:
            linked = self.account(name)
        except OmaWhatsAppError as exc:
            if result == 0:
                raise OmaWhatsAppError(
                    "The link command completed, but account state could not be reconciled."
                ) from exc
            return result
        return self._finalize_link(linked, result)

    def _finalize_link(self, account: Account, result: int) -> int:
        """Reconcile one terminal auth result and enable its sync exactly once."""
        committed = (account.store_dir / "session.db").is_file()
        if not committed:
            if result == 0:
                raise OmaWhatsAppError(
                    "The link command completed, but no linked session was created."
                )
            return result
        # Before the first-run setup there is no unit to start; the setup starts it.
        if account.unit and self.online(account) and self._units_state() != "missing":
            try:
                # It starts now; at login only if WhatsApp for Omarchy starts with the system.
                if self._preferences().get("start_at_login") is not False:
                    self._systemctl_user(["enable", "--now", account.unit])
                else:
                    self._systemctl_user(["start", account.unit])
            except OmaWhatsAppError as exc:
                raise OmaWhatsAppPartialError(
                    "The account linked, but its background sync could not start.",
                    {"kind": "account-link", "committed": True,
                     "account": account.name},
                ) from exc
        if result != 0:
            raise OmaWhatsAppPartialError(
                "The account linked even though the terminal exited with an error.",
                {"kind": "account-link", "committed": True,
                 "account": account.name},
            )
        return result

    @property
    def active(self) -> Account:
        if self._active is None:
            self._active = self.account("")
        return self._active

    @contextmanager
    def _using(self, account: Account) -> Iterator[Account]:
        previous = self._active
        self._active = account
        try:
            yield account
        finally:
            self._active = previous

    @contextmanager
    def _state_directory(self, *, create: bool) -> Iterator[int]:
        if create:
            self.state_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
        flags = os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        descriptor = os.open(self.state_dir, flags)
        try:
            metadata = os.fstat(descriptor)
            if not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid != os.getuid():
                raise OSError("WhatsApp for Omarchy state directory is not privately owned")
            if create:
                os.fchmod(descriptor, 0o700)
            yield descriptor
        finally:
            os.close(descriptor)

    def _read_state_json(self, name: str, limit: int, default: Any) -> Any:
        flags = os.O_RDONLY | os.O_CLOEXEC
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        descriptor = -1
        try:
            with self._state_directory(create=False) as directory:
                descriptor = os.open(name, flags, dir_fd=directory)
                metadata = os.fstat(descriptor)
                if (not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != os.getuid()
                        or metadata.st_nlink != 1 or metadata.st_size > limit):
                    return default
                output = bytearray()
                while len(output) <= limit:
                    chunk = os.read(descriptor, min(65_536, limit - len(output) + 1))
                    if not chunk:
                        break
                    output.extend(chunk)
                if len(output) > limit:
                    return default
                return json.loads(bytes(output).decode("utf-8"))
        except (OSError, UnicodeDecodeError, json.JSONDecodeError):
            return default
        finally:
            if descriptor >= 0:
                os.close(descriptor)

    def _write_state_json(self, name: str, value: Any, limit: int) -> None:
        encoded = json.dumps(
            value, ensure_ascii=False, separators=(",", ":")
        ).encode("utf-8")
        if len(encoded) > limit:
            raise OmaWhatsAppError("WhatsApp for Omarchy state exceeded its safe size limit.")
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        temporary = ""
        descriptor = -1
        with self._state_directory(create=True) as directory:
            try:
                for _ in range(16):
                    temporary = f".{name}.{secrets.token_hex(12)}.tmp"
                    try:
                        descriptor = os.open(temporary, flags, 0o600, dir_fd=directory)
                        break
                    except FileExistsError:
                        continue
                if descriptor < 0:
                    raise OmaWhatsAppError("WhatsApp for Omarchy could not create private state.")
                os.fchmod(descriptor, 0o600)
                view = memoryview(encoded)
                while view:
                    written = os.write(descriptor, view)
                    view = view[written:]
                os.fsync(descriptor)
                os.close(descriptor)
                descriptor = -1
                os.replace(temporary, name, src_dir_fd=directory, dst_dir_fd=directory)
                temporary = ""
                os.fsync(directory)
            finally:
                if descriptor >= 0:
                    os.close(descriptor)
                if temporary:
                    try:
                        os.unlink(temporary, dir_fd=directory)
                    except OSError:
                        pass

    @contextmanager
    def _state_lock(self, name: str) -> Iterator[None]:
        flags = os.O_RDWR | os.O_CREAT | os.O_CLOEXEC
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        descriptor = -1
        try:
            with self._state_directory(create=True) as directory:
                descriptor = os.open(name, flags, 0o600, dir_fd=directory)
                metadata = os.fstat(descriptor)
                if (not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != os.getuid()
                        or metadata.st_nlink != 1):
                    raise OmaWhatsAppError("WhatsApp for Omarchy refused an unsafe state lock.")
                os.fchmod(descriptor, 0o600)
                fcntl.flock(descriptor, fcntl.LOCK_EX)
                yield
        except OSError as exc:
            raise OmaWhatsAppError("WhatsApp for Omarchy refused an unsafe state path.") from exc
        finally:
            if descriptor >= 0:
                os.close(descriptor)

    def _lifecycle_recovery_records(self) -> list[dict[str, str]]:
        value = self._read_state_json(
            "lifecycle-recovery.json", MAX_LIFECYCLE_RECOVERY, {}
        )
        rows = value.get("records") if isinstance(value, dict) else None
        if not isinstance(rows, list):
            return []
        records: list[dict[str, str]] = []
        seen: set[str] = set()
        for item in rows[:MAX_ACCOUNTS + 1]:
            if not isinstance(item, dict):
                continue
            unit = str(item.get("unit") or "")
            lock = str(item.get("lock") or "")
            if (unit in seen or not SYNC_UNIT_NAME.fullmatch(unit)
                    or not LIFECYCLE_LOCK_NAME.fullmatch(lock)):
                continue
            records.append({"unit": unit, "lock": lock})
            seen.add(unit)
        return records

    def _lifecycle_recovery_units(self) -> list[str]:
        return [record["unit"] for record in self._lifecycle_recovery_records()]

    def _write_lifecycle_recovery_records(
        self, records: list[dict[str, str]]
    ) -> None:
        clean = [record for record in records[:MAX_ACCOUNTS + 1]
                 if SYNC_UNIT_NAME.fullmatch(record.get("unit", ""))
                 and LIFECYCLE_LOCK_NAME.fullmatch(record.get("lock", ""))]
        self._write_state_json(
            "lifecycle-recovery.json", {"records": clean},
            MAX_LIFECYCLE_RECOVERY,
        )

    def _record_lifecycle_recovery(self, account: Account) -> None:
        unit = account.unit
        if not SYNC_UNIT_NAME.fullmatch(unit):
            raise OmaWhatsAppError("WhatsApp for Omarchy refused an unsafe sync unit.")
        record = {"unit": unit, "lock": self._lifecycle_lock_name(account)}
        with self._state_lock("lifecycle-recovery.lock"):
            records = self._lifecycle_recovery_records()
            if unit not in {item["unit"] for item in records}:
                records.append(record)
                self._write_lifecycle_recovery_records(records)

    def _clear_lifecycle_recovery(self, unit: str) -> None:
        with self._state_lock("lifecycle-recovery.lock"):
            records = self._lifecycle_recovery_records()
            if unit in {item["unit"] for item in records}:
                self._write_lifecycle_recovery_records([
                    record for record in records if record["unit"] != unit
                ])

    def recover_lifecycle(self) -> None:
        """Restart units left stopped by a terminated foreground operation."""
        with self._state_lock("lifecycle-recovery.lock"):
            pending = self._lifecycle_recovery_records()
        failed = False
        for record in pending:
            # Never hold the global intent lock while waiting for an account
            # operation. Mutations use this same account -> global order.
            with self._state_lock(record["lock"]):
                with self._state_lock("lifecycle-recovery.lock"):
                    current = self._lifecycle_recovery_records()
                if record not in current:
                    continue
                try:
                    self._systemctl_user(["start", record["unit"]])
                except OmaWhatsAppError:
                    failed = True
                    continue
                self._clear_lifecycle_recovery(record["unit"])
        if failed:
            raise OmaWhatsAppError(
                "Background sync recovery is still pending; retry after checking the user service."
            )

    @contextmanager
    def _voice_draft_directory(self, *, create: bool) -> Iterator[int]:
        """Open the private recorder directory without following path links."""
        descriptor = -1
        try:
            with self._state_directory(create=create) as state_directory:
                if create:
                    try:
                        os.mkdir(
                            VOICE_DRAFT_DIRECTORY,
                            mode=0o700,
                            dir_fd=state_directory,
                        )
                    except FileExistsError:
                        pass
                flags = os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC
                if hasattr(os, "O_NOFOLLOW"):
                    flags |= os.O_NOFOLLOW
                descriptor = os.open(
                    VOICE_DRAFT_DIRECTORY,
                    flags,
                    dir_fd=state_directory,
                )
                metadata = os.fstat(descriptor)
                if (not stat.S_ISDIR(metadata.st_mode)
                        or metadata.st_uid != os.getuid()):
                    raise OmaWhatsAppError(
                        "WhatsApp for Omarchy refused an unsafe voice-draft directory."
                    )
                if create:
                    os.fchmod(descriptor, 0o700)
                yield descriptor
        except OSError as exc:
            raise OmaWhatsAppError(
                "WhatsApp for Omarchy could not open its private voice-draft directory."
            ) from exc
        finally:
            if descriptor >= 0:
                os.close(descriptor)

    def _voice_draft_name(self, value: Any) -> str:
        path = self._local_path(value)
        normalized = Path(os.path.abspath(path))
        expected_parent = Path(os.path.abspath(
            self.state_dir / VOICE_DRAFT_DIRECTORY
        ))
        if normalized.parent != expected_parent or not VOICE_DRAFT_PATTERN.fullmatch(
            normalized.name
        ):
            raise OmaWhatsAppError(
                "That recording is not an WhatsApp for Omarchy private voice draft."
            )
        return normalized.name

    def _inspect_voice_draft(self, value: Any, *, require_audio: bool) -> tuple[str, int]:
        name = self._voice_draft_name(value)
        flags = os.O_RDONLY | os.O_CLOEXEC
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        descriptor = -1
        try:
            with self._voice_draft_directory(create=False) as directory:
                descriptor = os.open(name, flags, dir_fd=directory)
                metadata = os.fstat(descriptor)
                if (not stat.S_ISREG(metadata.st_mode)
                        or metadata.st_uid != os.getuid()
                        or metadata.st_nlink != 1):
                    raise OmaWhatsAppError(
                        "WhatsApp for Omarchy refused an unsafe voice draft."
                    )
                if metadata.st_size > MAX_FILE:
                    raise OmaWhatsAppError(
                        "The voice note is too large (maximum 100 MB)."
                    )
                os.fchmod(descriptor, 0o600)
                header = os.read(descriptor, min(65_536, metadata.st_size))
                if require_audio:
                    if metadata.st_size <= 0:
                        raise OmaWhatsAppError("The voice note is empty.")
                    if not header.startswith(b"OggS") or b"OpusHead" not in header:
                        raise OmaWhatsAppError(
                            "The voice note must be an OGG/Opus recording."
                        )
                return name, metadata.st_size
        except FileNotFoundError as exc:
            raise OmaWhatsAppError("That voice draft is no longer available.") from exc
        except OSError as exc:
            raise OmaWhatsAppError("WhatsApp for Omarchy could not read that voice draft.") from exc
        finally:
            if descriptor >= 0:
                os.close(descriptor)

    def voice_draft(self, action: str, value: Any = None) -> dict[str, Any]:
        operation = str(action or "").strip().lower()
        if operation == "create":
            name = f"voice-{secrets.token_hex(16)}.ogg"
            flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC
            if hasattr(os, "O_NOFOLLOW"):
                flags |= os.O_NOFOLLOW
            descriptor = -1
            try:
                with self._voice_draft_directory(create=True) as directory:
                    descriptor = os.open(name, flags, 0o600, dir_fd=directory)
                    os.fchmod(descriptor, 0o600)
            except OSError as exc:
                raise OmaWhatsAppError(
                    "WhatsApp for Omarchy could not create a private voice draft."
                ) from exc
            finally:
                if descriptor >= 0:
                    os.close(descriptor)
            return {
                "ok": True,
                "kind": "voice-draft",
                "action": "create",
                "path": str(self.state_dir / VOICE_DRAFT_DIRECTORY / name),
            }
        if operation == "finalize":
            name, size = self._inspect_voice_draft(value, require_audio=True)
            return {
                "ok": True,
                "kind": "voice-draft",
                "action": "finalize",
                "path": str(self.state_dir / VOICE_DRAFT_DIRECTORY / name),
                "size": size,
            }
        if operation == "discard":
            name, _ = self._inspect_voice_draft(value, require_audio=False)
            try:
                with self._voice_draft_directory(create=False) as directory:
                    os.unlink(name, dir_fd=directory)
            except FileNotFoundError:
                pass
            except OSError as exc:
                raise OmaWhatsAppError(
                    "WhatsApp for Omarchy could not discard that private voice draft."
                ) from exc
            return {"ok": True, "kind": "voice-draft", "action": "discard"}
        raise OmaWhatsAppError("Choose create, finalize, or discard for the voice draft.")

    @staticmethod
    def _chat_snapshots(value: Any) -> dict[str, dict[str, Any]]:
        """Sanitize persisted unread/timestamp/message identity snapshots."""
        snapshots: dict[str, dict[str, Any]] = {}
        if not isinstance(value, dict):
            return snapshots
        for jid, item in list(value.items())[:MAX_NOTIFY_WATERMARKS]:
            if not isinstance(jid, str) or not isinstance(item, dict):
                continue
            snapshots[jid[:160]] = {
                "unread": bounded_int(item.get("unread"), 0, 0, 1_000_000_000),
                "timestamp": bounded_int(item.get("timestamp"), 0, 0, 9_999_999_999),
                "message_id": str(item.get("message_id") or "")[:256],
            }
        return snapshots

    @staticmethod
    def _signature(value: Any) -> dict[str, Any]:
        """The account's signature: off unless there is a name to sign with."""
        item = value if isinstance(value, dict) else {}
        name = " ".join("".join(
            char for char in str(item.get("name") or "")
            if char.isprintable() and char not in "*\n\r").split())[:MAX_SIGNATURE_NAME]
        position = item.get("position")
        return {
            "enabled": item.get("enabled") is True and name != "",
            "name": name,
            "position": position if position in SIGNATURE_POSITIONS else "top",
        }

    @classmethod
    def _store_state(cls, value: Any) -> dict[str, Any]:
        """Normalize the per-account half of the preferences file."""
        item = value if isinstance(value, dict) else {}
        return {
            "online": item.get("online") is not False,
            "send_read_receipts": item.get("send_read_receipts") is not False,
            "signature": cls._signature(item.get("signature")),
            # Popups off for this account only; the badge still counts it.
            "notifications_muted": item.get("notifications_muted") is True,
            "acknowledged_unread": cls._chat_snapshots(item.get("acknowledged_unread")),
            "notified": cls._chat_snapshots(item.get("notified")),
        }

    def _preferences(self) -> dict[str, Any]:
        value = self._read_state_json("preferences.json", MAX_PREFERENCES, {})
        if not isinstance(value, dict):
            value = {}
        stores: dict[str, dict[str, Any]] = {}
        raw_stores = value.get("stores")
        if isinstance(raw_stores, dict):
            for key, item in list(raw_stores.items())[:MAX_ACCOUNTS]:
                if isinstance(key, str) and key:
                    stores[key[:4096]] = self._store_state(item)
        elif any(key in value for key in
                 ("online", "send_read_receipts", "acknowledged_unread", "notified")):
            # Version 1 kept one account's state at the top level. It describes
            # the store that was in use when it was written, which is the
            # default account, not whichever account this request selected.
            stores[self.account("").key] = self._store_state(value)
        version = bounded_int(value.get("version"), 1, 1, 1_000)
        if version < 3:
            # Before version 3 "off" was the default, not a choice anyone made.
            for state in stores.values():
                state["send_read_receipts"] = True
        notifications = value.get("notifications")
        if not isinstance(notifications, dict):
            notifications = {}
        if version < 4:
            # Version 4: desktop notifications on by default (they were off by
            # default, not by choice), starting from a fresh watermark so the
            # archive is adopted instead of replayed; automatic photo refresh
            # off, because each batch pauses sync and loses what arrives.
            notifications = dict(notifications, enabled=True)
            value = dict(value, auto_refresh_avatars=False)
            for state in stores.values():
                state["notified"] = {}
        dropdown_rows = bounded_int(value.get("dropdown_rows"), 7, 5, 9)
        if dropdown_rows not in {5, 7, 9}:
            dropdown_rows = 7
        composer_max_lines = bounded_int(value.get("composer_max_lines"), 6, 4, 10)
        if composer_max_lines not in {4, 6, 8, 10}:
            composer_max_lines = 6
        time_format = value.get("time_format", "auto")
        if not isinstance(time_format, str) or time_format not in {"auto", "12h", "24h"}:
            time_format = "auto"
        return {
            "version": PREFERENCES_VERSION,
            "show_unread_count": value.get("show_unread_count") is not False,
            "check_updates_on_launch": value.get("check_updates_on_launch") is True,
            "start_at_login": value.get("start_at_login") is not False,
            "dropdown_rows": dropdown_rows,
            "composer_max_lines": composer_max_lines,
            "time_format": time_format,
            **{name: ui_preference(value, name) for name in UI_PREFERENCES},
            # The desktop popup is a separate surface from the bar badge, so it
            # keeps its own settings. Its watermark is per account, next to the
            # badge acknowledgements it must never read.
            "notifications": {
                "enabled": notifications.get("enabled") is True,
                "preview": notifications.get("preview") is not False,
                "sound": notifications.get("sound") is not False,
            },
            # Consent to what the first run writes outside the plugin folder.
            "setup": {
                "consented": isinstance(value.get("setup"), dict)
                and value["setup"].get("consented") is True,
                "agents": not isinstance(value.get("setup"), dict)
                or value["setup"].get("agents") is not False,
            },
            "stores": stores,
        }

    def _write_preferences(self, value: dict[str, Any]) -> None:
        self._write_state_json("preferences.json", value, MAX_PREFERENCES)

    def _update_preferences(self, update: Any) -> dict[str, Any]:
        with self._state_lock("preferences.lock"):
            value = self._preferences()
            update(value)
            self._write_preferences(value)
            return value

    def _account_state(
        self,
        preferences: dict[str, Any] | None = None,
        account: Account | None = None,
    ) -> dict[str, Any]:
        value = preferences if preferences is not None else self._preferences()
        return value["stores"].get((account or self.active).key) or self._store_state({})

    def _update_account_state(
        self, update: Any, account: Account | None = None
    ) -> dict[str, Any]:
        key = (account or self.active).key

        def apply(value: dict[str, Any]) -> None:
            state = value["stores"].get(key)
            if state is None:
                state = self._store_state({})
                value["stores"][key] = state
            update(state)

        return self._update_preferences(apply)

    def online(self, account: Account | None = None) -> bool:
        return self._account_state(account=account).get("online") is not False

    @staticmethod
    def _lifecycle_lock_name(account: Account) -> str:
        identity = hashlib.sha256(account.key.encode("utf-8")).hexdigest()[:24]
        return f"lifecycle-{identity}.lock"

    def settings(self, update: Any = None) -> dict[str, Any]:
        if update is None:
            value = self._preferences()
        else:
            if not isinstance(update, dict):
                raise OmaWhatsAppError("Settings must be a JSON object.")
            allowed = {
                "send_read_receipts",
                "signature",
                "account_notifications",
                "show_unread_count",
                "dropdown_rows",
                "check_updates_on_launch",
                "start_at_login",
                "composer_max_lines",
                "time_format",
                *UI_PREFERENCES,
            }
            if any(key not in allowed for key in update):
                raise OmaWhatsAppError("That WhatsApp for Omarchy setting is not supported.")
            if "send_read_receipts" in update and not isinstance(update["send_read_receipts"], bool):
                raise OmaWhatsAppError("Read receipts must be on or off.")
            if "account_notifications" in update and not isinstance(update["account_notifications"], bool):
                raise OmaWhatsAppError("This account's notifications must be on or off.")
            if "signature" in update:
                wanted = update["signature"]
                if not isinstance(wanted, dict) or any(
                        key not in {"enabled", "name", "position"} for key in wanted):
                    raise OmaWhatsAppError("The signature setting has an unsupported value.")
                if "enabled" in wanted and not isinstance(wanted["enabled"], bool):
                    raise OmaWhatsAppError("The signature must be on or off.")
                if "position" in wanted and wanted["position"] not in SIGNATURE_POSITIONS:
                    raise OmaWhatsAppError("The signature goes at the top or the bottom.")
                raw_name = wanted.get("name", "")
                if not isinstance(raw_name, str) or len(raw_name) > MAX_SIGNATURE_NAME \
                        or "*" in raw_name or "\n" in raw_name:
                    raise OmaWhatsAppError(
                        f"Sign with a name of up to {MAX_SIGNATURE_NAME} characters, without *.")
                if wanted.get("enabled") is True and not raw_name.strip():
                    raise OmaWhatsAppError("Type the name to sign messages with.")
            if "show_unread_count" in update and not isinstance(update["show_unread_count"], bool):
                raise OmaWhatsAppError("The unread badge must be on or off.")
            if "check_updates_on_launch" in update and not isinstance(update["check_updates_on_launch"], bool):
                raise OmaWhatsAppError("Update checks must be on or off.")
            if "start_at_login" in update and not isinstance(update["start_at_login"], bool):
                raise OmaWhatsAppError("Starting with the system must be on or off.")
            if "dropdown_rows" in update and update["dropdown_rows"] not in {5, 7, 9}:
                raise OmaWhatsAppError("Dropdown size must be 5, 7, or 9 chats.")
            if "composer_max_lines" in update and update["composer_max_lines"] not in {4, 6, 8, 10}:
                raise OmaWhatsAppError("Composer expansion limit must be 4, 6, 8, or 10 lines.")
            if "time_format" in update and (
                not isinstance(update["time_format"], str)
                or update["time_format"] not in {"auto", "12h", "24h"}
            ):
                raise OmaWhatsAppError("Time format must be auto, 12h, or 24h.")
            for name in UI_PREFERENCES:
                if name in update and not valid_ui_preference(name, update[name]):
                    raise OmaWhatsAppError(f"The {name.replace('_', ' ')} setting has an unsupported value.")

            key = self.active.key

            def apply(value: dict[str, Any]) -> None:
                for name, setting in update.items():
                    if name in {"send_read_receipts", "signature", "account_notifications"}:
                        state = value["stores"].get(key)
                        if state is None:
                            state = self._store_state({})
                            value["stores"][key] = state
                        if name == "signature":
                            state["signature"] = self._signature(dict(state["signature"], **setting))
                        elif name == "account_notifications":
                            state["notifications_muted"] = not bool(setting)
                        else:
                            state["send_read_receipts"] = bool(setting)
                    else:
                        value[name] = setting

            value = self._update_preferences(apply)
            if "start_at_login" in update:
                self._apply_start_at_login(bool(update["start_at_login"]))
        state = self._account_state(value)
        return {
            "ok": True,
            "kind": "settings",
            "account": self.active.name,
            "send_read_receipts": state.get("send_read_receipts") is True,
            "signature": self._signature(state.get("signature")),
            "account_notifications": state.get("notifications_muted") is not True,
            "show_unread_count": value.get("show_unread_count") is not False,
            "check_updates_on_launch": value.get("check_updates_on_launch") is True,
            "start_at_login": value.get("start_at_login") is not False,
            "dropdown_rows": value.get("dropdown_rows", 7),
            "composer_max_lines": value.get("composer_max_lines", 6),
            "time_format": value.get("time_format", "auto"),
            **{name: ui_preference(value, name) for name in UI_PREFERENCES},
            "auto_download_media": self.auto_download_media(),
        }

    def _sent_hint_key(self, jid: str, message_id: str) -> str:
        # WhatsApp message IDs can collide across chats, and a chat can be
        # reachable from more than one linked account.
        return f"{self.active.key}\n{jid}\n{message_id}"

    def _sent_media_hints(self) -> dict[str, dict[str, Any]]:
        value = self._read_state_json("sent-media.json", MAX_SENT_MEDIA_STATE, {})
        if not isinstance(value, dict):
            return {}
        clean: dict[str, dict[str, Any]] = {}
        default_key = self.account("").key
        for key, item in value.items():
            if not isinstance(key, str) or not isinstance(item, dict):
                continue
            local_path = Path(str(item.get("local_path") or ""))
            if not local_path.is_absolute() or not local_path.is_file():
                continue
            if key.count("\n") == 1:
                # A version 1 hint was written before hints were store scoped.
                key = f"{default_key}\n{key}"
            clean[key] = item
        return clean

    def _remember_sent_media(
        self,
        jid: str,
        message_id: str,
        path: Path,
        mime: str,
        media_type: str,
        album_id: str = "",
        album_index: int = 0,
        album_count: int = 1,
    ) -> None:
        target = message_id.strip()
        if not target:
            return
        with self._state_lock("sent-media.lock"):
            hints = self._sent_media_hints()
            hints[self._sent_hint_key(jid, target)] = {
                "local_path": str(path),
                "filename": path.name,
                "mime_type": mime,
                "media_type": media_type,
                "album_id": album_id[:64],
                "album_index": max(0, int(album_index)),
                "album_count": max(1, min(int(album_count), MAX_ATTACHMENTS)),
                "saved_at": int(time.time()),
            }
            if len(hints) > MAX_SENT_MEDIA_HINTS:
                ordered = sorted(
                    hints.items(),
                    key=lambda pair: bounded_int(
                        pair[1].get("saved_at"), 0, 0, 2**63 - 1
                    ),
                )
                hints = dict(ordered[-MAX_SENT_MEDIA_HINTS:])
            self._write_state_json("sent-media.json", hints, MAX_SENT_MEDIA_STATE)

    def _remember_sent_media_best_effort(self, *args: Any) -> bool:
        """Preview bookkeeping must never turn a delivered send into a retry."""
        try:
            self._remember_sent_media(*args)
        except (OmaWhatsAppError, OSError, TypeError, ValueError):
            return False
        return True

    def _sent_reply_hints(self) -> dict[str, dict[str, Any]]:
        value = self._read_state_json("sent-replies.json", MAX_SENT_REPLY_STATE, {})
        if not isinstance(value, dict):
            return {}
        clean: dict[str, dict[str, Any]] = {}
        for key, item in value.items():
            if not isinstance(key, str) or key.count("\n") != 2 \
                    or not isinstance(item, dict):
                continue
            quoted_id = str(item.get("quoted_id") or "").strip()
            if not quoted_id or len(quoted_id) > 256:
                continue
            clean[key] = {
                "quoted_id": quoted_id,
                "saved_at": bounded_int(item.get("saved_at"), 0, 0, 2**63 - 1),
            }
        return clean

    def _remember_sent_reply(
        self, jid: str, message_id: str, quoted_id: str,
    ) -> None:
        target = message_id.strip()
        quoted = quoted_id.strip()
        if not target or not quoted:
            return
        with self._state_lock("sent-replies.lock"):
            hints = self._sent_reply_hints()
            hints[self._sent_hint_key(jid, target)] = {
                "quoted_id": quoted[:256],
                "saved_at": int(time.time()),
            }
            if len(hints) > MAX_SENT_REPLY_HINTS:
                ordered = sorted(hints.items(), key=lambda pair: pair[1]["saved_at"])
                hints = dict(ordered[-MAX_SENT_REPLY_HINTS:])
            self._write_state_json(
                "sent-replies.json", hints, MAX_SENT_REPLY_STATE
            )

    def _remember_sent_reply_best_effort(
        self, jid: str, message_id: str, quoted_id: str,
    ) -> bool:
        """Reply bookkeeping must never turn a delivered send into a retry."""
        try:
            self._remember_sent_reply(jid, message_id, quoted_id)
        except (OmaWhatsAppError, OSError, TypeError, ValueError):
            return False
        return True

    def _run(
        self,
        args: list[str],
        *,
        timeout: float = 30,
        stdout_limit: int = MAX_WACLI_OUTPUT,
        stderr_limit: int = MAX_PROCESS_ERROR,
        account: Any = ACTIVE_ACCOUNT,
    ) -> subprocess.CompletedProcess[str]:
        if not self.wacli.is_file() or not os.access(self.wacli, os.X_OK):
            raise OmaWhatsAppError("wacli is not installed.")
        if account is ACTIVE_ACCOUNT:
            account = self.active
        scope = account.cli_args if account is not None else []
        try:
            return run_bounded(
                [str(self.wacli), *scope, *args],
                timeout=timeout,
                stdout_limit=stdout_limit,
                stderr_limit=stderr_limit,
            )
        except ProcessOutputLimitExceeded as exc:
            raise OmaWhatsAppError("WhatsApp returned too much data.") from exc
        except subprocess.TimeoutExpired as exc:
            raise OmaWhatsAppError("WhatsApp took too long to respond.") from exc
        except OSError as exc:
            raise OmaWhatsAppError("wacli could not be started.") from exc

    @staticmethod
    def _locked(result: subprocess.CompletedProcess[str]) -> bool:
        text = f"{result.stdout}\n{result.stderr}".casefold()
        return "store is locked" in text or "another wacli is running" in text

    @staticmethod
    def _tree_size(path: Path) -> tuple[int, int, bool]:
        """Bytes and files under path, without following links, bounded."""
        total = files = 0
        if not path.is_dir() or path.is_symlink():
            return 0, 0, False
        for root_dir, dirs, names in os.walk(path, followlinks=False):
            dirs[:] = [name for name in dirs if not os.path.islink(os.path.join(root_dir, name))]
            for name in names:
                try:
                    info = os.lstat(os.path.join(root_dir, name))
                except OSError:
                    continue
                if stat.S_ISREG(info.st_mode):
                    total += info.st_size
                    files += 1
                    if files >= MAX_ABOUT_FILES:
                        return total, files, True
        return total, files, False

    def about(self, plugin_dir: Path | None = None) -> dict[str, Any]:
        """Versions, install mode and local disk use. Local reads only."""
        plugin_dir = plugin_dir or self.plugin_root
        app_version = self._app_version(plugin_dir)
        # A git checkout is what `omarchy plugin add` makes and updates.
        install_mode = "git" if (plugin_dir / ".git").exists() else "copy"
        wacli_version = ""
        try:
            result = run_bounded([str(self.wacli), "--version"], timeout=5,
                                 stdout_limit=4096, stderr_limit=4096)
            match = re.search(r"wacli\s+v?([0-9]+(?:\.[0-9]+)+)", result.stdout or result.stderr)
            wacli_version = match.group(1) if match else ""
        except (OSError, subprocess.TimeoutExpired, ProcessOutputLimitExceeded):
            pass
        stores = []
        for account in self.accounts():
            database = sum(
                (account.store_dir / name).stat().st_size
                for name in ("wacli.db", "wacli.db-wal", "wacli.db-shm")
                if (account.store_dir / name).is_file()
            )
            media_bytes, media_files, truncated = self._tree_size(account.store_dir / "media")
            stores.append({
                "account": account.name, "label": account.label,
                "database_bytes": database, "media_bytes": media_bytes,
                "media_files": media_files, "media_truncated": truncated,
            })
        avatar_bytes, avatar_files, _ = self._tree_size(self.state_dir / "avatars")
        return {
            "ok": True, "kind": "about",
            "app_version": app_version,
            "install_mode": install_mode,
            "wacli_version": wacli_version,
            "wacli_minimum_version": WACLI_MINIMUM_VERSION,
            "wacli_tested_version": WACLI_PARITY_VERSION,
            "stores": stores,
            "avatar_cache_bytes": avatar_bytes,
            "avatar_cache_files": avatar_files,
        }

    def auto_download_media(self) -> bool:
        return not any(
            (self.unit_dir / f"{unit}.d" / MEDIA_DROPIN).exists()
            for unit in MEDIA_UNITS
        )

    def media_mode(self, enabled: Any) -> dict[str, Any]:
        """Turn automatic download of received media on or off for every account."""
        if not isinstance(enabled, bool):
            raise OmaWhatsAppError("Automatic media download must be on or off.")
        text = stamped(MEDIA_DROPIN_OFF)
        # Both drop-ins are checked before either changes: one that someone
        # edited, or wrote, stops the change and stays as it is.
        dropins = []
        for unit in MEDIA_UNITS:
            folder = self.unit_dir / f"{unit}.d"
            target = folder / MEDIA_DROPIN
            if folder.is_symlink() or (os.path.lexists(folder) and not folder.is_dir()):
                raise OmaWhatsAppError(
                    f"{folder} is not a plain folder; nothing was changed.")
            owner = self._written_file_owner(target, text.encode("utf-8"))
            if owner in {"edited", "foreign"}:
                raise OmaWhatsAppError(
                    f"{self._describe_written(target, owner)}; it was left as it is and "
                    "nothing was changed. Move it away to use this setting.")
            dropins.append((folder, target, owner))
        for folder, target, owner in dropins:
            if enabled:
                if owner != "missing":
                    target.unlink()
                continue
            if owner == "ok":
                continue
            folder.mkdir(parents=True, exist_ok=True, mode=0o700)
            temporary = folder / f".{MEDIA_DROPIN}.{secrets.token_hex(8)}.tmp"
            descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL
                                 | os.O_NOFOLLOW | os.O_CLOEXEC, 0o644)
            try:
                os.write(descriptor, text.encode("utf-8"))
                os.fsync(descriptor)
            finally:
                os.close(descriptor)
            os.replace(temporary, target)
        self._systemctl_user(["daemon-reload"])
        restarted = 0
        for account in self.accounts():
            if not account.unit or not self._unit_active(account.unit):
                continue
            with self._state_lock(self._lifecycle_lock_name(account)):
                self._systemctl_user(["restart", account.unit])
                restarted += 1
        return {
            "ok": True, "kind": "media-mode",
            "auto_download_media": self.auto_download_media(),
            "restarted": restarted,
        }

    # ------------------------------------------------------------------ setup
    #
    # `omarchy plugin add` only clones the repository, so the first run sets up
    # what lives outside the plugin folder, once the user agrees: the sync
    # units, a link that puts `omawhatsapp` on the command line, and, when
    # agents are allowed, the MCP server link and the agent skill. Links point
    # into the checkout, so `omarchy plugin update` updates them all at once.

    def _wacli_version(self) -> str:
        """wacli's version, cached until the binary changes (status runs often)."""
        try:
            info = self.wacli.stat()
        except OSError:
            return ""
        key = [str(self.wacli), info.st_mtime_ns, info.st_size]
        cached = self._read_state_json("wacli-version.json", 4096, {})
        if isinstance(cached, dict) and cached.get("key") == key:
            return str(cached.get("version") or "")
        version = ""
        try:
            result = run_bounded([str(self.wacli), "--version"], timeout=5,
                                 stdout_limit=4096, stderr_limit=4096)
            match = re.search(r"wacli\s+v?([0-9]+(?:\.[0-9]+)+)", result.stdout or result.stderr)
            version = match.group(1) if match else ""
        except (OSError, subprocess.TimeoutExpired, ProcessOutputLimitExceeded):
            return ""
        try:
            self._write_state_json("wacli-version.json", {"key": key, "version": version}, 4096)
        except (OSError, OmaWhatsAppError):
            pass
        return version

    @staticmethod
    def _wacli_too_old(version: str) -> bool:
        return bool(version) and version_tuple(version) < version_tuple(WACLI_MINIMUM_VERSION)

    @staticmethod
    def _app_version(plugin_dir: Path) -> str:
        try:
            manifest = json.loads((plugin_dir / "manifest.json").read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return ""
        return str(manifest.get("version") or "")[:32] if isinstance(manifest, dict) else ""

    def _setup_links(self, agents: bool) -> dict[Path, Path]:
        links = {self.local_bin / "omawhatsapp": self.plugin_root / "bin" / "omawhatsapp"}
        if agents:
            links[self.local_bin / "omawhatsapp-mcp"] = self.plugin_root / "bin" / "omawhatsapp-mcp"
            links[self.skill_link] = self.plugin_root / "skills" / "omawhatsapp"
        return links

    @staticmethod
    def _within(path: Path, folder: Path) -> bool:
        # Both as written and resolved, so a home reached through a link matches.
        roots = {os.path.normpath(str(folder)), os.path.normpath(str(folder.resolve(strict=False)))}
        paths = {os.path.normpath(str(path)), os.path.normpath(str(path.resolve(strict=False)))}
        for root in roots:
            for candidate in paths:
                try:
                    if os.path.commonpath([root, candidate]) == root:
                        return True
                except ValueError:
                    continue
        return False

    @staticmethod
    def _link_pointee(link: Path) -> Path | None:
        try:
            pointee = Path(os.readlink(link))
        except OSError:
            return None
        return pointee if pointee.is_absolute() else link.parent / pointee

    @staticmethod
    def _identifies_as_this_app(path: Path) -> bool:
        """A helper, MCP server, module or skill of this app says so in its content."""
        if path.is_dir():
            skill = path / "SKILL.md"
            try:
                text = skill.read_text(encoding="utf-8", errors="replace")[:65536]
            except OSError:
                return False
            return re.search(r"^name:\s*omawhatsapp\s*$", text, re.MULTILINE) is not None
        try:
            with path.open("rb") as handle:
                data = handle.read(1024 * 1024).lower()
        except OSError:
            return False
        return (b"omawhatsapp" in data and b"wacli" in data) or b"avatarcacheerror" in data

    def _path_owner(self, link: Path, target: Path) -> str:
        """Who owns a path the setup links, and so what the setup may do there.

        ok: it already links to target. missing: nothing is there. ours: a
        link into this app's own plugin folder, or a file or folder that an
        earlier install of this app (or the original OmaWhatsApp, which uses
        the same names) left and that says so; the setup replaces a link and
        moves a copy aside. foreign: anything else, which is never touched.
        """
        if link.is_symlink():
            pointee = self._link_pointee(link)
            if pointee is None:
                return "foreign"
            if self._within(pointee, self.plugin_root) or self._within(
                    pointee, self.plugins_dir / PLUGIN_ID):
                try:
                    if link.resolve(strict=True) == target.resolve(strict=True):
                        return "ok"
                except OSError:
                    pass
                return "ours"
            return "foreign"
        if link.is_file() or link.is_dir():
            return "ours" if self._identifies_as_this_app(link) else "foreign"
        if os.path.lexists(link):
            return "foreign"
        return "missing"

    def _is_own_copy(self, path: Path) -> bool:
        return (path.is_file() and not path.is_symlink()
                and self._identifies_as_this_app(path))

    @staticmethod
    def _written_file_owner(path: Path, expected: bytes | None = None) -> str:
        """Who owns a file the app writes outside its folder (a sync unit or
        the media drop-in), and so whether the app may replace or remove it.

        missing: nothing is there. ok: exactly `expected`. ours: what the app
        wrote, unchanged since. edited: the app's, changed after it wrote it.
        foreign: anything else. Only missing, ok and ours are ever touched.
        """
        if path.is_symlink():
            return "foreign"
        if not os.path.lexists(path):
            return "missing"
        if not path.is_file():
            return "foreign"
        try:
            with path.open("rb") as handle:
                data = handle.read(MAX_WRITTEN_FILE + 1)
        except OSError:
            return "foreign"
        if expected is not None and data == expected:
            return "ok"
        if len(data) <= MAX_WRITTEN_FILE and written_unchanged(data):
            return "ours"
        text = data.decode("utf-8", errors="replace")
        return "edited" if any(marker in text for marker in UNIT_MARKERS) else "foreign"

    @staticmethod
    def _describe_written(path: Path, owner: str) -> str:
        if owner == "edited":
            return f"{path} was changed after the app wrote it"
        return f"{path} belongs to something else"

    def _unit_conflicts(self) -> list[Path]:
        """Sync unit paths the setup may not write: edited, or not the app's."""
        return [self.unit_dir / name for name in SETUP_UNITS
                if self._written_file_owner(self.unit_dir / name) in {"edited", "foreign"}]

    @staticmethod
    def _describe(path: Path) -> str:
        if path.is_symlink():
            try:
                return f"{path} (a link to {os.readlink(path)})"
            except OSError:
                return f"{path} (a link)"
        return f"{path} (a {'folder' if path.is_dir() else 'file'})"

    def _back_up(self, path: Path) -> None:
        """Move something a link replaces aside instead of deleting it."""
        folder = self.state_dir / "setup-backup"
        folder.mkdir(parents=True, exist_ok=True, mode=0o700)
        stamp = time.strftime("%Y%m%d-%H%M%S")
        shutil.move(str(path), str(folder / f"{path.name}.{stamp}.{secrets.token_hex(3)}"))

    def _place_link(self, link: Path, target: Path) -> bool:
        state = self._path_owner(link, target)
        if state == "ok":
            return False
        if state == "foreign":
            raise OmaWhatsAppError(
                f"{self._describe(link)} belongs to something else; it was left as it is.")
        if not target.exists():
            raise OmaWhatsAppError(f"This copy of the app is missing {target.name}; reinstall it.")
        link.parent.mkdir(parents=True, exist_ok=True)
        if state == "ours" and not link.is_symlink():
            self._back_up(link)
        temporary = link.with_name(f".{link.name}.{secrets.token_hex(6)}.tmp")
        os.symlink(target, temporary)
        os.replace(temporary, link)
        return True

    def _render_unit(self, name: str) -> str:
        text = (self.plugin_root / "systemd" / "user" / name).read_text(encoding="utf-8")
        if self.wacli != self.local_bin / "wacli":
            path = str(self.wacli)
            if not re.fullmatch(r"/[A-Za-z0-9._/+-]+", path):
                raise OmaWhatsAppError("The wacli path cannot be used in a service unit.")
            text = text.replace(UNIT_WACLI, path)
        return stamped(text)

    def _units_state(self) -> str:
        """ok, missing, stale (the app's own, from another version), or
        foreign (changed after the app wrote it, or not the app's)."""
        states = []
        for name in SETUP_UNITS:
            try:
                expected: bytes | None = self._render_unit(name).encode("utf-8")
            except (OSError, OmaWhatsAppError):
                expected = None
            states.append(self._written_file_owner(self.unit_dir / name, expected))
        if any(state in {"edited", "foreign"} for state in states):
            return "foreign"
        if all(state == "ok" for state in states):
            return "ok"
        return "missing" if "missing" in states else "stale"

    def _write_unit(self, name: str, text: str) -> None:
        self.unit_dir.mkdir(parents=True, exist_ok=True)
        target = self.unit_dir / name
        owner = self._written_file_owner(target, text.encode("utf-8"))
        if owner not in {"missing", "ok", "ours"}:
            raise OmaWhatsAppError(
                f"{self._describe_written(target, owner)}; it was left as it is.")
        temporary = self.unit_dir / f".{name}.{secrets.token_hex(8)}.tmp"
        descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL
                             | os.O_NOFOLLOW | os.O_CLOEXEC, 0o644)
        try:
            os.write(descriptor, text.encode("utf-8"))
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
        os.replace(temporary, target)

    def _original_plugin(self) -> dict[str, bool]:
        installed = (self.plugins_dir / ORIGINAL_PLUGIN_ID).exists()
        enabled = False
        try:
            shell = json.loads(self.shell_config.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            shell = {}
        if isinstance(shell, dict):
            layout = shell.get("bar", {}).get("layout", {}) if isinstance(shell.get("bar"), dict) else {}
            entries = list(shell.get("plugins") or []) if isinstance(shell.get("plugins"), list) else []
            if isinstance(layout, dict):
                for section in ("left", "center", "right"):
                    if isinstance(layout.get(section), list):
                        entries.extend(layout[section])
            enabled = any(isinstance(item, dict) and item.get("id") == ORIGINAL_PLUGIN_ID
                          for item in entries)
        return {"installed": installed, "enabled": enabled}

    def _setup_state(self, preferences: dict[str, Any] | None = None) -> dict[str, Any]:
        value = preferences if preferences is not None else self._preferences()
        consent = value.get("setup") or {}
        agents = consent.get("agents") is not False
        links = {
            str(link): self._path_owner(link, target)
            for link, target in self._setup_links(agents).items()
        }
        # Paths the setup needs that belong to something else: it stops
        # before changing anything until they are moved away.
        conflicts = [path for path, owner in links.items() if owner == "foreign"]
        conflicts += [str(path) for path in self._unit_conflicts()]
        units = self._units_state()
        wacli_found = self.wacli.is_file() and os.access(self.wacli, os.X_OK)
        legacy = any(self._is_own_copy(self.local_bin / name) for name in LEGACY_HELPER_COPIES)
        original = self._original_plugin()
        consented = consent.get("consented") is True
        helper = self.local_bin / "omawhatsapp"
        # An install made with the old script already had the user's consent;
        # it moves to links without asking again.
        previous_install = not consented and units in {"ok", "stale"} and not conflicts and (
            legacy or self._is_own_copy(helper))
        return {
            "consented": consented,
            "agents": agents,
            "previous_install": previous_install,
            "complete": consented and units == "ok" and not legacy
            and all(state == "ok" for state in links.values()) and not original["enabled"],
            "units": units,
            "links": links,
            "conflicts": conflicts,
            "legacy_copies": legacy,
            "wacli": {"path": str(self.wacli), "found": wacli_found},
            "zenity": ZENITY.is_file(),
            "original_plugin": original,
            "managed": (self.plugin_root / ".git").exists(),
            "plugin_root": str(self.plugin_root),
        }

    def _sync_instances(self) -> set[str]:
        """Every wacli-sync instance systemd knows about, loaded or only enabled."""
        names: set[str] = set()
        for arguments in (["list-units", "--all", "--no-legend", "--no-pager", "--plain",
                           "wacli-sync@*.service"],
                          ["list-unit-files", "--no-legend", "--no-pager", "--plain"]):
            result = self._systemctl_user(arguments, require_success=False)
            for line in (result.stdout or "").splitlines():
                fields = line.split()
                if fields and fields[0] == "●" and len(fields) > 1:
                    fields = fields[1:]
                if fields and SYNC_UNIT_NAME.fullmatch(fields[0]) and "@" in fields[0] \
                        and fields[0] != "wacli-sync@.service":
                    names.add(fields[0])
        return names

    def _apply_units(self, changed: bool, start_inactive: bool) -> None:
        """Enable, start and restart each account's unit as its settings say."""
        start_at_login = self._preferences().get("start_at_login") is not False
        closed = self._session_marker("closed").exists()
        accounts = self.accounts()
        desired = {account.unit for account in accounts if account.unit}
        if changed:
            for unit in sorted(self._sync_instances() - desired):
                self._systemctl_user(["disable", "--now", unit], require_success=False)
        for account in accounts:
            if not account.unit:
                continue
            with self._state_lock(self._lifecycle_lock_name(account)):
                if not self.online(account):
                    self._systemctl_user(["disable", "--now", account.unit], require_success=False)
                    continue
                self._systemctl_user(["enable" if start_at_login else "disable", account.unit],
                                     require_success=False)
                if self._unit_active(account.unit):
                    if changed:
                        # enable --now would not restart it; the new unit needs one.
                        self._systemctl_user(["restart", account.unit], require_success=False)
                elif start_inactive and not closed:
                    self._systemctl_user(["start", account.unit], require_success=False)

    def setup(self, agents: Any = None, replace_original: Any = False) -> dict[str, Any]:
        if agents is not None and not isinstance(agents, bool):
            raise OmaWhatsAppError("Letting agents use WhatsApp must be on or off.")
        if not isinstance(replace_original, bool):
            raise OmaWhatsAppError("Replacing OmaWhatsApp must be yes or no.")
        if not self.wacli.is_file() or not os.access(self.wacli, os.X_OK):
            raise OmaWhatsAppError("Install wacli first: omarchy pkg aur add wacli-bin")
        if self._wacli_too_old(self._wacli_version()):
            raise OmaWhatsAppError(
                f"wacli is older than {WACLI_MINIMUM_VERSION}; update it: omarchy pkg aur add wacli-bin")
        with self._state_lock("setup.lock"):
            before = self._preferences()["setup"]
            want_agents = before["agents"] if agents is None else agents
            original = self._original_plugin()
            if original["enabled"] and not replace_original:
                raise OmaWhatsAppError(
                    "OmaWhatsApp is still turned on. Let this app replace it, then try again.")
            links = self._setup_links(want_agents)
            blocked = [self._describe(link) + " belongs to something else"
                       for link, target in links.items()
                       if self._path_owner(link, target) == "foreign"]
            units = [self._describe_written(path, self._written_file_owner(path))
                     for path in self._unit_conflicts()]
            if blocked or units:
                raise OmaWhatsAppError(
                    "Setup stopped before changing anything: " + "; ".join(blocked + units)
                    + ". Move it away, then set up again."
                    + (" To change how background sync runs, use systemctl --user edit, "
                       "which keeps your changes in a separate file the app never touches."
                       if units else ""))
            for link, target in links.items():
                self._place_link(link, target)
            if not want_agents:
                for link, target in ((self.local_bin / "omawhatsapp-mcp",
                                      self.plugin_root / "bin" / "omawhatsapp-mcp"),
                                     (self.skill_link, self.plugin_root / "skills" / "omawhatsapp")):
                    if self._path_owner(link, target) not in {"ok", "ours"}:
                        continue
                    if link.is_symlink():
                        link.unlink()
                    else:
                        self._back_up(link)
            for name in LEGACY_HELPER_COPIES:
                copy = self.local_bin / name
                if self._is_own_copy(copy):
                    self._back_up(copy)
            changed = False
            for name in SETUP_UNITS:
                rendered = self._render_unit(name)
                installed = self.unit_dir / name
                current = installed.read_text(encoding="utf-8", errors="replace") \
                    if installed.is_file() and not installed.is_symlink() else None
                if current != rendered:
                    self._write_unit(name, rendered)
                    changed = True
            if changed:
                self._systemctl_user(["daemon-reload"])

            def consent(value: dict[str, Any]) -> None:
                value["setup"] = {"consented": True, "agents": want_agents}

            self._update_preferences(consent)
            self._apply_units(changed=changed, start_inactive=not before["consented"])
            if original["enabled"] and replace_original:
                self._run_omarchy(["plugin", "disable", ORIGINAL_PLUGIN_ID])
        return {"ok": True, "kind": "setup", "changed": changed, "setup": self._setup_state()}

    def teardown(self, confirm: Any) -> dict[str, Any]:
        """Undo the setup; the linked device, the archive and the settings stay."""
        if confirm != "remove":
            raise OmaWhatsAppError('Confirm by sending "remove".')
        removed: list[str] = []
        # Files it left because they were edited after the app wrote them, or
        # are not the app's; a unit left here keeps running as it is.
        kept: list[str] = []
        with self._state_lock("setup.lock"):
            owners = {name: self._written_file_owner(self.unit_dir / name)
                      for name in SETUP_UNITS}
            units = {account.unit for account in self.accounts() if account.unit}
            units |= self._sync_instances() | {SYNC_UNIT}
            for unit in sorted(units):
                template = re.sub(r"@.+\.service$", "@.service", unit)
                if owners.get(template) in {"ours", "missing"}:
                    self._systemctl_user(["disable", "--now", unit], require_success=False)
            for name in SETUP_UNITS:
                installed = self.unit_dir / name
                if owners[name] == "ours":
                    installed.unlink()
                    removed.append(str(installed))
                elif owners[name] != "missing":
                    kept.append(str(installed))
                folder = self.unit_dir / f"{name}.d"
                if folder.is_symlink() or not folder.is_dir():
                    continue
                dropin = folder / MEDIA_DROPIN
                owner = self._written_file_owner(dropin)
                if owner == "ours":
                    dropin.unlink()
                    removed.append(str(dropin))
                    if not any(folder.iterdir()):
                        folder.rmdir()
                elif owner != "missing":
                    kept.append(str(dropin))
            self._systemctl_user(["daemon-reload"], require_success=False)
            for link, target in self._setup_links(True).items():
                # Only a link into this app's folder; never a copy, a link
                # owned by something else, or a broken link that is not ours.
                if link.is_symlink() and self._path_owner(link, target) in {"ok", "ours"}:
                    link.unlink()
                    removed.append(str(link))

            def withdraw(value: dict[str, Any]) -> None:
                value["setup"] = dict(value["setup"], consented=False)

            self._update_preferences(withdraw)
        return {"ok": True, "kind": "teardown", "removed": removed, "kept": kept,
                "remove_command": f"omarchy plugin remove {PLUGIN_ID}"}

    def _run_omarchy(self, arguments: list[str]) -> None:
        if not OMARCHY.is_file():
            raise OmaWhatsAppError("The omarchy command was not found.")
        result = run_bounded([str(OMARCHY), *arguments], timeout=60,
                             stdout_limit=MAX_PROCESS_ERROR)
        if result.returncode != 0:
            raise OmaWhatsAppError(clean_error(result.stderr or result.stdout,
                                               "The omarchy command failed."))

    def _git(self, arguments: list[str], timeout: float) -> str:
        environment = dict(os.environ, GIT_TERMINAL_PROMPT="0", GIT_ASKPASS="/bin/false")
        result = subprocess.run([str(GIT), "-C", str(self.plugin_root), *arguments],
                                capture_output=True, text=True, timeout=timeout,
                                env=environment, check=False)
        if result.returncode != 0:
            raise OmaWhatsAppError(clean_error(result.stderr, "git could not read this copy."))
        return result.stdout.strip()

    def update_check(self) -> dict[str, Any]:
        """Whether the repository has a newer commit. Contacts GitHub only."""
        current = self._app_version(self.plugin_root)
        if not (self.plugin_root / ".git").exists() or not GIT.is_file():
            return {"ok": True, "kind": "update-check", "managed": False,
                    "current": current, "available": False}
        try:
            local = self._git(["rev-parse", "HEAD"], 10)
            remote = self._git(["ls-remote", "origin", "HEAD"], 30).split()
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise OmaWhatsAppError("Could not reach the repository to check for updates.") from exc
        remote_commit = remote[0] if remote and re.fullmatch(r"[0-9a-f]{40}", remote[0]) else ""
        if not re.fullmatch(r"[0-9a-f]{40}", local) or not remote_commit:
            raise OmaWhatsAppError("The repository answered in an unexpected way.")
        # A commit this copy already contains (the repository is behind it,
        # or this is a development checkout) is not an update.
        available = remote_commit != local
        if available:
            try:
                self._git(["merge-base", "--is-ancestor", remote_commit, local], 10)
                available = False
            except OmaWhatsAppError:
                pass
        return {"ok": True, "kind": "update-check", "managed": True, "current": current,
                "commit": local, "remote_commit": remote_commit, "available": available}

    def self_update(self) -> int:
        """Run in a terminal: omarchy plugin update, then restart the shell."""
        if not (self.plugin_root / ".git").exists():
            print("This copy was not installed with omarchy plugin add; update it from its source.")
            return 1
        before = self._git(["rev-parse", "HEAD"], 10)
        result = subprocess.run([str(OMARCHY), "plugin", "update", PLUGIN_ID], check=False)
        if result.returncode != 0:
            return result.returncode
        if self._git(["rev-parse", "HEAD"], 10) == before:
            return 0
        print("Restarting the Omarchy shell to load the new version…")
        return subprocess.run([str(OMARCHY), "restart", "shell"], check=False).returncode

    def _sync_active(self, account: Account | None = None) -> bool:
        unit = (account or self.active).unit
        return bool(unit) and self._unit_active(unit)

    def _systemctl_user(
        self, parts: Sequence[str], *, require_success: bool = True
    ) -> subprocess.CompletedProcess[str]:
        try:
            result = run_bounded(
                [str(SYSTEMCTL), "--user", *parts],
                timeout=20,
                stdout_limit=16 * 1024,
                stderr_limit=MAX_PROCESS_ERROR,
            )
        except ProcessOutputLimitExceeded as exc:
            raise OmaWhatsAppError("Background sync returned too much output.") from exc
        except subprocess.TimeoutExpired as exc:
            raise OmaWhatsAppError("Background sync took too long to respond.") from exc
        except OSError as exc:
            raise OmaWhatsAppError("Background sync could not be controlled.") from exc
        if require_success and result.returncode != 0:
            raise OmaWhatsAppError(clean_error(
                result.stderr, "Background sync could not be controlled."
            ))
        return result

    def _unit_active(self, unit: str) -> bool:
        try:
            return self._systemctl_user(
                ["is-active", "--quiet", unit], require_success=False
            ).returncode == 0
        except OmaWhatsAppError:
            return False

    def _yield_active_sync(self, account: Account) -> bool:
        """Stop an active unit under its lifecycle lock, leaving crash intent."""
        if not self._sync_active(account):
            return False
        self._record_lifecycle_recovery(account)
        try:
            self._systemctl_user(["stop", account.unit])
        except BaseException:
            # A failed systemctl request is ambiguous. Only discard recovery
            # intent when systemd positively confirms the unit stayed active.
            if self._unit_active(account.unit):
                self._clear_lifecycle_recovery(account.unit)
            raise
        return True

    def _restore_yielded_sync(self, account: Account, yielded: bool) -> None:
        """Restore a yielded unit and clear its durable crash intent."""
        if not yielded:
            return
        self._systemctl_user(["start", account.unit])
        self._clear_lifecycle_recovery(account.unit)

    def _run_after_sync_yield(
        self,
        args: list[str],
        *,
        timeout: float,
        stdout_limit: int = MAX_WACLI_OUTPUT,
        stderr_limit: int = MAX_PROCESS_ERROR,
        account: Any = ACTIVE_ACCOUNT,
    ) -> subprocess.CompletedProcess[str]:
        """Run after stopping sync, tolerating its bounded lock-release delay."""
        result: subprocess.CompletedProcess[str] | None = None
        for attempt in range(5):
            result = self._run(
                args, timeout=timeout, stdout_limit=stdout_limit,
                stderr_limit=stderr_limit, account=account,
            )
            if not self._locked(result) or attempt == 4:
                return result
            time.sleep(0.15)
        raise AssertionError("bounded retry loop did not return")

    def _mutate(
        self,
        args: list[str],
        *,
        timeout: float,
        require_online: bool,
        stdout_limit: int = MAX_WACLI_OUTPUT,
        stderr_limit: int = MAX_PROCESS_ERROR,
        account: Any = ACTIVE_ACCOUNT,
    ) -> subprocess.CompletedProcess[str]:
        lifecycle_account = (
            self.active if account is ACTIVE_ACCOUNT or account is None else account
        )
        if not isinstance(lifecycle_account, Account):
            raise OmaWhatsAppError("Choose a valid wacli account for this operation.")
        if require_online and not self.online(lifecycle_account):
            raise OmaWhatsAppError(
                "Offline mode is on. Go online before connecting to or changing WhatsApp."
            )
        # wacli delegates supported mutations to sync --follow's companion socket.
        result = self._run(
            args, timeout=timeout, stdout_limit=stdout_limit,
            stderr_limit=stderr_limit, account=account,
        )
        if not self._locked(result):
            return result
        with self._state_lock(self._lifecycle_lock_name(lifecycle_account)):
            if require_online and not self.online(lifecycle_account):
                raise OmaWhatsAppError(
                    "Offline mode is on. Go online before connecting to or changing WhatsApp."
                )
            result = self._run(
                args, timeout=timeout, stdout_limit=stdout_limit,
                stderr_limit=stderr_limit, account=account,
            )
            if not self._locked(result):
                return result
            active = self._yield_active_sync(lifecycle_account)
            operation_error: BaseException | None = None
            try:
                result = self._run_after_sync_yield(
                    args, timeout=timeout, stdout_limit=stdout_limit,
                    stderr_limit=stderr_limit, account=account,
                )
            except BaseException as exc:
                operation_error = exc
            restart_error: OmaWhatsAppError | None = None
            if active:
                try:
                    self._restore_yielded_sync(lifecycle_account, active)
                except OmaWhatsAppError as exc:
                    restart_error = exc
            if restart_error is not None:
                if operation_error is None and result.returncode == 0 \
                        and not self._locked(result):
                    raise OmaWhatsAppPartialError(
                        "The WhatsApp action completed, but background sync could not restart.",
                        {"kind": "lifecycle", "committed": True,
                         "account": lifecycle_account.name},
                    ) from restart_error
                raise OmaWhatsAppPartialError(
                    "The WhatsApp request failed, and background sync could not restart.",
                    {"kind": "lifecycle", "committed": False,
                     "account": lifecycle_account.name},
                ) from restart_error
            if operation_error is not None:
                raise operation_error
            return result
        return result

    def _write(self, args: list[str], *, timeout: float) -> subprocess.CompletedProcess[str]:
        return self._mutate(
            args, timeout=timeout, require_online=True
        )

    def _profile_picture_metadata(
        self, account: Account, candidates: list[dict[str, str]],
    ) -> tuple[list[dict[str, Any]], list[str]]:
        """Fetch one account batch while yielding its sync service only once."""
        output: list[dict[str, Any]] = []
        failed: list[str] = []
        if not self.online(account):
            return output, [candidate["key"] for candidate in candidates]
        with self._state_lock(self._lifecycle_lock_name(account)):
            if not self.online(account):
                return output, [candidate["key"] for candidate in candidates]
            active = self._yield_active_sync(account)
            operation_error: BaseException | None = None
            started = time.monotonic()
            try:
                for candidate in candidates:
                    if time.monotonic() - started >= AVATAR_BATCH_SECONDS:
                        break
                    args = ["--json", "profile", "picture-info", "--jid",
                            candidate["jid"], "--preview"]
                    if candidate["picture_id"]:
                        args.extend(["--existing-id", candidate["picture_id"]])
                    try:
                        result = self._run_after_sync_yield(
                            args, timeout=20, account=account
                        )
                        envelope = self._envelope(result)
                        data = envelope.get("data")
                        if not isinstance(data, dict):
                            raise OmaWhatsAppError(
                                "WhatsApp returned invalid profile-photo metadata."
                            )
                        output.append({
                            "key": candidate["key"],
                            "picture_id": str(
                                data.get("id") or candidate["picture_id"]
                            ),
                            "url": str(data.get("url") or ""),
                            "unchanged": data.get("unchanged") is True,
                        })
                    except OmaWhatsAppError:
                        failed.append(candidate["key"])
            except BaseException as exc:
                operation_error = exc
            try:
                self._restore_yielded_sync(account, active)
            except OmaWhatsAppError as exc:
                raise OmaWhatsAppPartialError(
                    "Profile photos were checked, but background sync could not restart.",
                    {"kind": "lifecycle", "committed": False,
                     "account": account.name},
                ) from exc
            if operation_error is not None:
                raise operation_error
        return output, failed

    def _doctor(self, account: Account | None = None) -> dict[str, Any]:
        result = self._run(
            ["--read-only", "--json", "doctor"],
            timeout=8,
            account=account or self.active,
        )
        try:
            envelope = json.loads(result.stdout or "{}")
        except json.JSONDecodeError:
            return {}
        data = envelope.get("data") if isinstance(envelope, dict) else None
        return data if isinstance(data, dict) else {}

    def _doctor_cached(self, account: Account) -> dict[str, Any]:
        """The status poll's doctor, reused for a minute while all is well.

        Status runs every 12 seconds and doctor opens the WhatsApp session
        store each time; during a pairing that contention delayed the contact
        sync. A healthy, authenticated answer is kept for DOCTOR_CACHE_TTL;
        anything else is asked again at once, so a logout or a fresh link
        still shows up on the next poll.
        """
        now = int(time.time())
        key = hashlib.sha256(account.key.encode("utf-8")).hexdigest()[:24]
        cache = self._read_state_json(DOCTOR_CACHE_FILE, MAX_DOCTOR_CACHE, {})
        item = cache.get(key) if isinstance(cache, dict) else None
        if isinstance(item, dict) and 0 <= now - bounded_int(item.get("at"), 0, 0, 2**63 - 1) \
                < DOCTOR_CACHE_TTL and isinstance(item.get("doctor"), dict):
            return dict(item["doctor"])
        doctor = self._doctor(account)
        if doctor.get("authenticated") is True and not doctor.get("store_error"):
            kept = {name: doctor.get(name) for name in
                    ("authenticated", "fts_enabled", "store_dir", "linked_jid") if name in doctor}
            try:
                with self._state_lock("doctor-cache.lock"):
                    current = self._read_state_json(DOCTOR_CACHE_FILE, MAX_DOCTOR_CACHE, {})
                    current = current if isinstance(current, dict) else {}
                    current[key] = {"at": now, "doctor": kept}
                    self._write_state_json(DOCTOR_CACHE_FILE,
                                           dict(list(current.items())[-MAX_ACCOUNTS:]),
                                           MAX_DOCTOR_CACHE)
            except (OmaWhatsAppError, OSError):
                pass
        return doctor

    def _database(
        self,
        doctor: dict[str, Any] | None = None,
        account: Account | None = None,
    ) -> Path:
        discovered = str((doctor or {}).get("store_dir") or "").strip()
        candidate = Path(discovered).expanduser() if discovered else None
        store = candidate if candidate is not None and candidate.is_absolute() \
            else (account or self.active).store_dir
        return store / "wacli.db"

    def _connect(self) -> sqlite3.Connection:
        database = self._database()
        if not database.is_file():
            raise OmaWhatsAppError("WhatsApp has not synced yet.")
        connection = sqlite3.connect(
            f"file:{quote(str(database), safe='/')}?mode=ro", uri=True, timeout=1
        )
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA query_only = ON")
        return connection

    @staticmethod
    def _like(value: str) -> str:
        return "%" + value.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"

    @staticmethod
    def _chat_name_sql() -> str:
        # A person's chat shows the name saved in the phone's address book,
        # as the phone does; wacli can overwrite chats.name with a push name.
        return """COALESCE(
          NULLIF(CASE WHEN chats.jid GLOB '*@s.whatsapp.net' THEN contacts.full_name END, ''),
          NULLIF(chats.name, ''), NULLIF(groups.name, ''),
          NULLIF(contacts.business_name, ''), NULLIF(contacts.full_name, ''),
          NULLIF(contacts.push_name, ''), NULLIF(contacts.system_name, ''),
          NULLIF(latest.chat_name, ''), 'WhatsApp chat')"""

    def _chat(self, jid: str) -> dict[str, str]:
        target = jid.strip()
        if not target or len(target) > 160:
            raise OmaWhatsAppError("Choose a WhatsApp chat first.")
        name_sql = self._chat_name_sql()
        try:
            with closing(self._connect()) as connection:
                row = connection.execute(
                    f"""
                    SELECT chats.jid, {chat_kind_sql()} AS kind, {name_sql} AS name
                    FROM chats
                    LEFT JOIN groups ON groups.jid = chats.jid
                    LEFT JOIN contacts ON contacts.jid = chats.jid
                    LEFT JOIN messages AS latest ON latest.rowid = (
                      SELECT rowid FROM messages WHERE chat_jid = chats.jid
                      ORDER BY ts DESC, rowid DESC LIMIT 1)
                    WHERE chats.jid = ? AND {SUPPORTED_CHAT_WHERE}
                    """,
                    [target],
                ).fetchone()
        except sqlite3.Error as exc:
            raise OmaWhatsAppError("The local WhatsApp index could not be read.") from exc
        if row is None:
            raise OmaWhatsAppError("That chat is not available in the local WhatsApp index.")
        return {"jid": str(row["jid"]), "name": str(row["name"]), "kind": str(row["kind"])}

    def _lid_aliases(self) -> dict[str, str]:
        """@lid chat JID -> phone chat JID for this account, cached for good."""
        try:
            with closing(self._connect()) as connection:
                lids = [str(row[0]) for row in connection.execute(
                    "SELECT DISTINCT chat_jid FROM messages WHERE chat_jid GLOB '*@lid' LIMIT ?",
                    [MAX_LID_ALIASES]).fetchall()]
        except (sqlite3.Error, OmaWhatsAppError):
            return {}
        if not lids:
            return {}
        key = hashlib.sha256(self.active.key.encode("utf-8")).hexdigest()[:24]
        cache = self._read_state_json(LID_ALIASES_FILE, MAX_LID_ALIASES_STATE, {})
        cache = cache if isinstance(cache, dict) else {}
        known = cache.get(key) if isinstance(cache.get(key), dict) else {}
        aliases = {lid: str(known[lid]) for lid in lids
                   if isinstance(known.get(lid), str) and known[lid].endswith("@s.whatsapp.net")}
        missing = [lid for lid in lids if lid not in known]
        if not missing:
            return aliases
        learned = dict(known)
        for lid in missing[:16]:
            phone_jid = ""
            try:
                result = self._run(["--read-only", "--json", "contacts", "show", "--jid", lid],
                                   timeout=8)
                data = json.loads(result.stdout or "{}").get("data")
                candidate = str((data or {}).get("jid") or "") if isinstance(data, dict) else ""
                if re.fullmatch(r"[0-9]{5,20}@s\.whatsapp\.net", candidate):
                    phone_jid = candidate
            except (OmaWhatsAppError, ValueError, AttributeError):
                continue
            # An unresolved @lid is remembered as "" so it is not asked again
            # on every refresh; wacli's next sync start may still migrate it.
            learned[lid] = phone_jid
            if phone_jid:
                aliases[lid] = phone_jid
        try:
            with self._state_lock("lid-aliases.lock"):
                current = self._read_state_json(LID_ALIASES_FILE, MAX_LID_ALIASES_STATE, {})
                current = current if isinstance(current, dict) else {}
                current[key] = dict(list(learned.items())[-MAX_LID_ALIASES:])
                self._write_state_json(LID_ALIASES_FILE, current, MAX_LID_ALIASES_STATE)
        except (OmaWhatsAppError, OSError):
            pass
        return aliases

    def _chat_jids(self, jid: str) -> list[str]:
        """A phone chat and the @lid chats wacli filed some of its rows under."""
        if not jid.endswith("@s.whatsapp.net"):
            return [jid]
        return [jid] + sorted(lid for lid, phone in self._lid_aliases().items() if phone == jid)

    def _chat_any(self, jid: str) -> dict[str, str]:
        target = jid.strip()
        if not target or len(target) > 160:
            raise OmaWhatsAppError("Choose an exact locally indexed chat first.")
        try:
            with closing(self._connect()) as connection:
                row = connection.execute(
                    f"SELECT jid, {chat_kind_sql()} AS kind, "
                    "COALESCE(NULLIF(name, ''), 'WhatsApp chat') AS name "
                    "FROM chats WHERE jid = ?",
                    [target],
                ).fetchone()
        except sqlite3.Error as exc:
            raise OmaWhatsAppError("The local WhatsApp index could not be read.") from exc
        if row is None:
            raise OmaWhatsAppError(
                "That target is not an exact chat in the local WhatsApp index."
            )
        return {"jid": str(row["jid"]), "name": str(row["name"]), "kind": str(row["kind"])}

    def _message_any(self, jid: str, message_id: str) -> None:
        chat = self._chat_any(jid)
        target = message_id.strip()
        if not target or len(target) > 256:
            raise OmaWhatsAppError("Choose one exact locally indexed message ID.")
        try:
            with closing(self._connect()) as connection:
                row = connection.execute(
                    "SELECT 1 FROM messages WHERE chat_jid = ? AND msg_id = ? "
                    "AND deleted_at IS NULL AND COALESCE(reaction_to_id, '') = ''",
                    [chat["jid"], target],
                ).fetchone()
        except sqlite3.Error as exc:
            raise OmaWhatsAppError("The local WhatsApp index could not be read.") from exc
        if row is None:
            raise OmaWhatsAppError("That message is not available in the exact target chat.")

    def _contact_any(self, jid: str) -> None:
        target = jid.strip()
        if not target or len(target) > 160 or "@" not in target:
            raise OmaWhatsAppError("Choose one exact locally indexed contact JID.")
        try:
            with closing(self._connect()) as connection:
                row = connection.execute(
                    "SELECT 1 FROM contacts WHERE jid = ?", [target]
                ).fetchone()
        except sqlite3.Error as exc:
            raise OmaWhatsAppError("The local WhatsApp index could not be read.") from exc
        if row is None:
            raise OmaWhatsAppError("That contact is not available in the local WhatsApp index.")

    def _group_participant(self, group_jid: str, user_jid: str) -> None:
        target = user_jid.strip()
        if not target or len(target) > 160 or "@" not in target:
            raise OmaWhatsAppError("Choose one exact locally indexed participant JID.")
        try:
            with closing(self._connect()) as connection:
                row = connection.execute(
                    "SELECT 1 FROM group_participants WHERE group_jid = ? AND user_jid = ?",
                    [group_jid, target],
                ).fetchone()
        except sqlite3.Error as exc:
            raise OmaWhatsAppError("Group participants could not be read from the local index.") from exc
        if row is None:
            raise OmaWhatsAppError("That participant is not indexed in the exact target group.")

    def status(self) -> dict[str, Any]:
        if not self.wacli.is_file() or not os.access(self.wacli, os.X_OK):
            return {"ok": False, "installed": False, "authenticated": False,
                    "sync_active": False, "helper_version": HELPER_VERSION,
                    "setup": self._setup_state(),
                    "error": "wacli is not installed."}
        # Nothing installs wacli with the app, so its minimum is checked here.
        wacli_version = self._wacli_version()
        if self._wacli_too_old(wacli_version):
            return {"ok": False, "installed": True, "wacli_too_old": True,
                    "wacli_version": wacli_version, "authenticated": False,
                    "sync_active": False, "helper_version": HELPER_VERSION,
                    "setup": self._setup_state(),
                    "error": f"wacli {wacli_version} is older than {WACLI_MINIMUM_VERSION}; "
                             "update it: omarchy pkg aur add wacli-bin"}
        preferences = self._preferences()
        active = self.active
        accounts = self.accounts()

        def report(account: Account) -> dict[str, Any]:
            # Account is explicit all the way down: parallel probes must never
            # race through Backend._active or borrow another private store.
            doctor_error = ""
            try:
                doctor = self._doctor_cached(account)
            except OmaWhatsAppError as exc:
                doctor = {}
                doctor_error = clean_error(
                    exc, "That account could not be inspected."
                )
            authenticated = doctor.get("authenticated") is True
            state = self._account_state(preferences, account)
            online = state.get("online") is not False
            return {
                "account": account.name,
                "label": account.label,
                "store": account.key,
                "unit": account.unit,
                "default": account.default,
                "main": account.selector in {"implicit", "store"},
                "active": account.key == active.key,
                "authenticated": authenticated,
                "sync_active": self._sync_active(account),
                "online": online,
                "offline_mode": not online,
                "send_read_receipts": state.get("send_read_receipts") is True,
                "signature": self._signature(state.get("signature")),
                "notifications_muted": state.get("notifications_muted") is True,
                "fts_enabled": doctor.get("fts_enabled") is True,
                "database_ready": self._database(doctor, account).is_file(),
                "error": doctor_error or (
                    clean_error(doctor.get("store_error"), "")
                    if authenticated else ""
                ),
            }

        # Ordered map preserves configuration order while bounding a status
        # refresh to one doctor window instead of one window per account.
        if len(accounts) == 1:
            reports = [report(accounts[0])]
        else:
            from concurrent.futures import ThreadPoolExecutor
            with ThreadPoolExecutor(max_workers=min(len(accounts), 4)) as executor:
                reports = list(executor.map(report, accounts))
        current = next(report for report in reports if report["active"])
        return {
            "ok": True,
            "installed": True,
            "helper_version": HELPER_VERSION,
            "wacli_version": wacli_version,
            "setup": self._setup_state(preferences),
            # The rail is unified, but writes and receipts belong to the
            # selected account. Expose both invariants explicitly instead of
            # letting one account's readiness authorize another account.
            "authenticated": current["authenticated"],
            "database_ready": current["database_ready"],
            "any_authenticated": any(
                report["authenticated"] for report in reports
            ),
            "any_database_ready": any(
                report["database_ready"] for report in reports
            ),
            "rail_ready": any(
                report["authenticated"] and report["database_ready"]
                for report in reports
            ),
            "sync_active": current["sync_active"],
            "online": current["online"],
            "offline_mode": current["offline_mode"],
            "account": active.name,
            "accounts": reports,
            "notifications": preferences["notifications"],
            "notify_available": self._notify_send_ready(),
            "send_read_receipts": current["send_read_receipts"],
            "signature": current["signature"],
            "show_unread_count": preferences.get("show_unread_count") is not False,
            "check_updates_on_launch": preferences.get("check_updates_on_launch") is True,
            "start_at_login": preferences.get("start_at_login") is not False,
            # Quit, or not started because it does not start with the system.
            "closed": self._closed(preferences, reports),
            "dropdown_rows": preferences.get("dropdown_rows", 7),
            "composer_max_lines": preferences.get("composer_max_lines", 6),
            "time_format": preferences.get("time_format", "auto"),
            **{name: ui_preference(preferences, name) for name in UI_PREFERENCES},
            "auto_download_media": self.auto_download_media(),
            "fts_enabled": current["fts_enabled"],
            "error": current["error"],
        }

    @staticmethod
    def _avatar_key(account: Account, jid: str) -> str:
        return hashlib.sha256(
            f"{account.key}\n{jid}".encode("utf-8")
        ).hexdigest()

    def _attach_cached_avatars(
        self, chats: list[dict[str, Any]], accounts: list[Account]
    ) -> None:
        if self.avatar_cache is None:
            return
        by_name = {account.name: account for account in accounts}
        keyed: list[tuple[dict[str, Any], str]] = []
        for chat in chats:
            account = by_name.get(str(chat.get("account") or ""))
            if account is None:
                continue
            keyed.append((chat, self._avatar_key(account, str(chat.get("jid") or ""))))
        paths = self.avatar_cache.paths([key for _, key in keyed])
        for chat, key in keyed:
            chat["avatar_path"] = paths.get(key, "")

    def refresh_avatars(
        self, authorization: Any, limit: Any = AVATAR_REFRESH_LIMIT
    ) -> dict[str, Any]:
        """Refresh a bounded set of recent chat photos after an explicit click."""
        if str(authorization or "") != "remote-read":
            raise OmaWhatsAppError(
                "Refreshing profile photos requires authorization='remote-read'."
            )
        if self.avatar_cache is None or fetch_https_image is None:
            raise OmaWhatsAppError(
                "The profile-photo cache module is not installed. Re-run the installer."
            )
        with self._state_lock("avatars-refresh.lock"):
            return self._refresh_avatars(limit)

    def _refresh_avatars(self, limit: Any) -> dict[str, Any]:
        """Run one serialized metadata/download/cache refresh."""
        self.avatar_cache.prune()
        bounded = bounded_int(limit, AVATAR_REFRESH_LIMIT, 1, AVATAR_REFRESH_LIMIT)
        accounts = self.accounts()
        by_name = {account.name: account for account in accounts}
        rows = self.chats(limit=500)["chats"]
        candidates: list[dict[str, str]] = []
        keys: list[str] = []
        for row in rows:
            account = by_name.get(str(row.get("account") or ""))
            if account is None:
                continue
            key = self._avatar_key(account, str(row.get("jid") or ""))
            keys.append(key)
            candidates.append({
                "key": key, "jid": str(row.get("jid") or ""),
                "account": account.name, "picture_id": "",
            })
        entries = self.avatar_cache.entries(keys)
        cached_paths = self.avatar_cache.paths(keys)
        now = int(time.time())
        due: list[dict[str, str]] = []
        for candidate in candidates:
            entry = entries.get(candidate["key"], {})
            candidate["picture_id"] = str(entry.get("picture_id") or "")
            checked = bounded_int(entry.get("checked_at"), 0, 0, 2**63 - 1)
            retry_after = bounded_int(entry.get("retry_after"), 0, 0, 2**63 - 1)
            ttl = AVATAR_MISSING_TTL if entry.get("missing") is True \
                else AVATAR_REFRESH_TTL
            has_file = candidate["key"] in cached_paths
            if entry.get("missing") is not True and not has_file:
                candidate["picture_id"] = ""
            if retry_after <= now and (
                    checked <= 0 or now - checked >= ttl
                    or (entry.get("missing") is not True and not has_file)):
                due.append(candidate)
        due_total = len(due)
        due = due[:bounded]

        grouped: dict[str, list[dict[str, str]]] = {}
        for candidate in due:
            grouped.setdefault(candidate["account"], []).append(candidate)
        metadata: list[dict[str, Any]] = []
        failed_keys: list[str] = []
        batches = [(by_name[name], values) for name, values in grouped.items()]
        if batches:
            from concurrent.futures import ThreadPoolExecutor
            with ThreadPoolExecutor(max_workers=min(4, len(batches))) as pool:
                results = pool.map(
                    lambda batch: self._profile_picture_metadata(*batch), batches
                )
                for records, account_failed in results:
                    metadata.extend(records)
                    failed_keys.extend(account_failed)

        updates: list[dict[str, Any]] = []
        downloads: list[dict[str, Any]] = []
        unchanged = 0
        missing = 0
        for key in failed_keys:
            previous = entries.get(key, {})
            updates.append({
                "key": key,
                "picture_id": str(previous.get("picture_id") or ""),
                "checked_at": bounded_int(previous.get("checked_at"), 0, 0, 2**63 - 1),
                "retry_after": now + AVATAR_FAILURE_BACKOFF,
                "missing": previous.get("missing") is True,
            })
        for item in metadata:
            if item["unchanged"]:
                unchanged += 1
                updates.append({
                    "key": item["key"], "picture_id": item["picture_id"],
                    "checked_at": now, "missing": False,
                })
            elif item["url"]:
                downloads.append(item)
            else:
                missing += 1
                updates.append({
                    "key": item["key"], "picture_id": item["picture_id"],
                    "checked_at": now, "missing": True,
                })

        refreshed = 0
        if downloads:
            from concurrent.futures import ThreadPoolExecutor
            with ThreadPoolExecutor(max_workers=min(4, len(downloads))) as pool:
                futures = [(item, pool.submit(fetch_https_image, item["url"]))
                           for item in downloads]
                for item, future in futures:
                    try:
                        image = future.result()
                    except AvatarCacheError:
                        failed_keys.append(item["key"])
                        previous = entries.get(item["key"], {})
                        updates.append({
                            "key": item["key"],
                            "picture_id": str(previous.get("picture_id") or ""),
                            "checked_at": bounded_int(
                                previous.get("checked_at"), 0, 0, 2**63 - 1
                            ),
                            "retry_after": now + AVATAR_FAILURE_BACKOFF,
                            "missing": previous.get("missing") is True,
                        })
                        continue
                    refreshed += 1
                    updates.append({
                        "key": item["key"], "picture_id": item["picture_id"],
                        "checked_at": now, "missing": False, "data": image,
                    })
        try:
            if updates:
                self.avatar_cache.update(updates)
        except AvatarCacheError as exc:
            raise OmaWhatsAppError(str(exc)) from exc
        cached = len(self.avatar_cache.paths(keys))
        processed = len(metadata) + len(failed_keys)
        return {
            "ok": True, "kind": "avatars", "checked": processed,
            "pending": max(0, due_total - processed),
            "refreshed": refreshed, "unchanged": unchanged,
            "missing": missing, "failed": len(failed_keys), "cached": cached,
        }

    @staticmethod
    def _preview_sql(table: str) -> str:
        # A deleted message never shows its old words, as on the phone.
        return f"""CASE WHEN {revoked_sql(table)} THEN
                        CASE WHEN {table}.from_me = 1 THEN 'You deleted this message'
                          ELSE 'This message was deleted' END
                      WHEN COALESCE({table}.media_type, '') <> '' THEN
                        COALESCE(NULLIF(CASE WHEN {table}.media_type = 'audio'
                            AND {table}.text = '[Audio]' THEN '' ELSE {table}.text END, ''),
                          NULLIF({table}.media_caption, ''),
                          NULLIF({table}.filename, ''), '[' || {table}.media_type || ']')
                      ELSE COALESCE(NULLIF({table}.text, ''),
                        NULLIF({table}.display_text, ''), '') END"""

    def _account_chats(
        self, cleaned: str, limit: int, preferences: dict[str, Any]
    ) -> list[dict[str, Any]]:
        """Read one account's chat rail. The caller owns account selection."""
        name_sql = self._chat_name_sql()
        preview_sql = self._preview_sql("latest")
        where = SUPPORTED_CHAT_WHERE
        parameters: list[Any] = []
        if cleaned:
            where += f" AND LOWER({name_sql}) LIKE LOWER(?) ESCAPE '\\'"
            parameters.append(self._like(cleaned))
        parameters.append(limit)
        try:
            with closing(self._connect()) as connection:
                votes = (f"AND NOT {poll_vote_sql('messages')}"
                         if self._has_table(connection, "polls") else "")
                rows = connection.execute(
                    f"""
                    SELECT chats.jid, {chat_kind_sql()} AS kind, chats.last_message_ts, chats.archived,
                      chats.pinned, chats.muted_until, chats.unread_count,
                      chats.unread AS unread_flag,
                      {name_sql} AS name,
                      {preview_sql} AS preview,
                      COALESCE(latest.msg_id, '') AS last_message_id,
                      COALESCE(latest.media_type, '') AS last_media_type,
                      COALESCE(latest.from_me, 0) AS last_from_me,
                      COALESCE(latest.sender_name, '') AS last_sender
                    FROM chats
                    LEFT JOIN groups ON groups.jid = chats.jid
                    LEFT JOIN contacts ON contacts.jid = chats.jid
                    LEFT JOIN messages AS latest ON latest.rowid = (
                      SELECT rowid FROM messages WHERE chat_jid = chats.jid
                        AND (deleted_at IS NULL OR {revoked_sql("messages")})
                        AND COALESCE(reaction_to_id, '') = ''
                        AND ({revoked_sql("messages")} OR NOT {synthetic_message_sql("messages")})
                        {votes}
                      ORDER BY ts DESC, rowid DESC LIMIT 1)
                    WHERE {where}
                    ORDER BY chats.pinned DESC, chats.last_message_ts DESC, name COLLATE NOCASE
                    LIMIT ?
                    """,
                    parameters,
                ).fetchall()
                # Before wacli 0.19 (store migration 27), wacli counted every
                # new incoming row as unread, including reactions and payloads
                # it cannot decode ("(message)"); those are subtracted here.
                # From 0.19 its count already leaves them out, so subtracting
                # again would hide real messages. Either way a reply from
                # another device does not always clear the count, and the
                # phone treats a reply as reading the chat.
                last_delivery = self._delivery_status(connection, [
                    (str(row["jid"]), str(row["last_message_id"]))
                    for row in rows if bool(row["last_from_me"]) and row["last_message_id"]])
                accurate_counts = self._store_schema_version(connection) >= 27
                # wacli builds that record mentions (fork migration 1029) mark
                # a chat whose unread messages @mention this account.
                has_mentions = self._has_table(connection, "message_mentions")
                mentioned: dict[str, bool] = {}
                real_unread: dict[str, int] = {}
                synthetic = synthetic_message_sql("messages")
                for row in rows:
                    count = int(row["unread_count"] or 0)
                    if count <= 0:
                        continue
                    jid = str(row["jid"])
                    phantom, mine = connection.execute(
                        f"""
                        SELECT
                          (SELECT COUNT(*) FROM (
                             SELECT reaction_to_id, text, display_text, media_type,
                               media_caption, filename
                             FROM messages
                             WHERE chat_jid = ? AND from_me = 0 AND deleted_at IS NULL
                             ORDER BY ts DESC, rowid DESC LIMIT ?) AS messages
                           WHERE COALESCE(messages.reaction_to_id, '') <> ''
                             OR {synthetic}),
                          (SELECT MAX(ts) FROM messages WHERE chat_jid = ? AND from_me = 1)
                        """,
                        [jid, min(count, 999), jid],
                    ).fetchone()
                    remaining = count if accurate_counts else max(0, count - int(phantom or 0))
                    if mine is not None:
                        # Everything after your own last message is stored, so
                        # that bound never undercounts.
                        after = connection.execute(
                            f"""SELECT COUNT(*) FROM messages WHERE chat_jid = ?
                                AND from_me = 0 AND deleted_at IS NULL AND ts > ?
                                AND COALESCE(reaction_to_id, '') = '' AND NOT {synthetic}""",
                            [jid, int(mine)],
                        ).fetchone()[0]
                        remaining = min(remaining, int(after or 0))
                    real_unread[jid] = remaining
                    if has_mentions and remaining > 0:
                        mentioned[jid] = connection.execute(
                            """SELECT EXISTS(SELECT 1 FROM (
                                 SELECT msg_id FROM messages
                                 WHERE chat_jid = ? AND from_me = 0 AND deleted_at IS NULL
                                 ORDER BY ts DESC, rowid DESC LIMIT ?) AS recent
                               JOIN message_mentions ON message_mentions.chat_jid = ?
                                 AND message_mentions.msg_id = recent.msg_id
                                 AND message_mentions.is_self = 1)""",
                            [jid, min(remaining, 999), jid],
                        ).fetchone()[0] == 1
        except sqlite3.Error as exc:
            raise OmaWhatsAppError("The local WhatsApp index could not be read.") from exc
        account = self.active
        acknowledged = self._account_state(preferences)["acknowledged_unread"]
        chats: list[dict[str, Any]] = []
        for row in rows:
            jid = str(row["jid"])
            timestamp = int(row["last_message_ts"] or 0)
            unread = real_unread.get(jid, 0)
            # "Mark as unread" on the phone (or here) sets only the flag, with
            # no count; it counts as one, the way WhatsApp shows a dot.
            if int(row["unread_count"] or 0) <= 0 and bool(row["unread_flag"]):
                unread = 1
            archived = bool(row["archived"])
            muted = muted_until_active(row["muted_until"])
            notification_unread = unread
            snapshot = acknowledged.get(jid) if isinstance(acknowledged, dict) else None
            if isinstance(snapshot, dict):
                acknowledged_at = int(snapshot.get("timestamp") or 0)
                acknowledged_count = int(snapshot.get("unread") or 0)
                if timestamp <= acknowledged_at or bool(row["last_from_me"]):
                    notification_unread = 0
                elif unread > 0:
                    notification_unread = max(1, unread - acknowledged_count)
            if archived or muted:
                notification_unread = 0
            chats.append({
                "jid": jid, "name": str(row["name"]),
                "kind": str(row["kind"] or "unknown"),
                "account": account.name,
                "account_label": account.label,
                "timestamp": timestamp,
                "last_message_id": str(row["last_message_id"] or "")[:256],
                "last_media_type": str(row["last_media_type"] or "")[:32],
                "preview": " ".join(contact_preview(str(row["preview"] or "")).split())[:512],
                "last_from_me": bool(row["last_from_me"]),
                "last_status": last_delivery.get((jid, str(row["last_message_id"] or "")), ""),
                "last_sender": " ".join(str(row["last_sender"] or "").split())[:MAX_NOTIFY_SENDER],
                "archived": archived, "pinned": bool(row["pinned"]),
                "muted": muted,
                "unread": unread,
                "notification_unread": notification_unread,
                "mentioned": bool(mentioned.get(jid)) and unread > 0,
            })
        self._fold_lid_latest(chats)
        return chats

    def _fold_lid_latest(self, chats: list[dict[str, Any]]) -> None:
        """A row wacli filed under a contact's @lid still moves its chat."""
        aliases = self._lid_aliases()
        if not aliases:
            return
        by_jid = {str(chat["jid"]): chat for chat in chats}
        preview_sql = self._preview_sql("latest")
        try:
            with closing(self._connect()) as connection:
                for lid, phone in aliases.items():
                    chat = by_jid.get(phone)
                    if chat is None:
                        continue
                    row = connection.execute(
                        f"""SELECT latest.ts, latest.msg_id, latest.from_me, latest.sender_name,
                              {preview_sql} AS preview, COALESCE(latest.media_type, '') AS media
                            FROM messages AS latest
                            WHERE latest.chat_jid = ?
                              AND (latest.deleted_at IS NULL OR {revoked_sql("latest")})
                              AND COALESCE(latest.reaction_to_id, '') = ''
                              AND ({revoked_sql("latest")} OR NOT {synthetic_message_sql("latest")})
                            ORDER BY latest.ts DESC, latest.rowid DESC LIMIT 1""",
                        [lid],
                    ).fetchone()
                    if row is None or int(row["ts"] or 0) <= int(chat["timestamp"] or 0):
                        continue
                    key = (lid, str(row["msg_id"] or ""))
                    status = self._delivery_status(connection, [key]).get(key, "") \
                        if bool(row["from_me"]) else ""
                    chat.update({
                        "timestamp": int(row["ts"] or 0),
                        "last_message_id": str(row["msg_id"] or "")[:256],
                        "last_media_type": str(row["media"] or "")[:32],
                        "preview": " ".join(contact_preview(str(row["preview"] or "")).split())[:512],
                        "last_from_me": bool(row["from_me"]),
                        "last_status": status,
                        "last_sender": " ".join(str(row["sender_name"] or "").split())[:MAX_NOTIFY_SENDER],
                    })
        except (sqlite3.Error, OmaWhatsAppError):
            return
        chats.sort(key=lambda chat: (not chat["pinned"], -chat["timestamp"], chat["name"].casefold()))

    def chats(self, query: str = "", limit: int = 500) -> dict[str, Any]:
        """Merge every configured account into one rail, newest chat first."""
        cleaned = " ".join(query.split())[:256]
        limit = max(1, min(int(limit), 500))
        preferences = self._preferences()
        merged: list[dict[str, Any]] = []
        reports: list[dict[str, Any]] = []
        accounts = self.accounts()
        for account in accounts:
            with self._using(account):
                try:
                    rows = self._account_chats(cleaned, limit, preferences)
                except OmaWhatsAppError as exc:
                    # One account that has never synced must not empty the rail.
                    reports.append({"account": account.name, "ready": False,
                                    "error": clean_error(exc, "That account could not be read.")})
                    continue
            reports.append({"account": account.name, "ready": True, "error": ""})
            merged.extend(rows)
        merged.sort(key=lambda chat: (
            not chat["pinned"], -chat["timestamp"], chat["name"].casefold()))
        visible = merged[:limit]
        self._attach_cached_avatars(visible, accounts)
        return {"ok": True, "query": cleaned, "chats": visible, "accounts": reports}

    def acknowledge_notifications(self, jid: str = "") -> dict[str, Any]:
        target = jid.strip()
        preferences = self._preferences()
        # An empty JID dismisses the aggregated bar badge, so it covers every
        # account. A named chat belongs to the account this request selected.
        accounts = [self.active] if target else self.accounts()
        count = 0
        for account in accounts:
            with self._using(account):
                if target:
                    self._chat(target)
                try:
                    chats = self._account_chats("", 500, preferences)
                except OmaWhatsAppError:
                    continue
                selected = [chat for chat in chats if not target or chat["jid"] == target]
                if target and not selected:
                    raise OmaWhatsAppError(
                        "That chat is not available in the local WhatsApp index."
                    )
                count += len(selected)

                def update(state: dict[str, Any], selected: Any = selected) -> None:
                    acknowledged = state["acknowledged_unread"]
                    for chat in selected:
                        if int(chat.get("unread") or 0) <= 0:
                            acknowledged.pop(str(chat["jid"]), None)
                            continue
                        acknowledged[str(chat["jid"])] = {
                            "unread": int(chat.get("unread") or 0),
                            "timestamp": int(chat.get("timestamp") or 0),
                        }

                self._update_account_state(update)
        return {"ok": True, "kind": "acknowledge", "count": count}

    @staticmethod
    def _notify_send_ready() -> bool:
        return NOTIFY_SEND.is_file() and os.access(NOTIFY_SEND, os.X_OK)

    @staticmethod
    def _notification_text(value: Any, limit: int, *, markup: bool = False) -> str:
        """Collapse external chat text to one printable, markup-inert line."""
        printable = "".join(character for character in str(value or "")
                            if character.isprintable())
        text = " ".join(printable.split())[:limit]
        if not markup:
            return text
        return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

    @staticmethod
    def _notification_watermark(chats: Sequence[dict[str, Any]]) -> dict[str, dict[str, Any]]:
        return {
            str(chat["jid"])[:160]: {
                "unread": int(chat.get("unread") or 0),
                "timestamp": int(chat.get("timestamp") or 0),
                "message_id": str(chat.get("last_message_id") or "")[:256],
            }
            for chat in list(chats)[:MAX_NOTIFY_WATERMARKS]
        }

    def _deliver_notification(
        self, summary: str, body: str, target: dict[str, str] | None = None,
        image: str = "",
    ) -> bool:
        """Hand one popup to the desktop; a failing daemon must not raise.

        With a target, clicking the popup opens that exact chat. notify-send
        waits for the click, so a detached `notify-open` child owns the popup
        and this helper returns at once.
        """
        command = [str(NOTIFY_SEND), "--app-name=WhatsApp for Omarchy", "--urgency=normal",
                   "--category=im.received", f"--expire-time={NOTIFY_EXPIRE_MS}",
                   f"--icon={NOTIFY_APP_ICON}"]
        if image:
            command.append(f"--hint=string:image-path:{image}")
        if target and str(target.get("jid") or ""):
            command.append("--print-id")
            previous = self._notify_ids().get(self._notify_key(target))
            if previous:
                command.append(f"--replace-id={previous}")
            command.append("--action=default=Open chat")
            command.extend(["--", summary or "WhatsApp for Omarchy"])
            if body:
                command.append(body)
            request = json.dumps({"command": command, "target": {
                "account": str(target.get("account") or ""),
                "jid": str(target.get("jid") or ""),
            }})
            try:
                child = subprocess.Popen(
                    [sys.executable, str(Path(__file__).resolve().with_name("omawhatsapp")),
                     "notify-open"],
                    stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL, close_fds=True, start_new_session=True,
                )
                assert child.stdin is not None
                child.stdin.write(request.encode("utf-8"))
                child.stdin.close()
            except (OSError, AssertionError):
                return False
            return True
        command.extend(["--", summary or "WhatsApp for Omarchy"])
        if body:
            command.append(body)
        try:
            result = run_bounded(
                command, timeout=8, stdout_limit=16 * 1024, stderr_limit=MAX_PROCESS_ERROR
            )
        except (ProcessOutputLimitExceeded, subprocess.TimeoutExpired, OSError):
            return False
        return result.returncode == 0

    @staticmethod
    def _notify_key(target: dict[str, Any]) -> str:
        return f"{str(target.get('account') or '')}\n{str(target.get('jid') or '')}"

    def _notify_ids(self) -> dict[str, int]:
        value = self._read_state_json(NOTIFY_IDS_FILE, MAX_NOTIFY_IDS_STATE, {})
        if not isinstance(value, dict):
            return {}
        now = int(time.time())
        ids: dict[str, int] = {}
        for key, item in value.items():
            if not isinstance(key, str) or key.count("\n") != 1 or not isinstance(item, dict):
                continue
            popup = bounded_int(item.get("id"), 0, 0, 2**31 - 1)
            at = bounded_int(item.get("at"), 0, 0, 2**63 - 1)
            if popup > 0 and now - at < NOTIFY_ID_TTL:
                ids[key] = popup
        return ids

    def _remember_notify_id(self, key: str, popup: int) -> None:
        if key.count("\n") != 1 or not 0 < popup < 2**31:
            return
        try:
            with self._state_lock("notify-ids.lock"):
                value = self._read_state_json(NOTIFY_IDS_FILE, MAX_NOTIFY_IDS_STATE, {})
                current = value if isinstance(value, dict) else {}
                current = {k: v for k, v in current.items()
                           if isinstance(k, str) and isinstance(v, dict)}
                current[key] = {"id": popup, "at": int(time.time())}
                ordered = sorted(current.items(), key=lambda pair: bounded_int(
                    pair[1].get("at"), 0, 0, 2**63 - 1))
                self._write_state_json(NOTIFY_IDS_FILE, dict(ordered[-MAX_NOTIFY_IDS:]),
                                       MAX_NOTIFY_IDS_STATE)
        except (OmaWhatsAppError, OSError):
            pass

    def _notify_chat(self, chat: dict[str, Any], count: int, preview: bool,
                     label: str = "") -> bool:
        # Summary and body both reach markup-capable daemons, so neither may
        # carry live markup from a chat name, an account label, or a message.
        name = self._notification_text(
            chat.get("name"), MAX_NOTIFY_SUMMARY, markup=True) or "WhatsApp chat"
        account = self._notification_text(label, MAX_NOTIFY_SENDER, markup=True)
        if account:
            name = f"{name} ({account})"
        summary = f"{name} · {count} new" if count > 1 else name
        target = {"account": str(chat.get("account") or ""), "jid": str(chat.get("jid") or "")}
        image = str(chat.get("avatar_path") or "")
        if not image.startswith("/") or not Path(image).is_file():
            image = ""
        if not preview:
            body = "1 new message" if count == 1 else f"{count} new messages"
            return self._deliver_notification(summary, body, target, image)
        body = self._notification_text(
            self._notification_preview(chat), MAX_NOTIFY_BODY, markup=True)
        sender = self._notification_text(chat.get("last_sender"), MAX_NOTIFY_SENDER, markup=True)
        if str(chat.get("kind") or "") == "group" and sender and body:
            body = f"{sender}: {body}"
        return self._deliver_notification(summary, body, target, image)

    @staticmethod
    def _notification_preview(chat: dict[str, Any]) -> str:
        """Media reads as the phone shows it: "📷 Photo", or the icon and caption."""
        text = " ".join(str(chat.get("preview") or "").split())
        media = str(chat.get("last_media_type") or "").lower()
        if not media:
            return text
        label = NOTIFY_MEDIA_LABELS.get(media, "📎 Attachment")
        if not text or re.fullmatch(r"\[[A-Za-z _:0-9]+\]", text):
            return label
        return f"{label.split(' ', 1)[0]} {text}" if " " in label else f"{label}: {text}"

    @staticmethod
    def _do_not_disturb() -> bool:
        try:
            if OMARCHY_NOTIFICATION_STATE.stat().st_size > 64 * 1024:
                return False
            value = json.loads(OMARCHY_NOTIFICATION_STATE.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return False
        return isinstance(value, dict) and value.get("dnd") is True

    def _play_message_sound(self) -> bool:
        """One short sound per notification pass; silent under do-not-disturb."""
        if self._do_not_disturb() or not NOTIFY_SOUND.is_file() \
                or not os.access(SOUND_PLAYER, os.X_OK):
            return False
        try:
            subprocess.Popen(
                [str(SOUND_PLAYER), str(NOTIFY_SOUND)], stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                close_fds=True, start_new_session=True,
            )
        except OSError:
            return False
        return True

    def notify_open(self, request: Any) -> dict[str, Any]:
        """Show one popup and open its chat when it is clicked.

        The notification service shows no reply field or extra buttons, so a
        click opens the reply view by the bar on that chat (or, with
        `notify_reply` off, the full app).

        notify-send prints the popup id first and the chosen action later, so
        the id is recorded while the popup is still on screen: the next
        message in the same chat replaces it instead of stacking a new one.
        """
        if not isinstance(request, dict):
            raise OmaWhatsAppError("Invalid notification request.")
        command = request.get("command")
        target = request.get("target") if isinstance(request.get("target"), dict) else {}
        if (not isinstance(command, list) or not command
                or command[0] != str(NOTIFY_SEND)
                or not all(isinstance(part, str) for part in command)):
            raise OmaWhatsAppError("Invalid notification command.")
        key = self._notify_key(target) if str(target.get("jid") or "") else ""
        closed = {"ok": True, "kind": "notify-open", "opened": False}
        try:
            process = subprocess.Popen(
                command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL, close_fds=True,
            )
        except OSError:
            return closed
        output = b""
        recorded = False
        deadline = time.monotonic() + NOTIFY_EXPIRE_MS / 1000 + 60
        try:
            assert process.stdout is not None
            descriptor = process.stdout.fileno()
            with selectors.DefaultSelector() as selector:
                selector.register(descriptor, selectors.EVENT_READ)
                while len(output) <= 4096:
                    remaining = deadline - time.monotonic()
                    if remaining <= 0 or not selector.select(remaining):
                        break
                    chunk = os.read(descriptor, 1024)
                    if not chunk:
                        break
                    output += chunk
                    if not recorded and b"\n" in output:
                        recorded = True
                        first = output.split(b"\n", 1)[0].strip()
                        if key and first.isdigit():
                            self._remember_notify_id(key, int(first))
        except (OSError, AssertionError, ValueError):
            pass
        finally:
            if process.poll() is None:
                process.kill()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                pass
        words = output.decode("utf-8", errors="replace").split()
        action = words[-1] if words and not words[-1].isdigit() else ""
        if action != "default" or not str(target.get("jid") or ""):
            return closed
        shell = OMARCHY_SHELL if OMARCHY_SHELL.exists() else Path(shutil.which("omarchy-shell") or "")
        if not str(shell) or not shell.exists():
            return {"ok": True, "kind": "notify-open", "opened": False}
        payload = json.dumps({"account": str(target.get("account") or ""),
                              "jid": str(target["jid"])})
        surface = "openDropdown" if ui_preference(self._preferences(), "notify_reply") else "openApp"
        try:
            run_bounded([str(shell), PLUGIN_ID, surface, payload], timeout=10,
                        stdout_limit=4096, stderr_limit=4096)
        except (ProcessOutputLimitExceeded, subprocess.TimeoutExpired, OSError):
            return {"ok": True, "kind": "notify-open", "opened": False}
        return {"ok": True, "kind": "notify-open", "opened": True}

    def set_notifications(self, enabled: Any = None, preview: Any = None,
                          sound: Any = None) -> dict[str, Any]:
        if enabled is None and preview is None and sound is None:
            raise OmaWhatsAppError("Choose what to change about desktop notifications.")
        if sound is not None and not isinstance(sound, bool):
            raise OmaWhatsAppError("The notification sound must be on or off.")
        if enabled is not None and not isinstance(enabled, bool):
            raise OmaWhatsAppError("Desktop notifications must be on or off.")
        if preview is not None and not isinstance(preview, bool):
            raise OmaWhatsAppError("Message previews must be on or off.")
        if enabled is True and not self._notify_send_ready():
            raise OmaWhatsAppError(
                "Desktop notifications need notify-send from libnotify."
            )
        watermarks: dict[str, dict[str, dict[str, Any]]] = {}
        if enabled is True:
            # Adopt every archive on the way in so switching on never replays one.
            preferences = self._preferences()
            for account in self.accounts():
                with self._using(account):
                    try:
                        chats = self._account_chats("", MAX_NOTIFY_WATERMARKS, preferences)
                    except OmaWhatsAppError:
                        chats = []
                    watermarks[account.key] = self._notification_watermark(chats)

        def update(value: dict[str, Any]) -> None:
            settings = value["notifications"]
            if enabled is not None:
                settings["enabled"] = bool(enabled)
            if preview is not None:
                settings["preview"] = bool(preview)
            if sound is not None:
                settings["sound"] = bool(sound)
            for key, watermark in watermarks.items():
                state = value["stores"].get(key)
                if state is None:
                    state = self._store_state({})
                    value["stores"][key] = state
                state["notified"] = watermark

        value = self._update_preferences(update)
        return {"ok": True, "kind": "notify-mode", "notifications": value["notifications"]}

    def notify(self, skip_jid: str = "") -> dict[str, Any]:
        """Pop one popup per chat that gained incoming messages since last run.

        The popup is deliberately independent of the bar badge. It ignores
        ``notification_unread``, so neither ``show_unread_count`` nor a
        dismissal can silence it, and the caller only suppresses the chat the
        user is currently looking at. Every configured account is swept in one
        pass, under one shared burst cap.
        """
        preferences = self._preferences()
        settings = preferences["notifications"]
        if not settings["enabled"]:
            return {"ok": True, "kind": "notify", "enabled": False, "sent": 0}
        if not self._notify_send_ready():
            return {"ok": True, "kind": "notify", "enabled": True, "sent": 0,
                    "available": False,
                    "error": "Desktop notifications need notify-send from libnotify."}
        accounts = self.accounts()
        named = len(accounts) > 1
        # The visible chat belongs to the account that asked for this pass.
        skip = skip_jid.strip()[:160]
        skip_key = self.active.key
        pending: list[
            tuple[Account, dict[str, Any], int, str, dict[str, Any]]
        ] = []
        delivery_watermarks: dict[str, dict[str, dict[str, Any]]] = {}
        seeded: list[str] = []
        for account in accounts:
            with self._using(account):
                try:
                    chats = self._account_chats("", MAX_NOTIFY_WATERMARKS, preferences)
                except OmaWhatsAppError:
                    continue
                watermark = self._notification_watermark(chats)
                seen = self._account_state(preferences)["notified"]
                if self._account_state(preferences).get("notifications_muted") is True:
                    # Muted: what arrives is marked seen, so unmuting never
                    # replays it as popups.
                    self._update_account_state(
                        lambda state, value=watermark: state.update({"notified": value}))
                    continue
                if not seen:
                    # A missing watermark means a fresh account, not an unread
                    # archive: adopt it instead of replaying it.
                    self._update_account_state(
                        lambda state, value=watermark: state.update({"notified": value}))
                    seeded.append(account.name)
                    continue
                delivery_watermarks[account.key] = watermark
                for chat in chats:
                    jid = str(chat["jid"])
                    previous = dict(seen.get(jid) or {})
                    timestamp = int(chat.get("timestamp") or 0)
                    previous_timestamp = int(previous.get("timestamp") or 0)
                    unread = int(chat.get("unread") or 0)
                    previous_unread = int(previous.get("unread") or 0)
                    message_id = str(chat.get("last_message_id") or "")
                    previous_message_id = str(previous.get("message_id") or "")
                    # An edit, a reaction or a receipt moves the chat's time
                    # without a new message; only a new last message pops up.
                    if message_id and previous_message_id \
                            and message_id == previous_message_id:
                        continue
                    same_second_arrival = timestamp == previous_timestamp and (
                        unread > previous_unread
                        or bool(previous_message_id and message_id
                                and message_id != previous_message_id)
                    )
                    if timestamp < previous_timestamp \
                            or (timestamp == previous_timestamp and not same_second_arrival):
                        continue
                    if chat["last_from_me"] or chat["muted"] or chat["archived"]:
                        continue
                    if jid == skip and account.key == skip_key:
                        continue
                    # WhatsApp reports no unread when the chat was read
                    # elsewhere or read privately here. An advanced timestamp is
                    # still a new message, so it is worth exactly one popup.
                    arrived = unread - previous_unread
                    pending.append((
                        account,
                        chat,
                        max(1, arrived) if unread > 0 else 1,
                        account.label if named else "",
                        previous,
                    ))
        pending.sort(key=lambda item: -int(item[1].get("timestamp") or 0))
        sent = 0
        failed = 0

        def retain(item: tuple[Account, dict[str, Any], int, str, dict[str, Any]]) -> None:
            account, chat, _, _, previous = item
            watermark = delivery_watermarks[account.key]
            jid = str(chat["jid"])
            if previous:
                watermark[jid] = previous
            else:
                watermark.pop(jid, None)

        # The sender's cached photo becomes the popup image, as on the phone.
        self._attach_cached_avatars([item[1] for item in pending[:MAX_NOTIFY_BURST]], accounts)
        popup_ids = self._notify_ids()
        for item in pending[:MAX_NOTIFY_BURST]:
            _, chat, count, label, _ = item
            # A popup that replaces this chat's last one counts everything
            # still unseen there, not just this pass's arrivals.
            if self._notify_key(chat) in popup_ids:
                count = max(count, int(chat.get("notification_unread") or 0))
            if self._notify_chat(chat, count, settings["preview"], label):
                sent += 1
            else:
                failed += 1
                retain(item)
        overflow = len(pending) - MAX_NOTIFY_BURST
        if overflow > 0:
            if self._deliver_notification(
                    "WhatsApp for Omarchy", f"{overflow} more chats have new messages"):
                sent += 1
            else:
                failed += overflow
                for item in pending[MAX_NOTIFY_BURST:]:
                    retain(item)
        for account in accounts:
            watermark = delivery_watermarks.get(account.key)
            if watermark is None:
                continue
            self._update_account_state(
                lambda state, value=watermark: state.update({"notified": value}),
                account,
            )
        played = bool(sent) and settings.get("sound") is not False and self._play_message_sound()
        result = {"ok": True, "kind": "notify", "enabled": True, "sent": sent,
                  "failed": failed, "pending": len(pending), "sound": played}
        if seeded:
            result["seeded"] = True
            result["seeded_accounts"] = seeded
        return result

    def set_online(self, online: bool) -> dict[str, Any]:
        account = self.active
        # Online starts sync now; it also starts at login only when WhatsApp for Omarchy
        # starts with the system. Offline stops it and keeps it stopped.
        command = "disable" if not online else (
            "enable" if self._preferences().get("start_at_login") is not False else "disable")

        with self._state_lock(self._lifecycle_lock_name(account)):
            was_enabled = self._systemctl_user(
                ["is-enabled", "--quiet", account.unit], require_success=False
            ).returncode == 0
            was_active = self._systemctl_user(
                ["is-active", "--quiet", account.unit], require_success=False
            ).returncode == 0
            previous_online = self.online(account)
            if online:
                self._systemctl_user([command, account.unit])
                self._systemctl_user(["start", account.unit])
                self._set_session_marker("closed", False)
            else:
                self._systemctl_user([command, "--now", account.unit])

            def update(state: dict[str, Any]) -> None:
                state["online"] = bool(online)

            try:
                self._update_account_state(update, account)
            except (OmaWhatsAppError, OSError, TypeError, ValueError) as exc:
                rollback_errors: list[str] = []
                try:
                    self._update_account_state(
                        lambda state: state.update({"online": previous_online}),
                        account,
                    )
                except (OmaWhatsAppError, OSError, TypeError, ValueError):
                    rollback_errors.append("saved preference")
                for verb in (
                    "enable" if was_enabled else "disable",
                    "start" if was_active else "stop",
                ):
                    try:
                        self._systemctl_user([verb, account.unit])
                    except OmaWhatsAppError:
                        rollback_errors.append(f"service {verb}")
                if rollback_errors:
                    raise OmaWhatsAppError(
                        "Online mode was not saved and rollback was incomplete ("
                        + ", ".join(rollback_errors) + ")."
                    ) from exc
                raise OmaWhatsAppError(
                    "Online mode was not saved; the previous sync mode was restored."
                ) from exc
        return {"ok": True, "kind": "sync-mode", "account": account.name,
                "online": bool(online)}

    # Quitting and launching are for this login session: markers live in the
    # private runtime directory, which the system empties at reboot.
    def _session_marker(self, name: str) -> Path:
        return self._clipboard_stage_root() / "omawhatsapp-session" / name

    def _set_session_marker(self, name: str, present: bool) -> None:
        path = self._session_marker(name)
        try:
            if present:
                path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
                path.write_text("1\n", encoding="utf-8")
                path.chmod(0o600)
            else:
                path.unlink(missing_ok=True)
        except OSError as exc:
            raise OmaWhatsAppError("The session state could not be saved.") from exc

    def _closed(self, preferences: dict[str, Any], reports: list[dict[str, Any]]) -> bool:
        """Quit by the user, or not started because it does not start at login."""
        if self._session_marker("closed").exists():
            return True
        if preferences.get("start_at_login") is not False or self._session_marker("launched").exists():
            return False
        return not any(report.get("sync_active") for report in reports if report.get("online"))

    def unlink_account(self, name: Any, confirm: Any) -> dict[str, Any]:
        """Log one account out of WhatsApp and drop it from WhatsApp for Omarchy.

        The phone loses this linked device. The local archive stays on disk;
        only the session and, for a named account, its config entry go.
        """
        account = self.account(str(name or ""))
        if str(confirm or "") != account.name:
            raise OmaWhatsAppError(f"Confirm by naming the account: {account.name}.")
        with self._state_lock(self._lifecycle_lock_name(account)):
            if account.unit:
                self._systemctl_user(["disable", "--now", account.unit], require_success=False)
            result = self._run(["--json", "auth", "logout"], timeout=60, account=account)
            if result.returncode != 0:
                raise OmaWhatsAppError(clean_error(result.stderr or result.stdout,
                    "WhatsApp did not accept the logout; the account stays linked."))
            removed = False
            if account.selector not in {"implicit", "store"}:
                removal = self._run(["--json", "accounts", "remove", account.name], timeout=30, account=None)
                removed = removal.returncode == 0
        self._refresh_account_registry()
        return {"ok": True, "kind": "unlink", "account": account.name,
                "removed": removed, "archive_kept": True}

    def quit_app(self) -> dict[str, Any]:
        """Stop every account's sync until WhatsApp for Omarchy opens again."""
        self._set_session_marker("launched", False)
        self._set_session_marker("closed", True)
        for account in self.accounts():
            with self._state_lock(self._lifecycle_lock_name(account)):
                self._systemctl_user(["stop", account.unit], require_success=False)
        return {"ok": True, "kind": "quit", "closed": True}

    def launch_app(self) -> dict[str, Any]:
        """Start the sync of every account that is not in offline mode."""
        self._set_session_marker("closed", False)
        self._set_session_marker("launched", True)
        started = 0
        for account in self.accounts():
            if not self.online(account):
                continue
            with self._state_lock(self._lifecycle_lock_name(account)):
                self._systemctl_user(["start", account.unit])
            started += 1
        return {"ok": True, "kind": "launch", "closed": False, "started": started}

    def _apply_start_at_login(self, enabled: bool) -> None:
        """Enable or disable each online account's sync at login; what runs now stays."""
        for account in self.accounts():
            if not self.online(account):
                continue
            with self._state_lock(self._lifecycle_lock_name(account)):
                self._systemctl_user(["enable" if enabled else "disable", account.unit])

    def messages(self, jid: str, query: str = "", limit: int = 160,
                 before: Any = None, kind: str = "") -> dict[str, Any]:
        """Newest page of a chat, or the page older than ``before`` (ts and id).

        ``kind`` narrows it to the chat's media, links or documents, over the
        whole local history, for the media browser.
        """
        chat = self._chat(jid)
        sent_media_hints = self._sent_media_hints()
        sent_reply_hints = self._sent_reply_hints()
        cleaned = " ".join(query.split())[:256]
        limit = max(1, min(int(limit), 500))
        chat_jids = self._chat_jids(chat["jid"])
        # A message deleted for everyone stays as a placeholder, as on the
        # phone; one deleted only on your devices is gone.
        where = f"""base.chat_jid IN ({",".join("?" for _ in chat_jids)})
          AND (base.deleted_at IS NULL OR {revoked_sql("base")})
          AND COALESCE(base.reaction_to_id, '') = ''
          AND ({revoked_sql("base")} OR (
               (COALESCE(base.text, '') <> '' OR COALESCE(base.media_caption, '') <> '' OR
                COALESCE(base.display_text, '') <> '' OR COALESCE(base.filename, '') <> '' OR
                COALESCE(base.media_type, '') <> '')
               AND NOT {synthetic_message_sql("base")}))"""
        if cleaned or kind:
            # A deleted message's words and files stay out of searches and views.
            where += f" AND NOT {revoked_sql('base')}"
        parameters: list[Any] = list(chat_jids)
        if cleaned:
            where += """ AND LOWER(COALESCE(NULLIF(base.text, ''), NULLIF(base.media_caption, ''),
              NULLIF(base.display_text, ''), NULLIF(base.filename, ''), '')) LIKE LOWER(?) ESCAPE '\\'"""
            parameters.append(self._like(cleaned))
        if kind == "media":
            where += " AND base.media_type IN ('image', 'video', 'gif')"
        elif kind == "docs":
            where += " AND base.media_type = 'document'"
        elif kind == "links":
            where += """ AND (base.text LIKE '%http://%' OR base.text LIKE '%https://%'
              OR base.text LIKE '%www.%' OR base.media_caption LIKE '%http%')"""
        elif kind:
            raise OmaWhatsAppError("Choose media, links or docs.")
        cursor = before if isinstance(before, dict) else None
        if cursor is not None:
            before_ts = bounded_int(cursor.get("ts"), 0, 0, 2**63 - 1)
            before_id = str(cursor.get("id") or "")[:256]
            # Same ordering as the page itself: ts, then insertion order.
            where += """ AND (base.ts < ? OR (base.ts = ? AND base.rowid < COALESCE(
              (SELECT rowid FROM messages WHERE chat_jid = base.chat_jid AND msg_id = ?), 0)))"""
            parameters.extend([before_ts, before_ts, before_id])
        # One extra row says whether an older page exists.
        parameters.append(limit + 1)
        try:
            with closing(self._connect()) as connection:
                has_polls = self._has_table(connection, "polls")
                if has_polls:
                    where += f" AND NOT {poll_vote_sql('base')}"
                rows = connection.execute(
                    f"""SELECT base.msg_id, base.chat_jid AS stored_chat_jid,
                      base.sender_jid, base.sender_name,
                      base.ts, base.from_me, base.text, base.display_text,
                      {revoked_sql("base")} AS is_revoked,
                      base.media_type, base.media_caption, base.filename,
                      base.mime_type, base.local_path, base.file_length,
                      base.media_unavailable_at, base.edited, base.is_forwarded,
                      base.quoted_msg_id, base.buttons,
                      location.latitude, location.longitude, location.name AS location_name,
                      location.address AS location_address, location.is_live AS location_live,
                      EXISTS(SELECT 1 FROM starred
                        WHERE starred.chat_jid = base.chat_jid
                          AND starred.msg_id = base.msg_id) AS is_starred
                    FROM messages AS base
                    LEFT JOIN message_locations AS location
                      ON location.chat_jid = base.chat_jid
                        AND location.msg_id = base.msg_id
                    WHERE {where}
                    ORDER BY base.ts DESC, base.rowid DESC LIMIT ?""",
                    parameters,
                ).fetchall()
                has_more = len(rows) > limit
                rows = rows[:limit]
                message_ids = [str(row["msg_id"]) for row in rows]
                quoted_by_message = {}
                for row in rows:
                    message_id = str(row["msg_id"])
                    hint = sent_reply_hints.get(
                        self._sent_hint_key(chat["jid"], message_id), {}
                    )
                    quoted_by_message[message_id] = str(
                        row["quoted_msg_id"] or hint.get("quoted_id") or ""
                    )
                quoted_rows: dict[str, sqlite3.Row] = {}
                quoted_ids = sorted({value for value in quoted_by_message.values() if value})
                if quoted_ids:
                    quoted_placeholders = ",".join("?" for _ in quoted_ids)
                    resolved_quotes = connection.execute(
                        f"""SELECT msg_id, sender_name, from_me, media_type,
                          COALESCE(NULLIF(text, ''), NULLIF(media_caption, ''),
                            NULLIF(display_text, ''), NULLIF(filename, '')) AS quoted_text
                        FROM messages
                        WHERE chat_jid = ? AND msg_id IN ({quoted_placeholders})""",
                        [chat["jid"], *quoted_ids],
                    ).fetchall()
                    quoted_rows = {str(row["msg_id"]): row for row in resolved_quotes}
                reactions: dict[str, list[dict[str, Any]]] = {}
                if message_ids:
                    placeholders = ",".join("?" for _ in message_ids)
                    reaction_rows = connection.execute(
                        f"""WITH ranked_reactions AS (
                          SELECT reaction_to_id, reaction_emoji, from_me,
                            sender_name, sender_jid, ts, rowid,
                            ROW_NUMBER() OVER (
                              PARTITION BY reaction_to_id,
                                CASE WHEN from_me != 0 THEN 'me' ELSE
                                  COALESCE(NULLIF(sender_jid, ''),
                                    NULLIF(sender_name, ''), msg_id) END
                              ORDER BY ts DESC, rowid DESC
                            ) AS actor_rank
                          FROM messages
                          WHERE reaction_to_id IN ({placeholders})
                            AND deleted_at IS NULL
                            -- wacli can store a reaction under the contact's
                            -- opaque @lid chat instead of this chat's phone
                            -- JID; an @lid row joins only the message it
                            -- targets, never another contact's chat.
                            AND (chat_jid = ? OR chat_jid LIKE '%@lid')
                        )
                        SELECT reaction_to_id, reaction_emoji, from_me,
                          sender_name, sender_jid
                        FROM ranked_reactions
                        WHERE actor_rank = 1 AND COALESCE(reaction_emoji, '') <> ''
                        ORDER BY ts ASC, rowid ASC""",
                        [*message_ids, chat["jid"]],
                    ).fetchall()
                    for reaction in reaction_rows:
                        reactions.setdefault(str(reaction["reaction_to_id"]), []).append({
                            "emoji": str(reaction["reaction_emoji"]),
                            "from_me": bool(reaction["from_me"]),
                            "sender": "You" if bool(reaction["from_me"])
                                else str(reaction["sender_name"] or "WhatsApp"),
                            "sender_jid": str(reaction["sender_jid"] or ""),
                        })
                polls = self._polls(connection, chat_jids, message_ids) \
                    if has_polls and message_ids else {}
                delivery = self._delivery_status(connection, [
                    (str(row["stored_chat_jid"]), str(row["msg_id"]))
                    for row in rows if bool(row["from_me"])])
        except sqlite3.Error as exc:
            raise OmaWhatsAppError("The local WhatsApp index could not be read.") from exc
        values = []
        gone_media = self._media_gone()
        for row in rows:
            message_id = str(row["msg_id"])
            if bool(row["is_revoked"]):
                values.append({
                    "id": message_id, "text": "", "revoked": True,
                    "sender": "You" if bool(row["from_me"]) else str(row["sender_name"] or "WhatsApp"),
                    "sender_jid": str(row["sender_jid"] or ""),
                    "timestamp": int(row["ts"]), "from_me": bool(row["from_me"]),
                    "media_type": "", "reactions": [], "buttons": [],
                })
                continue
            quoted_id = quoted_by_message.get(message_id, "")
            quoted = quoted_rows.get(quoted_id)
            media_type = str(row["media_type"] or "")
            text_keys = ("text", "media_caption") if media_type else ("text", "display_text")
            text = next((str(row[key]).strip() for key in text_keys
                if row[key] is not None and str(row[key]).strip()
                and not (media_type == "audio" and key == "text"
                         and str(row[key]).strip() == SYNTHETIC_AUDIO_TEXT)), "")
            local_path = str(row["local_path"] or "")
            local_exists = bool(local_path) and Path(local_path).is_file()
            hint = sent_media_hints.get(self._sent_hint_key(chat["jid"], message_id), {})
            hinted_path = str(hint.get("local_path") or "")
            if not local_exists and hinted_path and Path(hinted_path).is_file():
                local_path = hinted_path
                local_exists = True
            values.append({
                "id": message_id, "text": text[:MAX_MESSAGE],
                "sender": "You" if bool(row["from_me"]) else str(row["sender_name"] or "WhatsApp"),
                "sender_jid": str(row["sender_jid"] or ""),
                "timestamp": int(row["ts"]), "from_me": bool(row["from_me"]),
                "media_type": media_type,
                "mime_type": str(row["mime_type"] or hint.get("mime_type") or ""),
                "local_path": local_path if local_exists else "",
                "filename": str(row["filename"] or hint.get("filename") or ""),
                "file_size": int(row["file_length"] or 0),
                "media_unavailable": row["media_unavailable_at"] is not None
                    or f"{row['stored_chat_jid']}\n{message_id}" in gone_media,
                "edited": bool(row["edited"]), "forwarded": bool(row["is_forwarded"]),
                "starred": bool(row["is_starred"]),
                "quoted_id": quoted_id,
                "quoted_sender": "You" if quoted is not None
                    and bool(quoted["from_me"])
                    else str((quoted["sender_name"] if quoted is not None else "")
                             or "WhatsApp"),
                "quoted_text": str(
                    (quoted["quoted_text"] if quoted is not None else "") or ""
                )[:512],
                "quoted_media_type": str(
                    (quoted["media_type"] if quoted is not None else "") or ""
                ),
                "reactions": reactions.get(str(row["msg_id"]), []),
                "buttons": self._json_list(row["buttons"]),
                "album_id": str(hint.get("album_id") or "")[:64],
                "album_index": bounded_int(hint.get("album_index"), 0, 0,
                                             MAX_ATTACHMENTS - 1),
                "album_count": bounded_int(hint.get("album_count"), 1, 1,
                                             MAX_ATTACHMENTS),
                "latitude": row["latitude"], "longitude": row["longitude"],
                "location_name": str(row["location_name"] or ""),
                "location_address": str(row["location_address"] or ""),
                "location_live": bool(row["location_live"]),
            })
            status = delivery.get((str(row["stored_chat_jid"]), message_id), "")
            if status:
                values[-1]["status"] = status
            if not media_type:
                cards = contact_cards(text)
                if cards:
                    values[-1]["contacts"] = self._with_known_people(cards)
            if message_id in polls:
                values[-1]["poll"] = polls[message_id]
                # "Poll: question" is wacli's text for the poll; the card shows it.
                values[-1]["text"] = ""
        return {"ok": True, "chat": chat, "query": cleaned, "messages": values,
                "has_more": has_more}

    def _with_known_people(self, cards: list[dict[str, str]]) -> list[dict[str, Any]]:
        """Each shared contact with the person's JID and chat when this account knows them."""
        output = []
        for card in cards:
            digits = re.sub(r"\D", "", card["phone"])
            item: dict[str, Any] = {"name": card["name"], "phone": card["phone"],
                                    "digits": digits, "jid": "", "has_chat": False}
            if 8 <= len(digits) <= 15:
                known = self._known_person(f"{digits}@s.whatsapp.net")
                if known is not None:
                    item["jid"] = f"{digits}@s.whatsapp.net"
                    item["has_chat"] = bool(known.get("has_chat"))
            output.append(item)
        return output

    def _polls(self, connection: sqlite3.Connection, chat_jids: list[str],
               message_ids: list[str]) -> dict[str, dict[str, Any]]:
        """Each poll among these messages with its options and current votes."""
        chat_marks = ",".join("?" for _ in chat_jids)
        id_marks = ",".join("?" for _ in message_ids)
        polls = connection.execute(
            f"""SELECT msg_id, question, options_json, selectable_count FROM polls
            WHERE chat_jid IN ({chat_marks}) AND msg_id IN ({id_marks})""",
            [*chat_jids, *message_ids]).fetchall()
        if not polls:
            return {}
        has_votes = self._has_table(connection, "poll_votes")
        votes = connection.execute(
            f"""SELECT poll_msg_id, voter_jid, selected_options_json FROM poll_votes
            WHERE chat_jid IN ({chat_marks}) AND poll_msg_id IN ({id_marks})
            ORDER BY ts""", [*chat_jids, *message_ids]).fetchall() if has_votes else []
        aliases = self._lid_aliases()
        own = self._own_jid()
        voters = sorted({aliases.get(str(row["voter_jid"]), str(row["voter_jid"]))
                         for row in votes})
        names: dict[str, str] = {}
        if voters:
            marks = ",".join("?" for _ in voters)
            for row in connection.execute(
                    f"""SELECT jid, COALESCE(NULLIF(full_name, ''), NULLIF(push_name, ''),
                      NULLIF(first_name, ''), NULLIF(business_name, ''), phone) AS name
                    FROM contacts WHERE jid IN ({marks})""", voters).fetchall():
                names[str(row["jid"])] = str(row["name"] or "")
        result: dict[str, dict[str, Any]] = {}
        for poll in polls:
            options = [str(option) for option in self._json_list(poll["options_json"])
                       if isinstance(option, str)][:12]
            chosen: dict[str, list[dict[str, Any]]] = {option: [] for option in options}
            for vote in votes:
                if str(vote["poll_msg_id"]) != str(poll["msg_id"]):
                    continue
                voter = aliases.get(str(vote["voter_jid"]), str(vote["voter_jid"]))
                mine = bool(own) and re.sub(r":[0-9]+@", "@", voter) == own
                person = {"jid": voter, "mine": mine,
                          "name": "You" if mine else (names.get(voter)
                                                     or voter.split("@", 1)[0])}
                for option in self._json_list(vote["selected_options_json"]):
                    if isinstance(option, str) and option in chosen:
                        chosen[option].append(person)
            result[str(poll["msg_id"])] = {
                "question": str(poll["question"] or "")[:512],
                "selectable": bounded_int(poll["selectable_count"], 1, 1, 12),
                "options": [{"text": option, "votes": len(chosen[option]),
                             "voters": [item["name"] for item in chosen[option]][:50],
                             "mine": any(item["mine"] for item in chosen[option])}
                            for option in options],
                "voters": len({vote["voter_jid"] for vote in votes
                               if str(vote["poll_msg_id"]) == str(poll["msg_id"])}),
            }
        return result

    def _own_jid(self, ask: bool = False) -> str:
        """This account's own user JID, without the device part.

        Read from the doctor answer the status poll keeps, so local views
        never start wacli for it; ``ask`` refreshes it when it is missing.
        """
        key = hashlib.sha256(self.active.key.encode("utf-8")).hexdigest()[:24]
        cache = self._read_state_json(DOCTOR_CACHE_FILE, MAX_DOCTOR_CACHE, {})
        item = cache.get(key) if isinstance(cache, dict) else None
        doctor = item.get("doctor") if isinstance(item, dict) else None
        linked = str(doctor.get("linked_jid") or "") if isinstance(doctor, dict) else ""
        if not linked and ask:
            linked = str(self._doctor_cached(self.active).get("linked_jid") or "")
        return re.sub(r":[0-9]+@", "@", linked)

    def _group_chat(self, jid: str) -> dict[str, str]:
        chat = self._chat(jid)
        if chat["kind"] != "group":
            raise OmaWhatsAppError("That chat is not a group.")
        return chat

    def group_info(self, jid: str, authorization: str = "") -> dict[str, Any]:
        """Live group settings from WhatsApp: an explicit remote read."""
        if authorization != "remote-read":
            raise OmaWhatsAppError("Reading group settings asks WhatsApp; pass authorization='remote-read'.")
        chat = self._group_chat(jid)
        envelope = self._envelope(self._mutate(
            ["--json", "groups", "info", "--jid", chat["jid"]], timeout=45, require_online=True))
        data = envelope.get("data") if isinstance(envelope.get("data"), dict) else {}
        own = self._own_jid(ask=True)
        role = ""
        participants = data.get("Participants") if isinstance(data.get("Participants"), list) else []
        for item in participants:
            if not isinstance(item, dict):
                continue
            ids = {str(item.get("JID") or ""), str(item.get("PhoneNumber") or "")}
            if own and own in ids:
                role = "superadmin" if item.get("IsSuperAdmin") else ("admin" if item.get("IsAdmin") else "member")
        return {
            "ok": True, "kind": "group-info", "jid": chat["jid"],
            "name": str(data.get("Name") or chat["name"])[:128],
            "description": str(data.get("Topic") or "")[:2048],
            "announce_only": data.get("IsAnnounce") is True,
            "locked": data.get("IsLocked") is True,
            "approval_required": data.get("IsJoinApprovalRequired") is True,
            "participant_count": len(participants),
            "my_role": role,
        }

    def _group_user(self, value: Any) -> str:
        raw = str(value or "").strip()
        if NEW_CHAT_JID.fullmatch(raw):
            return raw
        return "+" + self._phone_digits(raw)

    def group_action(self, jid: str, action: str, value: Any = None,
                     authorization: str = "") -> dict[str, Any]:
        """One admin or member action on a group, through wacli."""
        chat = self._group_chat(jid)
        target = chat["jid"]
        result: dict[str, Any] = {"ok": True, "kind": "group-action", "action": action, "jid": target}
        if action == "rename":
            name = " ".join(str(value or "").split())
            if not 1 <= len(name) <= 100:
                raise OmaWhatsAppError("A group name needs 1 to 100 characters.")
            command = ["groups", "rename", "--jid", target, "--name", name]
        elif action == "description":
            text = str(value or "").strip()
            if len(text) > 2048:
                raise OmaWhatsAppError("A group description can have up to 2048 characters.")
            command = ["groups", "description", "--jid", target, "--text", text]
        elif action in ("announce", "locked"):
            if not isinstance(value, bool):
                raise OmaWhatsAppError("That group setting must be on or off.")
            leaf = "announce-only" if action == "announce" else "locked"
            command = ["groups", leaf, "--jid", target, "--on" if value else "--off"]
        elif action == "add":
            users = value if isinstance(value, list) else [value]
            if not 1 <= len(users) <= 10:
                raise OmaWhatsAppError("Add 1 to 10 people at a time.")
            command = ["groups", "participants", "add", "--jid", target]
            for user in users:
                command.extend(["--user", self._group_user(user)])
        elif action in ("remove", "promote", "demote"):
            user = str(value or "").strip()
            self._group_participant(target, user)
            command = ["groups", "participants", action, "--jid", target, "--user", user]
        elif action in ("invite-get", "requests"):
            if authorization != "remote-read":
                raise OmaWhatsAppError("This asks WhatsApp; pass authorization='remote-read'.")
            command = (["groups", "invite", "link", "get", "--jid", target] if action == "invite-get"
                       else ["groups", "requests", "list", "--jid", target])
        elif action == "invite-revoke":
            command = ["groups", "invite", "link", "revoke", "--jid", target]
        elif action in ("approve", "reject"):
            user = str(value or "").strip()
            if not re.fullmatch(r"[0-9]{5,20}@(?:s\.whatsapp\.net|lid)", user):
                raise OmaWhatsAppError("Choose a pending request.")
            command = ["groups", "requests", action, "--jid", target, "--user", user]
        elif action == "leave":
            command = ["groups", "leave", "--jid", target]
        else:
            raise OmaWhatsAppError("That group action is not supported.")
        envelope = self._envelope(self._write(["--json", *command], timeout=60))
        data = envelope.get("data")
        if action in ("invite-get", "invite-revoke") and isinstance(data, dict):
            link = str(data.get("link") or "")
            if not link.startswith("https://chat.whatsapp.com/"):
                raise OmaWhatsAppError("WhatsApp returned no invite link.")
            result["link"] = link[:256]
        elif action == "requests":
            rows = data if isinstance(data, list) else []
            result["requests"] = [{
                "jid": str(row.get("JID") or "")[:160],
                "phone": str(row.get("phone_number") or "")[:32],
                "requested_at": str(row.get("RequestedAt") or "")[:40],
            } for row in rows[:256] if isinstance(row, dict) and row.get("JID")]
        elif action == "add" and isinstance(data, list):
            result["failed"] = [str(row.get("JID") or "")[:160] for row in data
                                if isinstance(row, dict) and int(row.get("Error") or 0) != 0]
        return result

    def chat_details(self, jid: str) -> dict[str, Any]:
        """Everything the mirror knows about one chat. Local only: no WhatsApp call."""
        chat = self._chat(jid)
        target = chat["jid"]
        live = "deleted_at IS NULL AND COALESCE(reaction_to_id, '') = ''"
        try:
            with closing(self._connect()) as connection:
                row = connection.execute(
                    f"""
                    SELECT chats.archived, chats.pinned, chats.muted_until,
                      (SELECT COUNT(*) FROM messages WHERE chat_jid = chats.jid AND {live}) AS total,
                      (SELECT MIN(ts) FROM messages WHERE chat_jid = chats.jid) AS since,
                      (SELECT COUNT(*) FROM messages WHERE chat_jid = chats.jid AND {live}
                        AND media_type IN ('image', 'video', 'gif')) AS media,
                      (SELECT COUNT(*) FROM messages WHERE chat_jid = chats.jid AND {live}
                        AND media_type = 'document') AS documents,
                      (SELECT COUNT(*) FROM messages WHERE chat_jid = chats.jid AND {live}
                        AND (text LIKE '%http://%' OR text LIKE '%https://%'
                          OR text LIKE '%www.%')) AS links,
                      (SELECT COUNT(*) FROM starred WHERE chat_jid = chats.jid) AS starred
                    FROM chats WHERE chats.jid = ?
                    """,
                    [target],
                ).fetchone()
                person: dict[str, Any] | None = None
                common: list[dict[str, str]] = []
                group: dict[str, Any] | None = None
                if chat["kind"] == "dm":
                    contact = connection.execute(
                        """SELECT contacts.phone, contacts.full_name, contacts.push_name,
                             contacts.business_name, aliases.alias
                           FROM (SELECT ? AS jid) AS wanted
                           LEFT JOIN contacts ON contacts.jid = wanted.jid
                           LEFT JOIN contact_aliases AS aliases ON aliases.jid = wanted.jid""",
                        [target],
                    ).fetchone()
                    phone = str(contact["phone"] or "") if contact is not None else ""
                    if not phone and target.endswith("@s.whatsapp.net"):
                        phone = target.split("@", 1)[0]
                    person = {
                        "phone": phone[:32],
                        "full_name": str(contact["full_name"] or "")[:128] if contact else "",
                        "push_name": str(contact["push_name"] or "")[:128] if contact else "",
                        "business_name": str(contact["business_name"] or "")[:128] if contact else "",
                        "alias": str(contact["alias"] or "")[:128] if contact else "",
                        "tags": sorted(str(item[0])[:64] for item in connection.execute(
                            "SELECT tag FROM contact_tags WHERE jid = ?", [target]).fetchall())
                            if self._has_table(connection, "contact_tags") else [],
                    }
                    common = [{"jid": str(item["jid"]), "name": str(item["name"])[:128]}
                              for item in connection.execute(
                        """SELECT groups.jid,
                             COALESCE(NULLIF(chats.name, ''), NULLIF(groups.name, ''), 'Group') AS name
                           FROM group_participants AS members
                           JOIN groups ON groups.jid = members.group_jid
                           LEFT JOIN chats ON chats.jid = groups.jid
                           WHERE members.user_jid = ? AND COALESCE(groups.left_at, 0) = 0
                             AND COALESCE(groups.is_parent, 0) = 0
                           ORDER BY name COLLATE NOCASE LIMIT 32""",
                        [target],
                    ).fetchall()]
                elif chat["kind"] == "group":
                    info = connection.execute(
                        """SELECT groups.owner_jid, groups.created_ts, groups.left_at
                           FROM groups WHERE groups.jid = ?""", [target]).fetchone()
                    group = {
                        "created_ts": int(info["created_ts"] or 0) if info else 0,
                        "owner_jid": str(info["owner_jid"] or "") if info else "",
                        "left": bool(info and info["left_at"]),
                    }
        except sqlite3.Error as exc:
            raise OmaWhatsAppError("The local WhatsApp index could not be read.") from exc
        if row is None:
            raise OmaWhatsAppError("That chat is not available in the local WhatsApp index.")
        output: dict[str, Any] = {
            "ok": True, "kind": "chat-details",
            "chat": chat, "account": self.active.name,
            "archived": bool(row["archived"]), "pinned": bool(row["pinned"]),
            "muted": muted_until_active(row["muted_until"]),
            "since": int(row["since"] or 0),
            "counts": {name: int(row[name] or 0)
                       for name in ("total", "media", "documents", "links", "starred")},
        }
        # Attachments of this chat not on this computer yet, for "Download missing".
        try:
            chat_jids = self._chat_jids(target)
            with closing(self._connect()) as connection:
                gone = self._media_gone()
                hints = self._sent_media_hints()

                def on_disk(message_id: str) -> bool:
                    # A file sent from here is on disk under its send hint.
                    hinted = str(hints.get(self._sent_hint_key(target, message_id), {})
                                 .get("local_path") or "")
                    return bool(hinted) and Path(hinted).is_file()

                output["counts"]["missing"] = sum(
                    1 for item in connection.execute(
                        f"""SELECT chat_jid, msg_id FROM messages
                        WHERE chat_jid IN ({",".join("?" for _ in chat_jids)})
                        AND media_type IN ('image', 'gif', 'video', 'audio', 'document', 'sticker')
                        AND COALESCE(local_path, '') = '' AND media_unavailable_at IS NULL
                        AND deleted_at IS NULL LIMIT 5000""", chat_jids).fetchall()
                    if f"{item[0]}\n{item[1]}" not in gone and not on_disk(str(item[1])))
        except (sqlite3.Error, OmaWhatsAppError):
            output["counts"]["missing"] = 0
        if person is not None:
            output["person"] = person
            output["groups_in_common"] = common
        if group is not None:
            members = self.members(target)["members"]
            owner = next((m for m in members if m.get("jid") == group["owner_jid"]), None)
            output["group"] = {
                "created_ts": group["created_ts"], "left": group["left"],
                "owner_name": str(owner["name"]) if owner else "",
                "participant_count": len(members),
            }
            own = self._own_jid()
            for member in members:
                member["me"] = bool(own) and member.get("jid") == own
            output["participants"] = members[:256]
            mine = next((m for m in members if m["me"]), None)
            output["group"]["my_role"] = str(mine["role"]) if mine else ""
        holder = {"account": self.active.name, "jid": target}
        self._attach_cached_avatars([holder], self.accounts())
        output["avatar_path"] = str(holder.get("avatar_path") or "")
        return output

    def members(self, jid: str, query: str = "", limit: int = 500) -> dict[str, Any]:
        """Return locally known group members for composer mention completion."""
        chat = self._chat(jid)
        cleaned = " ".join(query.split())[:128]
        limit = max(1, min(int(limit), 500))
        if chat["kind"] != "group":
            return {"ok": True, "chat": chat, "query": cleaned, "members": []}
        parameters: list[Any] = [chat["jid"], chat["jid"]]
        where = ""
        if cleaned:
            where = """WHERE LOWER(COALESCE(NULLIF(aliases.alias, ''),
              NULLIF(contacts.full_name, ''), NULLIF(contacts.business_name, ''),
              NULLIF(contacts.push_name, ''), NULLIF(contacts.system_name, ''),
              NULLIF(contacts.first_name, ''), NULLIF(candidates.sender_name, ''),
              NULLIF(contacts.phone, ''), candidates.jid)) LIKE LOWER(?) ESCAPE '\\'"""
            parameters.append(self._like(cleaned))
        parameters.append(limit)
        try:
            with closing(self._connect()) as connection:
                rows = connection.execute(
                    f"""
                    WITH candidates AS (
                      SELECT gp.user_jid AS jid, MAX(COALESCE(gp.role, '')) AS role,
                        MAX(COALESCE(recent.sender_name, '')) AS sender_name
                      FROM group_participants AS gp
                      LEFT JOIN messages AS recent
                        ON recent.rowid = (
                          SELECT rowid FROM messages
                          WHERE chat_jid = gp.group_jid
                            AND sender_jid = gp.user_jid AND from_me = 0
                          ORDER BY ts DESC, rowid DESC LIMIT 1)
                      WHERE gp.group_jid = ?
                      GROUP BY gp.user_jid
                      UNION
                      SELECT sender_jid AS jid, '' AS role,
                        MAX(COALESCE(sender_name, '')) AS sender_name
                      FROM messages
                      WHERE chat_jid = ? AND from_me = 0
                        AND COALESCE(sender_jid, '') <> ''
                      GROUP BY sender_jid
                    )
                    SELECT candidates.jid, MAX(candidates.role) AS role,
                      COALESCE(NULLIF(aliases.alias, ''),
                        NULLIF(contacts.full_name, ''), NULLIF(contacts.business_name, ''),
                        NULLIF(contacts.push_name, ''), NULLIF(contacts.system_name, ''),
                        NULLIF(contacts.first_name, ''), NULLIF(MAX(candidates.sender_name), ''),
                        NULLIF(contacts.phone, ''),
                        SUBSTR(candidates.jid, 1, INSTR(candidates.jid, '@') - 1)) AS name,
                      COALESCE(NULLIF(contacts.phone, ''),
                        SUBSTR(candidates.jid, 1, INSTR(candidates.jid, '@') - 1)) AS phone
                    FROM candidates
                    LEFT JOIN contacts ON contacts.jid = candidates.jid
                    LEFT JOIN contact_aliases AS aliases ON aliases.jid = candidates.jid
                    {where}
                    GROUP BY candidates.jid
                    ORDER BY CASE WHEN MAX(candidates.role) IN ('admin', 'superadmin')
                      THEN 0 ELSE 1 END, name COLLATE NOCASE
                    LIMIT ?
                    """,
                    parameters,
                ).fetchall()
        except sqlite3.Error as exc:
            raise OmaWhatsAppError("Group members could not be read from the local index.") from exc
        return {"ok": True, "chat": chat, "query": cleaned, "members": [{
            "jid": str(row["jid"]),
            "name": str(row["name"] or row["phone"] or "WhatsApp member")[:128],
            "phone": str(row["phone"] or "")[:64],
            "role": str(row["role"] or "member"),
        } for row in rows if str(row["jid"] or "").strip()]}

    @staticmethod
    def _json_list(value: Any) -> list[Any]:
        try:
            parsed = json.loads(str(value or "[]"))
        except json.JSONDecodeError:
            return []
        return parsed if isinstance(parsed, list) else []

    def _message(self, jid: str, message_id: str) -> tuple[dict[str, str], sqlite3.Row]:
        chat = self._chat(jid)
        target = message_id.strip()
        if not target or len(target) > 256:
            raise OmaWhatsAppError("Choose a message first.")
        try:
            with closing(self._connect()) as connection:
                chat_jids = self._chat_jids(chat["jid"])
                row = connection.execute(
                    f"""SELECT chat_jid, msg_id, sender_jid, sender_name, from_me, text,
                      media_type, deleted_at
                    FROM messages
                    WHERE chat_jid IN ({",".join("?" for _ in chat_jids)}) AND msg_id = ?
                      AND COALESCE(reaction_to_id, '') = ''
                    ORDER BY chat_jid = ? DESC LIMIT 1""",
                    [*chat_jids, target, chat["jid"]],
                ).fetchone()
        except sqlite3.Error as exc:
            raise OmaWhatsAppError("The local WhatsApp index could not be read.") from exc
        if row is None or row["deleted_at"] is not None:
            raise OmaWhatsAppError("That message is not available in this chat.")
        return chat, row

    def _media_row(self, chat: dict[str, Any], target: str) -> sqlite3.Row:
        try:
            with closing(self._connect()) as connection:
                chat_jids = self._chat_jids(chat["jid"])
                row = connection.execute(
                    f"""SELECT chat_jid, media_type, mime_type, filename, local_path,
                      media_unavailable_at
                    FROM messages
                    WHERE chat_jid IN ({",".join("?" for _ in chat_jids)}) AND msg_id = ?
                      AND deleted_at IS NULL AND COALESCE(reaction_to_id, '') = ''
                    ORDER BY chat_jid = ? DESC LIMIT 1""",
                    [*chat_jids, target, chat["jid"]],
                ).fetchone()
        except sqlite3.Error as exc:
            raise OmaWhatsAppError("The local WhatsApp index could not be read.") from exc
        if row is None or not str(row["media_type"] or ""):
            raise OmaWhatsAppError("That attachment is not available in this chat.")
        return row

    def _local_media_path(self, chat: dict[str, Any], target: str, row: sqlite3.Row) -> str:
        local_path = str(row["local_path"] or "")
        if local_path and Path(local_path).is_file():
            return local_path
        hint = self._sent_media_hints().get(self._sent_hint_key(chat["jid"], target), {})
        hinted = str(hint.get("local_path") or "")
        return hinted if hinted and Path(hinted).is_file() else ""

    @staticmethod
    def _safe_media_name(row: sqlite3.Row, target: str) -> str:
        name = Path(str(row["filename"] or "")).name
        name = re.sub(r"[^\w.\- ()]+", "_", name).strip(" .")[:120]
        if not name:
            extension = mimetypes.guess_extension(str(row["mime_type"] or "")) or ""
            name = re.sub(r"[^A-Za-z0-9]", "", target)[:32] + extension
        return name or "attachment"

    def _fetch_media_file(self, hint_jid: str, stored_jid: str, target: str,
                          row: sqlite3.Row) -> Path:
        """Download one attachment beside the live sync into the private folder."""
        folder = self.state_dir / "media" / hashlib.sha256(
            self.active.key.encode("utf-8")).hexdigest()[:16]
        folder.mkdir(parents=True, exist_ok=True, mode=0o700)
        stem = hashlib.sha256(f"{hint_jid}\n{target}".encode("utf-8")).hexdigest()[:16]
        destination = folder / f"{stem}-{self._safe_media_name(row, target)}"
        result = self._run(
            ["--read-only", "--json", "media", "download", "--chat", stored_jid,
             "--id", target, "--output", str(destination)],
            timeout=180,
        )
        envelope = self._envelope(result)
        data = envelope.get("data") if isinstance(envelope.get("data"), dict) else {}
        saved = Path(str(data.get("path") or destination))
        try:
            saved.resolve().relative_to(folder.resolve())
        except ValueError as exc:
            raise OmaWhatsAppError("wacli saved the attachment outside the media folder.") from exc
        if not saved.is_file() or saved.is_symlink():
            raise OmaWhatsAppError("The attachment download did not produce a file.")
        saved.chmod(0o600)
        self._remember_sent_media_best_effort(
            hint_jid, target, saved, str(row["mime_type"] or ""), str(row["media_type"] or ""))
        return saved

    def stickers(self, limit: int = MAX_STICKER_CHOICES) -> dict[str, Any]:
        """Recent stickers of this account, newest first, each file once."""
        limit = max(1, min(int(limit), MAX_STICKER_CHOICES))
        try:
            with closing(self._connect()) as connection:
                rows = connection.execute(
                    """SELECT chat_jid, msg_id, local_path, from_me, ts, media_type,
                         mime_type, filename, media_unavailable_at,
                         COALESCE(hex(file_sha256), '') AS sha
                       FROM messages
                       WHERE media_type = 'sticker' AND deleted_at IS NULL
                       ORDER BY ts DESC, rowid DESC LIMIT ?""",
                    [limit * 8],
                ).fetchall()
        except sqlite3.Error as exc:
            raise OmaWhatsAppError("The local WhatsApp index could not be read.") from exc
        seen: set[str] = set()
        gone = set(self._stickers_gone())
        choices: list[dict[str, Any]] = []
        for row in rows:
            identity = str(row["sha"] or "") or f"{row['chat_jid']}\n{row['msg_id']}"
            if identity in seen:
                continue
            seen.add(identity)
            path = self._local_media_path({"jid": str(row["chat_jid"])}, str(row["msg_id"]), row)
            if path and not path.casefold().endswith(".webp"):
                path = ""
            choices.append({
                "id": str(row["msg_id"])[:256], "chat": str(row["chat_jid"])[:160],
                "path": path, "from_me": bool(row["from_me"]),
                "unavailable": row["media_unavailable_at"] is not None
                or f"{row['chat_jid']}\n{row['msg_id']}" in gone,
            })
            if len(choices) >= limit:
                break
        return {"ok": True, "kind": "stickers", "stickers": choices}

    def _media_gone(self) -> set[str]:
        value = self._read_state_json(MEDIA_GONE_FILE, 512 * 1024, [])
        return {str(item) for item in value if isinstance(item, str)} if isinstance(value, list) else set()

    def _remember_media_gone(self, key: str) -> None:
        try:
            with self._state_lock("media-gone.lock"):
                current = self._read_state_json(MEDIA_GONE_FILE, 512 * 1024, [])
                current = [str(item) for item in current if isinstance(item, str)] \
                    if isinstance(current, list) else []
                merged = list(dict.fromkeys(current + [key]))
                self._write_state_json(MEDIA_GONE_FILE, merged[-MAX_MEDIA_GONE:], 512 * 1024)
        except (OmaWhatsAppError, OSError):
            pass

    def _stickers_gone(self) -> list[str]:
        value = self._read_state_json(STICKERS_GONE_FILE, 128 * 1024, [])
        return [str(item) for item in value if isinstance(item, str)] if isinstance(value, list) else []

    def fetch_stickers(self) -> dict[str, Any]:
        """Download the recent stickers that are not on this computer yet."""
        if not self.online():
            raise OmaWhatsAppError("Offline mode is on. Go online to load stickers.")
        started = time.monotonic()
        fetched = failed = 0
        gone = self._stickers_gone()
        newly_gone: list[str] = []
        try:
            with closing(self._connect()) as connection:
                for choice in self.stickers()["stickers"]:
                    key = f"{choice['chat']}\n{choice['id']}"
                    if choice["path"] or choice["unavailable"] or key in gone:
                        continue
                    if fetched + failed >= MAX_STICKER_FETCH \
                            or time.monotonic() - started >= STICKER_FETCH_SECONDS:
                        break
                    row = connection.execute(
                        """SELECT chat_jid, media_type, mime_type, filename, local_path
                           FROM messages WHERE chat_jid = ? AND msg_id = ?""",
                        [choice["chat"], choice["id"]]).fetchone()
                    if row is None:
                        continue
                    try:
                        self._fetch_media_file(choice["chat"], choice["chat"], choice["id"], row)
                        fetched += 1
                    except OmaWhatsAppError as exc:
                        failed += 1
                        if re.search(r"status code (403|404|410)", str(exc)):
                            newly_gone.append(key)
        except sqlite3.Error as exc:
            raise OmaWhatsAppError("The local WhatsApp index could not be read.") from exc
        if newly_gone:
            try:
                with self._state_lock("stickers-gone.lock"):
                    merged = list(dict.fromkeys(self._stickers_gone() + newly_gone))
                    self._write_state_json(STICKERS_GONE_FILE, merged[-MAX_STICKERS_GONE:], 128 * 1024)
            except (OmaWhatsAppError, OSError):
                pass
        result = self.stickers()
        result.update({"kind": "fetch-stickers", "fetched": fetched, "failed": failed})
        return result

    def download_media(self, jid: str, message_id: str) -> dict[str, Any]:
        """Fetch one attachment without taking wacli's store lock.

        `media download --read-only --output PATH` runs beside the live sync
        instead of pausing it; wacli does not record that path, so the file is
        kept in WhatsApp for Omarchy's own media folder and remembered in the private
        local-media index the timeline already consults.
        """
        chat = self._chat(jid)
        target = message_id.strip()
        if not target or len(target) > 256:
            raise OmaWhatsAppError("That attachment is missing its message ID.")
        row = self._media_row(chat, target)
        existing = self._local_media_path(chat, target, row)
        if existing:
            return {"ok": True, "kind": "media", "local_path": existing}
        gone_key = f"{row['chat_jid']}\n{target}"
        if row["media_unavailable_at"] is not None or gone_key in self._media_gone():
            raise OmaWhatsAppError("That older attachment is no longer available from WhatsApp.")
        if not self.online():
            raise OmaWhatsAppError("Offline mode is on. Go online to download attachments.")
        try:
            saved = self._fetch_media_file(chat["jid"], str(row["chat_jid"]), target, row)
        except OmaWhatsAppError as exc:
            if re.search(r"status code (403|404|410)", str(exc)):
                self._remember_media_gone(gone_key)
                raise OmaWhatsAppError(
                    "That older attachment is no longer available from WhatsApp.") from exc
            raise
        return {"ok": True, "kind": "media", "local_path": str(saved)}

    def save_media(self, jid: str, message_id: str, destination: Any,
                   replace: bool = False) -> dict[str, Any]:
        """Copy one attachment to a path the user chose in a save dialog.

        A file already there is replaced only with `replace`, which the app
        sends once the save dialog has asked the user."""
        if not isinstance(destination, str) or not destination.strip():
            raise OmaWhatsAppError("Choose where to save the attachment.")
        target_path = Path(destination).expanduser()
        if not target_path.is_absolute() or not target_path.parent.is_dir():
            raise OmaWhatsAppError("That folder does not exist.")
        if target_path.is_symlink() or target_path.is_dir():
            raise OmaWhatsAppError("Choose a file name, not a folder or a link.")
        if os.path.lexists(target_path) and replace is not True:
            raise OmaWhatsAppError("A file with that name is already there; choose another name.")
        source = Path(self.download_media(jid, message_id)["local_path"])
        temporary = target_path.with_name(f".{target_path.name}.{secrets.token_hex(6)}.part")
        try:
            shutil.copyfile(source, temporary, follow_symlinks=False)
            os.replace(temporary, target_path)
        except OSError as exc:
            try:
                temporary.unlink()
            except OSError:
                pass
            raise OmaWhatsAppError("The attachment could not be saved there.") from exc
        return {"ok": True, "kind": "save-media", "path": str(target_path)}

    @staticmethod
    def _envelope(result: subprocess.CompletedProcess[str]) -> dict[str, Any]:
        raw = result.stdout.strip() or result.stderr.strip()
        try:
            value = json.loads(raw or "{}")
        except json.JSONDecodeError:
            value = {}
        if result.returncode == 0 and isinstance(value, dict) and value.get("success") is True:
            return value
        error = value.get("error") if isinstance(value, dict) else None
        message = error.get("message") if isinstance(error, dict) else error
        cleaned = clean_error(message or result.stderr, "WhatsApp rejected the request.")
        if "store is locked" in cleaned.casefold() or "another wacli is running" in cleaned.casefold():
            cleaned = "WhatsApp is busy with maintenance. Your draft is safe; try again shortly."
        raise OmaWhatsAppError(cleaned)

    @staticmethod
    def _sent_message_id(envelope: dict[str, Any]) -> str:
        data = envelope.get("data")
        return str(data.get("id") or "") if isinstance(data, dict) else ""

    def _reply_args(
        self, chat: dict[str, str], reply_id: str,
    ) -> tuple[str, list[str]]:
        if not reply_id.strip():
            return "", []
        _, reply = self._message(chat["jid"], reply_id)
        quoted_id = str(reply["msg_id"])
        args = ["--reply-to", quoted_id]
        sender = str(reply["sender_jid"] or "")
        if chat["kind"] == "group" and sender:
            args.extend(["--reply-to-sender", sender])
        return quoted_id, args

    def presence(self, action: str, jid: str = "", lease: Any = None) -> dict[str, Any]:
        """Show this account online, offline, or follow a person's presence.

        Only through the running sync, which owns the connection: wacli
        refuses these without it, and the sync is never paused for them,
        because a paused sync loses what arrives meanwhile. The official wacli
        has no such commands; the answer then says so and the app stops asking.
        """
        if action not in ("available", "unavailable", "subscribe"):
            raise OmaWhatsAppError("Choose available, unavailable or subscribe.")
        if action != "unavailable" and not self.online(self.active):
            return {"ok": True, "skipped": "offline"}
        command = ["--json", "presence", action]
        if action == "available":
            command.extend(["--lease", f"{bounded_int(lease, 90, 30, 600)}s"])
        if action == "subscribe":
            chat = self._chat(jid)
            if chat["kind"] != "dm":
                raise OmaWhatsAppError("Only a person's presence can be followed.")
            command.extend(["--to", chat["jid"]])
        result = self._run(command, timeout=15)
        if result.returncode != 0:
            detail = f"{result.stderr or ''}\n{result.stdout or ''}"
            supported = "unknown command" not in detail and "unknown flag" not in detail
            return {"ok": False, "supported": supported,
                    "error": "wacli could not change presence." if supported
                    else "This wacli build does not follow presence."}
        envelope = self._envelope(result)
        data = envelope.get("data") if isinstance(envelope.get("data"), dict) else {}
        answer: dict[str, Any] = {"ok": True, "action": action}
        if action == "available":
            answer["until"] = str(data.get("until") or "")[:40]
        if action == "subscribe":
            answer["sent_now"] = data.get("sent_now") is True
        return answer

    def _validated_mentions(self, chat: dict[str, str], values: Any) -> list[str]:
        if values in (None, []):
            return []
        if chat["kind"] != "group":
            raise OmaWhatsAppError("Mentions are only available in group chats.")
        if not isinstance(values, list) or len(values) > 32:
            raise OmaWhatsAppError("Choose no more than 32 people to mention.")
        mentions: list[str] = []
        for value in values:
            target = str(value or "").strip()
            if not target or len(target) > 160 or target in mentions:
                continue
            mentions.append(target)
        known = {member["jid"] for member in self.members(chat["jid"])["members"]}
        if any(target not in known for target in mentions):
            raise OmaWhatsAppError("A selected mention is not a member of this group.")
        return mentions

    def send(self, jid: str, text: str, reply_id: str = "", mentions: Any = None) -> dict[str, Any]:
        chat = self._chat(jid)
        message = text.strip()
        if not message:
            raise OmaWhatsAppError("Type a message first.")
        if len(message) > MAX_MESSAGE:
            raise OmaWhatsAppError("Message is too long (maximum 4096 characters).")
        command = ["--json", "send", "text", "--to", chat["jid"],
            "--message", message, "--post-send-wait", "0"]
        for target in self._validated_mentions(chat, mentions):
            command.extend(["--mention", target])
        quoted_id, reply_args = self._reply_args(chat, reply_id)
        command.extend(reply_args)
        result = self._write(command, timeout=45)
        envelope = self._envelope(result)
        message_id = self._sent_message_id(envelope)
        self._remember_sent_reply_best_effort(chat["jid"], message_id, quoted_id)
        # The UI shows the message at once as pending and swaps in the stored
        # row carrying this id.
        return {"ok": True, "message_id": message_id[:256]}

    @staticmethod
    def _phone_digits(value: Any) -> str:
        raw = str(value or "").strip()
        if not raw or len(raw) > 40 or not re.fullmatch(r"\+?[0-9 ().\-]+", raw):
            raise OmaWhatsAppError("Type a phone number with its country code.")
        digits = re.sub(r"\D", "", raw)
        if not 7 <= len(digits) <= 15 or digits.startswith("0"):
            raise OmaWhatsAppError("Type a phone number with its country code.")
        return digits

    @classmethod
    def _store_schema_version(cls, connection: sqlite3.Connection) -> int:
        """The newest wacli store migration applied, 0 when unknown."""
        try:
            if not cls._has_table(connection, "schema_migrations"):
                return 0
            row = connection.execute("SELECT MAX(version) FROM schema_migrations").fetchone()
            return int(row[0] or 0) if row else 0
        except (sqlite3.Error, TypeError, ValueError):
            return 0

    @classmethod
    def _delivery_status(cls, connection: sqlite3.Connection,
                         keys: list[tuple[str, str]]) -> dict[tuple[str, str], str]:
        """Delivery state of sent messages, from wacli builds that keep receipts.

        Official wacli keeps none, so the table may be missing; a message
        without a row has no known state and shows no tick.
        """
        if not keys or not cls._has_table(connection, "message_status"):
            return {}
        found: dict[tuple[str, str], str] = {}
        by_chat: dict[str, list[str]] = {}
        for chat_jid, message_id in keys:
            by_chat.setdefault(chat_jid, []).append(message_id)
        for chat_jid, ids in by_chat.items():
            for start in range(0, len(ids), 400):
                chunk = ids[start:start + 400]
                rows = connection.execute(
                    f"""SELECT msg_id, status FROM message_status
                    WHERE chat_jid = ? AND msg_id IN ({",".join("?" for _ in chunk)})""",
                    [chat_jid, *chunk],
                ).fetchall()
                for row in rows:
                    code = row["status"]
                    if isinstance(code, int) and 0 <= code < len(DELIVERY_STATES):
                        found[(chat_jid, str(row["msg_id"]))] = DELIVERY_STATES[code]
        return found

    @staticmethod
    def _has_table(connection: sqlite3.Connection, name: str) -> bool:
        return connection.execute(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", [name]
        ).fetchone() is not None

    def contacts_search(self, query: str = "", limit: int = 40,
                        tag: str = "") -> dict[str, Any]:
        """Local only: the people this account's mirror knows, for a new chat.

        ``tag`` keeps the people carrying one wacli contact tag. Each person
        also reports the alias and tags you gave them.
        """
        cleaned = " ".join(str(query or "").split())[:128]
        wanted_tag = " ".join(str(tag or "").split())[:64]
        limit = max(1, min(int(limit), 80))
        digits = re.sub(r"\D", "", cleaned)
        phone_sql = """COALESCE(NULLIF(contacts.phone, ''),
          SUBSTR(people.jid, 1, INSTR(people.jid, '@') - 1))"""
        try:
            with closing(self._connect()) as connection:
                has_aliases = self._has_table(connection, "contact_aliases")
                has_tags = self._has_table(connection, "contact_tags")
                if wanted_tag and not has_tags:
                    return {"ok": True, "query": cleaned, "tag": wanted_tag, "people": []}
                alias_sql = ("(SELECT alias FROM contact_aliases WHERE jid = people.jid)"
                             if has_aliases else "''")
                tags_sql = ("(SELECT GROUP_CONCAT(tag, char(10)) FROM contact_tags "
                            "WHERE jid = people.jid)" if has_tags else "''")
                name_sql = f"""COALESCE(NULLIF({alias_sql}, ''), NULLIF(contacts.full_name, ''),
                  NULLIF(chats.name, ''), NULLIF(contacts.business_name, ''),
                  NULLIF(contacts.push_name, ''), NULLIF(contacts.system_name, ''),
                  NULLIF(contacts.first_name, ''), '')"""
                tag_where = ("AND EXISTS (SELECT 1 FROM contact_tags WHERE "
                             "contact_tags.jid = people.jid AND LOWER(contact_tags.tag) = LOWER(?))"
                             if wanted_tag else "")
                parameters: list[Any] = [cleaned, self._like(cleaned), digits, self._like(digits)]
                if wanted_tag:
                    parameters.append(wanted_tag)
                parameters.append(limit)
                rows = connection.execute(
                    f"""
                    WITH people(jid) AS (
                      SELECT jid FROM contacts WHERE jid LIKE '%@s.whatsapp.net'
                      UNION
                      SELECT jid FROM chats
                      WHERE kind IN ('dm', 'unknown') AND jid LIKE '%@s.whatsapp.net')
                    SELECT people.jid AS jid, {name_sql} AS name, {phone_sql} AS phone,
                      chats.jid IS NOT NULL AS has_chat,
                      COALESCE({alias_sql}, '') AS alias, COALESCE({tags_sql}, '') AS tags,
                      COALESCE(chats.last_message_ts, 0) AS ts
                    FROM people
                    LEFT JOIN contacts ON contacts.jid = people.jid
                    LEFT JOIN chats ON chats.jid = people.jid
                    WHERE (? = ''
                      OR LOWER({name_sql}) LIKE LOWER(?) ESCAPE '\\'
                      OR (? <> '' AND {phone_sql} LIKE ? ESCAPE '\\'))
                      {tag_where}
                    ORDER BY {name_sql} = '', LOWER({name_sql}), {phone_sql}
                    LIMIT ?
                    """,
                    parameters,
                ).fetchall()
        except sqlite3.Error as exc:
            raise OmaWhatsAppError("The local WhatsApp index could not be read.") from exc
        people = [{
            "jid": str(row["jid"]),
            "name": str(row["name"] or "")[:128],
            "phone": str(row["phone"] or "")[:32],
            "has_chat": bool(row["has_chat"]),
            "alias": str(row["alias"] or "")[:128],
            "tags": sorted(tag for tag in str(row["tags"] or "").split("\n") if tag),
        } for row in rows]
        result: dict[str, Any] = {"ok": True, "query": cleaned, "people": people}
        if wanted_tag:
            result["tag"] = wanted_tag
        return result

    def contact_tags(self) -> dict[str, Any]:
        """Local only: every contact tag in this account and how many carry it."""
        try:
            with closing(self._connect()) as connection:
                if not self._has_table(connection, "contact_tags"):
                    return {"ok": True, "tags": []}
                rows = connection.execute(
                    "SELECT MIN(tag) AS tag, COUNT(*) AS people FROM contact_tags "
                    "GROUP BY LOWER(tag) ORDER BY LOWER(tag) LIMIT 200"
                ).fetchall()
        except sqlite3.Error as exc:
            raise OmaWhatsAppError("The local WhatsApp index could not be read.") from exc
        return {"ok": True, "tags": [
            {"tag": str(row["tag"])[:64], "people": int(row["people"])} for row in rows]}

    ATTACHMENT_KINDS: dict[str, tuple[str, ...]] = {
        "image": ("image", "gif"), "video": ("video",), "audio": ("audio",),
        "document": ("document",), "sticker": ("sticker",), "location": ("location",),
    }

    def attachments(self, jid: str = "", sender: str = "", kinds: Any = None,
                    direction: str = "any", after: Any = None, before: Any = None,
                    limit: Any = 40, missing_only: bool = False) -> dict[str, Any]:
        """Local only: attachments newest first, in one chat or across the rail.

        ``after`` and ``before`` are epoch seconds. ``missing_only`` keeps the
        ones not yet on this computer, which ``media`` can then download.
        """
        count = bounded_int(limit, 40, 1, 200)
        requested = kinds if isinstance(kinds, list) else ([kinds] if kinds else [])
        types: list[str] = []
        for kind in requested:
            key = str(kind or "").strip().lower()
            if key not in self.ATTACHMENT_KINDS:
                raise OmaWhatsAppError(
                    "Choose attachment kinds among image, video, audio, document, sticker and location.")
            types.extend(self.ATTACHMENT_KINDS[key])
        if not types:
            types = [kind for group in self.ATTACHMENT_KINDS.values() for kind in group]
        if direction not in ("any", "received", "sent"):
            raise OmaWhatsAppError("Choose received, sent or any.")
        aliases = self._lid_aliases()
        where = [f"base.media_type IN ({','.join('?' for _ in types)})",
                 "base.deleted_at IS NULL", "COALESCE(base.reaction_to_id, '') = ''"]
        parameters: list[Any] = list(types)
        if jid:
            chat_jids = self._chat_jids(self._chat(jid)["jid"])
            where.append(f"base.chat_jid IN ({','.join('?' for _ in chat_jids)})")
            parameters.extend(chat_jids)
        if sender:
            target = str(sender).strip()[:160]
            senders = [target] + [lid for lid, phone in aliases.items() if phone == target]
            where.append(f"base.sender_jid IN ({','.join('?' for _ in senders)})")
            parameters.extend(senders)
        if direction != "any":
            where.append("base.from_me = ?")
            parameters.append(1 if direction == "sent" else 0)
        if after not in (None, ""):
            where.append("base.ts > ?")
            parameters.append(bounded_int(after, 0, 0, 2**63 - 1))
        if before not in (None, ""):
            where.append("base.ts < ?")
            parameters.append(bounded_int(before, 2**63 - 1, 0, 2**63 - 1))
        if missing_only:
            where.append("COALESCE(base.local_path, '') = ''")
        # A few extra rows cover the ones whose chat sits outside the rail.
        parameters.append(count * 3)
        try:
            with closing(self._connect()) as connection:
                rows = connection.execute(
                    f"""SELECT base.chat_jid, base.msg_id, base.sender_jid, base.sender_name,
                      base.ts, base.from_me, base.media_type, base.media_caption,
                      base.filename, base.mime_type, base.local_path, base.file_length,
                      base.media_unavailable_at,
                      location.latitude, location.longitude, location.name AS location_name,
                      location.address AS location_address
                    FROM messages AS base
                    LEFT JOIN message_locations AS location
                      ON location.chat_jid = base.chat_jid AND location.msg_id = base.msg_id
                    WHERE {" AND ".join(where)}
                    ORDER BY base.ts DESC, base.rowid DESC
                    LIMIT ?""",
                    parameters,
                ).fetchall()
        except sqlite3.Error as exc:
            raise OmaWhatsAppError("The local WhatsApp index could not be read.") from exc
        chats: dict[str, dict[str, str] | None] = {}
        items: list[dict[str, Any]] = []
        gone = self._media_gone()
        for row in rows:
            stored = str(row["chat_jid"])
            folded = aliases.get(stored, stored)
            if folded not in chats:
                try:
                    chats[folded] = self._chat(folded)
                except OmaWhatsAppError:
                    chats[folded] = None
            chat = chats[folded]
            if chat is None:
                continue
            target = str(row["msg_id"])
            local_path = self._local_media_path(chat, target, row)
            if missing_only and local_path:
                continue
            item: dict[str, Any] = {
                "chat_jid": chat["jid"], "chat_name": chat["name"], "chat_kind": chat["kind"],
                "id": target, "timestamp": int(row["ts"] or 0), "from_me": bool(row["from_me"]),
                "sender_jid": str(row["sender_jid"] or ""),
                "sender": str(row["sender_name"] or ""),
                "media_type": str(row["media_type"] or ""),
                "filename": str(row["filename"] or ""),
                "mime_type": str(row["mime_type"] or ""),
                "caption": str(row["media_caption"] or ""),
                "file_size": int(row["file_length"] or 0),
                "local_path": local_path,
                "available": row["media_unavailable_at"] is None
                    and f"{row['chat_jid']}\n{target}" not in gone,
            }
            if row["latitude"] is not None:
                item.update(latitude=row["latitude"], longitude=row["longitude"],
                            location_name=str(row["location_name"] or ""),
                            location_address=str(row["location_address"] or ""))
            items.append(item)
            if len(items) >= count:
                break
        return {"ok": True, "kind": "attachments", "attachments": items}

    def _known_person(self, jid: str) -> dict[str, Any] | None:
        try:
            with closing(self._connect()) as connection:
                row = connection.execute(
                    """SELECT (SELECT COUNT(*) FROM contacts WHERE jid = ?)
                         + (SELECT COUNT(*) FROM chats WHERE jid = ?) AS known,
                         (SELECT COUNT(*) FROM chats WHERE jid = ?) AS has_chat""",
                    [jid, jid, jid],
                ).fetchone()
        except sqlite3.Error as exc:
            raise OmaWhatsAppError("The local WhatsApp index could not be read.") from exc
        if row is None or not int(row["known"] or 0):
            return None
        return {"jid": jid, "has_chat": bool(int(row["has_chat"] or 0))}

    def _new_chat_checks(self) -> dict[str, dict[str, Any]]:
        value = self._read_state_json(NEW_CHAT_CHECKS_FILE, MAX_NEW_CHAT_STATE, {})
        if not isinstance(value, dict):
            return {}
        now = int(time.time())
        clean: dict[str, dict[str, Any]] = {}
        for key, item in value.items():
            if not isinstance(key, str) or key.count("\n") != 1 or not isinstance(item, dict):
                continue
            jid = str(item.get("jid") or "")
            checked = bounded_int(item.get("checked_at"), 0, 0, 2**63 - 1)
            if NEW_CHAT_JID.fullmatch(jid) and now - checked < NEW_CHAT_CHECK_TTL:
                clean[key] = {"jid": jid, "checked_at": checked}
        return clean

    def _remember_new_chat_check(self, digits: str, jid: str) -> None:
        try:
            with self._state_lock("new-chat-checks.lock"):
                checks = self._new_chat_checks()
                checks[f"{self.active.name}\n{digits}"] = {
                    "jid": jid, "checked_at": int(time.time())}
                ordered = sorted(checks.items(), key=lambda pair: pair[1]["checked_at"])
                self._write_state_json(
                    NEW_CHAT_CHECKS_FILE, dict(ordered[-MAX_NEW_CHAT_CHECKS:]),
                    MAX_NEW_CHAT_STATE)
        except (OmaWhatsAppError, OSError):
            pass

    def check_number(self, phone: Any, authorization: str = "") -> dict[str, Any]:
        """Ask WhatsApp whether a number is registered; nothing is stored in wacli."""
        if authorization != "remote-read":
            raise OmaWhatsAppError(
                "Checking a number asks WhatsApp; pass authorization='remote-read'."
            )
        digits = self._phone_digits(phone)
        result = self._mutate(
            ["--json", "contacts", "check", "+" + digits],
            timeout=45, require_online=True,
        )
        envelope = self._envelope(result)
        data = envelope.get("data")
        rows = data if isinstance(data, list) else []
        match = next((row for row in rows if isinstance(row, dict)
                      and str(row.get("phone") or "") == digits), None)
        if match is None and len(rows) == 1 and isinstance(rows[0], dict):
            match = rows[0]
        if match is None or match.get("responded") is not True:
            raise OmaWhatsAppError("WhatsApp did not answer for that number. Try again.")
        jid = str(match.get("jid") or "")
        registered = match.get("registered") is True and bool(NEW_CHAT_JID.fullmatch(jid))
        output: dict[str, Any] = {
            "ok": True, "kind": "check-number", "phone": digits,
            "registered": registered, "jid": jid if registered else "",
            "has_chat": False, "name": "",
        }
        if registered:
            self._remember_new_chat_check(digits, jid)
            # The mirror files a person's chat under their phone JID even when
            # WhatsApp answered with the @lid, so look for both.
            for candidate in dict.fromkeys([jid, f"{digits}@s.whatsapp.net"]):
                known = self._known_person(candidate)
                if known is not None and known["has_chat"]:
                    output.update(has_chat=True, jid=candidate,
                                  name=self._chat(candidate)["name"])
                    break
        return output

    def _chat_of_message(self, message_id: str) -> str:
        if not message_id:
            return ""
        try:
            with closing(self._connect()) as connection:
                row = connection.execute(
                    "SELECT chat_jid FROM messages WHERE msg_id = ? AND from_me = 1 "
                    "ORDER BY ts DESC LIMIT 1", [message_id]).fetchone()
        except sqlite3.Error:
            return ""
        return str(row["chat_jid"]) if row is not None else ""

    def send_new(self, target: Any, text: str) -> dict[str, Any]:
        """First message to someone: the recipient is known locally or was just confirmed."""
        request_target = target if isinstance(target, dict) else {}
        message = str(text or "").strip()
        if not message:
            raise OmaWhatsAppError("Type a message first.")
        if len(message) > MAX_MESSAGE:
            raise OmaWhatsAppError("Message is too long (maximum 4096 characters).")
        jid = str(request_target.get("jid") or "").strip()
        digits = ""
        if jid:
            if not NEW_CHAT_JID.fullmatch(jid):
                raise OmaWhatsAppError("Choose a person from your WhatsApp contacts.")
            known = self._known_person(jid)
            confirmed = [key.split("\n", 1)[1] for key, item in self._new_chat_checks().items()
                         if item["jid"] == jid and key.startswith(self.active.name + "\n")]
            if known is None and not confirmed:
                raise OmaWhatsAppError("Check that number with WhatsApp first.")
            digits = confirmed[0] if confirmed else ""
        else:
            digits = self._phone_digits(request_target.get("phone"))
            cached = self._new_chat_checks().get(f"{self.active.name}\n{digits}")
            if cached is None:
                raise OmaWhatsAppError("Check that number with WhatsApp first.")
            jid = cached["jid"]
            known = self._known_person(jid)
        if known is not None and known["has_chat"]:
            self.send(jid, message)
            return {"ok": True, "kind": "send-new", "jid": jid, "chat_jid": jid}
        command = ["--json", "send", "text", "--to", jid,
                   "--message", message, "--post-send-wait", "0"]
        envelope = self._envelope(self._write(command, timeout=45))
        # wacli stores the new chat under the phone JID when it knows the
        # mapping; the sent message says exactly where it landed.
        chat_jid = self._chat_of_message(self._sent_message_id(envelope))
        if not chat_jid:
            chat_jid = f"{digits}@s.whatsapp.net" if digits and jid.endswith("@lid") else jid
        return {"ok": True, "kind": "send-new", "jid": jid, "chat_jid": chat_jid}

    def react(self, jid: str, message_id: str, emoji: str) -> dict[str, Any]:
        chat, message = self._message(jid, message_id)
        reaction = emoji.strip()
        if len(reaction) > 16 or "\n" in reaction:
            raise OmaWhatsAppError("That reaction is not valid.")
        command = ["--json", "send", "react", "--to", chat["jid"],
            "--id", str(message["msg_id"]), "--reaction", reaction,
            "--post-send-wait", "0"]
        sender = str(message["sender_jid"] or "")
        if chat["kind"] == "group" and sender:
            command.extend(["--sender", sender])
        self._envelope(self._write(command, timeout=45))
        return {"ok": True, "kind": "react"}

    def edit_message(self, jid: str, message_id: str, text: str) -> dict[str, Any]:
        chat, message = self._message(jid, message_id)
        value = text.strip()
        if not bool(message["from_me"]):
            raise OmaWhatsAppError("Only your own messages can be edited.")
        if str(message["media_type"] or ""):
            raise OmaWhatsAppError("Only sent text messages can be edited.")
        if not value:
            raise OmaWhatsAppError("An edited message cannot be empty.")
        if len(value) > MAX_MESSAGE:
            raise OmaWhatsAppError("Message is too long (maximum 4096 characters).")
        command = ["--json", "messages", "edit", "--chat", str(message["chat_jid"]),
            "--id", str(message["msg_id"]), "--message", value,
            "--post-send-wait", "0"]
        self._envelope(self._write(command, timeout=45))
        return {"ok": True, "kind": "edit"}

    def delete_message(self, jid: str, message_id: str, for_me: bool) -> dict[str, Any]:
        chat, message = self._message(jid, message_id)
        if not for_me and not bool(message["from_me"]):
            raise OmaWhatsAppError("Only your own messages can be deleted for everyone.")
        command = ["--json", "messages", "delete", "--chat", str(message["chat_jid"]),
            "--id", str(message["msg_id"]), "--post-send-wait", "0"]
        if for_me:
            command.append("--for-me")
        self._envelope(self._write(command, timeout=45))
        return {"ok": True, "kind": "delete"}

    def chat_presence(self, jid: str, state: str) -> dict[str, Any]:
        """Tell the chat you are typing, recording audio, or stopped.

        Best effort and only through the running sync: an indicator never
        stops sync or opens a second session, so without one it is skipped.
        """
        if state not in {"typing", "recording", "paused"}:
            raise OmaWhatsAppError("Typing state must be typing, recording, or paused.")
        chat = self._chat(jid)
        if not self.online() or not self._sync_active():
            return {"ok": True, "kind": "chat-presence", "state": state, "sent": False}
        command = ["--json", "presence", "paused" if state == "paused" else "typing",
                   "--to", chat["jid"]]
        if state == "recording":
            command.extend(["--media", "audio"])
        result = self._run(command, timeout=15)
        return {"ok": True, "kind": "chat-presence", "state": state, "sent": result.returncode == 0}

    def star_message(self, jid: str, message_id: str, starred: bool) -> dict[str, Any]:
        """Star or unstar a message on every linked device (a wacli build that stars)."""
        _chat, message = self._message(jid, message_id)
        command = ["--json", "messages", "star", "--chat", str(message["chat_jid"]),
                   "--id", str(message["msg_id"])]
        if not starred:
            command.append("--unstar")
        result = self._write(command, timeout=60)
        if result.returncode != 0 and "unknown command" in f"{result.stdout}{result.stderr}".lower():
            raise OmaWhatsAppError("This wacli build cannot star messages; install one that can.")
        self._envelope(result)
        return {"ok": True, "kind": "star", "starred": bool(starred)}

    def forward_message(self, jid: str, message_id: str, to_jid: str,
                        to_phone: Any = "") -> dict[str, Any]:
        source, message = self._message(jid, message_id)
        if str(to_phone or "").strip():
            # A typed number with no chat yet: only one WhatsApp just confirmed,
            # the same rule as a first message.
            digits = self._phone_digits(to_phone)
            phone_jid = f"{digits}@s.whatsapp.net"
            try:
                target = self._chat(phone_jid)
            except OmaWhatsAppError:
                cached = self._new_chat_checks().get(f"{self.active.name}\n{digits}")
                if cached is None:
                    raise OmaWhatsAppError("Check that number with WhatsApp first.") from None
                target = {"jid": cached["jid"], "name": "+" + digits}
        else:
            target = self._chat(to_jid)
            phone_jid = ""
        command = ["--json", "messages", "forward", "--chat", str(message["chat_jid"]),
            "--id", str(message["msg_id"]), "--to", target["jid"],
            "--post-send-wait", "0"]
        envelope = self._envelope(self._write(command, timeout=90))
        data = envelope.get("data") if isinstance(envelope.get("data"), dict) else {}
        forwarded_id = str(data.get("id") or "").strip()[:256]
        if forwarded_id and message["media_type"]:
            self._share_forwarded_media(source["jid"], message, target["jid"], forwarded_id)
        return {"ok": True, "kind": "forward", "target": target["name"],
                "target_jid": phone_jid if phone_jid and str(target["jid"]).endswith("@lid")
                else target["jid"], "message_id": forwarded_id}

    def _share_forwarded_media(self, source_jid: str, message: sqlite3.Row,
                               target_jid: str, forwarded_id: str) -> None:
        """A forwarded copy shows the file already on this computer.

        A download of the original is wacli's own local path; a file sent
        from here only lives in the sent-media hints. Either way the copy is
        pointed at it, so the target chat never offers to download it again.
        """
        hint = self._sent_media_hints().get(
            self._sent_hint_key(source_jid, str(message["msg_id"])), {})
        path = Path(str(hint.get("local_path") or ""))
        if not path.is_file():
            try:
                row = self._media_row({"jid": source_jid}, str(message["msg_id"]))
            except OmaWhatsAppError:
                return
            path = Path(str(row["local_path"] or ""))
            if not path.is_absolute() or not path.is_file():
                return
            mime = str(row["mime_type"] or "")
        else:
            mime = str(hint.get("mime_type") or "")
        self._remember_sent_media_best_effort(
            target_jid, forwarded_id, path, mime, str(message["media_type"]))

    def export_chat(self, jid: str, destination: Any, replace: bool = False) -> dict[str, Any]:
        """Write one chat as readable text, like the phone's Export chat.

        A file already there is replaced only with `replace`, as in save_media."""
        chat = self._chat(jid)
        target = Path(str(destination or "")).expanduser()
        if not target.is_absolute() or target.name in {"", ".", ".."}:
            raise OmaWhatsAppError("Choose where to save the export.")
        try:
            home = HOME.resolve(strict=True)
            parent = target.parent.resolve(strict=True)
        except OSError as exc:
            raise OmaWhatsAppError("That folder does not exist.") from exc
        if parent != home and home not in parent.parents:
            raise OmaWhatsAppError("Save the export inside your home folder.")
        if any((folder / ".git").exists() for folder in (parent, *parent.parents)
               if folder == home or home in folder.parents):
            raise OmaWhatsAppError("Save the export outside a code repository; it holds private messages.")
        destination_path = parent / target.name
        if destination_path.is_symlink() or destination_path.is_dir():
            raise OmaWhatsAppError("Choose a file name, not a folder or a link.")
        if os.path.lexists(destination_path) and replace is not True:
            raise OmaWhatsAppError("A file with that name is already there; choose another name.")
        rows: list[dict[str, Any]] = []
        cursor: Any = None
        while True:
            page = self.messages(chat["jid"], "", 500, cursor)
            rows.extend(page["messages"])
            if not page["has_more"] or not page["messages"] or len(rows) >= 200000:
                break
            last = page["messages"][-1]
            cursor = {"ts": last["timestamp"], "id": last["id"]}
        lines = [f"WhatsApp chat with {chat['name']}"]
        for row in reversed(rows):
            when = time.strftime("%Y-%m-%d %H:%M", time.localtime(int(row["timestamp"])))
            who = "You" if row.get("from_me") else (row.get("sender") or chat["name"])
            if row.get("revoked"):
                body = "This message was deleted"
            elif row.get("poll"):
                poll = row["poll"]
                body = "POLL: " + str(poll.get("question") or "") + "".join(
                    f"\nOPTION: {option['text']} ({option['votes']} votes)" for option in poll["options"])
            elif row.get("media_type") == "location":
                body = (f"location: https://www.openstreetmap.org/?mlat={row.get('latitude')}"
                        f"&mlon={row.get('longitude')} {row.get('location_name') or ''}").strip()
            elif row.get("media_type"):
                label = row.get("filename") or row.get("media_type")
                body = f"<attached: {label}>" + (f" {row['text']}" if row.get("text") else "")
            else:
                body = str(row.get("text") or "")
            lines.append(f"{when} - {who}: {body}")
        temporary = destination_path.with_name(f".{destination_path.name}.{secrets.token_hex(4)}.tmp")
        try:
            descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
                handle.write("\n".join(lines) + "\n")
            os.replace(temporary, destination_path)
        except OSError as exc:
            temporary.unlink(missing_ok=True)
            raise OmaWhatsAppError("The export could not be written there.") from exc
        return {"ok": True, "kind": "export-chat", "path": str(destination_path),
                "messages": len(rows)}

    def download_pending(self, jid: str, limit: Any = 50) -> dict[str, Any]:
        """Download this chat's attachments that are not on this computer, beside sync."""
        chat = self._chat(jid)
        pending = self.attachments(jid=chat["jid"], missing_only=True,
                                   limit=bounded_int(limit, 50, 1, 200))["attachments"]
        downloaded = expired = failed = 0
        for item in pending:
            if item["media_type"] == "location":
                continue
            if not item["available"]:
                expired += 1
                continue
            try:
                self.download_media(chat["jid"], item["id"])
                downloaded += 1
            except OmaWhatsAppError as exc:
                if "403" in str(exc) or "no longer available" in str(exc):
                    expired += 1
                else:
                    failed += 1
        return {"ok": True, "kind": "download-pending", "downloaded": downloaded,
                "expired": expired, "failed": failed}

    def _known_contact(self, jid: str) -> str:
        target = str(jid or "").strip()
        if not NEW_CHAT_JID.fullmatch(target) or self._known_person(target) is None:
            raise OmaWhatsAppError("Choose a person from your WhatsApp contacts.")
        return target

    def contact_alias(self, jid: str, alias: Any) -> dict[str, Any]:
        """Your own name for a person, on this computer; empty clears it."""
        target = self._known_contact(jid)
        name = " ".join(str(alias or "").split())[:128]
        command = (["--json", "contacts", "alias", "set", "--jid", target, "--alias", name] if name
                   else ["--json", "contacts", "alias", "rm", "--jid", target])
        self._envelope(self._mutate(command, timeout=60, require_online=False))
        return {"ok": True, "kind": "contact-alias", "alias": name}

    def contact_tag(self, jid: str, tag: Any, remove: bool = False) -> dict[str, Any]:
        """Add a tag to a person, or remove it, on this computer."""
        target = self._known_contact(jid)
        label = " ".join(str(tag or "").split())
        if not 1 <= len(label) <= 64:
            raise OmaWhatsAppError("A tag needs 1 to 64 characters.")
        self._envelope(self._mutate(
            ["--json", "contacts", "tags", "rm" if remove else "add", "--jid", target, "--tag", label],
            timeout=60, require_online=False))
        return {"ok": True, "kind": "contact-tag", "tag": label, "removed": bool(remove)}

    def contact_profile(self, jid: str, authorization: str = "") -> dict[str, Any]:
        """A person's about text and business profile, asked of WhatsApp."""
        if authorization != "remote-read":
            raise OmaWhatsAppError("This asks WhatsApp; pass authorization='remote-read'.")
        target = self._known_contact(jid)
        about_data = self._envelope(self._mutate(
            ["--json", "profile", "get-about", "--jid", target], timeout=45,
            require_online=True)).get("data")
        about = str(about_data.get("about") or "").strip() if isinstance(about_data, dict) else ""
        business: dict[str, Any] = {}
        try:
            data = self._envelope(self._mutate(
                ["--json", "profile", "business", "--jid", target], timeout=45,
                require_online=True)).get("data")
            if isinstance(data, dict):
                business = {key: value for key, value in data.items()
                            if key != "jid" and value not in (None, "", [], {})}
        except OmaWhatsAppError:
            business = {}
        return {"ok": True, "kind": "contact-profile", "about": about[:1024], "business": business}

    GROUP_INVITE = re.compile(r"^(?:https?://)?(?:chat\.whatsapp\.com/(?:invite/)?)?([A-Za-z0-9]{16,32})/?$")

    def create_group(self, name: Any, participants: Any) -> dict[str, Any]:
        """Create a group with people this account knows."""
        title = " ".join(str(name or "").split())
        if not 1 <= len(title) <= 100:
            raise OmaWhatsAppError("A group name needs 1 to 100 characters.")
        users = list(dict.fromkeys(str(item or "").strip()
                                   for item in (participants if isinstance(participants, list) else [])))
        if not 1 <= len(users) <= 256:
            raise OmaWhatsAppError("Add 1 to 256 people to the group.")
        for user in users:
            if not NEW_CHAT_JID.fullmatch(user) or self._known_person(user) is None:
                raise OmaWhatsAppError("Choose people from your WhatsApp contacts.")
        command = ["--json", "groups", "create", "--name", title]
        for user in users:
            command.extend(["--user", user])
        envelope = self._envelope(self._write(command, timeout=120))
        data = envelope.get("data") if isinstance(envelope.get("data"), dict) else {}
        jid = str(data.get("JID") or data.get("jid") or "")
        return {"ok": True, "kind": "create-group", "jid": jid, "name": title}

    def join_group(self, invite: Any) -> dict[str, Any]:
        """Join a group from its invite link or code."""
        match = self.GROUP_INVITE.match(str(invite or "").strip())
        if not match:
            raise OmaWhatsAppError("That is not a WhatsApp group invite link.")
        envelope = self._envelope(self._write(
            ["--json", "groups", "join", "--code", match.group(1)], timeout=90))
        data = envelope.get("data") if isinstance(envelope.get("data"), dict) else {}
        return {"ok": True, "kind": "join-group", "jid": str(data.get("jid") or "")}

    STATUS_LIFETIME = 24 * 3600

    def statuses(self, mine_only: bool = False) -> dict[str, Any]:
        """Local only: the status updates of the last 24 hours, yours and your contacts'."""
        since = int(time.time()) - self.STATUS_LIFETIME
        try:
            with closing(self._connect()) as connection:
                if not self._has_table(connection, "status_messages"):
                    return {"ok": True, "kind": "statuses", "statuses": []}
                rows = connection.execute(
                    """SELECT status.msg_id, status.ts, status.from_me, status.sender_jid,
                      COALESCE(NULLIF(contacts.full_name, ''), NULLIF(contacts.push_name, ''),
                        NULLIF(status.sender_name, ''), '') AS sender_name,
                      status.text, status.media_type, status.media_caption, status.filename
                    FROM status_messages AS status
                    LEFT JOIN contacts ON contacts.jid = status.sender_jid
                    WHERE status.ts > ? AND (? = 0 OR status.from_me = 1)
                    ORDER BY status.ts DESC LIMIT 200""",
                    [since, 1 if mine_only else 0]).fetchall()
        except sqlite3.Error as exc:
            raise OmaWhatsAppError("The local WhatsApp index could not be read.") from exc
        return {"ok": True, "kind": "statuses", "statuses": [{
            "id": str(row["msg_id"]), "timestamp": int(row["ts"]),
            "from_me": bool(row["from_me"]),
            "sender": "You" if bool(row["from_me"]) else str(row["sender_name"] or ""),
            "sender_jid": "" if bool(row["from_me"]) else str(row["sender_jid"] or ""),
            "text": str(row["text"] or "")[:MAX_MESSAGE],
            "media_type": str(row["media_type"] or ""),
            "caption": str(row["media_caption"] or "")[:1024],
            "filename": str(row["filename"] or ""),
        } for row in rows]}

    def delete_status(self, status_id: str) -> dict[str, Any]:
        """Delete one of your own status updates for everyone."""
        target = str(status_id or "").strip()
        if not target or len(target) > 256:
            raise OmaWhatsAppError("Choose one of your status updates.")
        try:
            with closing(self._connect()) as connection:
                row = connection.execute(
                    "SELECT from_me FROM status_messages WHERE msg_id = ?", [target]
                ).fetchone() if self._has_table(connection, "status_messages") else None
        except sqlite3.Error as exc:
            raise OmaWhatsAppError("The local WhatsApp index could not be read.") from exc
        if row is None or not bool(row["from_me"]):
            raise OmaWhatsAppError("Only your own status updates can be deleted.")
        # wacli revokes by id when the status is not a stored chat message.
        self._envelope(self._write(["--json", "messages", "revoke", "--chat", "status@broadcast",
                                    "--id", target, "--post-send-wait", "0"], timeout=60))
        return {"ok": True, "kind": "delete-status", "id": target}

    def vote_poll(self, jid: str, message_id: str, options: Any) -> dict[str, Any]:
        """Vote in one stored poll with option texts exactly as written."""
        chat, message = self._message(jid, message_id)
        stored = str(message["chat_jid"])
        try:
            with closing(self._connect()) as connection:
                poll = connection.execute(
                    "SELECT options_json, selectable_count FROM polls "
                    "WHERE chat_jid = ? AND msg_id = ?", [stored, str(message["msg_id"])]
                ).fetchone() if self._has_table(connection, "polls") else None
        except sqlite3.Error as exc:
            raise OmaWhatsAppError("The local WhatsApp index could not be read.") from exc
        if poll is None:
            raise OmaWhatsAppError("That message is not a poll.")
        allowed = [str(option) for option in self._json_list(poll["options_json"])]
        chosen = list(dict.fromkeys(
            str(option) for option in (options if isinstance(options, list) else [options])))
        if not chosen:
            raise OmaWhatsAppError("Choose at least one option.")
        if any(option not in allowed for option in chosen):
            raise OmaWhatsAppError("That option is not in this poll.")
        if len(chosen) > bounded_int(poll["selectable_count"], 1, 1, 12):
            raise OmaWhatsAppError("This poll takes fewer choices.")
        command = ["--json", "poll", "vote", "--to", stored, "--id", str(message["msg_id"]),
                   "--post-send-wait", "0"]
        for option in chosen:
            command.extend(["--option", option])
        self._envelope(self._write(command, timeout=60))
        return {"ok": True, "kind": "poll-vote", "options": chosen}

    def select_option(self, jid: str, message_id: str, index: Any) -> dict[str, Any]:
        chat, message = self._message(jid, message_id)
        try:
            selected = int(index)
        except (TypeError, ValueError):
            selected = 0
        if selected < 1 or selected > 64:
            raise OmaWhatsAppError("Choose a valid option.")
        command = ["--json", "send", "select", "--to", chat["jid"],
            "--id", str(message["msg_id"]), "--index", str(selected),
            "--post-send-wait", "0"]
        sender = str(message["sender_jid"] or "")
        if sender:
            command.extend(["--sender", sender])
        self._envelope(self._write(command, timeout=45))
        return {"ok": True, "kind": "select"}

    def chat_action(self, jid: str, action: str) -> dict[str, Any]:
        chat = self._chat(jid)
        action_clean = action.strip().lower()
        if action_clean in {"remove-local", "delete-local"}:
            command = ["--json", "chats", "cleanup", "--jid", chat["jid"], "--confirm"]
            self._envelope(self._mutate(command, timeout=45, require_online=False))
            return {"ok": True, "kind": "chat-action", "action": action_clean}
        commands: dict[str, list[str]] = {
            "read": ["chats", "mark-read"],
            "unread": ["chats", "mark-unread"],
            "pin": ["chats", "pin"],
            "unpin": ["chats", "unpin"],
            "archive": ["chats", "archive"],
            "unarchive": ["chats", "unarchive"],
            "mute": ["chats", "mute", "--duration", "0"],
            "unmute": ["chats", "unmute"],
        }
        suffix = commands.get(action_clean)
        if suffix is None:
            raise OmaWhatsAppError("That chat action is not supported.")
        command = ["--json", *suffix, "--chat", chat["jid"]]
        self._envelope(self._write(command, timeout=45))
        return {"ok": True, "kind": "chat-action", "action": action}

    # wacli-sync.service runs with PrivateTmp, and a delegated send is opened
    # by that service, so it cannot see a file under /tmp or /var/tmp.
    PRIVATE_TMP_ROOTS = (Path("/tmp").resolve(), Path("/var/tmp").resolve())

    @contextmanager
    def _sync_visible_file(self, path: Path) -> Iterator[Path]:
        """The file itself, or a private copy the sync service can open."""
        resolved = path.resolve()
        if not any(root == resolved or root in resolved.parents
                   for root in self.PRIVATE_TMP_ROOTS):
            yield path
            return
        folder = self.state_dir / "outgoing"
        folder.mkdir(parents=True, exist_ok=True, mode=0o700)
        copy = folder / f"{secrets.token_hex(8)}{path.suffix[:16]}"
        try:
            try:
                shutil.copyfile(resolved, copy)
                copy.chmod(0o600)
            except OSError as exc:
                raise OmaWhatsAppError("That file could not be prepared for sending.") from exc
            yield copy
        finally:
            copy.unlink(missing_ok=True)

    def send_file(self, jid: str, path: Path, mime: str = "", caption: str = "",
                  reply_id: str = "", album_id: str = "", album_index: int = 0,
                  album_count: int = 1) -> dict[str, Any]:
        chat = self._chat(jid)
        self._validate_file(path)
        quoted_id, reply_args = self._reply_args(chat, reply_id)
        with self._sync_visible_file(path) as sendable:
            command = ["--json", "send", "file", "--to", chat["jid"], "--file", str(sendable),
                       "--filename", path.name, "--as", "auto"]
            if mime:
                command.extend(["--mime", mime])
            if caption.strip():
                command.extend(["--caption", caption.strip()[:1024]])
            command.extend(reply_args)
            command.extend(["--post-send-wait", "0"])
            envelope = self._envelope(self._write(command, timeout=120))
        data = envelope.get("data") if isinstance(envelope, dict) else None
        data = data if isinstance(data, dict) else {}
        message_id = self._sent_message_id(envelope)
        file_data = data.get("file") if isinstance(data.get("file"), dict) else {}
        detected_mime = str(file_data.get("mime_type") or mime)
        detected_type = str(file_data.get("media") or
                            ("image" if detected_mime.startswith("image/") else "document"))
        self._remember_sent_reply_best_effort(
            chat["jid"], message_id, quoted_id
        )
        self._remember_sent_media_best_effort(
            chat["jid"], message_id, path, detected_mime, detected_type,
            album_id, album_index, album_count,
        )
        return {"ok": True, "kind": "image" if detected_type == "image" else "file",
                "id": message_id, "local_path": str(path), "mime_type": detected_mime,
                "media_type": detected_type, "filename": path.name,
                "album_id": album_id, "album_index": album_index,
                "album_count": album_count}

    @staticmethod
    def _validate_file(path: Path) -> int:
        try:
            size = path.stat().st_size
        except OSError as exc:
            raise OmaWhatsAppError("That pasted file is no longer available.") from exc
        if not path.is_file() or size <= 0:
            raise OmaWhatsAppError("The pasted file is empty.")
        if size > MAX_FILE:
            raise OmaWhatsAppError("The pasted file is too large (maximum 100 MB).")
        return size

    @classmethod
    def _staged_file(cls, path: Path, mime: str = "") -> dict[str, Any]:
        cls._validate_file(path)
        media_type = "image" if mime.startswith("image/") else "file"
        return {"ok": True, "kind": media_type, "path": path.as_uri(), "name": path.name}

    @staticmethod
    def _local_path(value: Any) -> Path:
        raw = str(value or "").strip()
        if not raw:
            raise OmaWhatsAppError("Choose at least one file.")
        parsed = urlparse(raw)
        if parsed.scheme == "file" and parsed.netloc in ("", "localhost"):
            path = Path(unquote(parsed.path))
        elif parsed.scheme == "" and raw.startswith("/"):
            path = Path(raw)
        else:
            raise OmaWhatsAppError("Only local files can be attached.")
        if not path.is_absolute():
            raise OmaWhatsAppError("Only absolute local file paths can be attached.")
        return path

    def send_files(self, jid: str, values: Any, caption: str = "",
                   reply_id: str = "") -> dict[str, Any]:
        self._chat(jid)
        if not isinstance(values, list) or not values:
            raise OmaWhatsAppError("Choose at least one file.")
        if len(values) > MAX_ATTACHMENTS:
            raise OmaWhatsAppError(f"Choose no more than {MAX_ATTACHMENTS} files at once.")
        paths = [self._local_path(value) for value in values]
        for path in paths:
            try:
                self._validate_file(path)
            except OmaWhatsAppError as exc:
                raise OmaWhatsAppError(f"{path.name or 'That file'}: {exc}") from exc
        mime_types = [mimetypes.guess_type(path.name)[0] or "" for path in paths]
        is_visual_batch = len(paths) > 1 and all(
            mime.startswith("image/") or mime.startswith("video/")
            for mime in mime_types
        )
        album_id = secrets.token_hex(12) if is_visual_batch else ""
        sent = 0
        sent_items: list[dict[str, Any]] = []
        try:
            for index, path in enumerate(paths):
                item = self.send_file(
                    jid, path, mime_types[index], caption if index == 0 else "",
                    reply_id if index == 0 else "", album_id, index, len(paths)
                )
                sent += 1
                promoted = self._promote_clipboard_stage(path)
                if promoted is not None:
                    # Keep a bounded, private runtime copy after confirmed
                    # delivery so the just-sent bubble can still preview it.
                    # A promotion problem must never make a delivered send
                    # look retryable; in that case the original stage remains.
                    item["local_path"] = str(promoted)
                    item["staged_promoted"] = True
                    self._remember_sent_media_best_effort(
                        jid, str(item.get("id") or ""), promoted,
                        str(item.get("mime_type") or mime_types[index]),
                        str(item.get("media_type") or "file"),
                        album_id, index, len(paths),
                    )
                sent_items.append(item)
        except OmaWhatsAppError as exc:
            if sent:
                raise OmaWhatsAppPartialError(
                    f"Sent {sent} of {len(paths)} attachments. Do not retry the "
                    f"delivered {sent}; only the remaining attachments are still "
                    f"queued. {clean_error(exc, 'The rest failed.')}",
                    {
                        "kind": "files",
                        "sent_count": sent,
                        # Preserve the caller's exact URL/path representation
                        # so its composer can remove confirmed items safely.
                        "sent_paths": [str(value) for value in values[:sent]],
                        "remaining_paths": [str(value) for value in values[sent:]],
                        "items": sent_items,
                    },
                ) from exc
            raise
        return {"ok": True, "kind": "files", "count": sent,
                "album_id": album_id, "items": sent_items}

    def send_sticker(self, jid: str, value: Any, reply_id: str = "") -> dict[str, Any]:
        chat = self._chat(jid)
        path = self._local_path(value)
        self._validate_file(path)
        if path.suffix.casefold() != ".webp":
            raise OmaWhatsAppError("WhatsApp stickers must be WebP images.")
        command = ["--json", "send", "sticker", "--to", chat["jid"],
                   "--file", str(path)]
        quoted_id, reply_args = self._reply_args(chat, reply_id)
        command.extend(reply_args)
        command.extend(["--post-send-wait", "0"])
        envelope = self._envelope(self._write(command, timeout=120))
        message_id = self._sent_message_id(envelope)
        self._remember_sent_reply_best_effort(chat["jid"], message_id, quoted_id)
        return {"ok": True, "kind": "sticker", "message_id": message_id[:256]}

    def send_voice(self, jid: str, value: Any, reply_id: str = "") -> dict[str, Any]:
        """Send one helper-created OGG/Opus draft to one exact local chat."""
        chat = self._chat(jid)
        name, size = self._inspect_voice_draft(value, require_audio=True)
        path = self.state_dir / VOICE_DRAFT_DIRECTORY / name
        command = [
            "--json", "send", "voice", "--to", chat["jid"],
            "--file", str(path), "--mime", "audio/ogg",
        ]
        quoted_id, reply_args = self._reply_args(chat, reply_id)
        command.extend(reply_args)
        command.extend(["--post-send-wait", "0"])
        envelope = self._envelope(self._write(command, timeout=120))
        self._remember_sent_reply_best_effort(
            chat["jid"], self._sent_message_id(envelope), quoted_id
        )
        cleaned = True
        try:
            self.voice_draft("discard", path)
        except OmaWhatsAppError:
            # The send is already confirmed. Do not surface cleanup as a send
            # failure, which could invite an accidental duplicate.
            cleaned = False
        return {
            "ok": True,
            "kind": "voice",
            "size": size,
            "draft_cleaned": cleaned,
        }

    def send_poll(self, jid: str, question: str, options: Any, multi: Any = 1) -> dict[str, Any]:
        chat = self._chat(jid)
        value = question.strip()
        if not value:
            raise OmaWhatsAppError("Give the poll a question.")
        if len(value) > 255:
            raise OmaWhatsAppError("The poll question is too long.")
        if not isinstance(options, list):
            raise OmaWhatsAppError("Add between 2 and 12 poll options.")
        choices = [str(option or "").strip() for option in options]
        choices = [choice for choice in choices if choice]
        if len(choices) < 2 or len(choices) > 12:
            raise OmaWhatsAppError("Add between 2 and 12 poll options.")
        if len({choice.casefold() for choice in choices}) != len(choices):
            raise OmaWhatsAppError("Poll options must be unique.")
        if any(len(choice) > 100 for choice in choices):
            raise OmaWhatsAppError("A poll option is too long.")
        try:
            maximum = int(multi)
        except (TypeError, ValueError):
            maximum = 1
        if maximum < 1 or maximum > len(choices):
            raise OmaWhatsAppError("Choose a valid poll selection limit.")
        command = ["--json", "send", "poll", "--to", chat["jid"],
                   "--question", value, "--multi", str(maximum)]
        for choice in choices:
            command.extend(["--option", choice])
        command.extend(["--post-send-wait", "0"])
        envelope = self._envelope(self._write(command, timeout=90))
        return {"ok": True, "kind": "poll", "message_id": self._sent_message_id(envelope)}

    def open_media_external(self, value: Any) -> dict[str, Any]:
        path = self._local_path(value)
        self._validate_file(path)
        mime = mimetypes.guess_type(path.name)[0] or ""
        omasnap = shutil.which("omasnap")
        if mime.startswith("image/") and omasnap:
            command = [omasnap, "--file", str(path)]
            opener = "omasnap"
        else:
            if not XDG_OPEN.is_file() or not os.access(XDG_OPEN, os.X_OK):
                raise OmaWhatsAppError("No external media viewer is installed.")
            command = [str(XDG_OPEN), str(path)]
            opener = "system"
        try:
            subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL, close_fds=True, start_new_session=True)
        except OSError as exc:
            raise OmaWhatsAppError("The external media viewer could not be opened.") from exc
        return {"ok": True, "kind": "open-media", "opener": opener}

    @staticmethod
    def _clipboard_types() -> list[str]:
        if not WL_PASTE.is_file():
            raise OmaWhatsAppError("Clipboard support is not installed.")
        try:
            result = run_bounded(
                [str(WL_PASTE), "--list-types"], timeout=3,
                stdout_limit=MAX_CLIPBOARD_TYPES, stderr_limit=16 * 1024,
            )
        except ProcessOutputLimitExceeded as exc:
            raise OmaWhatsAppError("The clipboard advertised too many content types.") from exc
        except subprocess.TimeoutExpired as exc:
            raise OmaWhatsAppError("The clipboard did not respond.") from exc
        except OSError as exc:
            raise OmaWhatsAppError("The clipboard could not be read.") from exc
        if result.returncode != 0:
            raise OmaWhatsAppError("The clipboard could not be read.")
        return [line.strip() for line in result.stdout.splitlines() if line.strip()]

    @staticmethod
    def _clipboard(mime: str, limit: int = MAX_FILE) -> bytes:
        try:
            result = run_bounded(
                [str(WL_PASTE), "--type", mime], timeout=15,
                stdout_limit=limit, stderr_limit=16 * 1024, text=False,
            )
        except ProcessOutputLimitExceeded as exc:
            raise OmaWhatsAppError(
                f"The pasted content is too large (maximum {limit // (1024 * 1024) or limit}"
                f"{' MB' if limit >= 1024 * 1024 else ' bytes'})."
            ) from exc
        except subprocess.TimeoutExpired as exc:
            raise OmaWhatsAppError("The clipboard did not respond.") from exc
        except OSError as exc:
            raise OmaWhatsAppError("The clipboard could not be read.") from exc
        if result.returncode != 0:
            raise OmaWhatsAppError("The clipboard could not be read.")
        return result.stdout

    @staticmethod
    def _clipboard_stage_root() -> Path:
        raw = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
        root = Path(raw)
        if not root.is_absolute():
            raise OmaWhatsAppError("The private runtime directory is invalid.")
        return root

    @contextmanager
    def _clipboard_stage_directory(self, *, create: bool) -> Iterator[tuple[int, Path]]:
        root = self._clipboard_stage_root()
        root_descriptor = -1
        stage_descriptor = -1
        flags = os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        try:
            if create:
                root.mkdir(parents=True, exist_ok=True, mode=0o700)
            root_descriptor = os.open(root, flags)
            root_metadata = os.fstat(root_descriptor)
            if not stat.S_ISDIR(root_metadata.st_mode) \
                    or root_metadata.st_uid != os.getuid():
                raise OSError("runtime directory is not privately owned")
            if create:
                try:
                    os.mkdir(
                        CLIPBOARD_STAGE_DIRECTORY,
                        mode=0o700,
                        dir_fd=root_descriptor,
                    )
                except FileExistsError:
                    pass
            stage_descriptor = os.open(
                CLIPBOARD_STAGE_DIRECTORY,
                flags,
                dir_fd=root_descriptor,
            )
            metadata = os.fstat(stage_descriptor)
            if not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid != os.getuid():
                raise OSError("clipboard stage is not privately owned")
            if create:
                os.fchmod(stage_descriptor, 0o700)
            yield stage_descriptor, root / CLIPBOARD_STAGE_DIRECTORY
        except OSError as exc:
            raise OmaWhatsAppError(
                "WhatsApp for Omarchy could not open its private clipboard staging directory."
            ) from exc
        finally:
            if stage_descriptor >= 0:
                os.close(stage_descriptor)
            if root_descriptor >= 0:
                os.close(root_descriptor)

    def _stage_clipboard_image(self, data: bytes, suffix: str) -> Path:
        name = f"paste-{secrets.token_hex(16)}{suffix}"
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        descriptor = -1
        with self._clipboard_stage_directory(create=True) as (directory, path):
            try:
                descriptor = os.open(name, flags, 0o600, dir_fd=directory)
                os.fchmod(descriptor, 0o600)
                view = memoryview(data)
                while view:
                    written = os.write(descriptor, view)
                    view = view[written:]
            except OSError as exc:
                if descriptor >= 0:
                    os.close(descriptor)
                    descriptor = -1
                try:
                    os.unlink(name, dir_fd=directory)
                except OSError:
                    pass
                raise OmaWhatsAppError(
                    "The clipboard image could not be staged privately."
                ) from exc
            finally:
                if descriptor >= 0:
                    os.close(descriptor)
        return path / name

    def _promote_clipboard_stage(self, path: Path) -> Path | None:
        with self._state_lock("clipboard-cache.lock"):
            return self._promote_clipboard_stage_locked(path)

    def _promote_clipboard_stage_locked(self, path: Path) -> Path | None:
        expected = self._clipboard_stage_root() / CLIPBOARD_STAGE_DIRECTORY
        normalized = Path(os.path.abspath(path))
        if normalized.parent != Path(os.path.abspath(expected)) \
                or not CLIPBOARD_STAGE_PATTERN.fullmatch(normalized.name):
            return None
        descriptor = -1
        flags = os.O_RDONLY | os.O_CLOEXEC
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        try:
            with self._clipboard_stage_directory(create=False) as (directory, _):
                descriptor = os.open(normalized.name, flags, dir_fd=directory)
                metadata = os.fstat(descriptor)
                if not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != os.getuid() \
                        or metadata.st_nlink != 1:
                    return None
                os.close(descriptor)
                descriptor = -1
                promoted_name = "sent-" + normalized.name.removeprefix("paste-")
                os.rename(
                    normalized.name, promoted_name,
                    src_dir_fd=directory, dst_dir_fd=directory,
                )
                promoted = expected / promoted_name
                # Rename is the commit point: once delivery has succeeded and
                # the pending stage has this durable identity, housekeeping
                # must not report a retryable failure or return a dead path.
                self._prune_clipboard_sent_best_effort(directory, promoted_name)
                return promoted
        except (FileNotFoundError, OmaWhatsAppError, OSError):
            return None
        finally:
            if descriptor >= 0:
                os.close(descriptor)

    @staticmethod
    def _prune_clipboard_sent_best_effort(directory: int, promoted_name: str) -> None:
        """Refresh and bound confirmed-send previews without undoing delivery."""
        try:
            # Promotion time, not paste time, defines recency. Otherwise an
            # attachment composed earlier could be evicted immediately.
            now = time.time_ns()
            os.utime(
                promoted_name, ns=(now, now), dir_fd=directory,
                follow_symlinks=False,
            )
        except OSError:
            pass
        try:
            names = os.listdir(directory)
        except OSError:
            return
        candidates: list[tuple[int, int, str]] = []
        total = 0
        for name in names:
            if not CLIPBOARD_SENT_PATTERN.fullmatch(name):
                continue
            try:
                info = os.stat(name, dir_fd=directory, follow_symlinks=False)
            except OSError:
                continue
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() \
                    or info.st_nlink != 1:
                continue
            candidates.append((info.st_mtime_ns, info.st_size, name))
            total += info.st_size
        # Keep the just-promoted item until older confirmed sends are pruned,
        # even on filesystems with coarse timestamp precision.
        candidates.sort(key=lambda item: (item[2] == promoted_name, item[0]))
        while len(candidates) > MAX_CLIPBOARD_SENT_FILES \
                or total > MAX_CLIPBOARD_SENT_BYTES:
            _, size, name = candidates.pop(0)
            try:
                os.unlink(name, dir_fd=directory)
                total -= size
            except OSError:
                pass

    def discard_clipboard_stage(self, value: Any) -> dict[str, Any]:
        with self._state_lock("clipboard-cache.lock"):
            return self._discard_clipboard_stage_locked(value)

    def _discard_clipboard_stage_locked(self, value: Any) -> dict[str, Any]:
        """Discard only an unsent clipboard image owned by this runtime."""
        try:
            path = self._local_path(value)
        except OmaWhatsAppError:
            return {"ok": True, "kind": "discard-stage", "discarded": False}
        expected = self._clipboard_stage_root() / CLIPBOARD_STAGE_DIRECTORY
        normalized = Path(os.path.abspath(path))
        if normalized.parent != Path(os.path.abspath(expected)) \
                or not CLIPBOARD_STAGE_PATTERN.fullmatch(normalized.name):
            return {"ok": True, "kind": "discard-stage", "discarded": False}
        descriptor = -1
        flags = os.O_RDONLY | os.O_CLOEXEC
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        try:
            with self._clipboard_stage_directory(create=False) as (directory, _):
                descriptor = os.open(normalized.name, flags, dir_fd=directory)
                metadata = os.fstat(descriptor)
                if not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != os.getuid() \
                        or metadata.st_nlink != 1:
                    return {"ok": True, "kind": "discard-stage", "discarded": False}
                os.close(descriptor)
                descriptor = -1
                os.unlink(normalized.name, dir_fd=directory)
                return {"ok": True, "kind": "discard-stage", "discarded": True}
        except (FileNotFoundError, OmaWhatsAppError, OSError):
            return {"ok": True, "kind": "discard-stage", "discarded": False}
        finally:
            if descriptor >= 0:
                os.close(descriptor)

    def paste(self, jid: str) -> dict[str, Any]:
        self._chat(jid)
        types = self._clipboard_types()
        if "text/uri-list" in types:
            raw = self._clipboard("text/uri-list", MAX_CLIPBOARD_TYPES).decode("utf-8", "replace")
            for line in raw.splitlines():
                if not line or line.startswith("#"):
                    continue
                parsed = urlparse(line.strip())
                if parsed.scheme == "file" and parsed.netloc in ("", "localhost"):
                    path = Path(unquote(parsed.path))
                    return self._staged_file(path, mimetypes.guess_type(path.name)[0] or "")
        image_types = [kind for kind in
            ("image/png", "image/jpeg", "image/webp", "image/gif", "image/bmp") if kind in types]
        if image_types:
            mime = image_types[0]
            data = self._clipboard(mime)
            if not data:
                raise OmaWhatsAppError("The pasted image is empty.")
            suffix = {"image/png": ".png", "image/jpeg": ".jpg", "image/webp": ".webp",
                      "image/gif": ".gif", "image/bmp": ".bmp"}[mime]
            return self._staged_file(self._stage_clipboard_image(data, suffix), mime)
        text_type = next((kind for kind in ("text/plain;charset=utf-8", "text/plain", "UTF8_STRING")
                          if kind in types), None)
        if text_type:
            return {"ok": True, "kind": "text",
                    "text": self._clipboard(text_type, MAX_CLIPBOARD_TEXT)
                    .decode("utf-8", "replace")[:MAX_MESSAGE]}
        raise OmaWhatsAppError("The clipboard has no text, image, or local file to paste.")

    @staticmethod
    def _transport_args(value: Any) -> list[str]:
        if not isinstance(value, list) or not value or len(value) > 128:
            raise OmaWhatsAppError("wacli args must be a non-empty JSON string array.")
        args: list[str] = []
        total = 0
        for item in value:
            if not isinstance(item, str) or not item or "\x00" in item:
                raise OmaWhatsAppError("Every wacli argument must be a non-empty string.")
            encoded = len(item.encode("utf-8"))
            if encoded > 8192:
                raise OmaWhatsAppError("One wacli argument is too large.")
            total += encoded
            args.append(item)
        if total > 48 * 1024:
            raise OmaWhatsAppError("The wacli argument list is too large.")
        for item in args:
            if item.split("=", 1)[0] in WACLI_GLOBAL_FLAGS:
                raise OmaWhatsAppError(
                    "Pass wacli global options as WhatsApp for Omarchy request fields, not in args."
                )
        return args

    @staticmethod
    def _transport_path(args: Sequence[str]) -> tuple[str, ...]:
        for path in sorted(WACLI_OPERATION_POLICIES, key=len, reverse=True):
            if tuple(args[:len(path)]) == path:
                return path
        raise OmaWhatsAppError(
            f"That operation is not in the wacli {WACLI_PARITY_VERSION} parity registry."
        )

    @classmethod
    def _transport_policy(
        cls, args: Sequence[str], path: tuple[str, ...] | None = None
    ) -> str:
        operation = path or cls._transport_path(args)
        flags = {item.split("=", 1)[0] for item in args[len(operation):]}
        if operation == ("accounts", "add") \
                and cls._transport_boolean_flag(args, "--no-auth"):
            return "local-write"
        if operation == ("doctor",) \
                and cls._transport_boolean_flag(args, "--connect"):
            return "remote-read"
        if operation == ("history", "fill") \
                and cls._transport_boolean_flag(args, "--dry-run"):
            return "local-read"
        if operation == ("messages", "export") and "--output" in flags:
            return "private-export"
        if operation in (("messages", "purge"), ("store", "cleanup")) \
                and cls._transport_boolean_flag(args, "--dry-run"):
            return "local-read"
        return WACLI_OPERATION_POLICIES[operation]

    @staticmethod
    def _transport_boolean_flag(args: Sequence[str], flag: str) -> bool:
        values: list[bool] = []
        for item in args:
            if item == flag:
                values.append(True)
            elif item.startswith(flag + "="):
                raw = item.split("=", 1)[1].casefold()
                if raw not in {"true", "false"}:
                    raise OmaWhatsAppError(
                        f"{flag} must be true or false when a value is supplied."
                    )
                values.append(raw == "true")
        if len(values) > 1:
            raise OmaWhatsAppError(f"Pass {flag} at most once.")
        return values[0] if values else False

    @staticmethod
    def _transport_flag_values(args: Sequence[str], flag: str) -> list[str]:
        values: list[str] = []
        index = 0
        while index < len(args):
            item = args[index]
            if item == flag:
                if index + 1 >= len(args) or args[index + 1].startswith("--"):
                    raise OmaWhatsAppError(f"{flag} requires a value.")
                values.append(args[index + 1])
                index += 2
                continue
            if item.startswith(flag + "="):
                values.append(item.split("=", 1)[1])
            index += 1
        return values

    def _validate_transport_targets(
        self, args: Sequence[str], path: tuple[str, ...]
    ) -> None:
        if any(item == "--pick" or item.startswith("--pick=") for item in args):
            raise OmaWhatsAppError("Resolve an exact chat JID instead of using --pick.")

        def exact(flag: str, *, required: bool) -> list[str]:
            values = self._transport_flag_values(args, flag)
            if required and len(values) != 1:
                raise OmaWhatsAppError(
                    f"This operation requires one exact {flag} locally indexed JID."
                )
            return values

        for flag in WACLI_REQUIRED_CHAT_FLAGS.get(path, ()):
            for target in exact(flag, required=True):
                self._chat_any(target)
        for flag in WACLI_OPTIONAL_CHAT_FLAGS.get(path, ()):
            for target in exact(flag, required=False):
                self._chat_any(target)
        if path in WACLI_CHAT_TO_OPERATIONS \
                and "--to" not in WACLI_REQUIRED_CHAT_FLAGS.get(path, ()):
            for target in exact("--to", required=True):
                self._chat_any(target)

        if path in WACLI_GROUP_JID_OPERATIONS:
            group = self._chat_any(exact("--jid", required=True)[0])
            if group["kind"] != "group" or not group["jid"].endswith("@g.us"):
                raise OmaWhatsAppError("That exact target is not a locally indexed group.")
            if path in {
                ("groups", "participants", "add"),
                ("groups", "participants", "demote"),
                ("groups", "participants", "promote"),
                ("groups", "participants", "remove"),
            }:
                users = self._transport_flag_values(args, "--user")
                if not users:
                    raise OmaWhatsAppError("Choose at least one exact participant JID.")
                for user in users:
                    if path == ("groups", "participants", "add"):
                        self._contact_any(user)
                    else:
                        self._group_participant(group["jid"], user)
            elif path in {
                ("groups", "requests", "approve"),
                ("groups", "requests", "reject"),
            }:
                users = self._transport_flag_values(args, "--user")
                if not users or any("@" not in user or len(user) > 160 for user in users):
                    raise OmaWhatsAppError("Choose exact requesting-user JIDs, not phone selectors.")

        if path in WACLI_CHANNEL_JID_OPERATIONS:
            channel = self._chat_any(exact("--jid", required=True)[0])
            if not channel["jid"].endswith("@newsletter"):
                raise OmaWhatsAppError("That exact target is not a locally indexed channel.")

        if path in WACLI_CONTACT_JID_OPERATIONS:
            self._contact_any(exact("--jid", required=True)[0])

        message_target = WACLI_MESSAGE_TARGETS.get(path)
        if message_target:
            chat_flag, message_flag = message_target
            chat = exact(chat_flag, required=True)[0]
            message = exact(message_flag, required=True)[0]
            self._message_any(chat, message)

        replies = self._transport_flag_values(args, "--reply-to")
        if replies:
            if len(replies) != 1:
                raise OmaWhatsAppError("Choose one exact local reply message.")
            recipient = exact("--to", required=True)[0]
            self._message_any(recipient, replies[0])

        parents = self._transport_flag_values(args, "--linked-parent")
        if parents:
            if path != ("groups", "create") or len(parents) != 1:
                raise OmaWhatsAppError("Choose one exact linked parent group JID.")
            parent = self._chat_any(parents[0])
            if parent["kind"] != "group" or not parent["jid"].endswith("@g.us"):
                raise OmaWhatsAppError("The linked parent is not a locally indexed group.")

        if path == ("groups", "create"):
            for user in self._transport_flag_values(args, "--user"):
                self._contact_any(user)

        if path in {
            ("accounts", "add"),
            ("accounts", "remove"),
            ("accounts", "show"),
            ("accounts", "use"),
        }:
            tail = list(args[len(path):])
            if not tail or tail[0].startswith("-") or not ACCOUNT_NAME.fullmatch(tail[0]):
                raise OmaWhatsAppError("Choose one exact valid account name.")
            name = tail[0]
            if path == ("accounts", "add"):
                if any(account.name == name for account in self.accounts()):
                    raise OmaWhatsAppError("That wacli account is already configured.")
            else:
                self.account(name)

    @staticmethod
    def _transport_account(value: Any) -> str:
        account = str(value or "").strip()
        if not account:
            return ""
        if len(account) > 64 or not re.fullmatch(r"[A-Za-z0-9._-]+", account):
            raise OmaWhatsAppError("Choose a valid named wacli account.")
        return account

    @staticmethod
    def _transport_store(value: Any) -> str:
        raw = str(value or "").strip()
        if not raw:
            return ""
        if "\x00" in raw:
            raise OmaWhatsAppError("Choose a valid wacli store directory.")
        target = Path(raw).expanduser()
        if not target.is_absolute():
            raise OmaWhatsAppError("A one-off wacli store must use an absolute path.")
        try:
            resolved = target.resolve(strict=False)
            home = HOME.resolve(strict=True)
        except OSError as exc:
            raise OmaWhatsAppError("The wacli store path could not be resolved safely.") from exc
        if resolved != home and home not in resolved.parents:
            raise OmaWhatsAppError("A one-off wacli store must stay inside your home directory.")
        return str(resolved)

    @classmethod
    def _private_export_destination(
        cls, args: Sequence[str], *, allow_directory: bool = False
    ) -> tuple[str, Path | None]:
        values = cls._transport_flag_values(args, "--output")
        if len(values) != 1:
            raise OmaWhatsAppError("A private export requires one exact output path.")
        raw = values[0]
        if "\x00" in raw:
            raise OmaWhatsAppError("The private export path is invalid.")
        target = Path(raw).expanduser()
        if not target.is_absolute() or target.name in {"", ".", ".."}:
            raise OmaWhatsAppError("A private export needs an absolute file path.")
        try:
            home = HOME.resolve(strict=True)
            parent = target.parent.resolve(strict=True)
        except OSError as exc:
            raise OmaWhatsAppError(
                "The private export parent directory could not be resolved safely."
            ) from exc
        destination = parent / target.name
        if parent != home and home not in parent.parents:
            raise OmaWhatsAppError("A private export must stay inside your home directory.")
        try:
            metadata = destination.lstat()
        except FileNotFoundError:
            metadata = None
        except OSError as exc:
            raise OmaWhatsAppError("The private export path could not be inspected safely.") from exc
        directory = metadata is not None and allow_directory \
            and stat.S_ISDIR(metadata.st_mode)
        if metadata is not None and not directory:
            # An agent names the path; an export never replaces what is there.
            raise OmaWhatsAppError(
                "Something is already at that export path; choose a new file name.")
        if metadata is not None and metadata.st_uid != os.getuid():
            raise OmaWhatsAppError("WhatsApp for Omarchy refused an unsafe private export path.")
        repository_start = destination if directory else parent
        repository = next((
            candidate for candidate in (repository_start, *repository_start.parents)
            if candidate == home or home in candidate.parents
            if (candidate / ".git").exists() or (candidate / ".git").is_symlink()
        ), None)
        return str(destination), repository

    @classmethod
    def _external_stream_destinations(
        cls, args: Sequence[str], payload: dict[str, Any]
    ) -> list[str]:
        destinations: list[str] = []
        if payload.get("events") is True:
            destinations.append("response")
        webhooks = cls._transport_flag_values(args, "--webhook")
        webhook_options = any(
            item == "--webhook-secret" or item.startswith("--webhook-secret=")
            or item == "--webhook-events" or item.startswith("--webhook-events=")
            or item == "--webhook-allow-private"
            for item in args
        )
        if webhooks or webhook_options:
            if tuple(args[:1]) != ("sync",) or len(webhooks) != 1:
                raise OmaWhatsAppError("External streaming requires one exact sync webhook URL.")
            parsed = urlparse(webhooks[0])
            if parsed.scheme not in {"http", "https"} or not parsed.hostname \
                    or parsed.username is not None or parsed.password is not None:
                raise OmaWhatsAppError("Choose one exact HTTP(S) webhook destination without credentials.")
            destinations.append(webhooks[0])
        return destinations

    @staticmethod
    def _authorize_external_stream(
        payload: dict[str, Any], destinations: Sequence[str]
    ) -> None:
        raw = payload.get("external_stream_authorization")
        if raw in (None, ""):
            supplied = []
        elif isinstance(raw, str):
            supplied = [raw]
        elif isinstance(raw, list) and all(isinstance(item, str) for item in raw):
            supplied = list(raw)
        else:
            raise OmaWhatsAppError(
                "External-stream authorization must be a string or string array."
            )
        expected = {f"external-stream:{destination}" for destination in destinations}
        if len(supplied) != len(set(supplied)) or set(supplied) != expected:
            raise OmaWhatsAppError(
                "This request needs exact destination-bearing external-stream authorization."
            )

    @classmethod
    def _transport_globals(
        cls,
        payload: dict[str, Any],
        *,
        read_only: bool,
        json_output: bool,
    ) -> tuple[list[str], int, int, bool]:
        command: list[str] = []
        account = cls._transport_account(payload.get("account"))
        store = cls._transport_store(payload.get("store"))
        if account and store:
            raise OmaWhatsAppError("Choose either a named account or a one-off store, not both.")
        if account:
            command.extend(["--account", account])
        if store:
            command.extend(["--store", store])
        if payload.get("events") not in (None, False, True):
            raise OmaWhatsAppError("events must be true or false.")
        if payload.get("full") not in (None, False, True):
            raise OmaWhatsAppError("full must be true or false.")
        include_events = payload.get("events") is True
        if include_events:
            command.append("--events")
        if payload.get("full") is True:
            command.append("--full")
        lock_wait = str(payload.get("lock_wait") or "").strip()
        if lock_wait:
            if len(lock_wait) > 32 or not re.fullmatch(r"[0-9]+(?:ms|s|m|h)", lock_wait):
                raise OmaWhatsAppError("lock_wait must be a bounded duration such as 5s.")
            command.extend(["--lock-wait", lock_wait])
        timeout = bounded_int(payload.get("timeout"), 300, 1, 7200)
        command.extend(["--timeout", f"{timeout}s"])
        if read_only:
            command.append("--read-only")
        if json_output:
            command.append("--json")
        output_limit = bounded_int(
            payload.get("max_output_bytes"), MAX_WACLI_OUTPUT,
            4096, 8 * 1024 * 1024,
        )
        return command, timeout, output_limit, include_events

    @classmethod
    def _transport_sensitive_values(
        cls, args: Sequence[str]
    ) -> tuple[str, ...]:
        values: set[str] = set()
        for flag in WACLI_SENSITIVE_FLAGS:
            for value in cls._transport_flag_values(args, flag):
                if value:
                    values.add(value)
                if flag == "--webhook":
                    parsed = urlparse(value)
                    for _, query_value in parse_qsl(parsed.query, keep_blank_values=False):
                        if query_value:
                            values.add(query_value)
        return tuple(sorted(values, key=len, reverse=True))

    @staticmethod
    def _redact_transport_value(value: Any, sensitive: Sequence[str]) -> Any:
        if isinstance(value, str):
            redacted = value
            for secret in sensitive:
                if not secret:
                    continue
                redacted = redacted.replace(secret, "[redacted]")
                encoded = quote(secret, safe="")
                if encoded != secret:
                    redacted = redacted.replace(encoded, "[redacted]")
            return redacted
        if isinstance(value, list):
            return [Backend._redact_transport_value(item, sensitive) for item in value]
        if isinstance(value, dict):
            return {
                Backend._redact_transport_value(key, sensitive):
                    Backend._redact_transport_value(item, sensitive)
                for key, item in value.items()
            }
        return value

    @staticmethod
    def _transport_events(
        stderr: str, sensitive: Sequence[str] = ()
    ) -> list[Any]:
        events: list[Any] = []
        for line in stderr.splitlines()[:2048]:
            try:
                value = json.loads(line)
            except json.JSONDecodeError:
                value = clean_error(line, "")
            value = Backend._redact_transport_value(value, sensitive)
            if value not in (None, ""):
                events.append(value)
        return events

    @staticmethod
    def _transport_result(
        result: subprocess.CompletedProcess[str],
        path: tuple[str, ...],
        policy: str,
        include_events: bool,
        sensitive: Sequence[str] = (),
    ) -> dict[str, Any]:
        raw = result.stdout.strip()
        try:
            value: Any = json.loads(raw) if raw else None
        except json.JSONDecodeError:
            value = None
        if result.returncode != 0:
            error: Any = value.get("error") if isinstance(value, dict) else None
            if isinstance(error, dict):
                error = error.get("message")
            detail = Backend._redact_transport_value(
                str(error or result.stderr or raw), sensitive
            )
            raise OmaWhatsAppError(clean_error(detail, "wacli rejected the request."))
        if isinstance(value, dict) and value.get("success") is False:
            error = value.get("error")
            if isinstance(error, dict):
                error = error.get("message")
            error = Backend._redact_transport_value(str(error or ""), sensitive)
            raise OmaWhatsAppError(clean_error(error, "wacli rejected the request."))
        response: dict[str, Any] = {
            "ok": True,
            "kind": "wacli",
            "operation": " ".join(path),
            "policy": policy,
        }
        if isinstance(value, dict) and value.get("success") is True:
            response["data"] = Backend._redact_transport_value(value.get("data"), sensitive)
        elif value is not None:
            response["data"] = Backend._redact_transport_value(value, sensitive)
        elif raw:
            response["output"] = Backend._redact_transport_value(raw, sensitive)
        if include_events:
            response["events"] = Backend._transport_events(result.stderr, sensitive)
        return response

    def capabilities(self) -> dict[str, Any]:
        operations = [{
            "operation": " ".join(path),
            "policy": policy,
            "authorization": "" if policy == "local-read" else policy,
            "min_wacli": WACLI_LEAF_MINIMUM_VERSIONS.get(path, WACLI_MINIMUM_VERSION),
        } for path, policy in sorted(WACLI_OPERATION_POLICIES.items())]
        return {
            "ok": True,
            "kind": "capabilities",
            "wacli_parity_version": WACLI_PARITY_VERSION,
            "wacli_minimum_version": WACLI_MINIMUM_VERSION,
            "operation_count": len(operations),
            "operations": operations,
            "conditional_authorizations": [
                {
                    "policy": "private-export",
                    "when": "messages export --output ABSOLUTE_PATH",
                    "authorization": "private-export:<exact-absolute-output-path>",
                },
                {
                    "policy": "private-export",
                    "when": "media download --output ABSOLUTE_PATH",
                    "field": "private_export_authorization",
                    "authorization": "private-export:<exact-absolute-output-path>",
                },
                {
                    "policy": "external-stream",
                    "when": "events=true",
                    "authorization": "external-stream:response",
                },
                {
                    "policy": "external-stream",
                    "when": "sync --webhook URL",
                    "authorization": "external-stream:<exact-webhook-url>",
                },
            ],
        }

    @contextmanager
    def _transport_scope(self, payload: dict[str, Any]) -> Iterator[Account]:
        account = self._transport_account(payload.get("account"))
        store = self._transport_store(payload.get("store"))
        if account and store:
            raise OmaWhatsAppError("Choose either a named account or a one-off store, not both.")
        if store:
            # A one-off store is not owned by either managed sync unit. Lock
            # recovery may serialize against it, but must never stop the
            # unrelated default account's background service.
            scoped = Account(
                "", Path(store), managed_unit=False, selector="store"
            )
        elif account:
            scoped = self.account(account)
        else:
            scoped = self.active
        with self._using(scoped):
            yield scoped

    def transport(self, payload: dict[str, Any]) -> dict[str, Any]:
        args = self._transport_args(payload.get("args"))
        sensitive = self._transport_sensitive_values(args)
        path = self._transport_path(args)
        policy = self._transport_policy(args, path)
        if policy == "interactive":
            raise OmaWhatsAppError(
                "That operation needs a terminal. Use omawhatsapp wacli --interactive."
            )
        export_destination = ""
        repository: Path | None = None
        if policy == "private-export":
            export_destination, repository = self._private_export_destination(args)
            expected = f"private-export:{export_destination}"
        else:
            expected = "" if policy == "local-read" else policy
        authorization = str(payload.get("authorization") or "")
        if authorization != expected:
            if policy == "private-export":
                raise OmaWhatsAppError(
                    "This request needs exact destination-bearing private-export authorization."
                )
            raise OmaWhatsAppError(
                f"This operation requires authorization={expected!r} from the current request."
            )
        media_output = path == ("media", "download") \
            and bool(self._transport_flag_values(args, "--output"))
        private_export_authorization = payload.get("private_export_authorization")
        if media_output:
            export_destination, repository = self._private_export_destination(
                args, allow_directory=True
            )
            if private_export_authorization != f"private-export:{export_destination}":
                raise OmaWhatsAppError(
                    "This media download needs exact destination-bearing private-export authorization."
                )
        elif private_export_authorization not in (None, ""):
            raise OmaWhatsAppError(
                "Private-export authorization was not needed for this operation."
            )
        repository_override = payload.get("repository_export_authorization")
        if repository is not None:
            if repository_override != f"allow-repository-export:{export_destination}":
                raise OmaWhatsAppError(
                    "Private exports into a repository require a second exact destination authorization."
                )
        elif repository_override not in (None, ""):
            raise OmaWhatsAppError("Repository-export authorization was not needed for this path.")
        stream_destinations = self._external_stream_destinations(args, payload)
        self._authorize_external_stream(payload, stream_destinations)
        with self._transport_scope(payload) as scoped:
            self._validate_transport_targets(args, path)
            unscoped_payload = dict(payload, account="", store="")
            global_args, timeout, output_limit, include_events = self._transport_globals(
                unscoped_payload, read_only=policy == "local-read", json_output=True
            )
            command = [*scoped.cli_args, *global_args, *args]
            if policy == "local-read":
                result = self._run(
                    command, timeout=timeout + 5, stdout_limit=output_limit,
                    stderr_limit=output_limit if include_events else MAX_PROCESS_ERROR,
                    # The scope is already spelled out in global_args.
                    account=None,
                )
            else:
                local_destructive = path in {
                    ("accounts", "remove"),
                    ("messages", "purge"),
                    ("store", "cleanup"),
                }
                result = self._mutate(
                    command,
                    timeout=timeout + 5,
                    require_online=policy in {
                        "remote-read", "sync", "whatsapp-write", "destructive"
                    } and not local_destructive,
                    stdout_limit=output_limit,
                    stderr_limit=output_limit if include_events else MAX_PROCESS_ERROR,
                    account=None,
                )
        return self._transport_result(
            result, path, policy, include_events, sensitive
        )

    def _transport_interactive(
        self,
        values: Sequence[str],
        *,
        authorization: str,
        account: str = "",
        store: str = "",
    ) -> tuple[int, Account, tuple[str, ...]]:
        args = list(values)
        if args and args[0] == "--":
            args = args[1:]
        args = self._transport_args(args)
        path = self._transport_path(args)
        policy = self._transport_policy(args, path)
        if policy not in {"interactive", "sync"}:
            raise OmaWhatsAppError(
                "Interactive mode is only for linking accounts or a foreground sync."
            )
        if authorization != policy:
            raise OmaWhatsAppError(
                f"This operation requires --authorize {policy} from the current request."
            )
        if self._external_stream_destinations(args, {}):
            raise OmaWhatsAppError(
                "Interactive sync cannot export events. Use the structured gateway with exact external-stream authorization."
            )
        clean_account = self._transport_account(account)
        clean_store = self._transport_store(store)
        if clean_account and clean_store:
            raise OmaWhatsAppError("Choose either a named account or a one-off store, not both.")
        if not self.wacli.is_file() or not os.access(self.wacli, os.X_OK):
            raise OmaWhatsAppError("wacli is not installed.")
        if clean_store:
            scoped = Account(
                "", Path(clean_store), managed_unit=False, selector="store"
            )
            unit = ""
        elif clean_account:
            scoped = self.account(clean_account)
            unit = scoped.unit
        else:
            scoped = self.active
            unit = scoped.unit
        global_args = scoped.cli_args
        with self._using(scoped):
            self._validate_transport_targets(args, path)
        if policy == "sync" and not self.online(scoped):
            raise OmaWhatsAppError("Offline mode is on. Go online before syncing WhatsApp.")

        with self._state_lock(self._lifecycle_lock_name(scoped)):
            if policy == "sync" and not self.online(scoped):
                raise OmaWhatsAppError("Offline mode is on. Go online before syncing WhatsApp.")
            active = bool(unit) and path in {("auth",), ("sync",)} \
                and self._yield_active_sync(scoped)
            operation_error: BaseException | None = None
            returncode: int | None = None
            try:
                result = subprocess.run(
                    [str(self.wacli), *global_args, *args], check=False
                )
                returncode = result.returncode
            except BaseException as exc:
                operation_error = exc
            if active:
                try:
                    self._restore_yielded_sync(scoped, active)
                except OmaWhatsAppError as exc:
                    if returncode == 0:
                        raise OmaWhatsAppPartialError(
                            "The terminal command completed, but background sync could not restart.",
                            {"kind": "lifecycle", "committed": True,
                             "account": scoped.name},
                        ) from exc
                    raise OmaWhatsAppError(
                        "Background sync could not be restored after the terminal command."
                    ) from exc
            if operation_error is not None:
                if isinstance(operation_error, OSError):
                    raise OmaWhatsAppError(
                        "wacli could not be started in the terminal."
                    ) from operation_error
                raise operation_error
            return int(returncode or 0), scoped, path

    def transport_interactive(
        self,
        values: Sequence[str],
        *,
        authorization: str,
        account: str = "",
        store: str = "",
    ) -> int:
        result, scoped, path = self._transport_interactive(
            values, authorization=authorization, account=account, store=store
        )
        if path == ("auth",):
            return self._finalize_link(scoped, result)
        return result

    def session_ready(self) -> bool:
        """True when the active account has a linked-device session on disk."""
        return (self.active.store_dir / "session.db").is_file()

def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(prog="omawhatsapp")
    commands = value.add_subparsers(dest="command", required=True)
    status = commands.add_parser("status")
    status.add_argument("--account", default="")
    link_account = commands.add_parser("link-account")
    link_account.add_argument("name")
    link_account.add_argument("--authorize", default="")
    session_ready = commands.add_parser("session-ready")
    session_ready.add_argument("--account", default="")
    chats = commands.add_parser("chats")
    chats.add_argument("--limit", type=int, default=500)
    messages = commands.add_parser("messages")
    messages.add_argument("--limit", type=int, default=160)
    commands.add_parser("members")
    commands.add_parser("presence")
    commands.add_parser("chat-details")
    commands.add_parser("stickers")
    commands.add_parser("group-info")
    commands.add_parser("group-action")
    commands.add_parser("fetch-stickers")
    commands.add_parser("send")
    commands.add_parser("contacts-search")
    commands.add_parser("contact-tags")
    commands.add_parser("attachments")
    commands.add_parser("check-number")
    commands.add_parser("send-new")
    commands.add_parser("paste")
    commands.add_parser("discard-stage")
    commands.add_parser("files")
    commands.add_parser("voice-draft")
    commands.add_parser("voice")
    commands.add_parser("sticker")
    commands.add_parser("poll")
    commands.add_parser("open-media")
    commands.add_parser("media")
    commands.add_parser("react")
    commands.add_parser("edit")
    commands.add_parser("delete")
    commands.add_parser("forward")
    commands.add_parser("star")
    commands.add_parser("chat-presence")
    commands.add_parser("select")
    commands.add_parser("poll-vote")
    commands.add_parser("statuses")
    commands.add_parser("create-group")
    commands.add_parser("export-chat")
    commands.add_parser("download-pending")
    commands.add_parser("contact-alias")
    commands.add_parser("contact-tag")
    commands.add_parser("contact-profile")
    commands.add_parser("join-group")
    commands.add_parser("delete-status")
    commands.add_parser("chat-action")
    commands.add_parser("acknowledge")
    commands.add_parser("notify")
    commands.add_parser("notify-mode")
    commands.add_parser("media-mode")
    commands.add_parser("about")
    commands.add_parser("save-media")
    commands.add_parser("notify-open")
    commands.add_parser("sync-mode")
    commands.add_parser("quit")
    commands.add_parser("unlink-account")
    commands.add_parser("launch")
    commands.add_parser("setup")
    commands.add_parser("teardown")
    commands.add_parser("update-check")
    commands.add_parser("self-update")
    commands.add_parser("settings")
    commands.add_parser("avatars")
    commands.add_parser("capabilities")
    transport = commands.add_parser("wacli")
    transport.add_argument("--interactive", action="store_true")
    transport.add_argument("--authorize", default="")
    transport.add_argument("--account", default="")
    transport.add_argument("--store", default="")
    transport.add_argument("transport_args", nargs=argparse.REMAINDER)
    return value


def main() -> int:
    args = parser().parse_args()
    backend = Backend()
    if args.command != "session-ready":
        try:
            backend.recover_lifecycle()
        except OmaWhatsAppError as exc:
            return emit({
                "ok": False,
                "error": clean_error(
                    exc, "WhatsApp for Omarchy could not recover background sync."
                ),
            }, 1)
    if args.command == "link-account":
        try:
            return backend.link_account(args.name, args.authorize)
        except OmaWhatsAppPartialError as exc:
            print(clean_error(exc, "WhatsApp for Omarchy partly linked that account."),
                  file=sys.stderr)
            return 1
        except OmaWhatsAppError as exc:
            print(clean_error(exc, "WhatsApp for Omarchy could not link that account."),
                  file=sys.stderr)
            return 1
    if args.command == "self-update":
        # Interactive, in a terminal: no JSON request on stdin.
        try:
            return backend.self_update()
        except OmaWhatsAppError as exc:
            print(clean_error(exc, "WhatsApp for Omarchy could not update."), file=sys.stderr)
            return 1
    if args.command == "wacli" and args.interactive:
        try:
            return backend.transport_interactive(
                args.transport_args,
                authorization=str(args.authorize or ""),
                account=str(args.account or ""),
                store=str(args.store or ""),
            )
        except OmaWhatsAppError as exc:
            return emit({"ok": False, "error": clean_error(exc, "WhatsApp for Omarchy failed.")}, 1)
    try:
        if args.command == "session-ready":
            # ExecCondition contract: 0 runs the unit, 1 skips it quietly.
            backend.use_account(str(getattr(args, "account", "") or ""))
            ready = backend.session_ready()
            return emit({"ok": True, "kind": "session-ready", "ready": ready},
                        0 if ready else 1)
        if args.command == "status":
            backend.use_account(str(getattr(args, "account", "") or ""))
            return emit(backend.status())
        if args.command == "capabilities":
            return emit(backend.capabilities())
        if args.command == "update-check":
            return emit(backend.update_check())
        payload = request()
        # Every request may name the account it belongs to. Empty keeps a
        # preserved root session stable, then falls back to wacli's default.
        backend.use_account(payload.get("account"))
        if args.command == "wacli":
            if args.transport_args:
                raise OmaWhatsAppError(
                    "Pass non-interactive wacli arguments in the JSON request."
                )
            return emit(backend.transport(payload))
        if args.command == "chats":
            return emit(backend.chats(str(payload.get("query") or ""), args.limit))
        if args.command == "messages":
            return emit(backend.messages(str(payload.get("jid") or ""),
                                         str(payload.get("query") or ""), args.limit,
                                         payload.get("before"),
                                         str(payload.get("kind") or "")))
        if args.command == "group-info":
            return emit(backend.group_info(str(payload.get("jid") or ""),
                                           str(payload.get("authorization") or "")))
        if args.command == "group-action":
            return emit(backend.group_action(str(payload.get("jid") or ""),
                                             str(payload.get("action") or ""),
                                             payload.get("value"),
                                             str(payload.get("authorization") or "")))
        if args.command == "stickers":
            return emit(backend.stickers())
        if args.command == "fetch-stickers":
            return emit(backend.fetch_stickers())
        if args.command == "presence":
            return emit(backend.presence(str(payload.get("action") or ""),
                                         str(payload.get("jid") or ""),
                                         payload.get("lease")))
        if args.command == "chat-details":
            return emit(backend.chat_details(str(payload.get("jid") or "")))
        if args.command == "members":
            return emit(backend.members(str(payload.get("jid") or ""),
                                        str(payload.get("query") or "")))
        if args.command == "send":
            return emit(backend.send(str(payload.get("jid") or ""),
                                     str(payload.get("text") or ""),
                                     str(payload.get("reply_id") or ""),
                                     payload.get("mentions")))
        if args.command == "contacts-search":
            return emit(backend.contacts_search(
                str(payload.get("query") or ""),
                bounded_int(payload.get("limit"), 40, 1, 80),
                str(payload.get("tag") or "")))
        if args.command == "contact-tags":
            return emit(backend.contact_tags())
        if args.command == "attachments":
            return emit(backend.attachments(
                str(payload.get("jid") or ""), str(payload.get("sender") or ""),
                payload.get("kinds"), str(payload.get("direction") or "any"),
                payload.get("after"), payload.get("before"), payload.get("limit", 40),
                payload.get("missing_only") is True))
        if args.command == "check-number":
            return emit(backend.check_number(payload.get("phone"),
                                             str(payload.get("authorization") or "")))
        if args.command == "send-new":
            return emit(backend.send_new(payload.get("target"),
                                         str(payload.get("text") or "")))
        if args.command == "paste":
            return emit(backend.paste(str(payload.get("jid") or "")))
        if args.command == "discard-stage":
            return emit(backend.discard_clipboard_stage(payload.get("path")))
        if args.command == "files":
            return emit(backend.send_files(str(payload.get("jid") or ""),
                                           payload.get("paths"),
                                           str(payload.get("caption") or ""),
                                           str(payload.get("reply_id") or "")))
        if args.command == "voice-draft":
            return emit(backend.voice_draft(str(payload.get("action") or ""),
                                            payload.get("path")))
        if args.command == "voice":
            return emit(backend.send_voice(str(payload.get("jid") or ""),
                                           payload.get("path"),
                                           str(payload.get("reply_id") or "")))
        if args.command == "sticker":
            return emit(backend.send_sticker(str(payload.get("jid") or ""),
                                             payload.get("path"),
                                             str(payload.get("reply_id") or "")))
        if args.command == "poll":
            return emit(backend.send_poll(str(payload.get("jid") or ""),
                                          str(payload.get("question") or ""),
                                          payload.get("options"), payload.get("multi", 1)))
        if args.command == "open-media":
            return emit(backend.open_media_external(payload.get("path")))
        if args.command == "media":
            return emit(backend.download_media(str(payload.get("jid") or ""),
                                               str(payload.get("id") or "")))
        if args.command == "react":
            return emit(backend.react(str(payload.get("jid") or ""),
                                      str(payload.get("id") or ""),
                                      str(payload.get("emoji") or "")))
        if args.command == "edit":
            return emit(backend.edit_message(str(payload.get("jid") or ""),
                                             str(payload.get("id") or ""),
                                             str(payload.get("text") or "")))
        if args.command == "delete":
            return emit(backend.delete_message(str(payload.get("jid") or ""),
                                               str(payload.get("id") or ""),
                                               bool(payload.get("for_me"))))
        if args.command == "chat-presence":
            return emit(backend.chat_presence(str(payload.get("jid") or ""),
                                              str(payload.get("state") or "")))
        if args.command == "star":
            return emit(backend.star_message(str(payload.get("jid") or ""),
                                             str(payload.get("id") or ""),
                                             payload.get("starred") is not False))
        if args.command == "forward":
            return emit(backend.forward_message(str(payload.get("jid") or ""),
                                                str(payload.get("id") or ""),
                                                str(payload.get("to_jid") or ""),
                                                str(payload.get("to_phone") or "")))
        if args.command == "export-chat":
            return emit(backend.export_chat(str(payload.get("jid") or ""), payload.get("destination"),
                                            payload.get("replace") is True))
        if args.command == "download-pending":
            return emit(backend.download_pending(str(payload.get("jid") or ""), payload.get("limit", 50)))
        if args.command == "contact-alias":
            return emit(backend.contact_alias(str(payload.get("person") or ""), payload.get("alias")))
        if args.command == "contact-tag":
            return emit(backend.contact_tag(str(payload.get("person") or ""), payload.get("tag"),
                                            payload.get("remove") is True))
        if args.command == "contact-profile":
            return emit(backend.contact_profile(str(payload.get("person") or ""),
                                                str(payload.get("authorization") or "")))
        if args.command == "create-group":
            return emit(backend.create_group(payload.get("name"), payload.get("participants")))
        if args.command == "join-group":
            return emit(backend.join_group(payload.get("invite")))
        if args.command == "statuses":
            return emit(backend.statuses(payload.get("mine_only") is True))
        if args.command == "delete-status":
            return emit(backend.delete_status(str(payload.get("id") or "")))
        if args.command == "poll-vote":
            return emit(backend.vote_poll(str(payload.get("jid") or ""),
                                          str(payload.get("id") or ""),
                                          payload.get("options")))
        if args.command == "select":
            return emit(backend.select_option(str(payload.get("jid") or ""),
                                              str(payload.get("id") or ""),
                                              payload.get("index")))
        if args.command == "chat-action":
            return emit(backend.chat_action(str(payload.get("jid") or ""),
                                            str(payload.get("action") or "")))
        if args.command == "acknowledge":
            return emit(backend.acknowledge_notifications(str(payload.get("jid") or "")))
        if args.command == "notify":
            return emit(backend.notify(str(payload.get("skip_jid") or "")))
        if args.command == "notify-mode":
            return emit(backend.set_notifications(payload.get("enabled"),
                                                  payload.get("preview"),
                                                  payload.get("sound")))
        if args.command == "notify-open":
            return emit(backend.notify_open(payload))
        if args.command == "save-media":
            return emit(backend.save_media(str(payload.get("jid") or ""),
                                           str(payload.get("id") or ""),
                                           payload.get("destination"),
                                           payload.get("replace") is True))
        if args.command == "about":
            return emit(backend.about())
        if args.command == "media-mode":
            return emit(backend.media_mode(payload.get("auto_download_media")))
        if args.command == "unlink-account":
            return emit(backend.unlink_account(payload.get("name"), payload.get("confirm")))
        if args.command == "setup":
            return emit(backend.setup(payload.get("agents"), payload.get("replace_original", False)))
        if args.command == "teardown":
            return emit(backend.teardown(payload.get("confirm")))
        if args.command == "quit":
            return emit(backend.quit_app())
        if args.command == "launch":
            return emit(backend.launch_app())
        if args.command == "sync-mode":
            if not isinstance(payload.get("online"), bool):
                raise OmaWhatsAppError("Online mode must be true or false.")
            return emit(backend.set_online(bool(payload["online"])))
        if args.command == "settings":
            update = payload.get("settings") if "settings" in payload else None
            return emit(backend.settings(update))
        if args.command == "avatars":
            return emit(backend.refresh_avatars(
                payload.get("authorization"), payload.get("limit")
            ))
    except OmaWhatsAppPartialError as exc:
        return emit({
            "ok": False,
            "error": clean_error(exc, "WhatsApp for Omarchy partly completed that request."),
            "partial": exc.partial,
        }, 1)
    except OmaWhatsAppError as exc:
        return emit({"ok": False, "error": clean_error(exc, "WhatsApp for Omarchy failed.")}, 1)
    return emit({"ok": False, "error": "Unknown command."}, 2)


if __name__ == "__main__":
    raise SystemExit(main())
