import Foundation

/// CRIVID FORK (not upstream): what a raw live source was last refused with.
///
/// A live raw TS source that is refused publishes `.liveSourceUnavailable` at the open and a bare
/// `liveSourceReset` mid-session, neither carrying `sourceRateLimited`, so a host cannot tell an
/// account at its connection cap from a dead channel. The reader stamps every 429/503/509 (and the
/// text refusal `isLiveTextRefusal` turns into a 509) in the shared budget; this reads that stamp.
/// The answer for a cap is to wait or tell the user, not to hand the URL to a second player, which
/// the same panel refuses.
extension AetherEngine {
    /// The HTTP status the origin of `url` last refused a request with, if that was within `seconds`.
    public static func recentOriginRefusal(for url: URL, within seconds: TimeInterval) -> Int? {
        OriginRequestBudget.shared.recentRefusalStatus(url, within: seconds)
    }
}
