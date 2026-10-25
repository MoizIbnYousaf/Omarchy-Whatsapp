# Private wacli input extension

The application uses wacli 0.19.0 built from pinned upstream source
(`b87e6178b7b1e571ce2821ab516039cfa0c6ecf6`) with three patches from this
directory, applied in this order:

1. `wacli-private-input.patch`: private stdin argument transport and the
   group-name fallback, maintained by OmaWhatsApp.
2. `wacli-send-queue.patch`: an exact, unmodified backport of upstream
   commit `7c1b3bfbeb26b929ca60e3cbae1511ad9c58a02d` (#456, released in wacli
   v0.20.0) by Tsavo Knott, with co-authors Peter Steinberger and Claude.
3. `wacli-omawhatsapp-outcomes.patch`: small OmaWhatsApp-specific changes on
   top of the backport, described [below](#omawhatsapp-outcomes).

The combined build is extension `omawhatsapp.3`. It is an OmaWhatsApp-maintained
extension, not an official upstream release. Upstream source and its MIT license
remain at https://github.com/openclaw/wacli.

`wacli --private-args-version` returns
`{"protocol":1,"max_bytes":65536,"build":"omawhatsapp.3"}`. Earlier private
builds return the same object without `build`; the app accepts both and shows
the label, when present, under Settings → About.
`wacli --private-args-stdin` accepts one UTF-8 JSON array of arguments over stdin,
with a 64 KiB limit, 256 arguments and a three-second input deadline. The process
command line contains no message, caption, recipient or other payload. Normal
CLI parsing, account selection, authorization and locking still apply after
input decoding. Private-mode errors are sanitized: the typed store-lock error is
preserved so the app's existing pre-dispatch lock handoff remains available, and
two fixed outcome messages say whether a failed request was sent (see below).
The extension adds no send retries. Normal upstream command syntax stays available.

## Build and install

Run these commands on the target Linux machine from the OmaWhatsApp checkout
you reviewed. The bundled patches and builder are part of that checkout; review
changes to them before updating. Prerequisites are Git, Python 3.12 or newer,
Go 1.27.1 or newer, a C compiler and the upstream build prerequisites. Dependency
modules are verified by Go against upstream's committed `go.sum`; do not disable
that verification.

```bash
# Keep all build files separate from any linked-device state or existing binary.
set -euo pipefail
build_dir=$(mktemp -d)
trap 'rm -rf -- "$build_dir"' EXIT
git clone https://github.com/openclaw/wacli.git "$build_dir/source"
git -C "$build_dir/source" checkout --detach b87e6178b7b1e571ce2821ab516039cfa0c6ecf6
python3 ./scripts/build-private-wacli "$build_dir/source" "$build_dir/wacli" --test
"$build_dir/wacli" --private-args-version
# Expected JSON: {"protocol":1,"max_bytes":65536,"build":"omawhatsapp.3"}
mkdir -p "$HOME/.local/bin"
install -m 755 "$build_dir/wacli" "$HOME/.local/bin/wacli"
# A running sync keeps the old binary's send queue until it restarts.
systemctl --user restart wacli-sync.service
```

With named accounts, also restart each `wacli-sync@<account>.service` that is
running (`systemctl --user list-units 'wacli-sync@*'` lists them). Until sync
restarts, it keeps the previous build's queue: a queued send can still go out
after the app reported it as timed out.

The builder refuses a different upstream HEAD and exports only committed source
(ignoring working-tree edits). It reads each patch once, records the SHA256 of
exactly those bytes, and applies them in order through `git apply` on stdin with
no enclosing repository, failing if any file is skipped or a patch's sentinel is
missing. It then runs plain/FTS tests, a `-race` run of the queue, read-mark and
outcome tests and Go vet, builds locally, and checks the protocol and build label
before producing the output. It does not install anything or start WhatsApp.
Installation happens only in the final explicit commands after a successful
build. No account relinking or store migration is needed.

## Verify the upstream backport

Everything in `wacli-send-queue.patch` from its first `diff --git` line onward
is byte-for-byte the output of

```bash
git diff b87e6178 7c1b3bfb -- cmd/wacli
```

in a clone of https://github.com/openclaw/wacli with git's default diff
settings. The lines above it are a header that `git apply` ignores. A personal
`diff.algorithm` or prefix setting changes the layout, so compare with the
user configuration switched off:

```bash
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
  git -C wacli diff b87e6178 7c1b3bfb -- cmd/wacli \
  | cmp - <(sed -n '/^diff --git /,$p' dependencies/wacli-send-queue.patch)
```

Upstream's `CHANGELOG.md` and `docs/sync.md` hunks from that commit are not
included. Upgrading the pinned base to wacli 0.20.0 or later would make this
patch unnecessary.

## Build evidence and historical binaries

The supported route is the local source build above. Earlier release archives
are historical artifacts, not supported installation candidates: a release's
own provenance JSON and pinned binary hash do not independently prove which
source produced it. There is no prebuilt installer in this release.

Pass `--provenance build-evidence.json` to the builder to record the exact
upstream commit, source archive SHA256, each patch's SHA256
(`patch_sha256` for the private input patch, `send_queue_patch_sha256` for the
upstream backport, `outcomes_patch_sha256` for the OmaWhatsApp outcomes), the
extension label, Go/compiler versions, build flags and resulting executable
SHA256. CI runs the same builder and publishes this evidence in its log and
build summary. Output hashes from different toolchains are not assumed equal,
and this evidence does not attest to the older distributed binary. CI does not
publish an installable binary.

The app refuses sensitive commands when this protocol is unavailable, before
passing any private content to a child. Direct local SQLite reads still work with older versions; sensitive external
reads and terminal authentication require private input too. Never substitute an unsafe argv fallback.

The private input patch's group-name fallback preserves an existing cached
subject when metadata is temporarily unavailable, rather than substituting the
current participant's push name. The app independently prefers the groups
table's subject. Protocol version remains 1. Builds made before 0.19.0 of
OmaWhatsApp (extensions `omawhatsapp.1` and `omawhatsapp.2`) keep working; build
and install `omawhatsapp.3` for the send-queue and outcome fixes.

## Interactive send queue

The upstream backport (#456) puts every delegated operation behind one send
slot whose wait is bounded by the caller's deadline, paced or not. A request
still queued when that deadline arrives is refused with "it was not sent" and
is never dispatched later; a reply margin lets the refusal arrive before the
caller gives up.

The app passes each operation's budget to wacli as `--timeout`, in whole
milliseconds and slightly below the helper's own limit (a tenth of the budget,
from 0.5 to 5 seconds, at most half), so wacli answers before the helper stops
it. The helper's hard limit stays exactly the caller's budget, including the
2-second total for inline mention lookups. Protocol version, account selection
and private stdin transport are unchanged.

## OmaWhatsApp outcomes

`wacli-omawhatsapp-outcomes.patch` holds only changes specific to OmaWhatsApp.
Its header justifies each one:

- **App-state read marks bypass the send slot.** `chats mark-read` and
  `chats mark-unread` without `--receipts` can wait minutes on app-state
  recovery. wacli already serializes them on its own chat-state slot, so in the
  send slot they only held up interactive sends. Receipt-mode read marks never
  enter recovery and stay serialized and paced in the send slot, as upstream
  keeps them. The bypass follows upstream's own app-state bypass (bb80227, #454).
  A read mark can now overlap a reconnect started by a failed send; it then
  fails like any other read-mark failure: the app shows the error, the chat
  keeps its stored read state, and marking it again works. Contributed by
  Brunno Vert (#28).
- **Fixed private-mode outcomes.** Private input replaces every error with
  "Private WhatsApp command failed.", which hid upstream's "it was not sent" and
  "may still have gone through" reports. The daemon's exact pre-dispatch
  refusals now print "Private WhatsApp command was not sent."; a request that
  failed after dispatch at its deadline, an unanswered delegate and any other
  deadline print "Private WhatsApp command outcome is unknown." Both strings are
  fixed: no socket path, wrapped error, identifier or content is printed.
- **A send attempt's own deadline is uncertain.** wacli cuts each send attempt at
  45 seconds. File, voice and sticker sends get 120 seconds, so an attempt could
  expire after its message frame was written while the request was still live;
  upstream reported that as a definite failure. Its text is unchanged, but it now
  counts as a deadline and is reported as uncertain.
- **Build label.** `--private-args-version` adds `"build":"omawhatsapp.3"`.

What the app shows:

| wacli reports | App result | Retry |
| --- | --- | --- |
| "…was not sent." | "WhatsApp was busy with an earlier request, so this was not sent. You can try again." (`outcome: "not-sent"`) | Safe; only on the user's request |
| "…outcome is unknown.", or a generic failure at or after wacli's own deadline (older builds) | "WhatsApp did not confirm this in time. It may still have gone through, so check before trying again." (`outcome: "uncertain"`); reads keep "WhatsApp took too long to respond." | Never automatic |
| Any other failure | The generic failure, as before | Only on the user's request |

The uncertain outcome is reported when the caller's deadline, or a single send
attempt's 45-second deadline, expires after dispatch, and when the sync process
never answers. A failed send bubble then says it may have been sent, and Try
again stays an explicit choice. An older private build reports only the generic
failure; the app treats it as uncertain when it arrives at or after wacli's
deadline, so its result is never less cautious than before.
