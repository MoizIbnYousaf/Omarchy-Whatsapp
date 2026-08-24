# WhatsApp parity map

This is the implementation contract for OmaWhatsApp. “Feature complete” means
every row is either verified end to end or has a named upstream transport gap;
it does not mean that a button-shaped placeholder exists.

Evidence sources:

- **Web** — authenticated WhatsApp Web behavior, inspected without copying
  private conversation content.
- **Transport** — wacli 0.17.1 command help and the live local-store schema.
- **App** — the private OmaWhatsApp worktree, installed Omarchy plugin, and
  rendered runtime checks.

Status: `done` is implemented and tested, `building` has an active code path
but still needs complete rendered/live verification, `planned` is not yet
implemented, `intentionally excluded` is deferred product scope, and
`transport gap` is not exposed by wacli.

## 1. App shell and navigation

| Flow | Transport | App | Verification required |
|---|---|---|---|
| Link device / reconnect | `auth`, `doctor` | done | clean-store QR and reconnect |
| Warm local startup | read-only SQLite + resident sync | done | offline and live startup |
| Chat list | filtered `chats` mirror | done | DMs and standalone groups only |
| Chat search | mirror query | done | literal, Unicode, empty states |
| Chat filters | archived/pinned/muted/unread flags | planned | each filter and combinations |
| New chat | contact/chat lookup + send | planned | existing contact and first send |
| Archived chats surface | `chats list --archived` | planned | archive/unarchive round trip |
| Starred messages surface | `messages starred` | planned | global and per-chat lists |
| Channels/newsletters | `channels`, `...@newsletter` | intentionally excluded | later top-level section |
| Communities | `groups.is_parent`, `linked_parent_jid` | intentionally excluded | later top-level section |
| Calls history | `calls list` | intentionally excluded | later top-level section |
| Status list/view | local `status_messages` | planned | text and downloaded media |
| Settings/profile | `profile` commands | planned | read/update guarded flows |

## 2. Responsive structure

| Window | Expected behavior | App |
|---|---|---|
| `<640` logical px | one pane; chat list → conversation; visible Back | building |
| `640–899` | compact two-pane rail and conversation | building |
| `>=900` | wide rail, conversation filters, roomy message limits | building |
| Very short | composer and header fixed; timeline remains scrollable | building |
| HiDPI | logical-pixel layout; sharp media and icons | building |

No message bubble may exceed the conversation width. Header actions must never
cover the chat title. Composer context, attachments, errors, and the send
button must remain reachable at every supported size.

## 3. Chat lifecycle

| Flow | Transport | App |
|---|---|---|
| Select chat | local mirror | done |
| Mark read/unread | `chats mark-read/mark-unread` | building |
| Pin/unpin | `chats pin/unpin` | building |
| Mute/unmute | `chats mute/unmute` | building |
| Archive/unarchive | `chats archive/unarchive` | building |
| Per-chat text/reply/edit/attachment draft | local UI state | done |
| Paginate local history | bounded SQLite cursor | planned |
| Request older history | `history backfill` | planned |
| Contact info | `contacts show`, profile picture metadata | planned |
| Group member index / mention picker | participants + `send --mention` | building |
| Group info surface | `groups info` | planned |
| Group admin controls | rename/topic/lock/announce/participants | planned |
| Create/join/leave group | group commands | planned |
| Channel info/join/leave | channel commands | intentionally excluded |

## 4. Message rendering

