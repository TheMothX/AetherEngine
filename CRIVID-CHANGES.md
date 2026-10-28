# Modified by Crivid AS

This is AetherEngine 7.15.1 (upstream: https://github.com/superuser404notfound/AetherEngine,
tag 7.15.1, b93f9c4b) with one change made by Crivid AS for the Crivid IPTV Player on tvOS.
It is distributed under the same license as upstream (LGPL-3.0 with the App Store exception,
see LICENSE).

## Change

`Sources/AetherEngine/Demuxer/AVIOReader.swift`, `persistentReceivedResponse` and the new
`isLiveTextRefusal`:

An Xtream panel at its connection cap answers HTTP 200 with a short text body
("CONNECTION LIMIT REACHED / This account is already streaming on another device").
On a live source the reader took those bytes as media, the connection ended, the reconnect
ladder saw progress and asked again at once: 436 requests in 10 s against a test origin that
held the slot for 10 s. A live 200/206 response with `Content-Type: text/*` and a
`Content-Length` of at most 64 KiB is now treated as the 509 the engine already handles for
connection-capped panels (metered pacing, Retry-After, bounded give-up), and its body never
reaches the window. A text response without such a length is kept as a stream and logged.

All changes are marked `CRIVID FORK` in the source.
