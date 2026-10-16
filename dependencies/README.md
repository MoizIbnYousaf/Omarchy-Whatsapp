# Private wacli input extension

The application uses wacli 0.19.0 plus the small `wacli-private-input.patch` in
this directory. Upstream base: `b87e6178b7b1e571ce2821ab516039cfa0c6ecf6`.
This is an OmaWhatsApp-maintained extension, not an official upstream release.
Upstream source and its MIT license remain at https://github.com/openclaw/wacli.

`wacli --private-args-version` returns `{ "protocol": 1, "max_bytes": 65536 }`.
`wacli --private-args-stdin` accepts one UTF-8 JSON array of arguments over stdin,
with a 64 KiB limit, 256 arguments and a three-second input deadline. The process
command line contains no message, caption, recipient or other payload. Normal
CLI parsing, account selection, authorization and locking still apply after
input decoding. Private-mode errors are sanitized; the typed store-lock error
is preserved so the app's existing pre-dispatch lock handoff remains available.
The extension adds no send retries. Normal upstream command syntax stays available.

To reproduce the Linux binary, check out the exact upstream base above, then run
`./scripts/build-private-wacli /path/to/wacli /tmp/wacli-private --test`.
The builder exports only committed upstream source and applies only the bundled
patch. It neither downloads source nor installs a binary or starts WhatsApp.
Use Go 1.27.1 or newer, a C compiler and the upstream build prerequisites.

The app refuses mutation commands when this protocol is unavailable, before
passing any private content to a child. Existing local reads still work with
older supported wacli versions. Never substitute an unsafe argv fallback.
