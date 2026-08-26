# Multi-account scope map

Working document for adding multiple WhatsApp accounts to OmaWhatsApp, and for
landing the desktop-notification work that currently exists only on one
machine. It records what has to change, where, and in what order. It is not an
implementation.

## Starting position

wacli 0.17.1 already supports named accounts. `--account NAME` is a global flag
on every leaf, and `accounts add|list|remove|show|use` manage `config.yaml`.
Verified against 0.17.1 in a throwaway `XDG_STATE_HOME`:

```json
{"accounts": [{"name": "probe", "configured_store": "accounts/probe",
               "store_dir": "/…/wacli/accounts/probe", "default": true}],
 "config_path": "/…/wacli/config.yaml", "default_account": "probe"}
```

Three properties matter for this work:

- `accounts list` already resolves `store_dir` to an absolute path, so the
  helper reads store locations straight from it and never has to guess a layout
  or run `doctor` per account. The default layout is `<state>/wacli/accounts/<name>`.
- `configured_store` accepts `.`, which resolves to the root store. The account
  already linked on a machine can therefore be registered by name **without
  moving a single file**, which is the migration path this project should take.
- `--store` does not redirect the account config: `config_path` stays in the
  XDG state directory no matter what `--store` says. The two are parallel ways
  to pick a store, never a way to sandbox `config.yaml`.

One migration hazard follows from this: the first named account added becomes
`default_account`, so plain `wacli` commands stop pointing at the root store
the moment a second account is introduced. Registering the existing session as
a named account with `store: .` before adding any other account keeps the
current mirror addressable.

OmaWhatsApp assumes a single implicit account everywhere:

- `bin/omawhatsapp` builds `Backend` from one `STORE_DIR`, one `STATE_DIR`, one
  `wacli.db`, and never passes `--account` on the commands it runs itself.
- Local state under `~/.local/state/omawhatsapp/` is keyed by bare JID:
  `acknowledged_unread`, `sent-media.json`, and (with the notification patch)
  `notified`. The same contact or group reachable from two accounts collides on
  one key.
- `systemd/user/wacli-sync.service` is one unit for one store, and
  `set_online`, `_mutate`, `transport_interactive`, and `auth` all start and
  stop that fixed unit name.
- `Service.qml` watches one store directory with one `inotifywait`, keeps one
  `selectedChatJid`, and sends every helper payload without an account field.

### The unversioned notification patch

Desktop notifications exist on this machine only. They live in the installed
copies (`~/.local/bin/omawhatsapp`, `~/.config/omarchy/plugins/omawhatsapp/`,
manifest `0.7.0`) and were written against `47eaee6`, five commits behind
`main`. They were never committed and were never reinstalled after the
`b3948e9`/`1487456`/`70465c0`/`97ac672` work landed, so the machine is running
older code than the repository in every other respect.

What the patch adds: `NOTIFY_SEND` plus bounded `MAX_NOTIFY_*` limits, a
`notifications: {enabled, preview}` preference, a `notified` watermark map,
`notify` and `notify-mode` commands, markup-inert summary/body sanitising,
`last_sender` in the chat query, a `notify_available` field on `status`, a
`runNotify()` tick and `notifyProcess` in `Service.qml`, and a quiet/notify
pill in the `App.qml` header.

Porting it forward is prerequisite work, not part of multi-account: `main` has
since changed `_preferences` (`send_read_receipts`, `show_unread_count`,
`dropdown_rows`) and `status`, which is exactly where the patch touches.

## Decisions taken

- **Unified rail.** One merged chat list across all accounts, each row tagged
  with its account. The bar badge sums every account.
- **Notifications are independent of the badge.** A popup must still fire when
  `show_unread_count` is false, when the window and dropdown are closed, and
  when WhatsApp reports `unread = 0` but the chat timestamp advanced (read on
  the phone, or private reading).
- **Archived and muted keep suppressing.** No change to that filter.

## Scope by layer

### 1. Helper account resolution (`bin/omawhatsapp`)

- Introduce an account record (name, label, store dir, state namespace) and a
  resolver that reads `accounts list` once per request and fills each store dir
  from that account's `doctor`. The unnamed legacy account (no entry in
  `config.yaml`, default store) has to keep working as an implicit account, so
  the resolver returns it when the account list is empty.
- Thread the account through `_run`, `_mutate`, `_write`, `_doctor`,
  `_database`, and `_connect`. Today none of them can name an account.
- Every chat-scoped entry point gains an account argument and resolves its JID
  against that account's mirror: `_chat`, `_chat_any`, `messages`, `members`,
  `download_media`, `send`, `send_file`, `send_files`, `send_sticker`,
  `send_poll`, `react`, `edit_message`, `delete_message`, `forward_message`,
  `select_option`, `chat_action`, `paste`. This is the exact-chat boundary from
  `AGENTS.md`; resolving against the wrong store would silently widen it.
- `chats()` becomes N bounded queries plus an in-memory merge on
  `pinned DESC, timestamp DESC, name`, re-limited after the merge, with
  `account` and `account_label` on every row.
- `status()` returns a per-account array (authenticated, sync active, online,
  database ready, error) plus the aggregate the bar needs.

### 2. Helper local state

- Namespace `acknowledged_unread`, `notified`, and `sent-media.json` by
  account. `_media_hint_key` must include the account alongside JID and message
  ID.
