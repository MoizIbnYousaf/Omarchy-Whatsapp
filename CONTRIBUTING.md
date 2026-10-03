# Contributing to OmaWhatsApp

OmaWhatsApp stays lean by keeping one narrow boundary: Quickshell owns the UI,
the helper reads the local mirror, and `wacli` owns every WhatsApp/network
write. Changes should preserve that split and avoid browser or Electron
runtimes.

## Develop

Install the app the way users do, then try changes on top of it:

```bash
omarchy plugin add https://github.com/MoizIbnYousaf/Omarchy-Whatsapp --enable
make dev                    # copy the working tree over the plugin checkout
./scripts/dev-sync --reset  # back to its commit before omarchy plugin update
```

`make dev` restarts the shell when QML changed, since the shell keeps QML it
already compiled; the helper and the skill are read fresh on every call.

## Before opening a pull request

```bash
./scripts/test
```

- Keep every write scoped to an exact locally indexed chat and, when relevant,
  message ID.
- Never add a real session, database, JID, phone number, message, media file, or
  conversation screenshot to a commit or issue.
- Use demo mode for UI evidence and include narrow plus wide coverage for layout
  changes.
- Update the parity, technical, or privacy docs when their contract
  changes.
- Explain any new runtime dependency. Browser and Electron dependencies are out
  of scope.

The full verification contract is in [docs/TESTING.md](docs/TESTING.md).

## Rules for every change

WhatsApp data is private, and this repository must never hold any of it:

- Never commit or attach session keys, databases (`wacli.db`, `session.db` and
  their WAL files), media, exports, JIDs, message IDs, phone numbers, message
  text, or screenshots of real conversations. Tests and screenshots use the
  repository's synthetic demo data only.
- Never read `session.db` or write directly to `wacli.db`; every WhatsApp change
  goes through wacli.
- Develop against a test account or a contact who agreed to it. Never send a
  test message or media to anyone else.
- A send must resolve to an exact chat already in the local `chats` table before
  wacli is called.
- Long history or media maintenance stays apart from the interactive send path
  and always restarts background sync when it ends, even on failure.
- Keep `skills/omawhatsapp` in step with the helper's public JSON commands; the
  skill must never widen what an agent may change on WhatsApp.

The paths the app uses at runtime are listed in
[docs/TECHNICAL.md](docs/TECHNICAL.md#runtime-paths).

## Commit and pull request titles

This project follows [Conventional Commits](https://www.conventionalcommits.org).
Pull requests are squash-merged, so the pull request title becomes the commit
on `main`; use this form:

```text
<type>(<optional scope>): <what changes, in the imperative>

feat(accounts): mute notifications per account
fix(dropdown): make the Clear button clear the badge
docs: explain the richer wacli builds
```

| Type | Use it for | Next version |
|---|---|---|
| `feat` | Something new a user can do or see | minor |
| `fix` | A bug fix | patch |
| `perf` | Faster or lighter, same behavior | patch |
| `revert` | Undoing an earlier change | patch |
| `docs` | Documentation only | none |
| `refactor`, `test`, `build`, `ci`, `chore` | Everything else | none |

Mark a breaking change with `!` after the type (`feat!: …`) or a
`BREAKING CHANGE:` footer. Scopes are optional; the usual ones are `app`,
`dropdown`, `bar`, `settings`, `accounts`, `helper`, `setup`, `mcp` and
`skill`. Write titles and commit messages in English.

## Versions and releases

Versions follow [Semantic Versioning](https://semver.org):
`MAJOR.MINOR.PATCH`.

- **MAJOR**: an update that needs more than `omarchy plugin update`, such as
  a raised wacli minimum, a manual migration, or removing a setting, command or
  IPC call that users rely on. While the version is below 1.0, these raise the
  minor number instead.
- **MINOR**: new features that keep existing setups working.
- **PATCH**: fixes and performance.

The version lives in `manifest.json` and `HELPER_VERSION` in
`bin/omawhatsapp_core.py`; `./scripts/test` fails if they disagree.
Update both together with `CHANGELOG.md`, validate the final commit in CI,
then tag and publish its GitHub release.
