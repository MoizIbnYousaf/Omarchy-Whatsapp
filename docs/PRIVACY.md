# Privacy and local data

OmaWhatsApp handles end-to-end encrypted data after it reaches your linked
device. Treat wacli's database and media directory as private.

Never commit WhatsApp session keys, `wacli.db`, `session.db`, WAL/SHM files,
media downloads, chat/message identifiers, phone numbers, exports, or real
conversation screenshots. Repository ignore rules help, but every staged diff
must still be reviewed before push.

Runtime data remains under `~/.local/state/`. Clipboard images use a private
runtime file, pass through wacli, and are removed in a `finally` path.
OmaWhatsApp's mode-`0600` preferences contain the offline choice, private
reading/read-receipt choice, bar badge visibility, dropdown density, and local
notification acknowledgements. Private reading is the default. State reads and locks are descriptor-bound,
owner-checked, and no-follow; atomic replacement never follows a predictable
state-file symlink. They never leave the machine and are never written into
wacli's database.

Voice drafts are created under the mode-`0700`
`~/.local/state/omawhatsapp/voice-drafts` directory and finalized to mode
`0600`. They never leave the device during recording or preview. Capture opens
only after an explicit UI action, stops before review, and crosses WhatsApp
only after the user explicitly submits the reviewed draft. Failed sends remain
local for retry or discard; confirmed sends remove their draft.

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