- Split the preference set: `dropdown_rows` and `show_unread_count` stay
  global; `online` and `send_read_receipts` become per account, since `online`
  maps to a systemd unit that is now per account.
- Bump `PREFERENCES_VERSION` to 2 and migrate v1 in place, moving existing maps
  under the default account. The live file on this machine already carries 9
  acknowledgements and 500 watermarks, so a silent reset would replay or lose
  real state.

### 3. Background sync and the store lock

- Replace `wacli-sync.service` with a `wacli-sync@.service` template
  instantiated per account, with `ConditionPathExists` and `ReadWritePaths`
  derived from that account's store.
- `_sync_active`, `set_online`, `auth`, and the lock-contention fallback in
  `_mutate` must operate on one instance name. The fallback currently stops
  *the* sync unit; with several accounts it must stop only the unit that owns
  the contended store, or a send on one account interrupts sync on the others.
  `LOCK`, `HEARTBEAT`, and `.send.sock` are per store, so the contention itself
  stays per account.
- `scripts/install` installs and restarts the template, migrates an enabled
  legacy unit, and `scripts/uninstall` disables every instance. `scripts/test`
  greps for the literal `systemctl --user restart wacli-sync.service`, so that
  guard changes with the unit. Per `CLAUDE.md`, verify the unit with
  `systemd-analyze verify` before committing it.

### 4. Agent gateway (`transport`)

- `_transport_globals` and `transport_interactive` already accept and validate
  `--account` / `--store`, and `WACLI_OPERATION_POLICIES` already classifies
  `accounts add|list|remove|show|use`. No new authorization surface is needed.
- Latent bug to fix as part of this work: `_validate_transport_targets` calls
  `self._chat_any(...)` and therefore validates a `--to` JID against the
  default store even when the request names another account. Under one account
  it is invisible; under two it validates the wrong mirror.
- `transport_interactive` stops and restarts the fixed unit name around `auth`
  and `sync`; it must use the instance for the requested account.

### 5. QML surfaces

- `Service.qml`: chat rows carry `account`; the selection becomes an
  (account, JID) pair and every `runWrite` payload carries it; one store
  watcher per account (or one `inotifywait` over several paths) feeding the
  existing debounce; `notificationUnreadCount` already reduces over rows and
  aggregates for free.
- `Dropdown.qml` and `App.qml`: per-row account marker, optional per-account
  filter, account switcher in the header, and demo-mode fixtures with two
  accounts so the privacy-safe capture still represents the feature.
- `BarWidget.qml`: no structural change; badge and tooltip already derive from
  the aggregate.
- `IpcHandler.openApp` payload accepts an account so bindings can target one.

### 6. Notifications, ported and made per account

- Port the patch onto `main` first (conflicts expected in `_preferences` and
  `status`), commit it, reinstall, and only then extend it.
- `notified` moves under the account namespace, and seeding stays per account:
  adding a second account must not replay its entire archive as popups.
- One `notify` pass sweeps all accounts. `MAX_NOTIFY_BURST` stays a global cap
  with a single overflow summary, otherwise N accounts means N times five
  popups in one tick.
- The popup summary gains the account label when more than one account is
  configured, in both preview and names-only modes.
- The three decided behaviours need explicit tests, because two of them are
  properties of code that does not exist yet on `main`:
  - `unread = 0` with an advanced timestamp still notifies (already in the
    patch as `max(1, arrived) if unread > 0 else 1`),
  - `show_unread_count = false` hides the bar badge and does not suppress the
    popup,
  - a closed window and closed dropdown do not suppress; only the visible chat
    does, and that skip becomes an (account, JID) pair.
- `notify_available` stays global: it only reports whether `notify-send` exists.

### 7. Tests and docs

- `tests/test_backend.py` builds one temporary SQLite store. It needs a
  two-store fixture with a fake account config, covering: rail merge and
  ordering, isolation of an identical JID across accounts, `--account` present
  on each generated wacli command, the gateway exact-chat guard resolving in
  the right store, per-account notify behaviour, and the v1 to v2 preference
  migration.
- `scripts/check-wacli-parity` needs no change; parity already covers the
  `accounts` leaves.
- Update `docs/ARCHITECTURE.md` (lifetimes, data boundary), `docs/TECHNICAL.md`,
  `docs/PRIVACY.md` (per-account state), `docs/TESTING.md`, `README.md`, and
  `CHANGELOG.md`.

## Open questions and risks

- The systemd template still needs a real second account to confirm what
  `ReadWritePaths` should cover: every account store under one root, or one
  path per instance when an account points somewhere else entirely.
- Cost of N SQLite connections and N inotify watchers in the resident service,
  against the current single-store budget in `docs/ARCHITECTURE.md`.
- Machine and repository have diverged. Reinstalling `main` today would drop
  working notifications; committing the port is what makes the two agree again.

## Suggested sequence

0. Port and commit the notification patch onto `main`, with tests, then
   reinstall. Repository and machine agree again.
1. Helper-internal multi-account: resolver over `accounts list`, `--account` on
   every command, namespaced state, preference migration, and registering the
   existing session as a named account with `store: .`. No UI change.
2. Unit template, installer and uninstaller, per-account online mode.
3. QML unified rail, account marker, switcher, demo fixtures.
4. Per-account notifications: global burst cap, account label, (account, JID)
   skip.
5. Documentation, parity notes, changelog.
