import Foundation
import Testing
@testable import ArriqKit

// engine checks for the home adoption, the test round trip and the lamp hint; dry run only.

private final class Saves: @unchecked Sendable {
    var last: Settings?
    var fires = 0
}

@MainActor
@Test func firstReadableGatewayBecomesHomeWithoutTriggering() {
    let engine = ArriqEngine(dryRun: true)
    let saves = Saves()
    engine.onSettingsChange = { saves.last = $0 }
    engine.onFire = { saves.fires += 1 }
    var s = Settings()
    s.homeGatewayMAC = nil
    engine.apply(s)
    engine.homeProbed("0:1d:2:3e:4f:5")
    #expect(engine.settings.homeGatewayMAC == "00:1d:02:3e:4f:05")
    #expect(saves.last?.homeGatewayMAC == "00:1d:02:3e:4f:05")
    #expect(engine.snapshot.macHome)
    #expect(engine.snapshot.gatewayMAC == "0:1d:2:3e:4f:5")
    #expect(engine.snapshot.lastTrigger == nil)
    #expect(saves.fires == 0)
    #expect(engine.snapshot.log.last?.text == "home network set automatically · change it in the home tab")
}

@MainActor
@Test func savedHomeIsNeverOverwritten() {
    let engine = ArriqEngine(dryRun: true)
    var s = Settings()
    s.homeGatewayMAC = "00:1d:02:3e:4f:05"
    engine.apply(s)
    engine.homeProbed("aa:bb:cc:dd:ee:ff")
    #expect(engine.settings.homeGatewayMAC == "00:1d:02:3e:4f:05")
    #expect(!engine.snapshot.macHome)
    #expect(engine.snapshot.log.isEmpty)
}

@MainActor
@Test func noReadableGatewayAdoptsNothing() {
    let engine = ArriqEngine(dryRun: true)
    engine.homeProbed(nil)
    #expect(engine.settings.homeGatewayMAC == nil)
    #expect(!engine.snapshot.macHome)
    #expect(engine.snapshot.gatewayMAC == nil)
}

@MainActor
@Test func testBodyIsHeardButFeedsNoPresence() {
    let engine = ArriqEngine(dryRun: true)
    engine.simulate(.macHome(true))
    engine.phoneMessage(NtfyMessage(id: "round-1", time: Date(), body: "test"))
    #expect(engine.snapshot.lastPhoneSignal != nil)
    #expect(engine.snapshot.phoneHome == nil)
    #expect(engine.snapshot.lastTrigger == nil)
    #expect(engine.snapshot.log.last?.text == "heard from phone · test")
}

@MainActor
@Test func sendTestSignalIsLoggedOnlyInDryRun() {
    let engine = ArriqEngine(dryRun: true)
    engine.sendTestSignal()
    #expect(engine.snapshot.log.last?.text == "dry run: test signal to phone")
    #expect(engine.snapshot.phoneHome == nil)
}