| Content/state | Store evidence | App |
|---|---|---|
| Plain text and links | `messages.text` | done |
| Reply quote | `quoted_msg_id`, `quoted_sender_jid` | building |
| Forwarded marker | `is_forwarded` | building |
| Edited marker | `edited`, `edited_ts` | building |
| Deleted/revoked | deletion columns | planned |
| Reactions and counts | reaction rows | building |
| Star marker | `starred` table | building |
| Images | image media | done |
| WhatsApp GIF loops | `gif` + MP4/F4V | done |
| Uploaded GIF/WebP/sticker | image GIF/WebP | done |
| Video | video media | done |
| Audio / voice note | audio media | done |
| Documents | document media | done |
| Location | `message_locations` | building |
| Poll | `polls`, `poll_votes` | planned |
| Buttons/list rows | `messages.buttons` | building |
| Contact card | payload not normalized by wacli | transport gap |
| Link preview card | wacli sends previews; mirror lacks normalized card | transport gap |
| Delivery/read receipts | not exposed in the mirror | transport gap |
| Disappearing timer state | send flag exists; chat timer state not exposed | transport gap |
| Native image/GIF/video gallery | local media path | building |
| External image annotation | optional Omasnap CLI | done |

## 5. Message actions

| Action | Transport | App |
|---|---|---|
| Reply | `send ... --reply-to` | building |
| React / change / remove own reaction | `send react` | building |
| Edit own recent text | `messages edit` | building |
| Delete for me | `messages delete --for-me` | building |
| Delete for everyone | `messages delete` | building |
| Forward to another indexed chat | `messages forward` | building |
| Select interactive option | `send select` | building |
| Copy text / selection auto-copy | local clipboard | done |
| Star/unstar | list-only in wacli | transport gap |
| Message info / receipt detail | receipts not exposed | transport gap |

Destructive actions require an in-app confirmation. All message actions verify
the message belongs to the selected chat before crossing the helper boundary.

## 6. Composer and attachments

| Flow | Transport | App |
|---|---|---|
| Text + multiline | `send text` | done |
| Automatic link preview | `send text` default | building |
| Reply context | reply flags | building |
| Edit context | `messages edit` | building |
| Paste text/image/file | `wl-paste`, `send file` | done |
| Attachment tray | local UI | building |
| Crash-isolated multi-file picker | external `zenity` process | building |
| Drag and drop | QML `DropArea` | building |
| Review and remove before send | local UI | building |
| Caption | first attachment caption | building |
| Up to 10 attachments | bounded helper batch | building |
| Multi-photo album | private batch identity over real media messages | done |
| Photos/videos | `send file --as auto` | building |
| Documents | `send file --as auto` | building |
| Sticker | `send sticker` | building |
| Voice-note recording | `send voice`; recorder UI needed | planned |
| Location | `send location` | planned |
| Poll creation | `send poll` | building |
| Group mention completion | `send text --mention` | building |
| Camera capture | capture UI needed | planned |
| Contact attachment | normalized contact-send unavailable | transport gap |
| GIF search/provider | no provider exposed | transport gap |

The helper rejects remote URLs, non-absolute paths, empty files, files over
100 MB, and batches over 10 before sending anything. If the network fails in
the middle of a validated batch, the error reports the exact sent count so the
remaining selection can be recovered rather than silently duplicated.

## 7. Live behavior and reliability

| Flow | Transport | App |
|---|---|---|
| Background sync | `sync --follow` service | done |
| Writes through live companion | supported mutations | done |
| Store-lock fallback | bounded service yield/restart | done |
| On-demand media download | `media download` | done |
| Expired-media recovery | `media retry` | planned |
| Typing/paused indicator | `presence typing/paused` | planned |
| Incoming typing indicator | not exposed | transport gap |
| Desktop notifications | local new-message delta | planned |
| Offline draft/error recovery | local UI state | building |
| Audio/video calls | call events only | intentionally excluded |

## Release gate

Before public submission:

1. Finish the authenticated WhatsApp Web control/state/breakpoint audit.
2. Close every `building` row with backend, QML, and rendered evidence.
3. Implement every `planned` row supported by wacli.
4. Open upstream issues for every transport gap and keep the UI honest.
5. Verify 360×640, 540×720, 800×600, 1280×800, and maximized HiDPI.
6. Verify DMs, standalone groups, archived, muted, pinned, unread, media,
   quote, reaction, edit, deletion, poll, location, and interactive buttons.
7. Run privacy/secret scans; screenshots may contain demo data only.
8. Run the complete local validation suite and installed-runtime log audit.
