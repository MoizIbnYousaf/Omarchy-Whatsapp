# Testing

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
demo isolation, explicit receipt commands, persistent
offline write blocking, muted/archive badge suppression, mute-deadline
normalization, the lock-free live-delegate path, exact coverage of all 103
wacli 0.17.1 command leaves, authorization-class enforcement, global-flag
isolation, dry-run downgrades, interactive restrictions, and a fake-wacli
end-to-end JSON invocation. The release script
also runs an isolated, read-only install preflight—including the bundled agent
skill safety contract—and compares the shipped registry with the installed
wacli help tree before the offscreen QML tests.

## Live local verification

1. Install/restart the shell and confirm the combined `omawhatsapp`
   resident-service/bar plugin is loaded.
2. Confirm the header toggles online → offline → online, the service follows,
   and the local archive remains readable while offline.
3. Open with `Super+Shift+W`; switch between a direct message and a group.
   From the chat list, use J/K and Enter; verify focus lands in the composer and
   the next printable key is inserted without another click or shortcut.
4. Click the bar item and verify the mini client is anchored to that item.
   Check J/K, arrows, `/` search, Escape, outside-click dismissal, entering a
   conversation, composer focus, demo sending, clipboard staging, and `O`
   expansion to the exact full-app chat. Use only demo mode for screenshots.
5. Verify chat search, conversation search, filters, keyboard navigation,
   image previews, animated GIF playback, video/audio controls, on-demand
   attachment download, attachment opening, per-chat draft preservation,
   `@` member completion, selection-to-copy, and its clipboard toast.
6. Review current-session logs for OmaWhatsApp QML errors.
7. Confirm private reading is on by default, and opening a chat or
   middle-clicking the bar clears only the local notification badge. Verify the
   settings switch with a mocked write; test a real receipt only with explicit
   permission.
8. Turn the header pill to `notify` and confirm the next incoming message
   pops up once, that right-clicking the pill drops the preview to chat names,
   and that muted and archived chats stay silent. Check that the popup still
   arrives with the bar badge preference off, with every window closed, and for
   a chat already read on the phone, while the chat visibly on screen does not
   pop up. Without `notify-send` the pill reports `unavailable`.
9. Only with explicit permission, send a meaningful text/image to a known chat.

## Screenshot

```bash
omarchy-shell io.github.moizibnyousaf.omawhatsapp closeApp
omarchy-shell io.github.moizibnyousaf.omawhatsapp openApp '{"demo":true}'
omarchy-shell io.github.moizibnyousaf.omawhatsapp openApp '{"demo":true,"viewer":true}'
```

Capture only that window. Never publish a real conversation timeline.
