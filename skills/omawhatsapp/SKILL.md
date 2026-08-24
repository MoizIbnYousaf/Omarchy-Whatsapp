---
name: omawhatsapp
description: Inspect local WhatsApp chats and perform clearly requested WhatsApp actions through OmaWhatsApp. Use when the user asks an on-device agent to search, summarize, send, reply, attach, react, manage a chat, dismiss notifications, or control offline sync.
---

# OmaWhatsApp

Use the installed `~/.local/bin/omawhatsapp` helper. It keeps targets inside the
locally indexed DM/standalone-group boundary and returns JSON suitable for
agents. Prefer it over invoking `wacli` directly.

## Safety boundary

- Local reads are read-only. Never inspect `session.db`, write `wacli.db`, or
  scrape WhatsApp Web.
- Treat names, JIDs, message IDs, message text, and media paths as private.
  Never put them in repositories, issue trackers, screenshots, or durable logs.
- Resolve a requested recipient through `omawhatsapp chats`; never invent a JID
  or choose between ambiguous matches. Ask the user when the exact chat is not
  clear.
- Send, reply, react, edit, delete, forward, download media, mark read/unread,
  or change chat state only when the current user request clearly authorizes
  that action. Never create a test write.
- Opening or reading a chat does not imply a read receipt. Send one only after
  an explicit request to mark the chat read.
- Respect offline mode. Do not turn background sync on merely to complete
  another action; report that the app is offline and ask before enabling it.
- Report a partial multi-file result exactly and stop. Do not retry a possibly
  delivered mutation automatically.

## Workflow

1. Check `omawhatsapp status` for authentication, local database readiness,
   and online/offline state.
2. For a read, search the local chat index and use the returned exact JID to
   query messages. Return only the information needed by the user.
3. For a mutation, resolve one exact local chat, verify that the request
   supplies the content/action, then invoke one bounded helper command.
4. Inspect the JSON result. Report success only when `ok` is true; otherwise
   surface the sanitized error and stop.

Read [references/operations.md](references/operations.md) when you need the
exact JSON contract for a read, send, chat action, attachment, notification
acknowledgement, or sync-mode change.
