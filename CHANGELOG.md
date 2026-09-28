# Changelog

## [0.16.4](https://github.com/atoslins/Omarchy-WhatsApp-v2/compare/v0.16.3...v0.16.4) (2026-09-28)


### Fixes

* **setup:** keep agent access off until the user turns it on ([6713871](https://github.com/atoslins/Omarchy-WhatsApp-v2/commit/6713871b4d09c6b42d9a2122237914990b8e80c5))

## [0.16.3](https://github.com/atoslins/Omarchy-WhatsApp-v2/compare/v0.16.2...v0.16.3) (2026-09-28)


### Fixes

* **setup:** recognize an earlier copy only by its exact shipped content ([a4c6784](https://github.com/atoslins/Omarchy-WhatsApp-v2/commit/a4c67844191c51bf7e59f77dbbe060200c22687a))

## [0.16.2](https://github.com/atoslins/Omarchy-WhatsApp-v2/compare/v0.16.1...v0.16.2) (2026-09-27)


### Fixes

* **setup:** change only the files the app wrote, exactly as it wrote them ([b054af1](https://github.com/atoslins/Omarchy-WhatsApp-v2/commit/b054af1059ce1405a658eead3b64c6cd505d44bf))

## [0.16.1](https://github.com/atoslins/Omarchy-WhatsApp-v2/compare/v0.16.0...v0.16.1) (2026-09-27)


### Fixes

* **setup:** never replace a path that belongs to something else ([25f4c8e](https://github.com/atoslins/Omarchy-WhatsApp-v2/commit/25f4c8ecd75b0e2aff20c2e72b8e8258c013f302))

## [0.16.0](https://github.com/atoslins/Omarchy-WhatsApp-v2/compare/v0.15.0...v0.16.0) (2026-09-26)


### ⚠ BREAKING CHANGES

* scripts/install and scripts/uninstall are gone. Install with `omarchy plugin add https://github.com/atoslins/Omarchy-WhatsApp-v2 --enable`. An install made by the old script moves to links on its own after `omarchy plugin remove io.github.atoslins.whatsapp` and a new `omarchy plugin add`.

### Features

* install with omarchy plugin add ([74b1763](https://github.com/atoslins/Omarchy-WhatsApp-v2/commit/74b1763e0e8f71cde80ffc8b878ecd109eb22831))


### Fixes

* **ci:** copy only regular files when simulating plugin add ([a4d01ee](https://github.com/atoslins/Omarchy-WhatsApp-v2/commit/a4d01eec558ef1518861eae09eb0d8459d8a514e))
* **setup:** an older repository commit is not an update ([fa93c3b](https://github.com/atoslins/Omarchy-WhatsApp-v2/commit/fa93c3b005c1e257132453d3e09033ef8d405970))


### Documentation

* document installing with omarchy plugin add ([3008359](https://github.com/atoslins/Omarchy-WhatsApp-v2/commit/300835940f2e9abeb79001c4c94d19d7a75c8d65))

## 0.15.0 — WhatsApp for Omarchy — 2026-09-26

The first release under its own name. It started as a fork of OmaWhatsApp
0.14.0 and keeps its foundations: the resident service, the bar dropdown, the
helper boundary and the installer.

### Highlights

- **New identity.** WhatsApp for Omarchy, plugin ID
  `io.github.atoslins.whatsapp`. Installing over OmaWhatsApp takes its place
  in the bar and keeps the helper, services, linked device and history;
  keybindings that call the old ID are listed at the end of the install.
- **Follows current wacli.** Accepts 0.17.1 or newer and is tested with
  0.17.1, 0.18.3 and 0.19.0; newer wacli features turn on by themselves.
- **Restyled interface.** Chat bubbles, attachments, the chat list (comfortable
  or compact) and the bar dropdown, with a color per person and per account.
- **Sending that never waits.** Messages appear at once and stay as a bubble
  with Retry if they fail; replies no longer queue behind read marks.
- **Forward, delete and star in bulk.** Pick messages, then forward them to
  several chats or a new number with a note, delete them, or star them.
- **Feels like the phone.** Reading marks chats read on your devices, the
  contact sees you typing, notifications open or answer the chat, and ticks,
  presence and `@` mentions show when wacli records them.
- **Several accounts.** One merged list with a color per account, and each
  account's sync, notifications and unlink in its own settings card.
- **First run and lifecycle.** A welcome screen that links the phone from the
  app, Quit with `Ctrl+Q`, and a choice to start with the system.
- **For agents.** An MCP server with 46 tools next to the agent skill.

### All changes

- Settings → Accounts has one card per linked account: its state, its own
  background sync and, with more than one account, its own notifications, so
  one account can stay silent without replaying its messages later. Unlink
  asks first and names the account: the phone loses that linked device and
  the chats already here stay on disk. With several accounts, each chat's
  photo carries its account's color, in the list, the header and the bar
  dropdown.
- First run: with nothing linked, the window welcomes you instead of an empty
  list: what OmaWhatsApp is, what stays on this computer, the three steps to
  link the phone and a Show QR code button that opens the code in a terminal;
  it says what to install when wacli is missing. The list then says "Syncing
  your chats…" until the first sync fills it, and the bar dropdown offers
  Set up.
- The person you are writing to now sees "typing…" while you type in the app
  or the dropdown, and "recording audio…" during a voice note, as from the
  phone. It follows "Show me online" and only goes through the running sync.
- Quit OmaWhatsApp (Ctrl+Q in the app, or Settings → Sync & storage): every
  account's sync stops, so no message, popup or "online" until it opens
  again from the bar icon, which shows grey meanwhile. Start with the system
  is now its own setting: off, OmaWhatsApp stays closed at login until
  opened; the installer and offline mode respect it.
- A chat whose unread messages @mention you shows an @ beside its count, in
  the chat list and the bar dropdown. It needs the wacli fork, which records
  mentions from the moment it is installed.
- Star and unstar messages from the message menu or for all picked messages
  from the selection bar; the star reaches your phone and other linked
  devices. It needs the wacli fork's `messages star` and is hidden on a wacli
  that cannot star.
- Forward to a number with no chat yet: type it in the forward dialog, check
  it with WhatsApp in one click (the check no longer stops sync), and it
  joins the other chats as a chip. The note, if any, is that chat's first
  message.
- Picked messages can be deleted together from the selection bar: for you,
  or for everyone when they are all yours, after one confirmation, one
  WhatsApp action at a time, with a single notice at the end. With the
  matching wacli a delete goes through the running sync instead of stopping
  it.
- In a group, the photo (or initials, in the color of their name) of whoever
  wrote sits beside the last message of each of their runs, in a column that
  keeps the run aligned. The bar dropdown keeps its narrow bubbles without it.
- Signature (Settings → Chats → Sign my messages): each account can sign its
  texts and captions with a name in bold, on its own first line or at the
  end. It is off by default, never touches reactions, stickers or audio, and
  the message box shows it with a Skip once for a single message.
- A voice note keeps playing when a message arrives, and when it ends the
  next message plays if it is audio too, as on the phone. Each voice note had
  its own player inside its row, and a new message rebuilds the rows; the
  full app and the dropdown now each keep one player outside them.
- Sending no longer waits behind a read mark. Marking a chat read (on
  opening it, or after a reply) can make wacli wait minutes for WhatsApp to
  repair the account's app state, and it held the only write process, so
  every reply queued behind it and failed after 45 seconds. Read marks now
  have a process and queue of their own; with the matching wacli they also
  queue apart inside sync, and a request whose caller gave up is dropped
  instead of sent late.
- Restyle, phase 5 (flows): Forward on a message now picks it in the
  conversation, where more can be picked (an album counts each photo), with a
  bar to forward or copy them. The dialog takes several chats as chips, an
  optional note that follows the messages in each chat, and Ctrl+Enter; the
  messages go oldest first, one WhatsApp action at a time, and a toast says
  where they went with a button to open that chat. Message on a shared
  contact with no chat opens a draft chat for that person over the chat the
  card came from: it says who shared it, checks the number with WhatsApp
  once, offers Copy number and Show the card, and the first Enter starts the
  chat. With the matching wacli, that check no longer stops sync.
- Restyle, phase 4 (bar dropdown): the header says "Chats" and how many are
  unread (click to show only those, right-click or Clear to clear the
  badges), with new chat and full app beside it. Rows are shorter, with the
  same time stamps, ticks, media kinds and group senders as the full app;
  hovering a row offers mark read and reply here in place of its badge. The
  footer names what each key does. In a conversation, "3 new" marks where the
  unread messages start and a line under the composer says what Enter,
  Shift+Enter and Esc do.
- Restyle, phase 3 (chat list): pinned and recent chats sit under their own
  labels, every row shows the time of its last message (the time today, then
  Yesterday, the weekday, a short date), unread chats have a bold name and an
  accent time, and a muted chat counts in grey. Media previews name their
  kind with an icon ("Photo", "Voice message") instead of "[image]", a group
  preview names who wrote it, and a draft reads amber. People have round
  avatars and groups rounded squares, each in its own color from the theme.
  The views are a segmented control; compact density keeps each chat on one
  line with underlined views. Demo captures take `"density":"compact"`.
- Restyle, phase 2 (attachments): photos, GIFs, videos and albums fill a
  thin frame with rounded corners and a portrait photo gets a narrower
  bubble; with no caption the time sits on the picture. Voice notes get a
  waveform that fills as they play, with speed and time on one row; named
  audio files keep their name. Documents show their type as a colored badge,
  files not downloaded yet a round download button, locations a drawn map
  (nothing is fetched), shared contacts their initials, and a deleted
  message only an outline.
- Clicking a message notification opens the small reply view by the bar on
  that chat, with the composer ready, instead of the full app. Omarchy's
  notifications show no reply field or extra buttons, so this is the direct
  reply; Settings → Notifications can keep the full app instead.
- Restyle, phase 1 (bubbles and text): one person's messages form a run
  with tight gaps and a tight corner on their side in place of a tail, and in
  groups the name shows once per run in a color of its own, derived from the
  theme accent. The time and ticks sit on the last line of text when there is
  room. Quotes are an inset block with the author in their color.
- Forwarding is quick and says where it went. With a wacli build that
  delegates `messages forward`, the sync is no longer paused for it (it took
  seconds and could lose what arrived meanwhile); a toast names the chat it
  went to; a forwarded photo or file shows the copy already on this computer
  instead of offering a download; and forwarding from the dropdown opens the
  full app's picker for that message instead of starting over.
- The emoji picker stays open for as many emoji as wanted, closing with Esc,
  a click outside, the emoji button, or its new close button. Emoji are
  grouped by theme under headers, with a row of theme tabs that jump to each
  and follow the scroll; recent emoji come first.
- Formatting moves from a composer button to where the text is: a small bar
  (bold, italic, strikethrough, monospace, code, lists, quote) appears over
  any selection, and right-clicking the composer opens cut, copy, paste,
  select all, and the same formats with their shortcuts.
- Show who is online, when they were last seen, and who is typing or
  recording, under the chat name, in the dropdown, and as "typing…" in the
  chat list. The account shows itself online while the window (or the
  dropdown on a conversation) has focus, as WhatsApp requires to send any of
  it, on a lease the sync ends by itself; Settings → Reading can turn it off.
  It needs a wacli build that follows presence; with official wacli nothing
  changes.
- Fix the "N unread messages" divider moving onto your own replies. It is now
  anchored to the oldest unread message received when the chat opened, so
  anything sent or received afterwards stays below it.
- Show sent, delivered, read, and played ticks on your messages and before
  your last message in the chat list. The helper reads them from
  `message_status`, which wacli builds that keep receipts maintain. With
  official wacli, or for messages synced before such a build, no tick is
  shown. The agent server reports the same state as `delivery`.
- Sending no longer holds up typing. Each Enter puts the message on screen
  at once, even while an earlier message or a read mark is still going out.
  Messages then go out in the order they were typed. A message that fails
  stays in the conversation, marked as not sent, with Try again and Discard
  in its menu. The send button no longer dims for text.
- Every helper call starts about 0.15–0.2 s sooner. `bin/omawhatsapp` is now
  a launcher for the module `omawhatsapp_core.py`, whose compiled bytecode
  is cached instead of rebuilt on every call. Thread pools are only loaded
  when more than one account or download needs them.
- Accept wacli 0.17.1 or newer instead of exactly 0.17.1. The parity
  registry, tests, and CI are verified against 0.18.3; the installer reports
  a newer release and keeps its unclassified commands blocked.
- Classify the new `groups participants list` leaf (0.18.0) as a local read
  scoped to a locally indexed group. The registry now covers 104 leaves and
  records the release each leaf first appeared in (`min_wacli`).
- Run CI against both wacli 0.17.1 and 0.18.3 on the Omarchy 4.0.4 shell API.
- Drop the window title bar. Settings and hiding the chat list move to small
  icon buttons beside "Chats", the sync state shows as a quiet line at the
  bottom of the rail only while offline or reconnecting, and desktop
  notifications move into Settings. The manual refresh buttons are gone; the
  store watcher already refreshes.
- The conversation subtitle no longer says "direct message" or "group"; it
  names the chat's account only when more than one is linked.
- Remove the Ctrl+1…Ctrl+9 chat jumps.
- Hide wacli's synthetic rows: "(message)" for payloads it cannot decode and
  the "[Album: N images]" header before an album's real media no longer show as
  bubbles or chat previews, and uncaptioned voice notes no longer carry the
  "[Audio]" text. Drop the delivery tick, which the mirror has no data for.
- Show the WhatsApp mark in the empty conversation pane.
- Replying to a chat marks it read, so its unread count clears the way it does
  on the phone. wacli's mark-read only syncs the read state to your own
  devices; it sends the other side no read receipt.
- The conversation on screen is read: opening a chat and messages arriving
  while it is open mark it read, as on the phone. This is now the default for
  every account (preferences version 3 migrates the old "off" default). A chat
  marked unread from the list stays unread until it is chosen again. The chat
  menu no longer offers "Mark read · send receipt", which was never a receipt.
- Mark a chat read or unread from the rail row on hover, where the button takes
  the place of the unread count.
- Rebuild Settings as a full view with sections for reading, notifications,
  chats, media, sync and storage, accounts, updates, shortcuts and about. New
  options: mark read on reply, Enter sends, chat photos, compact chat list,
  automatic download of received media, and automatic chat-photo refresh.
  Storage use and the installed wacli version are shown.
- Turning automatic media download off writes a systemd drop-in that empties
  `$OMAW_MEDIA_FLAGS`; the sync units now pass `--download-media` through that
  variable. Uninstall removes the drop-ins it wrote.
- Chat photos refresh by themselves while every window is closed, in short
  batches, then once a day. wacli needs the store lock for photo lookups, so
  each batch still pauses sync for a few seconds.
- In-app update checks and the release link in Settings look at this fork,
  not upstream.
- The dropdown footer just says "Open full app"; its key and the list keys
  are explained in tooltips instead of a bare row of letters.
- The conversation shows day headers (Today, Yesterday, weekday, date), a
  "N unread messages" divider where unread messages start, and a jump-to-latest
  button with the count of messages that arrived while you read above; the
  bar dropdown gets the headers, the divider and the button too.
- Desktop notifications are on by default; they were off by default, which
  read as "notifications do not work". Preferences version 4 turns them on for
  existing installs with a fresh watermark, so the archive is adopted instead
  of replayed. A popup now shows the chat photo, reads media the way the phone
  does ("📷 Photo", "📄 report.pdf"), plays one short sound per batch unless
  Omarchy's do not disturb is on (new Sound setting), and appears as soon as
  the message lands in the mirror instead of at the next 12-second tick.
- Automatic chat-photo refresh is off by default. Every photo batch pauses
  sync, and the short wacli connection that checks photos acknowledges every
  message and receipt that arrives meanwhile without storing it; that is how a
  chat read on another device could stay unread here. Settings says so.
- A chat marked unread on the phone shows as unread (one) instead of read.
- Unread counts match the phone: wacli counts reactions and the "(message)"
  rows it cannot decode as unread, and a reply sent from another device can
  leave its count behind. The helper subtracts those rows, treats your own last
  message as reading the chat, and counts only what arrived after it. On the
  owner's mirror this took twelve unread chats to the ten the phone showed.
- When this app stops sync for something wacli cannot delegate, the rail line
  says why ("Sync paused · sending files") instead of "Reconnecting…", and its
  tooltip says messages arriving in those seconds may not reach this computer.
- A new message in a chat whose popup is still around updates that popup
  ("Design team · 5 new") instead of stacking another one.
- An edit or a reaction that moves a chat's time no longer pops up a
  notification with the old message; only a new last message does.
- The bar badge counts unread chats instead of unread messages; the tooltip
  names both.
- The jump-to-latest button and the floating day measure the distance on the
  newest message itself, and jumping repositions once the newest bubbles have
  their real height; a single pass could leave the newest message cut at the
  bottom, and without the theme fonts the button showed at the bottom and not
  at the top.
- Full group control in the chat details. Right-click a participant (or
  use its menu button) to message them and, as an admin, make or dismiss
  admins and remove people. "Load group settings" reads the live settings
  from WhatsApp on request (sync pauses a moment): rename, edit the
  description, "only admins send messages", "only admins edit group info",
  get, copy or reset the invite link, approve or reject join requests, add
  people by number, and leave the group. Removing, resetting the link and
  leaving take a second click to confirm.
- The details and media panels own every click inside them: a right click on
  a group participant also opened the menu of the message bubble underneath,
  because the panel's mouse guard did not stop tap handlers. The conversation
  under a covering panel is now disabled, and the draft gets its focus back
  when the panel closes.
- Add `omawhatsapp-mcp`, a Model Context Protocol server that lets Claude
  Code and other MCP clients use WhatsApp through 44 named tools: unread
  messages with context, chats awaiting a reply, reading by period, full-text
  search with filters, attachments across chats, contacts and tags, calls,
  polls, sending, replying, files, groups, profile, status, channels, exports,
  and older history. Writes are annotated so the host asks first; the server
  calls the helper and never opens the store. The installer places it and
  prints the `claude mcp add` line.
- The helper lists attachments across chats (`attachments`), contact tags
  (`contact-tags`), and people by tag (`contacts-search` with `tag`), and a
  sent poll now returns its message id.
- A person's chat no longer disappears after you send a poll or vote: wacli
  0.18.3 stored it with the kind and push name of the hidden @lid. The chat is
  read as a person again, under the name saved on the phone.
- Files under `/tmp` send again. The sync service that performs the send
  cannot see `/tmp`, so such a file goes from a private copy that is removed
  right after.
- A reply typed while another WhatsApp action runs (such as the read mark of a
  chat opened from a notification) waits for it and then goes, with an
  hourglass on the send button, instead of doing nothing. The bar dropdown
  does the same, and typing there never waits.
- Ctrl+V no longer waits behind a running send or read mark; it has its own
  process, and plain text still pastes when the helper cannot read the
  clipboard.
- Verified with wacli 0.19.0 (CI runs 0.17.1, 0.18.3 and 0.19.0). From 0.19
  (store migration 27) wacli's own unread counts already leave out reactions
  and undecodable rows, so the helper stops subtracting them there; with an
  older store it still does. `chats mark-read --receipts` is new in 0.19 and
  stays a WhatsApp write in the gateway.
- Chat details export the chat as readable text, like the phone ("2026-09-25
  10:15 - Ana: …"), to a file you choose outside code repositories; download
  the chat's missing attachments in one go; and, for a person, set your own
  alias, add or remove tags, and show their about text and business profile.
- An attachment WhatsApp's server no longer has (403/404/410) is remembered:
  it shows as no longer available and is not counted or asked for again.
- A "To reply" view in the chat list shows the people whose message is the
  last one in the chat.
- Groups inside a Community show in the chat list and open like any group,
  as on the phone; the Community itself stays out.
- New group and "Join a group with a link" at the top of the new chat dialog:
  pick people you know, name the group and create it, or paste an invite link.
- Format messages as on WhatsApp: *bold*, _italic_, ~strikethrough~,
  ```monospace```, `code`, bulleted and numbered lists, and quotes. The
  composer's formatting button lists every option with its syntax;
  Ctrl+B and Ctrl+I (on a selection), Ctrl+Shift+X and Ctrl+Shift+M apply
  them, in the full app and the bar dropdown. Messages show the formatting,
  rendered from escaped text with a fixed set of tags, and chat previews drop
  the markers.
- A shared contact shows as a card with the name, the number, "Message" (its
  chat, or a new chat with the number typed in) and "Copy number", instead of
  the text "Contact: Name (+…)". Chat previews show "👤 Name".
- The MCP server gains `list_statuses` and `delete_status`, so a posted status
  can be taken back; `fetch_older_history` first asks the user to open WhatsApp
  on the phone and pauses nothing until they confirm; group actions reach
  communities and their groups through the gateway; `read_chat` reports shared
  contacts.
- Reactions show under their message again. Lists inside a message reach the
  bubble as Qt sequences through the list model, so the reaction and button
  rows had been empty.
- Polls show as polls: the question, each option with its vote count, a bar
  and who voted, and a tap votes (several choices when the poll allows).
  Votes cast from this computer no longer appear as a "Voted: …" message.
- A message deleted for everyone stays as "You deleted this message" or "This
  message was deleted", as on the phone, without its old text in the chat,
  the rail preview, searches or the media view.
- A location shows its name, address and coordinates, and opens in the
  browser map.
- Right-click the bar icon to mute or unmute every desktop notification and
  its sound. A crossed bell beside the count shows the mute, the Omarchy OSD
  confirms the change, and unmuting never replays what arrived meanwhile. It
  replaces the old right-click refresh, which the store watcher made
  redundant.
- Media, links and docs open in their own view (header button, or the counts
  in the chat details) with Media, Links and Docs tabs over the chat's whole
  local history: a photo grid that opens the viewer, links that open in the
  browser, and documents that open or download. The conversation is no
  longer filtered; before, the all/media/links chips hid in compact windows
  and left a filtered conversation with no way back.
- While scrolling, the day of the topmost message floats at the top of the
  conversation and fades a moment after scrolling stops, in both clients.
- Stickers look like stickers: no bubble behind them, about 160 px, animated
  ones play while the conversation is on screen, and a click no longer opens
  an external viewer.
- Send stickers from a Stickers tab in the emoji picker, in both clients. It
  lists the recent stickers of the account, each file once, fetches the ones
  not on this computer yet on first open (beside the live sync), skips the
  ones WhatsApp has expired, and sends on click with a pending bubble that
  already shows the sticker.
- The conversation has a scroll bar that shows while scrolling or hovered;
  Page Up and Page Down move a screen even while typing, Home goes to the
  oldest loaded message and End back to the newest.
- A file sent to a contact no longer vanishes from the chat on the next
  refresh. wacli swaps the phone JID for the contact's `@lid` before a file
  send and files the message there; the helper folds those rows back into the
  phone chat (conversation, preview and order), and actions on them use the
  chat they were filed in.
- The rail's pause reason no longer names files or voice notes: wacli 0.18.3
  sends them through the sync process, which never pauses for them.
- Drag the chat list's edge to resize it; the width is saved, and a double
  click on the edge goes back to the automatic width.
- The All/Unread/Groups/Archived chips scroll sideways, with the wheel too,
  when the list is too narrow for them; the scroll bar shows only while moving.
- Pin, mute and archive show in the chat list at once; wacli cannot delegate
  them, so the write itself still pauses sync for a few seconds. The pin icon
  is larger and in the accent colour.
- The hover actions of a message have a solid background and no longer sit
  inside the bubble: the theme's fill is about 4% opaque, so in the dropdown
  the text showed through and the buttons looked buried under it. They now go
  beside the bubble whenever the row has room, and straddle the top edge of a
  bubble as wide as the row. The
  jump-to-latest button, which floats over the conversation, gets a solid
  backing for the same reason, and a row showing its actions draws above its
  neighbours.
- Voice notes and audio play at 1×, 1.5× or 2× (one choice for every
  bubble, as on the phone), show elapsed and total time, and seek where the
  bar is clicked.
- Less work on every mirror change: an answer identical to the previous one
  no longer rebuilds the chat list or the conversation, and the 12-second
  status poll reuses a healthy `wacli doctor` answer for a minute instead of
  opening the WhatsApp session store every time.
- Scrolling up past the newest 240 messages loads the older ones, 200 at a
  time, down to the start of this computer's copy of the chat. A mirror change
  refreshes only the newest page and keeps the older pages loaded.
- Ctrl+K jumps to any chat by typing part of its name; arrows move, Enter
  opens, and archived chats are found too.
- The chat list gets All, Unread, Groups and Archived views under the search
  field. Archived chats move to their own view, as on the phone, and leave the
  bar dropdown's recent list; a search still finds them.
- A sent message shows at once as a pending bubble with a clock, in both
  clients, instead of appearing only after WhatsApp confirmed the send and the
  mirror stored it; the stored row then takes its place. Files show one pending
  bubble with the file name and caption. A failed send removes the bubble and
  puts the text back in the composer.
- Chat details: click the chat's photo or name in the header (or Chat actions →
  Chat details) for a contact or group panel read entirely from the local
  mirror, so it never pauses sync: photo, phone and other names, mute, pin,
  unread and search, media, link and document counts that filter the
  conversation, starred messages, groups in common or participants with their
  roles, and how long this computer has held the chat. It sits beside the
  conversation on wide windows and over it otherwise; a covered conversation
  does not count as read.
- Start a new chat from the button beside "Chats" (Ctrl+N) or from the bar
  dropdown. The dialog searches the people the account's mirror knows by name
  or number; a person with a chat opens it. A typed number is first checked
  with WhatsApp (`contacts check`, an explicit remote read), and a first
  message only goes to a person the mirror knows or to the JID WhatsApp just
  confirmed, never to the typed digits.
- Clicking a desktop notification opens that chat in the full app.
- The chat list shows pinned and muted icons, and "Draft: …" for chats with an
  unsent message.
- Links in messages open from chips under the text, and the message menu gains
  Copy link; the text itself stays plain. Hovering a time shows the full date.
- Download attachments with `media download --read-only --output` into
  OmaWhatsApp's own media folder, so opening media no longer pauses sync.
- Save as… for attachments, from the message menu and the media viewer.
- Insert emoji from a picker beside the attach button in both composers; it
  reads Omarchy's own emoji list and types at the cursor. In the bar dropdown
  it replaces the paste button (Ctrl+V still pastes).
- The bar dropdown's count now filters the list to unread chats; right-click
  clears the badge. Background writes such as automatic reading no longer show
  "sending…" in the dropdown or block going back to the list.
- Only a conversation that is actually on screen is read: the full app open on
  it, or the bar dropdown showing it. The dropdown open on its chat list no
  longer marks the last selected chat read when a message arrives, and no
  longer clears its badge or suppresses its desktop popup.
- Each chat-photo batch stops after 20 seconds of paused sync; the rest stays
  due for the next batch. Automatic reading waits for sync to be running.
- Right-click a chat in the list for read or unread, pin, mute, archive and
  remove, and right-click a message for its actions at the pointer; the
  message menu gains React.
- Redo the message composer in the full app and the bar dropdown: attach,
  field and send share one height and one bottom edge, so one line reads as
  centred and a longer draft grows upward; the placeholder sits on the line
  the text will use. The Enter instructions move from the dropdown header into
  a tooltip on the field, and a new preference makes Ctrl+Enter send instead
  of Enter. The attach menu drops Camera, Contact and Event, which only showed
  an error.
- Show reactions that wacli stored under the contact's opaque @lid chat
  instead of the phone chat of the reacted message; a sent reaction used to
  vanish from the bubble.
- Add interface preferences to the helper: read on reply, Enter sends, chat
  photos, automatic photo refresh, and rail density.
- Add `make dev`, which copies working-tree changes over an existing install
  and restarts the shell when QML changed, and `make demo`. The installer and
  test gate find qmllint in /usr/lib/qt6/bin on their own.
- Every icon-only control has a tooltip, and the message hover actions use
  reply, emoji and more-actions icons instead of unrelated glyphs. The bar
  dropdown's attach button shows a paperclip instead of a megaphone.
- Keep up to 2048 chat photos in the private cache instead of 128, so accounts
  with more chats than that stop evicting and re-downloading photos on every
  refresh, and check 64 chats per explicit refresh instead of 12 so filling the
  cache restarts background sync far fewer times.

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
