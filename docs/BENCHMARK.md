# Local benchmark

Measured on the project XPS on 2026-08-24 with the installed production
helper, an authenticated local store, and the background sync service already
warm. These are reproducible local-path measurements, not marketing estimates.

## Snapshot

| Measurement | Result |
|---|---:|
| Load 217 supported chats, median / p95 (100 runs) | 64.79 / 68.91 ms |
| Load 160 messages, median / p95 (100 runs) | 66.55 / 71.20 ms |
| Local `status`, median / p95 (100 runs) | 78.36 / 83.86 ms |
| Local `status` min–max | 63.29–100.62 ms |
| Installed QML/source tree | 160,936 bytes |
| Helper script | 52,516 bytes |
| Warm `wacli sync --follow` RSS | 29,672 KiB |
| Browser/Electron runtime | none |

The opening path reads only local state. Its first paint does not wait for a
WhatsApp connection or media download. Quickshell RSS is intentionally not
reported as “app memory”: OmaWhatsApp shares the already-running Omarchy shell,
so attributing the whole shell process to one plugin would be misleading.

## Reproduce

```bash
./scripts/benchmark 100
du -sb plugins/omawhatsapp bin/omawhatsapp
pid=$(systemctl --user show wacli-sync.service -p MainPID --value)
ps -o rss= -p "$pid"
```

`scripts/benchmark` records only timings and row counts from successful bounded
helper calls. It never prints chat identifiers or conversation text, and it
performs no WhatsApp write.
