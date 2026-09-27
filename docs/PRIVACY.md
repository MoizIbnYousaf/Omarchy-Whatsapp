# Privacy and local data

[← Documentation](README.md)

WhatsApp for Omarchy handles end-to-end encrypted data after it reaches your linked
device. Treat wacli's database and media directory as private.

Never commit WhatsApp session keys, `wacli.db`, `session.db`, WAL/SHM files,
media downloads, chat/message identifiers, phone numbers, exports, or real
conversation screenshots. Repository ignore rules help, but every staged diff
must still be reviewed before push.

Runtime data remains under `~/.local/state/`. Clipboard images use a private
runtime file, pass through wacli, and are removed in a `finally` path.
WhatsApp for Omarchy's mode-`0600` preferences contain the bar badge visibility, the
dropdown density, and the desktop-notification choice, plus one private section
per account store holding that account's offline choice,
automatic-reading choice, the name it signs messages with (when the signature
is on), local notification acknowledgements, and the
per-chat watermark that decides which popups are still owed. Accounts never
read each other's section, so the same contact reachable from two linked
phones keeps two independent local badges. State reads and locks are descriptor-bound,
owner-checked, and no-follow; atomic replacement never follows a predictable
state-file symlink. They never leave the machine and are never written into
wacli's database.

The first-run setup writes only in your home folder and only after you agree:
the sync units in `~/.config/systemd/user`, links in `~/.local/bin` and, when
agents are allowed, `~/.agents/skills`. It replaces only what is provably
this app's, moving earlier copies to `~/.local/state/omawhatsapp/setup-backup`
instead of deleting them, and never touches a path that belongs to anything
else. Checking for updates
asks the repository's git remote for its latest commit; no chat data is sent.

Marking a chat read, automatically or from the chat list, sends WhatsApp an
app-state change that syncs the read state to the user's own devices. wacli
has no path that sends a read receipt, so the other side is not told.

With a wacli build that keeps receipts, the mirror also records when each
recipient received, read, or played the messages you sent, as WhatsApp
reports it to your linked devices. The app shows that as ticks and never sends
anything for it. The rows are removed with their chat.

Such a build also keeps `presence.json` (mode `0600`) in the store while its
sync runs: which followed contacts are online, their last seen when they share
it, and who is typing. The app reads it directly and shows it for the open
chat. To receive it, the account shows itself online to WhatsApp while the
window, or the dropdown on a conversation, has focus. That is on by default
and turned off in Settings → Reading. The same setting tells a chat that you
are typing (as keys are pressed in its message box, stopped after a few
seconds or when the box empties) or recording a voice note, through the
running sync only. The sync ends that online state by
itself about 90 seconds after the app stops renewing it, and removes the file
when it stops.

Desktop popups leave the process: chat names, senders, and message previews
reach the notification daemon and its history. They are on by default, can be
muted from the bar icon, the preview can be dropped so only chat names travel, and every field is truncated
to one printable, markup-inert line before it is handed to `notify-send`.

An agent connected through `omawhatsapp-mcp` reads what its tools return:
chat names, message text, contacts, and attachment paths. That content goes
wherever the agent sends its prompts, which for a hosted model means the
model provider. Nothing is read until the agent calls a tool for a request,
the server keeps no copy, and every tool that changes WhatsApp is marked so the
host asks first. An export writes one private file where the user asked,
refused inside a repository unless separately authorized. A file sent from
`/tmp` is copied to the mode-`0700` `~/.local/state/omawhatsapp/outgoing`
folder, because the sandboxed sync service cannot see `/tmp`, and the copy is
removed as soon as the send returns.

Voice drafts are created under the mode-`0700`
`~/.local/state/omawhatsapp/voice-drafts` directory and finalized to mode
`0600`. They never leave the device during recording or preview. Capture opens
only after an explicit UI action, stops before review, and crosses WhatsApp
only after the user explicitly submits the reviewed draft. Failed sends remain
local for retry or discard; confirmed sends remove their draft.

Profile-photo refresh is an explicit remote read, never part of ordinary chat
browsing. The helper accepts only public, hostname-verified HTTPS targets,
pins each connection to the address it validated, and repeats that boundary at
every redirect. It keeps at most 2048 one-megabyte JPEG, PNG, or WebP files in
an owner-private cache with opaque names. CDN URLs, query tokens, account store
paths, and chat identifiers are not stored in that index or exposed to QML;
the UI receives only a validated absolute local path.

Group settings are read from WhatsApp only when "Load group settings" is
pressed (`wacli groups info`, an explicit remote read that pauses sync for a
moment); the invite link and pending join requests are likewise fetched only
on request. Group changes go through `wacli groups`, and a participant action
must name someone the mirror lists in that exact group.

Checking a typed number for a new chat is also an explicit remote read: the
helper runs `wacli contacts check`, which asks WhatsApp whether the number is
registered and stores nothing in the mirror. Pressing Message on a shared
contact nobody here has a chat with opens a draft chat for that person and
asks the same question once, as it opens; nothing is sent until Enter. With a
wacli build that delegates the check, it goes through the running sync, which
keeps running. The confirmed JID is kept for 15
minutes in the owner-private `new-chat-checks.json` (mode `0600`, at most 32
entries), so the first message can go to exactly that recipient; expired
entries are ignored and dropped the next time a number is checked.
Unregistered numbers are not kept. WhatsApp answers with the person's `@lid`;
wacli sends to it and files the chat under the phone JID when it knows the
mapping.

Desktop notifications are on by default. A popup carries the chat name, the
sender and message text (unless previews are off), and the chat's cached
photo as its image, which Omarchy's notification service may copy into its
own history directory. The helper reads only the `dnd` flag of
`~/.local/state/omarchy/notifications.json` to keep the notification sound
quiet under do not disturb; the sound is the freedesktop theme's
`message-new-instant`, played with `pw-play`.

The sticker picker fetches the recent stickers that are not on this computer
yet into the same private media folder as other downloads, and remembers in
`stickers-gone.json` the ones WhatsApp answered 403/404/410 for, so they are
not requested again.

`lid-aliases.json` (mode `0600`) maps each `@lid` chat found in the mirror to
the contact's phone chat, as answered by `wacli --read-only contacts show`, so
a file wacli filed under the `@lid` still shows in that contact's chat.

So that the next message in a chat updates its popup instead of stacking a
new one, the helper keeps each chat's last popup id for an hour in the
owner-private `notify-ids.json` (mode `0600`, at most 64 entries, keyed by
account and chat JID).

If a foreground wacli operation briefly yields background sync, the helper
stores a crash-recovery intent containing only the public systemd unit name and
an opaque lock filename. It contains no account store path, chat identifier,
message, media, URL, or credential and is removed after sync is restored.

Child-process and clipboard pipes are drained incrementally under hard byte
caps. Chat names, senders, message bodies, filenames, button labels, and error
strings are always rendered as plain text in QML.

The shipped agent skill contains instructions only—no account, chat, message,
or media data. Its advanced gateway does not echo command arguments, because
they may contain phone numbers, JIDs, message text, filenames, invite codes,
locations, webhook destinations, or profile values. Agents must keep local
results, exports, event streams, downloaded media, and webhook secrets out of
repositories, issues, screenshots, and durable logs, and must use the helper
rather than touching a WhatsApp database directly.

For screenshots, open `omawhatsapp` with `{"demo":true}`. Demo mode contains
repository-owned sample data and performs no WhatsApp writes.
