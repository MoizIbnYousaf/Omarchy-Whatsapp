# Technical notes

## Runtime shape

OmaWhatsApp is one Omarchy plugin with two shell entry points:

- `Service.qml` stays resident, owns local sync/read state, and owns the one
  lazily displayed `App.qml` responsive window.
- `BarWidget.qml` owns a keyboard-capable `Dropdown.qml` anchored to the bar;
  it reads and writes through the same resident service.

`bin/omawhatsapp` is a bounded Python bridge, not a daemon. The only long-lived
backend is the user-owned `wacli sync --follow` process.

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
delta, never `wacli.db`; private reading is the default. Read receipts use
`wacli chats mark-read` only after the user opts in or chooses the explicit
chat-menu action. Archived and currently muted chats retain their
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

## Plugin reload safety

Quickshell watches installed plugins recursively. Copying QML files one at a
time can expose a half-installed tree and trigger repeated reloads. The local
installer therefore:

1. validates and stages a complete plugin tree;
2. prepares the new shell configuration;
3. records a mode-`0600`, fsynced transaction journal and the exact prior
   service states;
4. stops the shell and atomically swaps each target beside its destination;
5. verifies the installed helper, manifests, and service lifecycle;
6. restarts the shell once and removes backups only after commit.

If the process or machine stops mid-upgrade, the next install or uninstall
finishes a committed cleanup or rolls every target and service back from the
journal before doing new work. The journal contains only installation paths
and public service names—never WhatsApp data.

Build/test artifacts remain outside the installed plugin tree.

## Runtime paths

| Path | Purpose |
|---|---|
| `~/.config/omarchy/plugins/io.github.moizibnyousaf.omawhatsapp` | installed plugin |
| `~/.agents/skills/omawhatsapp` | shared on-device agent skill |
| `~/.local/bin/omawhatsapp` | bounded helper |
| `~/.local/bin/omawhatsapp_assets.py` | private bounded avatar-cache module |
| `~/.config/systemd/user/wacli-sync.service` | background sync unit |
| `~/.local/state/wacli` | linked-device store owned by wacli |
| `~/.local/state/omawhatsapp` | helper lock/disposable app state |
| `~/.local/state/omawhatsapp/voice-drafts` | private reviewed voice drafts |

## Verification

`scripts/test` runs backend unit tests, root manifest validation, QML lint,
real synthetic MP4/GIF/WebP decode tests, cross-surface playback and deferred
intent tests, account/avatar boundary tests, interrupted-install recovery tests, shell syntax checks, diff
hygiene, and a guard against browser/Electron runtime dependencies. Live
verification also checks service health, picker cancellation, window
breakpoints, shell logs, and coredump count without sending test messages.
