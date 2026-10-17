# Media decoder boundaries

## Findings and coverage

| Finding / related path | Prevention | Regression evidence |
| --- | --- | --- |
| Incoming PNG documents expand compressed text before pixel limits (HANCORE-linux, marketplace #10728) | Drop all PNG ancillary chunks except palette transparency, then decode in a separate limited process. The shell receives raw RGBA, never the PNG. | Valid one-pixel PNG with 192 separate 1-MiB compressed text chunks; ordinary Qt probe exhausts its 384-MiB limit, worker returns four pixel bytes. |
| The same decoder serves photos, albums, avatars, outgoing attachments, media browser/viewer, GIFs and stickers | All image surfaces use SafeImage/SafeAnimatedImage. Only the worker contains QImageReader. | Source inventory, static/multiframe tests, malformed media, cancellation, rapid source replacement and concurrent image loads. |
| Other image formats may contain huge metadata, frames, dimensions, or expensive decoding | Explicit PNG/JPEG/GIF/WebP/BMP allowlist. Per-process address/CPU/wall limits, input/pixel/frame limits, bounded raw output, aggregate display budget. SVG and unknown formats fail closed. | Oversized dimensions and input, FIFO, unsupported vectors, live resource limits, forged output, excessive stdout, stalled/crashed worker, aggregate budget pressure. |
| Qt multimedia can parse image artwork or other metadata in original audio/video containers | Limited FFmpeg worker decodes/re-encodes selected audio/video streams without source metadata, chapters, subtitles, data or attached artwork. Qt only opens the generated preview. | Regenerated audio/video playback, explicit stream/container/protocol policy and inventory guard against direct MediaPlayer usage. |
| Notifications could reopen remote avatar images in the shared desktop | Notifications already use a fixed application icon and generic text. No avatar is passed to the daemon. | Existing notification privacy suite and fixed-icon inventory regression. |

## Enforced limits and behavior

- Image workers: at most two concurrent jobs; each has a 384-MiB address-space limit, five CPU seconds and six wall seconds. The parent also enforces a seven-second deadline. A bounded queue holds at most 128 pending jobs; image requests expire after ten seconds waiting for a worker (media requests after seventy).
- Images: at most 64 MiB input, 32 megapixels declared size (Qt's additional 96-MiB allocation limit applies), 1,000 animation frames, and 1,024 pixels per rendered edge. Only one bounded raw frame per request reaches the shell. Animation advances on the event loop and stops when hidden or paused.
- The shell retains at most 32 MiB of decoded image pixels across all these controls. Worker failures, malformed replies or budget exhaustion show an unavailable state; no original-file fallback exists.
- Audio/video: one concurrent worker, 512-MiB address space, 30 CPU seconds, 60 wall seconds, 512-MiB input and 128-MiB output. No duration-based truncation: a worker killed by a limit fails the entire preview. Source container/protocol allowlists exclude network and playlist inputs. Video is regenerated at no more than 1280×720 and 24 fps; audio is 48-kHz stereo. Original files remain unchanged for saving/opening explicitly.
- Media previews use private anonymous memory files, capped at 128 MiB total retained output. They disappear on source replacement/destruction or process exit; no decoded disk cache is created.
- Workers disable core dumps, set no-new-privileges and die with their parent. Arguments contain no source filenames; requests use bounded stdin. Decoder diagnostics are discarded rather than copied to UI or logs. A missing compiler/worker or missing FFmpeg fails closed.

This is a resource boundary, not a general-purpose sandbox or a guarantee that
codecs have no vulnerabilities. Explicitly opening the original in another
application transfers decoding to that application. Future decoder/library
upgrades still require review and the regression suite.

## Developer verification

Run `./scripts/test`. All hostile fixtures are generated locally from synthetic
bytes and run only in offscreen/disposable test processes. Never reproduce a
metadata bomb by opening it in the live shared shell with ordinary Image.
`tests/png_metadata_probe.cpp` is the intentionally unguarded comparison probe;
it sets resource limits before constructing Qt and is never installed.
