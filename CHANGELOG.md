# Changelog

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
