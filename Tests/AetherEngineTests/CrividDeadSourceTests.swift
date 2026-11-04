// CRIVID FORK, change 4 (CRIVID-CHANGES.md): a live source that answers 404/410 at byte 0 is stamped
// for its exact URL, so the host can tell "the channel does not exist" from "try another player".
// Measured 04.11.2026 on an Apple TV against an Xtream panel: without it the host handed such a channel
// to VLCKit, whose HTTP/2 teardown hung and took the main thread with it.
//
// These tests drive the reader against a scripted loopback origin, so the wiring in AVIOReader is
// covered, not only the store.
import Foundation
import Testing
@testable import AetherEngine

@Suite("CRIVID FORK: a live source that answered not found is stamped", .serialized)
struct CrividDeadSourceTests {

    private static func url(_ server: ScriptedOriginServer, _ name: String) -> URL {
        URL(string: "http://127.0.0.1:\(server.port)/live/u/p/\(name).ts")!
    }

    /// Opens and reads until the reader gives up or `seconds` pass. The reader may throw at open or
    /// return an error from read; both are fine here, the stamp is what is measured.
    private static func drive(_ reader: AVIOReader, seconds: Double = 8) {
        _ = try? reader.open()
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 64 * 1024)
        defer { buf.deallocate() }
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            let n = reader.read(into: buf, size: 64 * 1024)
            if n <= 0 { break }
        }
    }

    private static func waitForStamp(_ u: URL, seconds: Double = 3) async -> Int? {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if let s = CrividDeadSource.recentStatus(for: u, within: 120) { return s }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return CrividDeadSource.recentStatus(for: u, within: 120)
    }

    @Test("a live 404 at byte 0 is stamped with 404")
    func live404IsStamped() async throws {
        CrividDeadSource.reset()
        let server = try #require(ScriptedOriginServer { _ in .init(status: 404, declaredLength: 32, bodyBytes: 32) })
        defer { server.stop() }
        let u = Self.url(server, "404")
        let reader = AVIOReader(url: u, isLive: true)
        defer { reader.markClosed(); reader.close() }
        Self.drive(reader)
        #expect(await Self.waitForStamp(u) == 404)
    }

    /// Opus 04.11, MEDIUM 1: the host's open watchdog can fire before the reader gives up, so the stamp
    /// must be there at the first answer. Nothing is read here, so the give-up path never runs.
    @Test("the stamp is there at the first answer, before the reader gives up")
    func stampedAtTheFirstAnswer() async throws {
        CrividDeadSource.reset()
        let server = try #require(ScriptedOriginServer { _ in .init(status: 404, declaredLength: 0) })
        defer { server.stop() }
        let u = Self.url(server, "first")
        let reader = AVIOReader(url: u, isLive: true)
        defer { reader.markClosed(); reader.close() }
        _ = try? reader.open()
        #expect(await Self.waitForStamp(u, seconds: 2) == 404)
    }

    @Test("a live 410 at byte 0 is stamped with 410")
    func live410IsStamped() async throws {
        CrividDeadSource.reset()
        let server = try #require(ScriptedOriginServer { _ in .init(status: 410, declaredLength: 0) })
        defer { server.stop() }
        let u = Self.url(server, "410")
        let reader = AVIOReader(url: u, isLive: true)
        defer { reader.markClosed(); reader.close() }
        Self.drive(reader)
        #expect(await Self.waitForStamp(u) == 410)
    }

    @Test("a live 403 (an Xtream panel at its cap) is not stamped")
    func live403IsNotStamped() async throws {
        CrividDeadSource.reset()
        let server = try #require(ScriptedOriginServer { _ in .init(status: 403, declaredLength: 0) })
        defer { server.stop() }
        let u = Self.url(server, "403")
        let reader = AVIOReader(url: u, isLive: true)
        defer { reader.markClosed(); reader.close() }
        Self.drive(reader)
        #expect(await Self.waitForStamp(u, seconds: 1) == nil)
    }

    @Test("a 404 on a source that is not live is not stamped")
    func vod404IsNotStamped() async throws {
        CrividDeadSource.reset()
        let server = try #require(ScriptedOriginServer { _ in .init(status: 404, declaredLength: 0) })
        defer { server.stop() }
        let u = Self.url(server, "vod404")
        let reader = AVIOReader(url: u, isLive: false)
        defer { reader.markClosed(); reader.close() }
        Self.drive(reader, seconds: 3)
        #expect(await Self.waitForStamp(u, seconds: 1) == nil)
    }

    @Test("a 404 followed by an accepted live answer leaves no stamp")
    func acceptedAnswerClearsTheStamp() async throws {
        CrividDeadSource.reset()
        let count = Counter()
        let server = try #require(ScriptedOriginServer { _ in
            count.next() == 1 ? .init(status: 404, declaredLength: 0)
                              : .init(status: 200, declaredLength: nil, bodyBytes: 512 * 1024, close: true)
        })
        defer { server.stop() }
        let u = Self.url(server, "flap")
        let reader = AVIOReader(url: u, isLive: true)
        defer { reader.markClosed(); reader.close() }
        Self.drive(reader, seconds: 4)
        #expect(count.value >= 2, "the reader never asked again after the 404: \(count.value)")
        #expect(CrividDeadSource.recentStatus(for: u, within: 120) == nil)
    }

    @Test("a 404 after the channel has delivered bytes is not a dead channel")
    func midStream404IsNotStamped() async throws {
        CrividDeadSource.reset()
        let count = Counter()
        let server = try #require(ScriptedOriginServer { _ in
            count.next() == 1 ? .init(status: 200, declaredLength: nil, bodyBytes: 256 * 1024, close: true)
                              : .init(status: 404, declaredLength: 0)
        })
        defer { server.stop() }
        let u = Self.url(server, "mid")
        let reader = AVIOReader(url: u, isLive: true)
        defer { reader.markClosed(); reader.close() }
        Self.drive(reader)
        #expect(count.value >= 2, "the reader never reconnected after the first body: \(count.value)")
        #expect(CrividDeadSource.recentStatus(for: u, within: 120) == nil)
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func next() -> Int { lock.lock(); defer { lock.unlock() }; n += 1; return n }
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
}
