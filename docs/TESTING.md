# Testing

[← Documentation](README.md)

The release gate every change passes, the live checks on a real install,
and the rules for screenshots.

## Release gate

```bash
./scripts/test
```

The unit suite verifies focused DM/standalone-group listing, exclusion of
channels and Communities, single-line previews, literal search, strict
conversation boundaries, media metadata, outgoing-media handoff and album
identity, target validation, bounded messages, group-member mention scoping,
local notification acknowledgement, private-reading defaults, bounded
settings persistence and mode-0600 storage, automatic-receipt policy guards,
private voice-draft paths, OGG/Opus validation, exact-chat/reply voice sends,
failed-send retention, confirmed-send cleanup, voice state labels,
demo isolation, explicit receipt commands, persistent
offline write blocking, muted/archive badge suppression, mute-deadline
normalization, the lock-free live-delegate path, exact coverage of all 108
wacli 0.19.0 command leaves, authorization-class enforcement, global-flag
isolation, false-valued Boolean authorization flags, dry-run downgrades,
interactive restrictions, bounded parallel account probes, compensating
service rollback, and a fake-wacli end-to-end JSON invocation. The release script
also runs an isolated, read-only install preflight—including the bundled agent
skill safety contract—and compares the shipped registry with the installed
wacli help tree. Offscreen QML coverage uses generated MP4, GIF, and WebP
fixtures and exercises cross-window playback leasing, account-identical JIDs,
account-filter purity, private local avatars, missing-video transitions, and
file-picker/action interleavings. Setup tests run the first-run setup in an
isolated home: links into the checkout, rendered units with the found wacli,
exact copies from the old installer moved aside while a wrapper, module or
skill that only uses the app's names is left alone, units that are not this
app's left alone, and the teardown. With the git history at hand, they also
check that `bin/earlier-copies.json` is exactly what `scripts/earlier-copies`
derives from it. The gate also copies only the distributed files into
an empty home's plugins folder, as `omarchy plugin add` would, validates it,
and checks that its helper finds itself there.

## Live local verification

1. `omarchy plugin add` the repository (or `make dev` over an existing
   checkout), open the app, run the setup, and confirm the combined
   resident-service/bar plugin is loaded, `~/.local/bin/omawhatsapp` links
   into the checkout and `systemctl --user status wacli-sync.service` runs.
2. Confirm Settings → Background sync toggles online → offline → online, the
   rail status line appears only while offline or reconnecting, the service follows,
   and the local archive remains readable while offline.
3. Open with `Super+Shift+W`; switch between a direct message and a group.
   From the chat list, use J/K and Enter; verify focus lands in the composer and
   the next printable key is inserted without another click or shortcut. Press
   `/` from the list, type a chat query, then press Escape to return to J/K.
4. Click the bar item and verify the mini client is anchored to that item.
   Check J/K, arrows, `/` search, Escape, outside-click dismissal, entering a
   conversation, composer focus, demo sending, clipboard staging, and `O`
   expansion to the exact full-app chat. Use only demo mode for screenshots.
5. Verify chat search, conversation search, filters, keyboard navigation,
   image previews, animated GIF playback, video/audio controls, on-demand
   attachment download, attachment opening, per-chat draft preservation,
   `@` member completion, selection-to-copy, and its clipboard toast. With the
   message timeline focused, select a message with J/K and press `r` or `R`;
   verify its reply context opens and the composer receives focus. Confirm the
   same keys type normally while a text field owns focus.
6. With explicit microphone permission, press `Ctrl+Shift+V`, speak briefly,
   press it again, and confirm capture stops into a playable draft without a
   send. Verify Escape also stops into review, discard removes the draft, a
   failed/offline send keeps it, and the explicit send button is the only
   action that transmits it. Repeat once in the compact dropdown.
7. Review current-session logs for OmaWhatsApp QML errors.
8. Confirm automatic reading is on by default: opening a chat, a new message
   arriving in the open chat, and replying mark it read on the phone, while a
   chat marked unread from the list stays unread until chosen again.
   Clicking a message popup opens the reply view by the bar on that chat
   (or the full app when "Reply from the bar" is off).
   Middle-clicking the bar clears only the local notification badge.
   Right-clicking it mutes notifications: the OSD confirms, a crossed bell
   shows beside the count, no popup or sound arrives, and a second right-click
   unmutes without replaying the muted messages. Verify the settings switch
   with a mocked write.
