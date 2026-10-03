---
name: omawhatsapp
description: Inspect, search, summarize, sync, and operate WhatsApp through OmaWhatsApp, including complete guarded wacli parity for messages, media, chats, groups, channels, calls, contacts, history, profiles, accounts, and maintenance.
---

# OmaWhatsApp

When the `whatsapp` MCP server (`~/.local/bin/omawhatsapp-mcp`) is connected,
prefer its tools: they call this helper with the right authorization classes
and apply the same boundaries below. Otherwise use the helper directly.

Use the installed `~/.local/bin/omawhatsapp` helper. Its focused commands keep
ordinary chat work inside the locally indexed DM/standalone-group boundary.
Its guarded `wacli` gateway covers every command leaf in the supported wacli
version without exposing an arbitrary executable passthrough. Prefer it over
invoking `wacli` directly.

## Route the request

- For a runtime WhatsApp operation, follow the guarded workflow below.
- For source, test, deployment, release, or submission work, follow the
  repository's `CONTRIBUTING.md` and workflow. Never edit an installed
  helper, plugin, or skill as source; use only synthetic/demo data for public
  evidence. Runtime authorization does not authorize repository writes,
  pushes, deployments, releases, or submissions.
  In-app release checks are opt-in and contact GitHub, not WhatsApp. App settings
  include `check_updates_on_launch`; changing it is a local preference write.
  Updates run `omarchy plugin update` in a terminal the user confirms; they
  need separate approval and are never started by the skill.

## Safety boundary

- Local reads are read-only. Never inspect `session.db`, write `wacli.db`, or
  scrape WhatsApp Web.
- Treat names, JIDs, message IDs, message text, and media paths as private.
  Never put them in repositories, issue trackers, screenshots, or durable logs.
- Resolve existing-chat targets before mutating them; never invent a JID, use
  an ambiguous name/pick, or infer a recipient. Invite codes, new group names,
  phone numbers, locations, profile values, and status audiences must come
  from the current request or an unambiguous read result.
- External reads, local writes, private filesystem exports, external event
  streams, sync/history work, WhatsApp writes, destructive actions, and
  interactive linking are separate authorization classes. Export/stream
  tokens also name their exact destination. Supply a class token only when
  the current request authorizes that exact class and operation. Full parity
  never grants standing permission.
- Never create a test write. Never retry a possibly delivered send, vote,
  reaction, edit, deletion, membership change, profile change, status,
  channel/group action, or account mutation automatically.
- Reading a chat through the helper never marks it read. Mark a chat read or
  unread, or change the automatic-reading preference, only after an explicit
  request; the phone shows the change.
- Respect offline mode. Do not turn background sync on merely to complete
  another action. Local reads and explicitly requested local maintenance may
  continue; remote reads, sync, and WhatsApp mutations must stop.
- Report a partial multi-file result exactly and stop. Do not retry a possibly
  delivered mutation automatically.
- Treat exports, webhooks, event streams, media paths, account stores, and
  command results as private. Never place them in repositories, issues,
  screenshots, or durable logs.
- Raw status and logs can contain account labels, store paths, and other
  private context. Project them to the minimum needed fields before reporting.

## Workflow

1. For a runtime operation, check authentication, local database readiness,
   and online/offline state without retaining account or store details:

   ```bash
   "$HOME/.local/bin/omawhatsapp" status | jq \
     '{ok,installed,authenticated,database_ready,any_authenticated,
       any_database_ready,rail_ready,sync_active,online,offline_mode,
       account_count:((.accounts // [])|length)}'
   ```
2. Use focused helper commands for ordinary chat reads and writes. Resolve one
   exact local chat and message before any mutation.
3. For channels, calls, contacts, history, group administration, profiles,
   accounts, store work, or another advanced operation, read
   [references/wacli-parity.md](references/wacli-parity.md). Inspect
   `omawhatsapp capabilities` and the relevant `wacli ... --help` before
   constructing the JSON argument array.
4. Invoke one bounded operation with the required authorization class. Use
   interactive mode only for account linking or a foreground sync requested
   by the user.
5. Inspect the JSON result. Report success only when `ok` is true; otherwise
   surface the sanitized error and stop.

Read [references/operations.md](references/operations.md) for focused chat,
message, attachment, notification, and offline-mode contracts. Read
[references/wacli-parity.md](references/wacli-parity.md) for complete advanced
wacli coverage and authorization classes.
