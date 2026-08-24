# Technical notes

## Runtime shape

OmaWhatsApp is one Omarchy plugin with three entry points:

- `Service.qml` stays resident and owns local sync/read state.
- `App.qml` creates the disposable responsive window.
- `BarWidget.qml` is a thin launcher/unread view over the service.

`bin/omawhatsapp` is a bounded Python bridge, not a daemon. The only long-lived
backend is the user-owned `wacli sync --follow` process.

## Data and trust boundary

Reads open wacli's discovered `wacli.db` with SQLite URI `mode=ro` and
`PRAGMA query_only=ON`. Every write target must already exist in the local
`chats` table. Message mutations must additionally resolve inside that exact
chat. Requests are limited to 64 KiB, message text to 4096 characters, files
to 100 MiB each, and batches to 10 files.

The helper accepts local absolute paths only. Clipboard images are staged with
mode `0600` below the user's runtime directory so the composer can preview and
remove them before sending. No WhatsApp database, session, phone number, chat
JID, or media byte is stored in the repository.

Successful outgoing uploads are reconciled with a bounded private
`sent-media.json` index (mode `0600`) because wacli's outgoing database row
does not retain the original local path. Keys include both chat and message ID,
and missing/stale paths are ignored. Group mentions are likewise bounded and
must resolve to a participant or known sender in the selected indexed group.

`preferences.json` is another atomic mode-`0600` helper file. It stores only
the online/offline preference and per-chat unread/timestamp acknowledgement
snapshots. Acknowledgement affects the local notification delta, never
`wacli.db`; read receipts use `wacli chats mark-read` only after an explicit
chat-menu action.

## Writes while sync is live

wacli's companion socket handles supported mutations without stopping sync.
If a command reports the store is locked, the helper retries under a private
file lock. Only after a second locked result does it briefly stop the exact
`wacli-sync.service`; a `finally` block always starts it again. This avoids two
writers while preserving the normal instant path.

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
toast.

The gallery's external action routes readable images to `omasnap --file` when
Omasnap is present on `PATH`. Videos, documents, and machines without Omasnap
use the fixed `/usr/bin/xdg-open` fallback. The helper validates that the input
is an existing local file before starting either process.

## Plugin reload safety

Quickshell watches installed plugins recursively. Copying QML files one at a
time can expose a half-installed tree and trigger repeated reloads. The local
installer therefore:

1. validates and stages a complete plugin tree;
2. prepares the new shell configuration;
3. stops the shell;
4. replaces only the exact OmaWhatsApp plugin directories and unit/helper;
5. restarts the shell once.

Build/test artifacts remain outside the installed plugin tree.

## Runtime paths

| Path | Purpose |
|---|---|
| `~/.config/omarchy/plugins/omawhatsapp` | installed plugin |
| `~/.local/bin/omawhatsapp` | bounded helper |
| `~/.config/systemd/user/wacli-sync.service` | background sync unit |
| `~/.local/state/wacli` | linked-device store owned by wacli |
| `~/.local/state/omawhatsapp` | helper lock/disposable app state |

## Verification

`scripts/test` runs backend unit tests, root manifest validation, QML lint,
offscreen media-viewer state tests, shell syntax checks, diff hygiene, and a
guard against browser/Electron runtime dependencies. Live verification also
checks service health, picker cancellation, window breakpoints, shell logs,
and coredump count without sending test messages.
