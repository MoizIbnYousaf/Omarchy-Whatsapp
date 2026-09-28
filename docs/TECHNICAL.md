# Technical notes

[← Documentation](README.md)

The runtime shape, the trust boundary, how writes coexist with live sync,
and the paths the app uses at runtime.

## Runtime shape

WhatsApp for Omarchy is one Omarchy plugin with two shell entry points:

- `Service.qml` stays resident, owns local sync/read state, and owns the one
  lazily displayed `App.qml` responsive window.
- `BarWidget.qml` owns a keyboard-capable `Dropdown.qml` anchored to the bar;
  it reads and writes through the same resident service.

`bin/omawhatsapp` is a bounded Python bridge, not a daemon. The only long-lived
backend is the user-owned `wacli sync --follow` process. `bin/omawhatsapp` is a
short launcher. The bridge itself is the module `bin/omawhatsapp_core.py`,
which Python compiles once and caches under
`${XDG_CACHE_HOME:-~/.cache}/omawhatsapp/pycache`. Without that cache, every
call would recompile about six thousand lines before doing any work.

One account is one store. The helper reads the account list from wacli, opens
each account's mirror separately, passes `--account` on every command it runs,
and keys its own private state by store path so a rename cannot orphan a badge.
The chat rail is merged in the helper and re-limited after the merge, so a
bounded read stays bounded no matter how many accounts are linked.

The resident service uses Omarchy's existing `inotifywait` utility to watch
each account store's database/WAL filenames. Events are debounced before a
bounded read, and the original 12-second cadence remains as a fallback if the
watcher exits. `setpriv --pdeathsig TERM` ensures the watcher cannot outlive the
Quickshell process.

## Data and trust boundary

Reads open wacli's discovered `wacli.db` with SQLite URI `mode=ro` and
`PRAGMA query_only=ON`. Every write target must already exist in the local
`chats` table. Message mutations must additionally resolve inside that exact
chat. Requests are limited to 64 KiB, message text to 4096 characters, files
to 100 MiB each, and batches to 10 files. wacli, systemctl, and clipboard
output is drained concurrently under command-specific hard byte caps; an
over-limit child is killed and reaped before its output reaches JSON parsing.

The helper accepts local absolute paths only. Clipboard images are staged with
mode `0600` below the user's runtime directory so the composer can preview and
remove them before sending. No WhatsApp database, session, phone number, chat
JID, or media byte is stored in the repository.

Successful outgoing uploads are reconciled with a bounded private
`sent-media.json` index (mode `0600`) because wacli's outgoing database row
does not retain the original local path. Keys include the account store, the chat, and the message ID,
and missing/stale paths are ignored. Group mentions are likewise bounded and
must resolve to a participant or known sender in the selected indexed group.

`preferences.json` is another atomic mode-`0600` helper file. State files and
locks are opened relative to an owner-checked directory descriptor with
`O_NOFOLLOW`; writes use same-directory descriptor-bound atomic replacement.
It stores the online/offline choice, private-reading/read-receipt preference,
bar badge visibility, dropdown density, and per-chat unread/timestamp
acknowledgement snapshots. Acknowledgement affects the local notification
delta, never `wacli.db`. The open chat, a reply, and the chat-list toggle use
`wacli chats mark-read`/`mark-unread`, which only sync the read state to the
user's own devices; no read receipt reaches the sender. Archived and currently muted chats retain their
true unread count inside the chat rail while contributing zero to the bar's
local notification total.

`avatars.json` and its opaque-named image directory form a separate bounded,
owner-private cache. Cache keys hash the account store and exact chat JID;
remote CDN URLs are used only in memory by the helper and never reach QML.
Refresh is an explicit `remote-read` action over a small recent-chat batch, so
opening or searching the rail remains a SQLite/local-file operation. A
lock-contended metadata read uses the same short, exact-account sync yield as
other live requests. One refresh yields each account once for its whole bounded
batch; failed entries use a retained retry deadline so they cannot starve later
chats even when the cache is full.

`VoiceRecorder.qml` is instantiated once by the resident service and shared by
both composers. Qt Multimedia writes 48 kHz mono OGG/Opus into a random path
allocated below the helper's private state directory. Stopping capture runs a
separate finalize check before exposing preview playback. The focused `voice`
command revalidates the exact local chat, optional reply message, private path,
owner, link count, size, and OGG/Opus signature before invoking `wacli send
voice` with an argument array. A transport error keeps the review draft; a
confirmed send deletes it and never retries automatically.

## Writes while sync is live

wacli's companion socket handles supported mutations without stopping sync.
If a command reports the store is locked, the helper retries under a private
file lock. Only after a second locked result does it briefly stop the exact
sync unit; every normal completion and exception path attempts to start it
again. Before stopping it, the helper durably records a bounded restart intent;
the next helper invocation repairs a unit left down by process termination
before serving any request. Recovery takes the same per-account lifecycle lock
and re-reads the intent, so it cannot restart sync under a live foreground
operation. This avoids two writers while preserving the normal instant path.
`lifecycle-recovery.json` contains only a validated public systemd unit name
and an opaque lock filename—never WhatsApp data.

## File picker isolation

The desktop picker runs as a separate `zenity` process. A portal/GLib failure
there cannot corrupt or terminate the Quickshell process. Picker output is
newline parsed, filtered to absolute local paths, converted to file URLs, and
then revalidated by the helper before any send.

## Native interaction details

