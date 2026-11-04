# Modified by Crivid AS

This is AetherEngine 7.15.1 (upstream: https://github.com/superuser404notfound/AetherEngine,
tag 7.15.1, b93f9c4b) with four changes made by Crivid AS for the Crivid IPTV Player on tvOS.
It is distributed under the same license as upstream (LGPL-3.0 with the App Store exception,
see LICENSE).

## Changes

### 1. A connection-cap refusal is a refusal (29 October 2026)

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

### 2. The host can ask what the origin last refused with (29 October 2026)

`Sources/AetherEngine/Demuxer/OriginRequestBudget.swift` (`lastRefusalStatus`,
`recentRefusalStatus`) and the new `Sources/AetherEngine/AetherEngine+CrividOriginRefusal.swift`
(`AetherEngine.recentOriginRefusal(for:within:)`):

A raw live source that is refused publishes `.liveSourceUnavailable` at the open and a bare
`liveSourceReset` mid-session, so the host cannot tell an account at its connection cap from a
dead channel. The budget already stamps every 429/503/509; it now keeps the status with the
stamp, and a public static function returns it when it is recent. The Crivid player uses it to
tell the user the account is in use on another device instead of handing the stream to a second
player that the same panel refuses.

### 3. The host can ask how often a live source was cut and refused (29 October 2026, revised 30 October 2026)

`Sources/AetherEngine/Demuxer/AVIOReader.swift` (`isLiveDenialStatus` and the calls to
`noteLiveDenial` and `noteLiveAccepted` in `persistentReceivedResponse`),
`Sources/AetherEngine/Demuxer/OriginRequestBudget.swift` (`liveDenials`, `liveDenialPending`,
`noteLiveDenial`, `noteLiveAccepted`, `liveDenialCount`) and
`Sources/AetherEngine/AetherEngine+CrividOriginRefusal.swift` (`AetherEngine.recentLiveDenials(for:within:)`):

Measured on an Apple TV against an Xtream panel at its connection cap: the panel cuts the newest
connection with a clean end every 11-44 s, refuses the reconnect with 403 and accepts the one 1-2 s
later. The engine recovers in about a second, so nothing shows on screen while the other devices on the
account stall, and the accepted answer clears the refusal change 2 reads. The budget now counts live
refusal rounds, a 403/429/509 on a live source followed by an accepted live answer, stamped at the
accept, and a public static function returns how many fell within a window. One outage with several
refusals in a row is one round. The Crivid player tells the user the account is in use after three
rounds within 120 s of the channel showing a picture.

### 4. The host can ask whether a live source answered "not found" (4 November 2026)

`Sources/AetherEngine/Demuxer/AVIOReader.swift` (calls to `CrividDeadSource.note` in
`persistentReceivedResponse` at the first 404/410 at byte 0 and where `readPersistent` gives up, and to
`CrividDeadSource.clear` when a live answer is accepted, each only for the reader's current connection
and while it is open) and the new `Sources/AetherEngine/AetherEngine+CrividDeadSource.swift`
(`CrividDeadSource`):

A live source that answers 404 or 410 before a single byte arrives publishes the same failure as one
that is slow, so the host cannot tell a channel that does not exist from one worth handing to another
player. The reader now stamps the exact URL with that status at the first such answer at byte 0 and when it
gives up on a live source with nothing read, clears the stamp when a live answer is accepted, and the
host can ask for it within a window. 403 is left out, an Xtream panel at its cap
answers 403 to a fresh connection that is accepted moments later. The Crivid player uses it to skip its
second player for such a channel. Accepted cost: one 404/410 at byte 0 with no accepted answer after it is
enough, also when later attempts answer something else. The tests are in
`Tests/AetherEngineTests/CrividDeadSourceTests.swift`.

All changes are marked `CRIVID FORK` in the source.
