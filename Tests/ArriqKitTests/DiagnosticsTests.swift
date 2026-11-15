import Foundation
import Testing
@testable import ArriqKit

private let stamp = Date(timeIntervalSince1970: 1_800_000_000)

@Test func fileLogLinesAreTimestampedAndLowerCase() {
    let line = FileLog.format("Presence · PHONE Arrived", at: stamp)
    #expect(line.hasSuffix(" presence · phone arrived"))
    #expect(line.hasPrefix("2027-01-15T"))
}

@Test func topicIsMaskedToItsLastTwoCharacters() {
    #expect(FileLog.mask("arriq-3f9a0c71") == "topic…71")
    #expect(FileLog.mask("ab") == "topic…")
    #expect(!FileLog.mask("arriq-3f9a0c71").contains("arriq"))
}

@Test func appendCreatesTheFileAndRotatesAtTheLimit() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("arriq-log-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("arriq.log")

    FileLog.append("first", at: stamp, to: url)
    let text = try String(contentsOf: url, encoding: .utf8)
    #expect(text.hasSuffix(" first\n"))

    // fill past the limit, then the next append must move the old file to .1
    try Data(repeating: 0x20, count: FileLog.maxBytes).write(to: url)
    FileLog.append("after rotation", at: stamp, to: url)
    let rotated = url.appendingPathExtension("1")
    #expect(FileManager.default.fileExists(atPath: rotated.path))
    let fresh = try String(contentsOf: url, encoding: .utf8)
    #expect(fresh.hasSuffix(" after rotation\n"))
    #expect(fresh.count < 1000)
}

@Test func filterSaysWhyAMessageWasDropped() {
    var f = NtfyFilter()
    let fresh = NtfyMessage(id: "a", time: stamp, body: "arrived")
    #expect(f.verdict(fresh, now: stamp) == .accept)
    #expect(f.verdict(fresh, now: stamp) == .duplicate)
    let old = NtfyMessage(id: "b", time: stamp.addingTimeInterval(-600), body: "left")
    #expect(f.verdict(old, now: stamp) == .stale)
}

@Test func onlyTheNewestStreamAttemptIsCurrent() {
    let gen = NtfyGeneration()
    let first = gen.next()
    #expect(gen.isCurrent(first))
    let second = gen.next()
    // a replaced attempt must not report listening changes any more
    #expect(!gen.isCurrent(first))
    #expect(gen.isCurrent(second))
}

@Test func reduceDetailedNamesTheCooldownThatBlocksATrigger() {
    let cfg = PresenceConfig(cooldown: 1800, pairWindow: 900)
    // a trigger 10 minutes after the last one is blocked by the cooldown
    let last = PresenceState(phoneHome: false, macHome: true, lastTrigger: stamp)
    let blocked = reduceDetailed(last, .phoneArrived, now: stamp.addingTimeInterval(600), config: cfg)
    #expect(!blocked.trigger)
    #expect(blocked.blocked == .cooldown)
    // after the cooldown the same arrival fires and nothing is blocked
    let free = reduceDetailed(last, .phoneArrived, now: stamp.addingTimeInterval(1900), config: cfg)
    #expect(free.trigger)
    #expect(free.blocked == nil)
}

/// counts calls from any thread
private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func hit() { lock.lock(); n += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return n }
}

@Test func startNeverTouchesTheKeychainInDryRun() {
    // a keychain prompt blocked the main thread at launch once: start() must not ask for the token
    let engine = ArriqEngine(dryRun: true)
    let asked = CallCounter()
    engine.tokenProbe = { asked.hit(); return true }
    engine.start()
    #expect(asked.count == 0)
    engine.stop()
}
