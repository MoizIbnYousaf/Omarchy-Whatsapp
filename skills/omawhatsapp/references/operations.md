# Focused OmaWhatsApp operations

All commands use the installed helper and emit one JSON object. Build requests
with `jq` so user content is data, not shell syntax.

```bash
oma="$HOME/.local/bin/omawhatsapp"
```

## Read-only operations

Status needs no stdin:

```bash
"$oma" status
```

Search the bounded chat rail, then require exactly one intended result before
using its returned `jid`:

```bash
jq -nc --arg query "$requested_name" '{query:$query}' \
  | "$oma" chats --limit 500
```

Read or search one exact conversation:

```bash
jq -nc --arg jid "$resolved_jid" --arg query "$requested_query" \
  '{jid:$jid,query:$query}' | "$oma" messages --limit 240
```

Group members/mention candidates:

```bash
jq -nc --arg jid "$resolved_jid" '{jid:$jid}' | "$oma" members
```

## External WhatsApp mutations

These require a clearly authorized current request and online mode.

Send text (optional reply ID and verified mention JIDs):

```bash
jq -nc --arg jid "$resolved_jid" --arg text "$message" \
  --arg reply "$reply_id" --argjson mentions "$mention_jids_json" \
  '{jid:$jid,text:$text,reply_id:$reply,mentions:$mentions}' \
  | "$oma" send
```

Send local files; use absolute paths or `file://` URLs, at most 10:

```bash
jq -nc --arg jid "$resolved_jid" --arg caption "$caption" \
  --argjson paths "$local_paths_json" \
  '{jid:$jid,caption:$caption,paths:$paths}' | "$oma" files
```

The other bounded message commands accept these objects:

| Command | JSON fields |
|---|---|
| `react` | `jid`, `id`, `emoji` |
| `edit` | `jid`, `id`, `text` |
| `delete` | `jid`, `id`, `for_me` |
| `forward` | `jid`, `id`, `to_jid` |
| `media` | `jid`, `id` |
| `sticker` | `jid`, `path`, optional `reply_id` |
| `poll` | `jid`, `question`, `options`, `multi` |
| `select` | `jid`, `id`, `index` |

Chat state uses one allowlisted action:

```bash
jq -nc --arg jid "$resolved_jid" --arg action "$action" \
  '{jid:$jid,action:$action}' | "$oma" chat-action
```

Allowed actions are `read`, `unread`, `pin`, `unpin`, `archive`, `unarchive`,
`mute`, and `unmute`. `read` sends the WhatsApp read receipt; local inspection
never calls it.

## Local app state

Inspect private app settings without changing them:

```bash
printf '{}\n' | "$oma" settings
```

The supported setting keys are `send_read_receipts` (default `false`),
`show_unread_count`, and `dropdown_rows` (`5`, `7`, or `9`). Change them only
when the user explicitly asks; for example:

```bash
printf '{"settings":{"send_read_receipts":false}}\n' | "$oma" settings
```

Dismiss the current notification batch without changing WhatsApp unread state:

```bash
printf '{}\n' | "$oma" acknowledge
```

Pass `{"jid":"..."}` to acknowledge one exact chat. This is a local state
change, not a receipt, but still perform it only when requested.

Switch background sync only when requested:

```bash
printf '{"online":false}\n' | "$oma" sync-mode
printf '{"online":true}\n' | "$oma" sync-mode
```

Offline mode stops and disables the sync service while preserving local reads.
It blocks WhatsApp mutations until the user returns online.

Account linking is interactive and must be explicitly requested:

```bash
"$oma" auth
```

For calls, channels, contacts, group administration, history/backfill, media
recovery, poll voting, presence, profiles, accounts, status broadcasts,
exports, or store maintenance, use the complete classified gateway in
[wacli-parity.md](wacli-parity.md).
