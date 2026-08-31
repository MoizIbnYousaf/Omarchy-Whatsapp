# Architecture

## Lifetimes

- `Service.qml` is resident. It owns authentication/sync state, the chat rail,
  selected conversation, unread total, drafts-in-flight, one native voice
  recorder, and refresh cadence.
- `App.qml` is owned once by the resident service. Its window remains hidden
  until summoned and owns composition, focus, filtering, and visible drafts.
- `BarWidget.qml` hosts `Dropdown.qml`, a bar-anchored recent-chat view over
  the existing service. It never creates another backend or poller.
- `bin/omawhatsapp` is a bounded local bridge; it is not a daemon. Its focused
  commands serve the graphical client, while its classified `wacli` gateway
  accounts for every command leaf in the supported transport version.
- `skills/omawhatsapp` teaches compatible local agents to use that same bridge
  without bypassing its exact-chat and authorization boundaries.

The window can disappear without making the data path cold.

The bar click and global shortcut intentionally lead to different surfaces.
The click opens a compact interactive conversation client; `Super+Shift+W`
summons the full app. Both share the same selected exact JID, messages, write
serialization, offline state, voice draft, and resident refresh path.

The resident voice recorder opens the system microphone only after a click or
`Ctrl+Shift+V`. A second toggle, Escape, surface close, or chat switch stops
capture into review and releases the microphone. It does not send. The review
draft remains tied to the exact chat and optional reply ID captured at start;
only its explicit send action crosses the helper boundary.

Desktop popups are a third, opt-in surface with their own watermark. They
read the same chat rail but never the badge's acknowledged delta, so the badge
preference, a dismissal, and a closed window cannot silence them, and a chat
read on another device still notifies once when its timestamp advances. Only
the chat currently on screen is skipped, a burst is capped, and muted and
archived chats stay silent.

Unread state has two independent layers. wacli's `unread_count` remains the
authoritative WhatsApp value. OmaWhatsApp stores a mode-`0600` local
acknowledgement snapshot and derives only the bar's new-message delta from it.
Opening or dismissing never mutates WhatsApp by default. Users can explicitly
opt into automatic exact-chat receipts in the in-app settings card; the
labelled chat-menu action remains the one-off receipt path.

## Accounts

wacli owns the account list. The helper reads it from `accounts list`, which
already resolves each account's absolute store, and keys its own private state
by that store rather than by account name, so renaming an account keeps its
history. A machine with no account config stays single account and keeps the
original sync unit. When named accounts are added, an existing root session is
exposed as `primary` through wacli's `--store` selector without rewriting its
config or moving data; configured accounts each get a
`wacli-sync@<name>.service` instance.

The chat rail merges every account and tags each row with the account it came
from. An account that has never synced is reported as unready beside the rail
instead of emptying it. Everything downstream of a row stays inside that row's
account: its mirror resolves the exact chat, its store scopes the badge
acknowledgement and the popup watermark, its unit is the one paused when the
store lock is contended, and its offline choice governs only its own writes.
Rail account filters are a pure view over those already-scoped rows; selecting
a filter never rewrites or infers a chat target. The explicit `+` flow delegates
linking to a terminal and keeps an existing root session addressable as
`primary` without moving its store or authoring wacli configuration.

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

Profile photos have a separate explicit remote-read boundary. One click asks
for metadata for a bounded recent-chat batch, downloads supported small HTTPS
images behind the helper, and stores them in an owner-private account-and-chat
keyed cache. CDN URLs and tokens never enter QML or persistent index data;
normal rail refreshes consult only the local cache.

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

Voice recordings live only in OmaWhatsApp's owner-private `voice-drafts`
directory. The helper accepts its own random filenames, rejects links and
paths outside that directory, requires a regular single-link file under 100
MiB, and verifies the final OGG/Opus header. A failed send retains the draft;
a confirmed send removes it without turning cleanup trouble into a duplicate
send opportunity.

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
- Static images use bounded aspect-fit decoding, image GIFs and WebP stickers
  use `AnimatedImage`, and WhatsApp's MP4/F4V GIF messages use a muted looping
  `MediaPlayer`. A resident exact-message lease allows motion/audio on only one
  app, dropdown, or gallery surface; ordinary video and audio remain paused
  until requested.
- A native full-window gallery keeps image/GIF/video viewing inside the panel;
  its navigation and zoom boundaries are covered by offscreen QML tests.
- Search is debounced and scoped to the selected conversation.
- Window opening performs no network request.

## Extension boundary

OmaWhatsApp has no special chat names, task semantics, or personal capture
configuration. Personal workflows belong in separate, user-owned extensions.
