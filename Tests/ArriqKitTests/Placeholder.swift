import Foundation
import Testing
@testable import ArriqKit

// engine smoke tests; dry run only, so nothing reaches the network, bluetooth or a device.

private final class Counter: @unchecked Sendable {
    var fires = 0
}

@MainActor
@Test func phoneArrivalWithMacHomeFiresOnceInDryRun() {
    let engine = ArriqEngine(dryRun: true)
    let counter = Counter()
    engine.onFire = { counter.fires += 1 }
    engine.simulate(.macHome(true))
    #expect(engine.snapshot.macHome)
    engine.simulate(.phoneArrived)
    engine.simulate(.phoneArrived)
    #expect(counter.fires == 1)
    #expect(engine.snapshot.phoneHome == true)
    #expect(engine.snapshot.lastTrigger != nil)
}

@MainActor
@Test func disabledEngineTracksButDoesNotFire() {
    let engine = ArriqEngine(dryRun: true)
    let counter = Counter()
    engine.onFire = { counter.fires += 1 }
    var s = Settings()
    s.enabled = false
    engine.apply(s)
    engine.simulate(.macHome(true))
    engine.simulate(.phoneArrived)
    #expect(counter.fires == 0)
    #expect(engine.snapshot.lastTrigger == nil)
    #expect(engine.snapshot.phoneHome == true)
}

@MainActor
@Test func fireNowIgnoresPresence() {
    let engine = ArriqEngine(dryRun: true)
    let counter = Counter()
    engine.onFire = { counter.fires += 1 }
    engine.fireNow()
    #expect(counter.fires == 1)
}

@MainActor
@Test func phoneURLUsesTheTopic() {
    let engine = ArriqEngine(dryRun: true)
    var s = Settings()
    s.phoneTopic = "arriq-test"
    #expect(engine.phoneURL(for: s) == "https://ntfy.sh/arriq-test")
}
