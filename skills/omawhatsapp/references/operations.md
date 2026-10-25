# Focused OmaWhatsApp operations

All commands use the installed helper and emit one JSON object. Keep private
values on stdin for the entire pipeline, including JSON construction. In Bash,
define this function once; its arguments stay inside the shell, and the Bash
`printf` builtin sends them to `jq` over a pipe:

```bash
set +x
set +a
set -o pipefail
oma="$HOME/.local/bin/omawhatsapp"
oma_request() {
  builtin printf '%s\0' "$@" | jq -Rsc '
    split("\u0000")[:-1] |
    if length % 2 != 0 then error("expected key/value pairs")
    else . as $values |
      reduce range(0; length; 2) as $i ({}; .[$values[$i]] = $values[$i + 1])
    end'
}
```

Run these examples in that same Bash session. Keep private values in
non-exported shell variables populated from stdin or helper results. Never
interpolate them into `bash -c`/`python -c` source, `jq --arg`/`--argjson`,
external `printf` arguments, environment variables, temporary files, shell
history, or tracing output. `set +a` prevents new variables from being
automatically exported; it does not unexport existing ones. If an existing
variable was exported, use Bash's `export -n variable_name` before assigning
private content. JSON arrays below travel as strings over stdin and are parsed
by a fixed `jq` filter, never supplied as process arguments.

## Accounts

Every request may carry `account`, naming one configured wacli account. An
empty or absent value means the default account. `status` reports the
configured accounts, and `chats` returns one merged rail where each row carries
the `account` it came from. A chat target is resolved inside its own account's
mirror, so pass back the exact `account` a row reported before mutating it:

```bash
oma_request jid "$resolved_jid" account "$row_account" text "$message" \
  | "$oma" send
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
oma_request query "$requested_name" \
  | "$oma" chats --limit 500
```

Read or search one exact conversation:

```bash
oma_request jid "$resolved_jid" query "$requested_query" \
  | "$oma" messages --limit 240
```

Group members/mention candidates:

```bash
oma_request jid "$resolved_jid" | "$oma" members
```

## External WhatsApp mutations

These require a clearly authorized current request and online mode.

Send text (optional reply ID and verified mention JIDs):

```bash
oma_request jid "$resolved_jid" text "$message" \
  reply_id "$reply_id" mentions "$mention_jids_json" \
  | jq '.mentions |= fromjson' \
  | "$oma" send
```

Send local files; use absolute paths or `file://` URLs, at most 10:

```bash
oma_request jid "$resolved_jid" caption "$caption" paths "$local_paths_json" \
  | jq '.paths |= fromjson' | "$oma" files
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
oma_request jid "$resolved_jid" action "$action" | "$oma" chat-action
```

Allowed actions are `read`, `unread`, `pin`, `unpin`, `archive`, `unarchive`,
`mute`, `unmute`, and `remove-local` (`remove-local` purges the chat and its
messages from local storage without modifying WhatsApp servers). `read` and
`unread` change the chat's read state on the user's own devices through
WhatsApp app state; no read receipt reaches the sender. Local inspection never
calls them.

## Local app state

Inspect private app settings without changing them:

`check_updates_on_launch` is a global Boolean preference, off by default.
Changing it needs permission for a local preference write. Release checks
contact GitHub, never WhatsApp, and do not install software. Application
upgrades are a separate repository/deployment task, not a WhatsApp operation.

```bash
printf '{}\n' | "$oma" settings
```

The supported setting keys are `send_read_receipts` (mark the open chat read;
per account), `sender_read_receipts` (request sender-facing receipts on every
mark-read; default `false`, per account, requires wacli 0.19.0+), `read_on_reply`,
`enter_sends`, `show_avatars`, `auto_refresh_avatars`, `rail_density`
(`comfortable` or `compact`), `show_unread_count`, `dropdown_rows` (`5`, `7`, or `9`), and
`composer_max_lines` (`4`, `6`, `8`, or `10`, default `6`), and `time_format`
(`auto`, `12h`, or `24h`, default `auto`). Time format is global; `auto` follows
the system locale in chat previews, messages, and the media viewer. Change them only
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

The global `shortcuts` setting is a map of known keyboard action IDs to lists
of up to three canonical key strings (for example `{"find":["Ctrl+Alt+F"]}`).
An omitted action inherits its default; `[]` disables it; `{}` restores the
entire default map. When an omitted action's default would take a key already
saved for another action, the helper reports it as `[]`, so the saved binding
keeps working; send the map back as reported. The helper rejects invalid keys,
unknown actions and context conflicts. This is a local preference write; it
does not change the Hyprland launcher binding or perform any WhatsApp
operation. Prefer the Settings → Shortcuts editor for interactive capture and
conflict feedback.

## Account-name clipboard

`omawhatsapp paste-account-name` is a local clipboard read, only for an explicit
paste request. It reads at most 256 bytes within three seconds and returns only
a valid ASCII account identifier (1–64 characters). It does not select an
account, recover services, link a device, or send anything to WhatsApp. Never
invoke it to inspect the clipboard without a user request.

`prepare-inputs` is a local preparation command used by the GUI. It compiles
the bundled native input module into the private cache for the installed Qt,
without downloading code, inspecting accounts, or contacting WhatsApp.
