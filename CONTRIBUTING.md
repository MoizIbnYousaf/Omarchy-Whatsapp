# Contributing to OmaWhatsApp

OmaWhatsApp stays lean by keeping one narrow boundary: Quickshell owns the UI,
the helper reads the local mirror, and `wacli` owns every WhatsApp/network
write. Changes should preserve that split and avoid browser or Electron
runtimes.

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