9. Desktop notifications are on by default. Confirm the next incoming message
   pops up within about a second with the chat photo and one sound, that a photo
   reads "📷 Photo", that Omarchy's do not disturb keeps the sound quiet, that
   turning off Sound silences it, that popups contain no chat names, message text or photos,
   and that muted and archived chats stay silent. Check that the popup still
   arrives with the bar badge preference off, with every window closed, and for
   a chat already read on the phone, while the chat visibly on screen does not
   pop up. Without `notify-send` the setting explains that libnotify is needed.
10. With more than one account configured, confirm the rail merges them, each
   row names its account, the conversation subtitle names the open chat's account, the bar
   badge counts unread chats across every account, and a middle-click clears all of them. Confirm a
   send, a receipt, and the offline setting act only on the open chat's account,
   and that `systemctl --user list-units 'wacli-sync@*'` shows one instance per
   linked account. Exercise `All` and each account chip and confirm filtering
   never retargets the selected chat. Only with explicit permission, exercise
   `+` and complete or cancel its terminal QR flow.
11. In settings, click profile-photo refresh only with explicit remote-read permission.
   Confirm recent photos appear, fallbacks remain clear where no photo exists,
   and opening/searching chats does not itself trigger network work.
12. Only with explicit permission, send a meaningful text/image/voice note to a
   known chat. Never create a throwaway WhatsApp test message.
13. In demo mode, open settings and verify maintenance actions are disabled.
    The update tests cover the helper's `update-check` against a local git
    remote, opt-in launch checks, cancellation, copies that are not a checkout,
    and malformed results. Never run an actual downgrade just to test the
    update button.

## Screenshot

```bash
omarchy-shell io.github.moizibnyousaf.omawhatsapp closeApp
omarchy-shell io.github.moizibnyousaf.omawhatsapp openApp '{"demo":true}'
omarchy-shell io.github.moizibnyousaf.omawhatsapp openApp '{"demo":true,"viewer":true}'
omarchy-shell io.github.moizibnyousaf.omawhatsapp openApp '{"demo":true,"voice":true}'
```

Capture only that window. Never publish a real conversation timeline.

The screenshots in `docs/screenshots/` and the store banner `preview.png` are
rendered offscreen instead, so no other window can end up in them:
`qmltestrunner` loads `App.qml` or `Dropdown.qml` in demo mode with the stubs
from `tests/imports`, a Tokyo Night `Color` singleton, and the app window sized
to each layout, then saves `grabImage`. Demo chats are shown with initials,
since the photo mask needs a GPU that offscreen rendering lacks. Every image
comes from the repository's demo data.

## Agent server

`tests/test_mcp.py` drives the MCP server three ways. Protocol tests cover the
handshake, notifications, batches, schemas, and honest annotations. Tool tests
replace the helper with a recorder and check each of the 44 tools' request,
authorization class, and answer shape. End-to-end tests run the real server
and helper over a synthetic mirror and a fake wacli that records its
arguments, which proves the helper accepts every token the server sends and
that a guessed recipient never reaches wacli.

Live checks of the write tools use only a chat the owner names for the
purpose, with every text marked as a test, and undo what they create (a test
group is emptied and left, an alias and a tag are removed). Never run them
against other contacts.

## Store refresh regression

`tests/test_store_watcher.py` runs the event mask from the resident service against disposable SQLite databases and a real `inotifywait`. It checks that read-only queries settle without another refresh, both with and without a persistent WAL writer, while committed writes, checkpoints, atomic replacement, deletion, and rollback-journal commits still produce relevant events. Repeated write/read cycles must show fresh rows and then go quiet. These tests reproduce the feedback loop against the pre-0.13.1 mask without using a private chat store.

### Sidebar keyboard route

Using synthetic/demo chats, focus the sidebar (Esc back from the conversation)
and press Tab through All, Unread, To reply and Groups, then into chats. Verify
that each filter activates with a visible focus outline, J/K moves the chat
cursor, and Shift+Tab reverses the route. `/` opens search from either filters
or chats; typing there must not move chat selection. Include empty lists,
Archived when present, live unread-count updates, and a narrow rail with
overflowing filters; keyboard focus must stay visible and stable.
