# Architecture

## Lifetimes

- `Service.qml` is resident. It owns authentication/sync state, the chat rail,
  selected conversation, unread total, drafts-in-flight, and refresh cadence.
- `App.qml` is disposable. It owns window composition, focus, filtering, and
  the current visible draft.
- `BarWidget.qml` is a thin view over the existing service.
- `bin/omawhatsapp` is a bounded local bridge; it is not a daemon. Its focused
  commands serve the graphical client, while its classified `wacli` gateway
  accounts for every command leaf in the supported transport version.
- `skills/omawhatsapp` teaches compatible local agents to use that same bridge
  without bypassing its exact-chat and authorization boundaries.

The window can disappear without making the data path cold.

Unread state has two independent layers. wacli's `unread_count` remains the
authoritative WhatsApp value. OmaWhatsApp stores a mode-`0600` local
acknowledgement snapshot and derives only the bar's new-message delta from it.
Opening or dismissing never mutates WhatsApp; the labelled chat-menu action is
the sole read-receipt path.

## Data boundary

Read paths open wacli's SQLite mirror in URI read-only/query-only mode. Chat
targets are accepted only if their exact JID already exists in the local
`chats` table, preventing arbitrary destinations from crossing the UI/helper
boundary. All writes use wacli's public CLI.

The graphical chat boundary is intentionally narrower than the mirror: only `dm` rows
and standalone `group` rows are discoverable. Newsletter/channel rows,
Community parents, Community-linked subgroups, broadcasts, and call-event data
stay out of this release's UI. Explicit agent requests can reach those
capabilities through the versioned parity registry without widening the chat
rail or its default write paths.

The advanced gateway is an argument-array adapter, not an arbitrary executable
passthrough. Every wacli 0.17.1 leaf has a fixed policy. Local reads receive
`--read-only`; network work respects offline mode; local writes, sync,
WhatsApp writes, destructive operations, and interactive linking require
distinct current-request authorization tokens. Global options are structured
JSON fields, child output remains bounded, and unknown future leaves fail
closed until reviewed.

Media metadata is read with the message, but bytes stay in wacli's private
store. Existing files render locally. Missing files are fetched only after an
explicit click, and the helper verifies both chat JID and message ID against
the mirror before asking wacli to download anything.

wacli intentionally does not persist the original local path on outgoing
media rows. After a successful upload, OmaWhatsApp keeps a private, bounded,
mode-`0600` message-ID-to-path handoff under its own state directory. This
lets the just-sent image render immediately without touching wacli's database.
For a visual batch, that index also records a random local album ID and bounded
position/count metadata. The UI groups only those exact IDs; wacli still sends
and syncs each standards-compliant WhatsApp media message independently.

Group mention choices come only from participants and senders already indexed
inside that exact group. The helper rejects arbitrary mention JIDs before
passing the verified set to wacli.

`wacli sync --follow` normally owns the store. Supported sends delegate through
its companion socket. If that path is unavailable, the helper serializes a
bounded fallback, briefly yields the user service, sends, and restarts sync in
a `finally` block.

The header's offline choice is persisted privately and maps to
`systemctl --user disable --now wacli-sync.service`. Read paths remain usable;
all WhatsApp mutations fail closed until the user explicitly returns online.
Installer upgrades preserve that choice.

## Performance

- Chat and conversation reads are bounded and use wacli's chat/timestamp index.
- The resident service watches only `wacli.db` and its SQLite WAL sibling,
  then debounces change bursts before refreshing the chat rail and the visible
  conversation. A 12-second timer remains only as a recovery fallback.
- `ListView` virtualizes both rails; images decode asynchronously.
- Static images use aspect-fit decoding, image GIFs and WebP stickers use
  `AnimatedImage`, and WhatsApp's MP4/F4V GIF messages use a muted looping
  `MediaPlayer`. Ordinary video and audio remain paused until requested.
- A native full-window gallery keeps image/GIF/video viewing inside the panel;
  its navigation and zoom boundaries are covered by offscreen QML tests.
- Search is debounced and scoped to the selected conversation.
- Window opening performs no network request.

## Extension boundary

OmaWhatsApp has no special chat names, task semantics, or personal capture
configuration. Personal workflows belong in separate, user-owned extensions.
