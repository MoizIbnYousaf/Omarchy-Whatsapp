# Testing

## Release gate

```bash
./scripts/test
```

The unit suite verifies focused DM/standalone-group listing, exclusion of
channels and Communities, single-line previews, literal search, strict
conversation boundaries, media metadata, outgoing-media handoff and album
identity, target validation, bounded messages, group-member mention scoping,
local notification acknowledgement, explicit receipt commands, persistent
offline write blocking, muted/archive badge suppression, mute-deadline
normalization, and the lock-free live-delegate path. The release script
also runs an isolated, read-only install preflight—including the bundled agent
skill safety contract—before the offscreen QML tests.

## Live local verification

1. Install/restart the shell and confirm the combined `omawhatsapp`
   service/panel/bar plugin is loaded.
2. Confirm the header toggles online → offline → online, the service follows,
   and the local archive remains readable while offline.
3. Open with `Super+Shift+W`; switch between a direct message and a group.
4. Verify chat search, conversation search, filters, keyboard navigation,
   image previews, animated GIF playback, video/audio controls, on-demand
   attachment download, attachment opening, per-chat draft preservation,
   `@` member completion, selection-to-copy, and its clipboard toast.
5. Review current-session logs for OmaWhatsApp QML errors.
6. Confirm opening a chat and middle-clicking the bar clear only the local
   notification badge. Test the real read receipt only with explicit permission.
7. Only with explicit permission, send a meaningful text/image to a known chat.

## Screenshot

```bash
omarchy-shell shell hide io.github.moizibnyousaf.omawhatsapp
omarchy-shell shell toggle io.github.moizibnyousaf.omawhatsapp '{"demo":true}'
omarchy-shell shell toggle io.github.moizibnyousaf.omawhatsapp '{"demo":true,"viewer":true}'
```

Capture only that window. Never publish a real conversation timeline.
