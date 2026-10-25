# Keyboard shortcuts

Change these in **Settings → Shortcuts**. Click a key, press the replacement, then save. Up to three alternatives are supported. An empty action has no keyboard binding; its clickable control still works.

The following are the defaults. A custom Send message binding takes precedence over Settings → Chats → Enter sends. With Enter sends off, the default send key is Ctrl+Enter.

## Everyday actions

| Action | Default keys |
| --- | --- |
| Find in conversation | `Ctrl+F` |
| Show or hide chat list | `Ctrl+B` |
| Start a new chat | `Ctrl+N` |
| Go to a chat by name | `Ctrl+K` |
| Open chat 1–9 | `Alt+1` … `Alt+9` |
| Attach documents | `Ctrl+O` |
| Attach photos and videos | `Ctrl+Shift+O` |
| Record or stop a voice note | `Ctrl+Shift+V` |
| Quit OmaWhatsApp | `Ctrl+Q` |

In the full app, Alt+1–9 opens the corresponding conversation in the current chat list, respecting its order, search, view and account filter. It works while typing and with the sidebar hidden, preserves each chat’s draft, and focuses the selected chat’s composer. If chat details or the media browser covers the conversation, it stays open, as after a click in the chat list; Esc closes it and returns you to the composer. The position is read when you press the keys, so a chat that a new message moves up can take the row you were looking at; the conversation header names the chat that opened. A position beyond the list does nothing. Settings, onboarding, a contact draft, the media viewer and any open dialog or menu keep these shortcuts inactive. Each position can be changed or disabled separately in Settings → Shortcuts.

## Navigation

| Action | Default keys |
| --- | --- |
| Search chats | `/` |
| Move down | `J` · `Down` |
| Move up | `K` · `Up` |
| Reply to selected message | `R` · `Shift+R` |
| Write a message | `C` |
| Open selected chat | `Enter` |
| Open selected media | `Space` |
| Step back | `Escape` |
| Scroll conversation up | `PageUp` |
| Scroll conversation down | `PageDown` |

## Writing

| Action | Default keys |
| --- | --- |
| Send message | `Enter` · `Ctrl+Enter` |
| Paste text, image or file | `Ctrl+V` |
| Bold selected text | `Ctrl+B` |
| Italic text | `Ctrl+I` |
| Strikethrough text | `Ctrl+Shift+X` |
| Monospace text | `Ctrl+Shift+M` |

## Mini client

| Action | Default keys |
| --- | --- |
| Refresh mini client | `R` · `Shift+R` |
| Open full app from mini client | `O` · `Shift+O` |
| Write in mini client | `I` · `Shift+I` |
| Next mini-client panel | `Right` · `L` |
| Previous mini-client panel | `Left` · `H` |

## Media viewer

| Action | Default keys |
| --- | --- |
| Close media viewer | `Escape` · `Backspace` |
| Previous media | `Left` |
| Next media | `Right` |
| Zoom in | `+` · `=` |
| Zoom out | `-` |
| Reset zoom | `0` |
| Play or pause media | `Space` |

## Forwarding

| Action | Default keys |
| --- | --- |
| Send forwarded messages | `Ctrl+Enter` |

## Desktop and standard controls

Super+Shift+W opens/closes the app once configured in Omarchy. This is a desktop-wide Hyprland binding, so it is managed outside the in-app editor. Desktop shortcuts can intercept keys before the app receives them.

Tab/Shift+Tab move focus. Escape cancels dialogs and capture. Text fields retain ordinary copy, cut, undo, select-all, caret movement, and new lines. Search/mention/dialog lists keep standard arrows and confirmation keys. These standard control behaviors are not custom action bindings. Ctrl+B formats selected text, otherwise it toggles the sidebar. Navigation letter keys never act on ordinary typed text. Forwarding requires a modified key or function key.

Bindings are saved privately on this device, shared by all accounts and open surfaces, and preserved on upgrade. If an update adds an action whose default key you already use, your binding keeps the key and the new action starts unassigned. Demo edits do not save or send anything.
