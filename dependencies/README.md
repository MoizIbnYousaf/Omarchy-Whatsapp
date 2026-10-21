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

## Build and install

Run these commands on the target Linux machine from the OmaWhatsApp checkout
you reviewed. The bundled patch and builder are part of that checkout; review
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
# Expected JSON: {"protocol":1,"max_bytes":65536}
mkdir -p "$HOME/.local/bin"
install -m 755 "$build_dir/wacli" "$HOME/.local/bin/wacli"
```

The builder refuses a different upstream HEAD, exports only committed source
(ignoring working-tree edits), applies only the bundled patch, runs plain/FTS
tests and Go vet, builds locally, and checks the protocol before producing the
output. It does not install anything or start WhatsApp. Installation happens
only in the final explicit commands after a successful build. No account
relinking or store migration is needed.

## Build evidence and historical binaries

The supported route is the local source build above. Earlier release archives
are historical artifacts, not supported installation candidates: a release's
own provenance JSON and pinned binary hash do not independently prove which
source produced it. There is no prebuilt installer in this release.

Pass `--provenance build-evidence.json` to the builder to record the exact
upstream commit, source archive SHA256, bundled patch SHA256, Go/compiler
versions, build flags and resulting executable SHA256. CI runs the same builder
and publishes this evidence in its log and build summary. Output hashes from
different toolchains are not assumed equal, and this evidence does not attest
to the older distributed binary. CI does not publish an installable binary.

The app refuses sensitive commands when this protocol is unavailable, before
passing any private content to a child. Direct local SQLite reads still work with older versions; sensitive external
reads and terminal authentication require private input too. Never substitute an unsafe argv fallback.

The bundled patch is extension `omawhatsapp.2`. Its group-name fallback preserves
an existing cached subject when metadata is temporarily unavailable, rather than
substituting the current participant's push name. The app independently prefers
the groups table's subject. Protocol version remains 1; existing private-input
binaries protect reads, but build and install the .2 extension for the sync-name correction.
