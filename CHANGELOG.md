# Changelog

## 0.11.2 — 2026-08-31

- Make the aggregate notification count in the dropdown header actionable.
  Clearing it requires confirmation, dismisses only local notification badges,
  and never marks messages read or sends read receipts.
- Add an offscreen dropdown regression harness with shell-surface test doubles,
  covering cancel, confirm, and already-clear behavior without loading private
  chat data.
- Resolve [#7](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/issues/7),
  reported by [FoxesRCool1](https://github.com/FoxesRCool1).

## 0.11.1 — 2026-08-31

- Keep the last decoded GIF or video frame visible when another timeline
  player takes over. Fully hidden surfaces still stop and release media
  resources instead of retaining offscreen decoders.
- Press `R` or `r` while navigating messages to reply to the selected message
  and focus the composer. Modified shortcuts and active text fields remain
  untouched, so ordinary typing and shortcuts such as `Ctrl+R` do not get
  intercepted. Demo replies preserve their quoted-message preview, and the
  keyboard selection outline appears only while the timeline owns focus.

## 0.11.0 — 2026-08-30

- Add one-click `All`/per-account rail filters and a guarded in-app account
  linking flow. An existing unnamed session remains untouched and appears as
  `primary`, while every linked account keeps its own store and sync unit.
- Add explicit profile-photo refresh for a bounded recent-chat batch. Remote
  URLs stay behind the helper boundary; QML receives only owner-private,
  account-isolated local cache paths and ordinary browsing stays local-only.
- Turn a missing video's explicit download action into the same native player once its
  bytes arrive, with real decoded previews for locally available videos.
- Extend the isolated release harness with legacy-root, authorization,
  avatar privacy, remote-URL rejection, account-filter, and real-video
  transition regressions.
- Resolve reports [#3](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/issues/3)
  and [#5](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/issues/5), and
  improve the explicit-download path tracked in
  [#4](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/issues/4), reported by
  [FoxesRCool1](https://github.com/FoxesRCool1).

## 0.10.1 — 2026-08-30

- Bound every image, GIF, sticker, audio control, and video preview to its
  bubble; keep a poster before first play and the decoded frame while paused.
  One shared playback lease prevents the app, dropdown, and gallery from
  playing media over one another.
- Keep every deferred action attached to the exact account, chat, and message
  that created it. Chat switches can no longer redirect file-picker results,
  drafts, replies, forwarding, polls, receipts, or message actions—even when
  two accounts contain the same JID.
- Serialize and coalesce read acknowledgements independently of other helper
  work, without allowing an older completion to clear newer unread state.
- Make local state, clipboard previews, wacli parity, authorization flags,
  systemd lifecycle changes, and partial-delivery reporting fail closed at
  their boundaries. Interactive linking now restores only the exact account
  service it changed.
- Make install, upgrade, recovery, and uninstall durable transactions. A
  terminated run is recovered before the next operation, so users never keep
  a mixed helper/QML/service version.
- Exercise the media pipeline with generated MP4, GIF, and WebP fixtures and
  cover cross-account, deferred-intent, playback, lifecycle, and interrupted
  installation behavior without reading or sending real WhatsApp data.
- Preserve and build on the desktop-notification and multi-account work from
  [Leonardo Lucas de Castro Filho](https://github.com/LLawli) in
  [PR #1](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/pull/1).

## 0.10.0 — 2026-08-29

- Document the required upgrade path: after pulling a release, re-run
  `./scripts/install` so the QML, helper, skill, and user-service templates are
  upgraded together instead of mixing new UI code with an older helper.
- Merge desktop notifications and multi-account support contributed by
  [Leonardo Lucas de Castro Filho](https://github.com/LLawli) in
  [PR #1](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/pull/1).
- Make `J`/Down move visibly downward and `K`/Up move visibly upward through
  messages in both the full client and compact bar conversation.
- Preserve the newest-first, bottom-anchored timeline while adding bounded
  direction regressions for both conversation surfaces.
- Support every wacli account on the machine. The chat rail merges them into
  one list, each row named by the account it came from, and the bar badge sums
  them.
- Keep each account's world separate where it matters: a chat is resolved in
  its own mirror, every wacli command carries `--account`, and sending,
  receipts, drafts, forwarding, the badge, and offline mode all stay inside the
  account of the chat on screen. An account that has never synced is reported
  as unready beside the rail instead of emptying it.
- Key private state by store rather than by account name, so renaming an
  account keeps its history and the same contact reachable from two linked
  phones keeps two independent badges. Version 1 preferences migrate into the
  default account on first read.
- Run one `wacli-sync@<account>.service` instance per account, asking the
  helper whether that account has a linked session. A machine that never named
  an account keeps the original unit and pays for no extra work.
- Sweep every account in one notification pass, under one shared burst cap,
  naming the account in the popup when more than one is linked.
- Fix the agent gateway's exact-chat guard, which validated a `--to` JID
  against the default store even when the request named another account.
- Add optional desktop notifications: one bounded popup per chat that gained
  incoming messages, delivered through `notify-send` and off by default.
  The header pill toggles quiet/notify on left click and drops the message
  preview on right click.
- Keep popups independent of the bar badge. A chat WhatsApp reports as read
  elsewhere still notifies when its timestamp advances, hiding the badge with
  the unread-count preference does not silence anything, and a closed window
  and dropdown suppress nothing. Only the chat currently on screen is skipped.
- Adopt the existing archive when notifications are switched on, and seed the
  watermark on first run, so enabling the feature never replays history.
- Keep muted and archived chats silent, cap a burst at five popups plus one
  summary, and render every chat name, sender, and preview as a single
  markup-inert line.

## 0.9.1 — 2026-08-29

- Balance message-bubble spacing by applying the existing theme margin above
  the content as well as below it, preserving compact natural-width bubbles
  and clean wrapping at narrow sizes.
- Add an offscreen layout regression that verifies the bubble keeps equal top
  and bottom breathing room.

## 0.9.0 — 2026-08-28

- Add native OGG/Opus voice-note recording to the full client and compact bar
  conversation, with `Ctrl+Shift+V` as the shared start/stop shortcut.
- Stop into a WhatsApp-style review draft: preview playback, elapsed time,
  explicit discard, and explicit send. Stopping never sends automatically.
- Keep one resident recorder across both surfaces, release the microphone
  before review, bind the draft to its original exact chat/reply, and stop
  safely when its surface closes or the user switches conversations.
- Create recordings only inside an owner-private directory, validate the final
  bytes as OGG/Opus, retain failed sends for retry, and delete a draft only
  after wacli confirms delivery.
- Cover the lifecycle with backend boundary tests and an offscreen state-model
  suite without opening a microphone or creating a WhatsApp test message.

## 0.8.3 — 2026-08-28

- Show only each participant's latest reaction on a message, so changing an
  emoji replaces the old one and removing a reaction clears it.
- Keep reactions from different participants independently countable, with
  backend regressions for changes and removals.

## 0.8.2 — 2026-08-26

- Press `/` from the full-app chat list to focus chat search immediately;
  Escape returns to the J/K navigation layer.
- Keep slash inert while typing and outside the chat-list context, with an
  offscreen keyboard regression test for the complete transition.

## 0.8.1 — 2026-08-26

- Use the same crisp, theme-native WhatsApp mark in the bar, compact client,
  and full app instead of mixing the brand mark with a generic group glyph.
- Guard the three branded surfaces in the release test so their identity stays
  visually consistent across future UI work.

## 0.8.0 — 2026-08-26

- Replace the bar item's full-window launch with a compact, bar-anchored mini
  client backed by the already-resident local service.
- Add unread badges, local chat search, online/offline state, configurable
  5/7/9-row density, refresh, outside-click dismissal, and J/K, arrow, `/`,
  Enter, Escape, and `O` keyboard flows.
- Read recent messages and send text, replies, reactions, clipboard text, and
  staged clipboard files directly from the dropdown; `O` expands the exact
  chat into the full client with its composer focused.
- Add a theme-native settings card for private reading/read receipts,
  background sync, bar badge visibility, and 5/7/9-chat dropdown density.
  Private reading remains the default; opting in is explicit and persisted in
  the mode-0600 local preferences file.
- Move full-window ownership into the single resident service so bar clicks
  cannot race Omarchy's generic panel loader. `Super+Shift+W` remains the
  direct full-client toggle.
- Make the receipt boundary regression-tested: private reading can never
  auto-write, offline/busy states suppress opted-in receipts, opening the
  already-warm conversation honors an enabled receipt preference, and demo
  windows never refresh or acknowledge the real account.
- Install into Omarchy's canonical manifest-id directory and remove the old
  short-name directory, preventing a stale marketplace copy from winning a
  duplicate-id scan after shell restart.

## 0.7.0 — 2026-08-26

- Give the shared `$omawhatsapp` skill guarded parity with all 103 command
  leaves in wacli 0.17.1: calls, channels, contacts, group administration,
  history, media recovery, polls, presence, profiles, accounts, status,
  synchronization, exports, and store maintenance now share one bounded JSON
  gateway.
- Classify every advanced operation as local read, remote read, local write,
  sync, WhatsApp write, destructive, or interactive. Unknown future commands
  fail closed, local reads force `--read-only`, offline mode blocks network
  work, and mutations require an exact current-request authorization token.
- Add a terminal-preserving path for interactive account linking and
  foreground sync without replacing the resident wacli service.
- Make Enter from the keyboard-selected chat list open that conversation with
  the composer focused immediately; the next keypress now types the message.
- Add twelve backend parity/escape-boundary tests and one keyboard-transition
  test, including an end-to-end fake-wacli invocation with no live mutations.

## 0.6.1 — 2026-08-24

- Stream wacli, systemctl, and clipboard output under hard byte caps instead
  of capturing unbounded child output before validation.
- Read, lock, and atomically replace helper state through descriptor-bound,
  owner-checked, no-follow file operations.
- Force every QML `Text` surface to plain-text mode so chat, sender, button,
  filename, and error strings can never trigger Qt rich-text interpretation.
- Expand the fixture suite with subprocess-cap, symlink-refusal, and QML
  plain-text invariants.

## 0.6.0 — 2026-08-24

- Ship a shared `omawhatsapp` agent skill that lets compatible on-device
  agents search the local archive and perform clearly requested WhatsApp
  actions through the same exact-chat helper boundary as the UI.
- Install the skill under `~/.agents/skills/omawhatsapp` for cross-agent
  discovery, remove it on uninstall, and validate its safety contract during
  installation preflight.

## 0.5.0 — 2026-08-24

- Add a persistent online/offline toggle: offline mode disables and stops
  background sync while keeping the read-only local archive fully available.
- Split notification acknowledgement from WhatsApp read state. Opening a chat
  or middle-clicking the bar clears only OmaWhatsApp's local new-message badge;
  new arrivals reappear, while actual unread counts remain intact.
- Make read receipts an explicit chat-menu action labelled
  `Mark read · send receipt`; OmaWhatsApp emits no desktop message popups by
  default, and its in-app confirmations auto-dismiss.
- Adopt the permanent marketplace ID
  `io.github.moizibnyousaf.omawhatsapp` and migrate existing shell entries
  automatically during installation.
- Remove private-extension references and prepare one privacy-audited public
  source snapshot for marketplace submission.

## 0.4.0 — 2026-08-24

- Focus the chat rail on direct messages and standalone groups; channels,
  calls, Communities, and Community-linked subgroups are intentionally hidden.
- Add native mentions, selection-to-copy, compact message bubbles, responsive
  rail collapse, album sending, rich media, and the native media viewer.
- Add a versioned install preflight and a hardened background sync service;
  upgrades now restart that service so a changed unit
  takes effect immediately.
- Refresh the repository presentation with a release preview, responsive demo
  gallery, and public-facing metadata.

## 0.3.0 — 2026-08-24

### Added

- Native full-window image/GIF/video viewer with zoom, fit, gallery navigation,
  playback, metadata, and external-open controls.
- Optional Omasnap handoff for annotating an open image, with a system-viewer
  fallback for other media and installations.
- Multi-file review queue, drag/drop, staged clipboard images/files, caption,
  sticker picker, poll composer, and per-chat attachment drafts.
- Reply, reaction, edit, delete, forward, interactive-option, and copy actions.
- Keyboard-first real group mentions backed by the locally indexed participant
  list, plus drag-selection auto-copy with a confirmation toast.
- `Ctrl+1` through `Ctrl+9` instant chat jumps that follow the visible/search
  order and enter the conversation in single-pane mode.
- `Ctrl+B` chat-rail focus mode with an animated, state-preserving collapse.
- Multi-photo sends retain one private batch identity and render as a single
  responsive album while preserving each real WhatsApp message ID.
- Metric-driven text bubbles that hug short messages while reserving exactly
  enough room for sender and delivery metadata, then wrap at a responsive max.
- Quote, reaction, forwarded, edited, starred, location, poll/button, and typed
  media rendering.
- 360 px single-pane, narrow, compact, and wide responsive modes.
- Configurable unread bar item in a combined service/panel/bar plugin.
- Offscreen QML tests, an uninstall path, and release docs.

### Reliability

- Restrict chat discovery to direct messages and standalone groups; channels,
  calls, Community parents, and linked Community subgroups remain out of scope.
- Collapse all chat previews to one line before QML rendering so feed-style
  content cannot bleed across neighboring rows.
- Stage the complete installed plugin before one shell stop/restart, avoiding
  watched-directory partial reloads.
- Move file picking out of the Quickshell process so picker/portal failures
  cannot crash the desktop shell.
- Keep writes scoped to an indexed chat/message and preserve background sync
  across every fallback path.
- Reconcile successful outgoing uploads to their original local path so sent
  photos and GIFs preview immediately instead of flashing a download card.

## 0.2.0 — 2026-08-23

- Added typed local media rendering and verified on-demand media download.

## 0.1.0 — 2026-08-23

- Added the resident service, all-chat rail, local conversation view, bar item,
  background wacli sync, and `Super+Shift+W` launch flow.