Typing `@` in a group filters the locally indexed participant list; the chosen
display name is inserted into the draft while its JID travels separately as a
real WhatsApp mention. Message body text is read-only selectable text. A stable
selection is piped directly to `wl-copy`, followed by an in-app confirmation
toast. Every QML `Text` surface explicitly uses `Text.PlainText`, including
remote chat, sender, message, filename, option, and error values.

The gallery's external action routes readable images to `omasnap --file` when
Omasnap is present on `PATH`. Videos, documents, and machines without Omasnap
use the fixed `/usr/bin/xdg-open` fallback. The helper validates that the input
is an existing local file before starting either process.

One resident playback coordinator leases decoded motion/audio to one exact
account, chat, message, and surface at a time. Opening the gallery, switching
chats, or starting media in the other window revokes the previous lease; the
old player stops immediately and paused video retains its decoded frame.

## Installation and first-run setup

`omarchy plugin add` clones the whole repository into the plugins folder and
validates it; it runs no script. The helper, the QML, the unit templates and
the agent skill therefore always come from one commit, and the app runs the
helper from `bin/` in that checkout, never from a copy.

What has to live outside the plugin folder is set up by the app on first run,
after the user agrees (`omawhatsapp setup`, idempotent):

1. **Sync units.** `systemd/user/*.service` are written to
   `~/.config/systemd/user` with the same sandbox, pointing at the wacli the
   helper found (`~/.local/bin/wacli` first, then `/usr/local/bin` and
   `/usr/bin`, never `PATH`). The units are enabled and started per account
   as its settings say; an unchanged setup restarts nothing.
2. **Links, not copies.** `~/.local/bin/omawhatsapp` links to the checkout's
   helper, which the units and the command line use; when agents are allowed,
   `~/.local/bin/omawhatsapp-mcp` and `~/.agents/skills/omawhatsapp` link to
   the MCP server and the skill. `omarchy plugin update` moves them all at
   once. The setup only replaces what is provably this app's: a link into its
   own plugin folder, or a copy an earlier install script left unchanged —
   byte for byte a version of that file, or of the whole skill folder, that
   the scripts before 0.16.0 (this app's and the original OmaWhatsApp's)
   copied. `bin/earlier-copies.json` lists their sha256, generated from the
   git history by `scripts/earlier-copies`. Such copies are moved to
   `~/.local/state/omawhatsapp/setup-backup`, not deleted. A link, file or
   folder that belongs to anything else, including one that only mentions
   the app's name, stops the setup before it changes anything, and the app
   lists the paths to move away.
   Teardown and turning agents off follow the same rule.
3. **Consent.** Stored in the preferences; an install made by the old script
   counts as consent. Turning off the original OmaWhatsApp, which shares the
   helper name, units and state, always asks.

`omawhatsapp teardown` undoes it (Settings → Sync & storage → Remove from this
computer) and keeps the linked device, the archive and the settings.

**Files the app writes, and only those.** The sync units and the media drop-in
(`10-omawhatsapp-media.conf`, which Settings → Media writes to turn automatic
downloads off) start with a line holding the sha256 of the rest of the file.
The setup, the media setting and teardown replace or remove such a file only
while that checksum matches, or when it is byte for byte a text an earlier
version wrote (`EARLIER_WRITTEN_SHA256`). A file someone edited, or wrote, is
left as it is: the setup and the media setting stop before changing anything
and name it, and teardown lists it as kept and leaves that unit's service
running. `systemctl --user edit` is the way to change how sync runs; it keeps
the change in a separate drop-in the app never touches.

Files the user asks for follow the same rule: saving an attachment or
exporting a chat replaces an existing file only after the save dialog asked,
and an export an agent requests never replaces one.

After `omarchy plugin update` the shell keeps the QML it loaded until it
restarts, while the helper is already new: the app compares the helper's
`HELPER_VERSION` with its manifest and asks for a shell restart.
`scripts/test` fails when the two versions differ in the repository.

## Runtime paths

| Path | Purpose |
|---|---|
| `~/.config/omarchy/plugins/io.github.atoslins.whatsapp` | the plugin: a git checkout of this repository |
| `…/bin/omawhatsapp`, `…/bin/omawhatsapp_core.py` | bounded helper (launcher and code), run from the checkout |
| `~/.local/bin/omawhatsapp` | link to the checkout's helper (units and command line) |
| `~/.local/bin/omawhatsapp-mcp` | link to the MCP server, when agents are allowed |
| `~/.agents/skills/omawhatsapp` | link to the agent skill, when agents are allowed |
| `~/.cache/omawhatsapp/pycache` | the helper's compiled bytecode (disposable) |
| `~/.config/systemd/user/wacli-sync.service`, `wacli-sync@.service` | background sync units, written by the setup |
| `~/.local/state/wacli` | linked-device store owned by wacli |
| `~/.local/state/omawhatsapp` | helper lock/disposable app state |
| `~/.local/state/omawhatsapp/voice-drafts` | private reviewed voice drafts |

## Verification

`scripts/test` runs backend unit tests, root manifest validation, QML lint,
real synthetic MP4/GIF/WebP decode tests, cross-surface playback and deferred
intent tests, account/avatar boundary tests, first-run setup tests, a simulated `omarchy plugin add`, shell syntax checks, diff
hygiene, and a guard against browser/Electron runtime dependencies. Live
verification also checks service health, picker cancellation, window
breakpoints, shell logs, and coredump count without sending test messages.
