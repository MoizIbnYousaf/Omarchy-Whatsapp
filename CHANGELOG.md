# Changelog

## [0.16.0](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/compare/v0.15.0...v0.16.0) (2026-10-03)


### ⚠ BREAKING CHANGES

* scripts/install and scripts/uninstall are gone. Install with `omarchy plugin add https://github.com/atoslins/Omarchy-WhatsApp-v2 --enable`. An install made by the old script moves to links on its own after `omarchy plugin remove io.github.atoslins.whatsapp` and a new `omarchy plugin add`.
* the plugin ID is now io.github.atoslins.whatsapp. Keybindings and scripts that call omarchy-shell with io.github.moizibnyousaf.omawhatsapp must use the new ID.

### Features

* add draft-first voice notes ([f652975](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/f6529753b574af5e9bf33b4f05227fefe1136402))
* add guarded wacli parity ([2544736](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/2544736e3ea1f5ecb8436fb15391587ca5acbb8f))
* add interactive bar client and private reading ([b3948e9](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/b3948e991b9dff72d9dd360d2e07f1e1046e2409))
* add layered keyboard navigation ([47eaee6](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/47eaee6a2ec09880e755f8edba44c2bed74d598e))
* add local chat removal action and confirmation dialog ([e5d65ba](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/e5d65ba33a5d3edeaa9d875f7a7ba936509ee46a))
* add opt-in desktop notifications ([85f0d2c](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/85f0d2cd86598a7036269fd18175be8b5b7c14eb))
* add slash search from chat list ([83f4c4a](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/83f4c4a35498b36a64adf613749765d4084b30b6))
* add system and 12/24-hour timestamp settings ([66ac5dc](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/66ac5dcc15cfd6aadcb87d598484e16b8acc8302))
* add toggleDropdown IPC for speakercorners hot-corner toggle ([866010f](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/866010f6c2db4127a1996b3398869e9f80b0502a))
* add toggleDropdown IPC for speakercorners hot-corner toggle ([650f570](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/650f5708aa018189098a1f11b9703e2b62b2cdef))
* expand chat composer upward with configurable max lines and scroll tracking ([4280f9c](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/4280f9cd2b15843a8a9fe180930c755bb7a05d11))
* install with omarchy plugin add ([74b1763](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/74b1763e0e8f71cde80ffc8b878ecd109eb22831))
* integrate expanded messaging, UI, setup and agent capabilities ([29de22c](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/29de22cb39b40766c4913a6145d9293f655e7198))
* read and write every configured wacli account ([b3c041b](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/b3c041b5bf411cf055a575d1eec33e95ea271d41))
* refresh chats from local store changes ([680b7c8](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/680b7c8241e6381efa843c3be7ab94fb2c8f7d7a))
* rename the plugin to WhatsApp for Omarchy ([f4250fe](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/f4250fe6503f3ad369f368c3ffe2ee4d26a3e4b9))
* reply to keyboard-selected message ([cea7ef1](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/cea7ef118bec719f0c3e8b91cdac68ffbfa47d6c))
* run one sync instance per account ([22db7da](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/22db7da8d81652189c890594489c77d9bb71da11))
* show one rail across accounts ([2abdf23](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/2abdf23b45bf2d341e43bc1bb70f2974bce795da))


### Fixes

