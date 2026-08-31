# Guarded wacli parity

Use this reference for capabilities outside the focused chat helper: calls,
channels, contacts, group administration, history, media recovery, polls,
presence, profiles, accounts, status broadcasts, sync, exports, and store
maintenance.

## Discover the installed surface

The helper's registry is the machine-readable source of truth:

```bash
oma="$HOME/.local/bin/omawhatsapp"
"$oma" capabilities
```

It accounts for every command leaf in exactly wacli 0.17.1. Before an
advanced operation, inspect its flags without changing state:

```bash
wacli <command> <subcommand> --help
```

Unknown future command leaves fail closed until OmaWhatsApp classifies them.

## Non-interactive contract

Send one JSON object to `omawhatsapp wacli`:

```json
{
  "args": ["messages", "starred", "--limit", "50"],
  "authorization": "",
  "private_export_authorization": "",
  "repository_export_authorization": "",
  "external_stream_authorization": "",
  "account": "",
  "store": "",
  "timeout": 300,
  "lock_wait": "5s",
  "events": false,
  "full": false,
  "max_output_bytes": 1048576
}
```

Build it with `jq`; user text, filenames, JIDs, phone numbers, invite codes,
URLs, and secrets are data, never shell source:

```bash
jq -nc --argjson args '["messages","starred","--limit","50"]' \
  '{args:$args}' | "$oma" wacli
```

Pass `--account`, `--store`, `--timeout`, `--lock-wait`, `--events`, and
`--full` through the matching JSON fields, not inside `args`. Never pass
`--read-only` or `--json`; OmaWhatsApp adds JSON output and read-only
enforcement itself. Prefer a named `account`; a one-off `store` must be an
absolute path inside the user's home directory.

The response reports `ok`, `operation`, `policy`, and `data`. It deliberately
does not echo the argument array, because arguments may contain private data.

## Authorization classes

`local-read` needs an empty authorization string and runs with wacli's
`--read-only` guard. Every other primary policy requires an exact token in the
JSON `authorization` field; external streaming uses the additional field
described below:

| Policy | Token | Meaning |
|---|---|---|
| `local-read` | `""` | Inspect local metadata/history without writing |
| `remote-read` | `"remote-read"` | Query WhatsApp live and possibly refresh local metadata |
| `local-write` | `"local-write"` | Change only local aliases/config/store metadata |
| `private-export` | `"private-export:<exact-absolute-output-path>"` | Write a private message export to that one local file |
| `external-stream` | `"external-stream:<exact-destination>"` | Emit private lifecycle/events to `response` or one exact webhook URL |
| `sync` | `"sync"` | Download/synchronize history or media |
| `whatsapp-write` | `"whatsapp-write"` | Send or change visible WhatsApp state |
| `destructive` | `"destructive"` | Delete, leave, revoke, remove, reject, or invalidate state |
| `interactive` | CLI flag | Link an account in a terminal |

`private-export` replaces `local-write` for `messages export --output`.
`media download --output` keeps `authorization:"sync"` and additionally needs
`private_export_authorization:"private-export:<exact-output-path>"`.
`external-stream` is an additional gate: keep the operation's ordinary token
in `authorization` and put the destination-bound token in
`external_stream_authorization`. Use `external-stream:response` for
`events:true`. If a request deliberately enables both response events and a
webhook, supply both exact stream tokens as an array.

Never supply a token merely to make a command pass. The current user request
must clearly authorize the exact operation, target, content, and scope. A
request to inspect data does not authorize `remote-read`; a request to sync
does not authorize a send; a request to send does not authorize a status
broadcast or group/profile/account mutation.

Examples:

```bash
# Local read: no token.
jq -nc '{args:["calls","list","--limit","20"]}' | "$oma" wacli

# Live metadata refresh: only after the user requests the live lookup.
jq -nc '{args:["groups","info","--jid","EXACT_GROUP_JID"],
  authorization:"remote-read"}' | "$oma" wacli

# WhatsApp mutation: only after the user requests this exact vote.
jq -nc '{args:["poll","vote","--to","EXACT_CHAT_JID","--id","EXACT_ID",
  "--option","Yes"],authorization:"whatsapp-write"}' | "$oma" wacli
```

Dry runs for `history fill`, `messages purge`, and `store cleanup` are
automatically downgraded to `local-read`. `messages export --output` requires
the destination-bearing `private-export` token. Export paths inside a Git
repository are rejected unless the request also supplies
`repository_export_authorization:"allow-repository-export:<exact-path>"`;
prefer a private non-repository directory. `doctor --connect` is
`remote-read`.

## Interactive linking and foreground sync

Interactive mode inherits the terminal so QR/progress output remains visible.
Use it only when the user explicitly requests linking or a foreground sync:

```bash
"$oma" wacli --interactive --authorize interactive -- auth
"$oma" wacli --interactive --authorize interactive -- accounts add NAME
"$oma" wacli --interactive --authorize sync -- sync --once
```

The helper pauses the resident default sync service when necessary and
restores it afterward. It never overrides OmaWhatsApp's explicit offline mode.

## High-impact boundaries

- Resolve existing chat/group/channel/message targets to exact identifiers
  before mutation. Never use `--pick` to guess an ambiguous result.
- Treat mark-read as a receipt and presence as visible activity.
- Status broadcasts, profile changes, group/channel membership and admin
  changes, logout, account removal, revoke/delete/purge, and cleanup require
  exact current authorization and no automatic retry.
- `sync --webhook` requires both `authorization:"sync"` and
  `external_stream_authorization:"external-stream:<exact-webhook-url>"`.
  Use it only when the user explicitly supplies and authorizes that
  destination; never expose webhook secrets in output or durable logs.
- Exports and downloaded media remain private local data. Do not place output
  under a repository or shared directory unless explicitly requested.
