import Foundation

/// CRIVID FORK (not upstream): a live source that answered 404 or 410 before a single byte arrived.
///
/// A raw live source that is gone publishes the same `.liveSourceUnavailable` as one that is merely
/// slow, so a host cannot tell "the channel does not exist" from "try another player". The host's
/// answer to the first is to show the failure, not to hand the URL to a second player: a 404 does not
/// get better with another engine, and on tvOS the second player (VLCKit) could hang the main thread
/// tearing down its HTTP/2 connection to such an origin (measured 04.11).
///
/// Keyed by the exact URL the reader was given, not by origin: one dead channel says nothing about
/// the other channels on the same panel. 403 is left out on purpose, a capped Xtream panel answers
/// 403 to a fresh connection that a moment later gets 200.
public enum CrividDeadSource {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var seen: [String: (status: Int, at: Date)] = [:]  // guarded by `lock`

    /// The statuses that mean "this resource does not exist".
    public static func isDeadStatus(_ status: Int) -> Bool { status == 404 || status == 410 }

    /// Called by the reader at the first 404/410 at byte 0 of a live source, and again when it gives up
    /// with no bytes read.
    public static func note(_ url: URL, status: Int, at date: Date = Date()) {
        guard isDeadStatus(status) else { return }
        lock.lock(); defer { lock.unlock() }
        seen[url.absoluteString] = (status, date)
        if seen.count > 64 {
            // Bounded: drop the oldest, a host asks within seconds of the failure.
            if let oldest = seen.min(by: { $0.value.at < $1.value.at })?.key { seen[oldest] = nil }
        }
    }

    /// The dead status `url` answered within `seconds` before `now`, if any.
    public static func recentStatus(for url: URL, within seconds: TimeInterval, now: Date = Date()) -> Int? {
        lock.lock(); defer { lock.unlock() }
        guard let hit = seen[url.absoluteString], now.timeIntervalSince(hit.at) <= seconds,
              now >= hit.at else { return nil }
        return hit.status
    }

    /// Called by the reader when a live answer for `url` is accepted: the channel is there after all.
    public static func clear(_ url: URL) {
        lock.lock(); defer { lock.unlock() }
        seen[url.absoluteString] = nil
    }

    /// Test seam.
    public static func reset() { lock.lock(); seen = [:]; lock.unlock() }
}
