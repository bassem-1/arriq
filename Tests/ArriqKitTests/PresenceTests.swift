import Foundation
import Testing
@testable import ArriqKit

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let cfg = PresenceConfig(cooldown: 1800, pairWindow: 900)

/// runs events at offsets (seconds from t0); returns the final state and each trigger flag
private func run(_ events: [(PresenceEvent, TimeInterval)], from start: PresenceState = PresenceState()) -> (PresenceState, [Bool]) {
    var s = start
    var fires: [Bool] = []
    for (e, dt) in events {
        let (next, fire) = reduce(s, e, now: t0.addingTimeInterval(dt), config: cfg)
        s = next
        fires.append(fire)
    }
    return (s, fires)
}

@Test func phoneArrivesWithMacHomeTriggers() {
    let (_, fires) = run([(.macHome(true), 0), (.phoneArrived, 10)])
    #expect(fires == [false, true])
}

@Test func macArrivesWithinWindowTriggers() {
    let (_, fires) = run([(.phoneArrived, 0), (.macHome(true), 300)])
    #expect(fires == [false, true])
}

@Test func macArrivingAfterWindowDoesNotTrigger() {
    let (_, fires) = run([(.phoneArrived, 0), (.tick, 901), (.macHome(true), 902)])
    #expect(fires == [false, false, false])
    let (_, late) = run([(.phoneArrived, 0), (.macHome(true), 901)])
    #expect(late == [false, false])
}

@Test func duplicateArrivalFiresOnce() {
    let (_, fires) = run([(.macHome(true), 0), (.phoneArrived, 1), (.phoneArrived, 2)])
    #expect(fires == [false, true, false])
}

@Test func cooldownBlocksThenAllows() {
    let (state, fires) = run([
        (.macHome(true), 0),
        (.phoneArrived, 0),        // fires
        (.phoneLeft, 100),
        (.phoneArrived, 200),      // inside cooldown
        (.phoneLeft, 1000),
        (.phoneArrived, 2000),     // after cooldown
    ])
    #expect(fires == [false, true, false, false, false, true])
    #expect(state.armedUntil == nil)
}

@Test func cooldownClearsArmedWindow() {
    let (state, fires) = run([
        (.phoneArrived, 0),        // fires nothing yet, armed
        (.macHome(true), 10),      // fires
        (.phoneLeft, 20),
        (.phoneArrived, 30),       // inside cooldown: armed must stay clear
    ])
    #expect(fires == [false, true, false, false])
    #expect(state.armedUntil == nil)
}

@Test func macAloneNeverTriggers() {
    let (_, fires) = run([(.macHome(true), 0)])
    #expect(fires == [false])
    let (_, awayThenHome) = run([(.phoneArrived, 0), (.phoneLeft, 5), (.macHome(true), 10)])
    #expect(awayThenHome == [false, false, false])
}

@Test func windowExpiryClearsArmedWithoutTrigger() {
    let (state, fires) = run([(.phoneArrived, 0), (.tick, 901)])
    #expect(state.armedUntil == nil)
    #expect(fires == [false, false])
}

@Test func phoneLeavingCancelsArming() {
    let (_, fires) = run([(.phoneArrived, 0), (.phoneLeft, 5), (.macHome(true), 10)])
    #expect(fires == [false, false, false])
}

@Test func macLeavingCancelsArming() {
    let (state, fires) = run([(.phoneArrived, 0), (.macHome(false), 5), (.macHome(true), 10)])
    #expect(fires == [false, false, false])
    #expect(state.armedUntil == nil)
}