* accept machines with no wacli-sync@ unit files ([147efbe](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/147efbe48937c319fe6805caf232834e96deaa8c))
* add top padding to message bubbles ([93f317c](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/93f317c0f0f5013701e83d3af03902e0539760a4))
* add top padding to message bubbles ([393bb3a](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/393bb3a253fcc239bb36928fa3dbfc5004dab22a))
* **app:** show the chat photo in the conversation header ([ad005db](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/ad005dbb39a8db9be3de1ea4421e6101a19aaf38))
* **ci:** copy only regular files when simulating plugin add ([a4d01ee](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/a4d01eec558ef1518861eae09eb0d8459d8a514e))
* harden external data boundaries ([c30b1b9](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/c30b1b9524a75ff6fdc1b3f62ca428023d214d95))
* install plugin under canonical id ([70465c0](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/70465c0bc3f883aee4901794ed69dd85c309c740))
* **install:** accept machines with no wacli-sync@ unit files ([7e63cdb](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/7e63cdb0910e214df58363c9fa7fb9a3eb780102))
* keep composer cursor and saved preferences in sync ([cd238b7](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/cd238b7663e6bf8b80629c18c6a5d8154e1f4665))
* keep managed installations coherent and prepare 0.15.0 ([c966492](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/c9664924745468712b87080344b244fbc15f94cf))
* make read receipt preference exact ([1487456](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/1487456877d91767f7a309c8e1d34d83a4d73700))
* preserve demo selection after local chat removal ([d549d71](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/d549d71304a289ea3b53270c52e6f51bc7c8ae98))
* preserve paused media previews ([353419f](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/353419fed37a69fb4879a68adc6da3380bcfa9f1))
* report sync state for the selected account ([45c3889](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/45c38894eefeef8b9d86161cc57f2cbdb300e901))
* respect composer line limits and credit contributed features ([33f415f](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/33f415fc4b0f12ea343e5ee579d94bdc11e89104))
* **setup:** an older repository commit is not an update ([fa93c3b](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/fa93c3b005c1e257132453d3e09033ef8d405970))
* **setup:** change only the files the app wrote, exactly as it wrote them ([b054af1](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/b054af1059ce1405a658eead3b64c6cd505d44bf))
* **setup:** keep agent access off until the user turns it on ([6713871](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/6713871b4d09c6b42d9a2122237914990b8e80c5))
* **setup:** never replace a path that belongs to something else ([25f4c8e](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/25f4c8ecd75b0e2aff20c2e72b8e8258c013f302))
* **setup:** recognize an earlier copy only by its exact shipped content ([a4c6784](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/a4c67844191c51bf7e59f77dbbe060200c22687a))
* show only current message reactions ([59fdffe](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/59fdffe37d87ec5e1a1c7feead9e953c3eaa164b))
* show the chat photo in the conversation header ([30eae4a](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/30eae4ae9d794ab42f94e14047ddc876402d5b3b))
* stop SQLite WAL refresh feedback loop (v0.13.1) ([7ee1540](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/7ee1540f01d4f7fb698d683577fecd57063a9204))
* unify WhatsApp brand mark ([97ac672](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/97ac6725d2c8aeecc319a76629d8063902b201ca))
* wait for the store lock instead of restarting ([647d7f0](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/647d7f0f401178ef247f569a96e5ed5f95c8abc2))


### Documentation

* add copyable agent install prompt ([f4294a7](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/f4294a7510d94553acdbc2ac0d5703ab8159af8f))
* document installing with omarchy plugin add ([3008359](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/300835940f2e9abeb79001c4c94d19d7a75c8d65))
* document remove-local action in parity map and skill reference ([3194dbd](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/3194dbd4e64264a5189d762a2a7f16e8ad0ccbb1))
* document the complete upgrade path ([14f7e18](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/14f7e18049722117d6486c2b73dc95b8447f0cf5))
* explain why OmaWhatsApp exists ([d67d9dc](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/d67d9dc2b34a12050a1408f7da0a5ea8aaf6f06b))
* map the multi-account scope ([c280e2d](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/c280e2d77fe703742cbe9eab5e06eafd13a30164))
* new README, usage guide, screenshots and store banner ([0dd8c18](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/0dd8c18dcf8b154c056cae84b2438a43214ab5f3))
* record the two-account run and what it found ([4470a90](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/4470a909b6fac4b86a386b524055dffe5e049775))
* remove benchmark machinery ([23bb7a1](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/23bb7a1f2dcda9ef987419e1224b58e24e040702))
* say that the installer needs no sudo in the form the store scan reads ([70ff93f](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/70ff93f23f99833ae2c06ed4e965f1ddc8edee92))
* **skill:** harden privacy-safe agent routing ([9928289](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/commit/9928289e11de375c39f8ba73049b338ae6e7d57d))

