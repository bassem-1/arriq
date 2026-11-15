import Foundation
import Testing
@testable import ArriqKit

@Test func parsesAMessageLine() {
    let line = #"{"id":"abc","time":1800000000,"event":"message","message":"arrived","topic":"arriq-x"}"#
    #expect(parseNtfyLine(line) == NtfyMessage(id: "abc", time: Date(timeIntervalSince1970: 1_800_000_000), body: "arrived"))
}

@Test func openAndKeepaliveAreNotMessages() {
    #expect(parseNtfyLine(#"{"id":"1","time":1,"event":"open","topic":"t"}"#) == nil)
    #expect(parseNtfyLine(#"{"id":"2","time":2,"event":"keepalive","topic":"t"}"#) == nil)
    #expect(parseNtfyLine(#"{"id":"3","time":3,"event":"poll_request"}"#) == nil)
}

@Test func junkAndMissingFieldsAreIgnored() {
    #expect(parseNtfyLine("") == nil)
    #expect(parseNtfyLine("hello") == nil)
    #expect(parseNtfyLine("[1,2]") == nil)
    #expect(parseNtfyLine(#"{"time":1,"event":"message","message":"left"}"#) == nil)
    #expect(parseNtfyLine(#"{"id":"","time":1,"event":"message","message":"left"}"#) == nil)
    #expect(parseNtfyLine(#"{"id":"x","event":"message","message":"left"}"#) == nil)
    #expect(parseNtfyLine(#"{"id":"x","time":1,"event":"message"}"#) == nil)
    #expect(parseNtfyLine(#"{"id":"x","time":"soon","event":"message","message":"left"}"#) == nil)
}

@Test func filterRejectsStaleAndDuplicates() {
    var f = NtfyFilter()
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let fresh = NtfyMessage(id: "a", time: now.addingTimeInterval(-10), body: "arrived")
    let first = f.accept(fresh, now: now)
    let again = f.accept(fresh, now: now)
    let stale = NtfyMessage(id: "b", time: now.addingTimeInterval(-301), body: "arrived")
    let old = f.accept(stale, now: now)
    let edge = NtfyMessage(id: "c", time: now.addingTimeInterval(-300), body: "left")
    let atLimit = f.accept(edge, now: now)
    #expect(first)
    #expect(!again)
    #expect(!old)
    #expect(atLimit)
}

@Test func filterForgetsOldIdsPastCapacity() {
    var f = NtfyFilter(maxAge: 300, capacity: 2)
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func msg(_ id: String) -> NtfyMessage { NtfyMessage(id: id, time: now, body: "arrived") }
    let a1 = f.accept(msg("a"), now: now)
    let b1 = f.accept(msg("b"), now: now)
    let c1 = f.accept(msg("c"), now: now)
    let c2 = f.accept(msg("c"), now: now)
    let a2 = f.accept(msg("a"), now: now)   // evicted, so accepted again
    #expect(a1 && b1 && c1)
    #expect(!c2)
    #expect(a2)
}

@Test func backoffGrowsAndCaps() {
    #expect(NtfyBackoff.delay(afterFailures: 0) == 1)
    #expect(NtfyBackoff.delay(afterFailures: 1) == 2)
    #expect(NtfyBackoff.delay(afterFailures: 5) == 32)
    #expect(NtfyBackoff.delay(afterFailures: 6) == 60)
    #expect(NtfyBackoff.delay(afterFailures: 500) == 60)
    #expect(NtfyBackoff.delay(afterFailures: -3) == 1)
}

@Test func streamURLIsTheJsonSubscription() {
    #expect(NtfyClient.streamURL(topic: "arriq-abc")?.absoluteString == "https://ntfy.sh/arriq-abc/json?since=5m")
}

@Test func testBodyParsesAsAMessage() {
    let line = #"{"id":"t1","time":1800000000,"event":"message","message":"test","topic":"arriq-x"}"#
    #expect(parseNtfyLine(line) == NtfyMessage(id: "t1", time: Date(timeIntervalSince1970: 1_800_000_000), body: "test"))
}

@Test func phoneBodiesClassify() {
    #expect(PhoneSignal.classify("arrived") == .arrived)
    #expect(PhoneSignal.classify("left") == .left)
    #expect(PhoneSignal.classify("test") == .test)
    #expect(PhoneSignal.classify("  TEST \n") == .test)
    #expect(PhoneSignal.classify("") == nil)
    #expect(PhoneSignal.classify("testing") == nil)
    #expect(PhoneSignal.classify("hello") == nil)
}

@Test func jsonPhoneBodiesClassify() {
    #expect(PhoneSignal.classify(#"{"":"arrived"}"#) == .arrived)
    #expect(PhoneSignal.classify(#"{"":"left"}"#) == .left)
    #expect(PhoneSignal.classify(#"{"a":"Arrived"}"#) == .arrived)
    #expect(PhoneSignal.classify(#"["left"]"#) == .left)
    #expect(PhoneSignal.classify(#"{"x":"arrived","y":"left"}"#) == nil)
    #expect(PhoneSignal.classify(#"{"x":{"y":["test"]}}"#) == .test)
    #expect(PhoneSignal.classify("{not json") == nil)
}

@Test func quotedAndTrailingNewlineBodiesClassify() {
    #expect(PhoneSignal.classify(#""arrived""#) == .arrived)
    #expect(PhoneSignal.classify("arrived\n") == .arrived)
}

@Test func wholeWordFallbackClassifies() {
    #expect(PhoneSignal.classify("I have arrived") == .arrived)
    #expect(PhoneSignal.classify("leftover") == nil)
    #expect(PhoneSignal.classify("i left the house") == .left)
    #expect(PhoneSignal.classify("arrived and left") == nil)
    #expect(PhoneSignal.classify("junk") == nil)
}
