import Foundation
import Testing
@testable import ArriqKit

private func object(_ d: Data) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: d) as? [String: Any]) ?? [:]
}
private func msg(_ d: Data) -> [String: Any] { (object(d)["msg"] as? [String: Any]) ?? [:] }
private func body(_ d: Data) -> [String: Any] { (msg(d)["data"] as? [String: Any]) ?? [:] }

@Test func scanCommand() {
    let d = GoveeCommand.scan()
    #expect(msg(d)["cmd"] as? String == "scan")
    #expect(body(d)["account_topic"] as? String == "reserve")
}

@Test func devStatusCommand() {
    #expect(msg(GoveeCommand.devStatus())["cmd"] as? String == "devStatus")
}

@Test func turnCommand() {
    #expect(msg(GoveeCommand.turn(on: true))["cmd"] as? String == "turn")
    #expect(body(GoveeCommand.turn(on: true))["value"] as? Int == 1)
    #expect(body(GoveeCommand.turn(on: false))["value"] as? Int == 0)
}

@Test func brightnessIsClamped() {
    #expect(body(GoveeCommand.brightness(60))["value"] as? Int == 60)
    #expect(body(GoveeCommand.brightness(0))["value"] as? Int == 1)
    #expect(body(GoveeCommand.brightness(150))["value"] as? Int == 100)
}

@Test func warmWhiteCommand() {
    let d = GoveeCommand.warmWhite(kelvin: 2700)
    #expect(msg(d)["cmd"] as? String == "colorwc")
    let color = body(d)["color"] as? [String: Any]
    #expect(color?["r"] as? Int == 0)
    #expect(color?["g"] as? Int == 0)
    #expect(color?["b"] as? Int == 0)
    #expect(body(d)["colorTemInKelvin"] as? Int == 2700)
    #expect(body(GoveeCommand.warmWhite(kelvin: 100))["colorTemInKelvin"] as? Int == 2000)
    #expect(body(GoveeCommand.warmWhite(kelvin: 99999))["colorTemInKelvin"] as? Int == 9000)
}

@Test func scanReplyGivesTheLampIP() {
    let reply = Data(#"{"msg":{"cmd":"scan","data":{"ip":"10.10.1.5","device":"aa:bb","sku":"H6076"}}}"#.utf8)
    #expect(GoveeCommand.scanIP(from: reply) == "10.10.1.5")
}

@Test func badScanRepliesGiveNoIP() {
    #expect(GoveeCommand.scanIP(from: Data(#"{"msg":{"cmd":"scan","data":{"ip":"999.1.1.1"}}}"#.utf8)) == nil)
    #expect(GoveeCommand.scanIP(from: Data(#"{"msg":{"cmd":"scan","data":{}}}"#.utf8)) == nil)
    #expect(GoveeCommand.scanIP(from: Data("junk".utf8)) == nil)
    #expect(GoveeCommand.scanIP(from: Data()) == nil)
}