## 0.15.0 (2026-10-03)

- Add forwarding, message selection, favorites, emoji and text formatting.
- Add contact/group details, group administration, new-chat search and onboarding.
- Add media browsing, older-message pagination, audio controls and pending-send queues.
- Improve notification routing, chat filters, unread counts, delivery ticks and optional presence.
- Add opt-in agent setup and an MCP server backed by the guarded helper.
- Harden setup ownership checks, teardown and sync locking; support wacli 0.17.1–0.19.0.
- Deploy the complete app through My Plugins so UI and helper cannot drift apart.
- Preserve existing notification and private-reading choices during upgrades.
- Validate every shipped QML/JavaScript component and test multi-account preference migrations.


## 0.14.0 — 2026-09-16

- Add `toggleDropdown` IPC for hot corners and keybindings, contributed by
  nagualcode (@ffloress) in PR #14. Existing open-only IPC remains available.
- Fix fresh installs and uninstall when no sync instance unit files exist,
  while still rejecting service-manager discovery failures (PR #15).
  Resolves #17, reported by Josh Biddick (@sadsa).
- Show the selected chat’s cached photo, initials, or group icon in the full
  app conversation header, with account-specific identity (PR #16).
- Thanks to Guilherme Casimiro (@gocasimiro) for the installer and avatar fixes
  and their regression coverage. Add toggle and discovery-failure regressions.

## 0.13.1 — 2026-09-08

- Stop a background refresh loop caused by SQLite closing write-open WAL
  sidecars after read-only queries. Watch actual database changes instead.
- Preserve prompt chat updates for committed WAL writes, checkpoints, database
  replacement/removal, and rollback-journal commits. Keep the existing
  debounce, per-account watchers, and periodic refresh fallback.
- Add regression coverage for repeated write/read cycles and reading while
  sync has no persistent database writer. No changes to WhatsApp permissions,
  receipts, or sending behavior.

## 0.13.0 — 2026-09-08

- Add a saved **System / 12-hour / 24-hour** timestamp preference across chat
  previews, message bubbles, and the media viewer. System follows the locale
  by default. Requested by [Henning Weiss (@hdweiss)](https://github.com/hdweiss)
  in [#10](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/issues/10).
- Add a confirmed **Remove local chat** action that deletes a conversation
  from the local mirror, including while offline, without deleting it from
  WhatsApp's servers ([PR #11](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/pull/11)).
- Expand the message composer in the full app and bar dropdown, with a
  configurable line limit and scrolling for longer drafts
  ([PR #12](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp/pull/12)).
- Local chat removal and the expanding composer were contributed by
  [Pedro Barbosa (@petebarbosa)](https://github.com/petebarbosa).
- Harden the reviewed changes: keep the cursor visible after the composer
  shrinks, preserve saved preference updates, and handle demo chat removal
  across accounts and an empty chat list.

## 0.12.0 — 2026-09-05

- Move chat-photo refresh from the account rail into settings, keeping its
  progress/error feedback and explicit remote-read action (#8).
- Add manual update checks and an opt-in check when opening the full app.
  Checks contact GitHub only, stay off in demo/offline mode, and never install
  automatically (#9). A newer release is announced with a settings prompt.
- Standalone installs made with this version can launch a confirmation terminal
  and upgrade the complete app through the existing transactional installer.
  Downloads are commit-pinned, bounded, and reject redirects and unsafe archive
  paths. Managed and older installations retain their existing upgrade route.
- Thanks to FoxesRCool1 for both suggestions.
- Fix demo image references to use the bundled PNG in timeline and viewer.

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
