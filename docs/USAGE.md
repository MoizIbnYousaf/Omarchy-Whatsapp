# Using OmaWhatsApp

[← Documentation](README.md)

Everything the app does, where to find it, and every shortcut. The
[README](../README.md) has the short tour; this page is the reference.

- [Two ways in: the bar and the full app](#two-ways-in-the-bar-and-the-full-app)
- [Chats and the chat list](#chats-and-the-chat-list)
- [Writing and sending](#writing-and-sending)
- [Messages you receive](#messages-you-receive)
- [Reading, ticks and presence](#reading-ticks-and-presence)
- [Notifications and the bar badge](#notifications-and-the-bar-badge)
- [Several accounts](#several-accounts)
- [Groups and chat details](#groups-and-chat-details)
- [Settings](#settings)
- [Keyboard](#keyboard)
- [Commands and IPC](#commands-and-ipc)

## Two ways in: the bar and the full app

**The bar dropdown.** Click the bar icon for a compact client anchored to the
bar: recent chats with unread counts, search, the messages of a chat, and a
real composer with attachments, emoji, voice notes and clipboard paste. `O`
opens the same chat in the full app. Most replies never need more.

**The full app.** `Super+Shift+W` (see [Install](../README.md#install)) opens
the window: the chat list, the conversation, chat details, the media gallery,
search and settings. It is a real responsive layout at every size, from a wide
two-pane window down to a 360 px single pane.

Both open from the local mirror without waiting for the network, and closing
them keeps the chat list warm in the resident service.

## Chats and the chat list

- Every locally synced direct message and group, groups inside a Community
  included, as on the phone. Channels, calls and the Community itself are not
  in the list.
- Views: All, Unread, To reply (chats whose last message is theirs) and
  Groups; pinned chats stay on top under their own label.
- Search chats with `/`; `Ctrl+K` jumps to a chat by typing part of its name.
- Each row shows the time, the sender in groups, the kind of media, your ticks,
  "typing…" and your unsent draft.
- An `@` beside the unread count means an unread message mentions you.
- Hover a row, or right-click it, to mark it read or unread, pin, mute,
  archive or clear it locally.
- Drag the list's edge to resize it; `Ctrl+B` hides or shows it.
- Comfortable or compact density in Settings → Chats.

## Writing and sending

- Multiline text with WhatsApp formatting: `Ctrl+B`/`Ctrl+I` on a selection,
  `Ctrl+Shift+X` strikethrough, `Ctrl+Shift+M` monospace, and a formatting
  menu with lists, quotes and code.
- Reply, edit, react, delete for you or for everyone, and forward.
- Up to 10 files with one caption: documents (`Ctrl+O`), photos and videos
  (`Ctrl+Shift+O`), drag and drop, or paste text, screenshots, GIFs and files
  with `Ctrl+V`. Review and remove attachments before sending.
- Several photos go out as one album.
- **Voice notes are draft-first.** `Ctrl+Shift+V` starts and stops recording;
  stopping opens a review card with playback, discard and one explicit send.
  Nothing is sent when you stop.
- `@` in a group opens a member picker and sends a real WhatsApp mention.
- Polls, stickers (Emoji → Stickers) and interactive options.
- **Forward to many at once.** Pick messages in the conversation, then send
  them to several chats, or to a number with no chat yet, with an optional
  note.
- **Pick several messages** to forward, star or delete them together.
- **New chat** with `Ctrl+N`: search people by name or number, or type a
  number with its country code; WhatsApp confirms the number first.
- A contact card's Message button opens a draft chat with that person.
- **Signature** (off by default, per account): your name in bold at the top or
  the end of texts and captions, with Skip once in the message box.
- Every chat keeps its own draft, reply or edit, and pending attachments while
  you move between chats.
- Sending never waits: a message appears at once and, if it fails, stays as a
  bubble with Retry and Discard.
- While you type or record, the other person sees "typing…" or "recording
  audio…", as from the phone. It follows Settings → Reading → Show me online.

## Messages you receive

- Images, stickers, GIFs, videos, voice and audio, documents, locations,
  contact cards, quotes, reactions, polls, button rows, and edited, forwarded
  and starred marks.
- Voice notes play inline; the player keeps playing when new messages arrive
  and moves on to the next voice note when one ends.
- Media is downloaded when it arrives, or only when you open it (Settings →
  Media). A missing video downloads into its inline player with one click.
- **Native gallery**: photos, GIFs and videos full window, with zoom, previous
  and next, playback and metadata. `Space` opens the selected media.
- Save as… for any received file.
- With [Omasnap](https://github.com/tobi/omasnap) installed, Open externally
  sends images to its annotation editor.
- Select text to copy it, or use Copy in the message menu.

## Reading, ticks and presence

- Automatic marking as read on open or reply is opt-in in Settings → Reading.
  Existing private-reading choices are preserved during upgrades.
- Marking read only syncs your phone and your other linked devices. The app
  never sends a read receipt, so contacts are not told.
- Ticks for what you send (sent, delivered, read) and a contact's online, last
  seen and typing need a wacli that records them; see
  [wacli: official and richer builds](../README.md#wacli-official-and-richer-builds).
  Without it no tick is shown rather than a guessed one.

## Notifications and the bar badge

- A private desktop notification per chat with new messages: a generic notice
  and app icon, one short sound unless Omarchy's do not disturb is on, and a
  click that opens the chat or a small reply view by the bar. Chat names,
  message text and photos stay inside the app.
- Muted and archived chats stay silent, and so does the chat you are reading.
  Unmuting starts from now: nothing that arrived meanwhile pops up later.
- The bar badge counts unread chats, not messages; its tooltip gives both.
  Middle-click clears the current batch; right-click mutes every notification
  and shows a crossed bell until you right-click again.
- Notifications need `notify-send` from libnotify.

## Several accounts

- Link another account from Settings → Accounts or the `+` beside the account
  filters; a terminal shows the QR code.
- One merged chat list with a filter per account. Each account has a color, on
  the edge of its chats, on its filter and on its name in the conversation
  header.
- Each account has its own card in Settings → Accounts: background sync,
  notifications (one account can stay silent) and Unlink, which asks first,
  names the account and keeps the chats already on disk.
- Replies, receipts, offline mode and the signature follow the account of the
  chat on screen.

## Groups and chat details

- Click the conversation photo or name for its details: photo, about, phone,
  shared media, links and documents, starred messages, and actions.
- In a group: participants and their roles; admins can add, remove, make or
  dismiss admins, rename, edit the description, choose who may send or edit,
  manage the invite link and join requests. Anyone can leave.
- The media button in the header lists the chat's media, links and documents.

## Settings

| Section | What it holds |
|---|---|
| Reading | Mark read on open, mark read on reply, show me online (needed to see presence and to show typing) |
| Notifications | Desktop notifications, reply from the notification, message text, sound, unread badge, dropdown size |
| Chats | Signature, Enter sends, chat photos, list density, time format, message box height |
| Media | Automatic downloads, chat photo refresh |
| Sync & storage | Background sync, start with the system, Quit, letting AI agents use WhatsApp, removing it from this computer, storage used |
| Accounts | One card per account, link another |
| Updates | Check for a newer version, update in a terminal, restart the shell after an update |

## Keyboard

### Everywhere

| Keys | Action |
|---|---|
| `Super+Shift+W` | Open or close the app (once bound) |
| `Ctrl+Q` | Quit: nothing arrives until you open it again from the bar |
| `Esc` | Step back: composer → messages → chat list → close |
| `J`/Down · `K`/Up | Move through messages or chats |
| `Enter` · `Shift+Enter` | Send · new line (swap in Settings → Chats) |
| `Ctrl+V` | Paste text, an image, a GIF or a file |
| `Ctrl+Shift+V` | Start or stop a voice note (never sends by itself) |

### Full app

| Keys | Action |
|---|---|
| `Ctrl+N` | New chat |
| `Ctrl+K` | Go to a chat by name |
| `Ctrl+F` | Find in this conversation |
| `Ctrl+B` | Hide or show the chat list (bold on a selection) |
| `Tab` · `Shift+Tab` | From the sidebar, cycle All → Unread → To reply → Groups → chats (reverse with Shift); Archived joins when present. Focus activates each filter. |
| `/` | Search chats from the list or filters |
| `C` | Write a message |
| `R` | Reply to the selected message |
| `Space` | Open the selected media; play or pause in the viewer |
| `Left` · `Right` | Previous or next item in the gallery |
| `+` · `-` · `0` | Zoom in, out, fit |
| `Page Up` · `Page Down` | Scroll a screen, even while typing |
| `Home` · `End` | Oldest loaded message · newest |
| `Ctrl+O` · `Ctrl+Shift+O` | Attach documents · photos and videos |
| `Ctrl+I` · `Ctrl+Shift+X` · `Ctrl+Shift+M` | Italic · strikethrough · monospace |
| `@`, then arrows and `Enter` | Mention a group member |

### Bar dropdown

| Keys | Action |
|---|---|
| `/` | Search recent chats |
| `Enter` | Open the chat and focus its message box |
| `O` | Open this chat in the full app |
| `Ctrl+O` | Attach files |

## Commands and IPC

Keybindings and hot corners can drive the app through the Omarchy shell:

```bash
omarchy-shell io.github.moizibnyousaf.omawhatsapp toggleApp '{}'
omarchy-shell io.github.moizibnyousaf.omawhatsapp toggleDropdown '{}'
omarchy-shell io.github.moizibnyousaf.omawhatsapp openDropdown '{}'
```

`toggleDropdown` and `openDropdown` need the bar widget, as clicking its icon
does.

The helper is also a command line tool for scripts and agents; `omawhatsapp
--help` lists its commands. Its guarded wacli gateway, the agent skill and the
MCP server are described in the [README](../README.md#let-your-agent-use-whatsapp)
and in the [agent gateway reference](../skills/omawhatsapp/references/wacli-parity.md).
