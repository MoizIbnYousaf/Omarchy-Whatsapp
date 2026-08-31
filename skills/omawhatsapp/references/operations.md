# Focused OmaWhatsApp operations

All commands use the installed helper and emit one JSON object. Build requests
with `jq` so user content is data, not shell syntax.

```bash
oma="$HOME/.local/bin/omawhatsapp"
```

## Accounts

Every request may carry `account`, naming one configured wacli account. An
empty or absent value means the default account. `status` reports the
configured accounts, and `chats` returns one merged rail where each row carries
the `account` it came from. A chat target is resolved inside its own account's
mirror, so pass back the exact `account` a row reported before mutating it:

```bash
jq -nc --arg jid "$resolved_jid" --arg account "$row_account" --arg text "$message" \
  '{account:$account,jid:$jid,text:$text}' | "$oma" send
```

Never send to a JID resolved from a different account's rail.

The graphical account chips are a local view filter and never authorize a
target change. Account linking is interactive and must be explicitly requested:

```bash
"$oma" link-account NAME --authorize interactive
```

On a legacy single-account installation the existing root store stays
untouched and remains addressable as `primary` while the requested named
account is linked.
Never invent the account name or retry a canceled/uncertain QR flow.

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
| `voice` | `jid`, private OmaWhatsApp voice-draft `path`, optional `reply_id` |
| `poll` | `jid`, `question`, `options`, `multi` |
| `select` | `jid`, `id`, `index` |

The graphical client alone creates and finalizes private voice drafts. Agents
must not manufacture a draft path or record the microphone implicitly. For an
explicitly requested pre-existing audio file, use the guarded `wacli send
voice` operation with the exact `whatsapp-write` authorization described in
[wacli-parity.md](wacli-parity.md).

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

The supported setting keys are `send_read_receipts` (default `false`, per
account), `show_unread_count`, and `dropdown_rows` (`5`, `7`, or `9`). Change them only
when the user explicitly asks; for example:

```bash
printf '{"settings":{"send_read_receipts":false}}\n' | "$oma" settings
```

Dismiss the current notification batch without changing WhatsApp unread state:

```bash
printf '{}\n' | "$oma" acknowledge
```

An empty request clears the aggregated badge across every account. Pass
`{"account":"...","jid":"..."}` to acknowledge one exact chat. This is a local state
change, not a receipt, but still perform it only when requested.

Switch background sync only when requested:

```bash
printf '{"online":false}\n' | "$oma" sync-mode
printf '{"online":true}\n' | "$oma" sync-mode
```

Offline mode stops and disables that account's sync service while preserving
local reads. It blocks that account's WhatsApp mutations until the user returns
online, and leaves the other accounts alone.

## Desktop notifications

Inspect only the non-identifying notification state:

```bash
"$oma" status | jq '{notifications,notify_available}'
```

Change notifications only when the user explicitly asks:

```bash
printf '{"enabled":true,"preview":false}\n' | "$oma" notify-mode
printf '{"preview":true}\n' | "$oma" notify-mode
printf '{"enabled":false}\n' | "$oma" notify-mode
```

While notifications are enabled, future popups send the chat name and, in
multi-account setups, the account label to the desktop notification daemon;
the daemon may retain them in history. With previews enabled, sender names and
message text also cross that boundary. The resident app owns the `notify`
sweep; never invoke it as a test over a real archive. Use demo data or mocks
when testing notification behavior.

Account linking is interactive and must be explicitly requested:

```bash
"$oma" wacli --interactive --authorize interactive -- auth
```

Profile-photo refresh is a separate explicit remote read. It operates on a
bounded recent-chat batch, stores only private local cache paths, and must not
be used merely because a chat was opened or inspected:

```bash
printf '{"authorization":"remote-read","limit":12}\n' | "$oma" avatars
```

For calls, channels, contacts, group administration, history/backfill, media
recovery, poll voting, presence, profiles, accounts, status broadcasts,
exports, or store maintenance, use the complete classified gateway in
[wacli-parity.md](wacli-parity.md).
