# OmaWhatsApp agent contract

## Scope

This repository is the general Omarchy client. It contains no personal
workflow assumptions and no WhatsApp history.

## Safety

- Use the official `wacli` skill before operating wacli.
- Default to read-only inspection; never send a test message or media without
  the user's explicit approval for that write.
- Never commit or push session keys, databases, media, exports, JIDs, message
  IDs, phone numbers, message contents, or screenshots of real conversations.
- Never inspect `session.db` or write directly to `wacli.db`.
- A send target must resolve to an exact chat already present in the local
  `chats` table before invoking wacli.
- Long history/media maintenance must remain separate from the interactive
  write path and restart background sync through an exit trap.
- Keep `skills/omawhatsapp` aligned with the helper's public JSON commands.
  The skill must never broaden authorization for external WhatsApp mutations.

## Local paths

```text
~/.local/state/wacli/                  private linked-device state and mirror
~/.local/state/omawhatsapp/            private helper serialization state
~/.config/omarchy/plugins/omawhatsapp/ installed full app
```

## Required verification

Run `make validate` after code changes. For UI changes, restart the Omarchy
shell, inspect current-session logs, and capture only privacy-safe demo mode.
