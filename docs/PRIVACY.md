# Privacy and local data

OmaWhatsApp handles end-to-end encrypted data after it reaches your linked
device. Treat wacli's database and media directory as private.

Never commit WhatsApp session keys, `wacli.db`, `session.db`, WAL/SHM files,
media downloads, chat/message identifiers, phone numbers, exports, or real
conversation screenshots. Repository ignore rules help, but every staged diff
must still be reviewed before push.

Runtime data remains under `~/.local/state/`. Clipboard images use a private
runtime file, pass through wacli, and are removed in a `finally` path.
OmaWhatsApp's mode-`0600` preferences contain the offline choice and local
notification acknowledgements. They never leave the machine and are never
written into wacli's database.

For screenshots, open `omawhatsapp` with `{"demo":true}`. Demo mode contains
repository-owned sample data and performs no WhatsApp writes.
