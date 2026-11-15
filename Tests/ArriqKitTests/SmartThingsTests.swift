import Foundation
import Testing
@testable import ArriqKit

@Test func devicesRequestIsAuthorisedGET() {
    let r = SmartThingsAPI.devicesRequest(token: "tok")
    #expect(r?.url?.absoluteString == "https://api.smartthings.com/v1/devices")
    #expect((r?.httpMethod ?? "GET") == "GET")
    #expect(r?.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
    #expect(r?.timeoutInterval == 10)
}

@Test func commandRequestSwitchesOn() throws {
    let r = try #require(SmartThingsAPI.commandRequest(deviceID: "abc-123", token: "tok"))
    #expect(r.url?.absoluteString == "https://api.smartthings.com/v1/devices/abc-123/commands")
    #expect(r.httpMethod == "POST")
    #expect(r.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
    #expect(r.value(forHTTPHeaderField: "Content-Type") == "application/json")
    let body = try #require(r.httpBody)
    let obj = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    let commands = try #require(obj["commands"] as? [[String: Any]])
    #expect(commands.count == 1)
    #expect(commands[0]["component"] as? String == "main")
    #expect(commands[0]["capability"] as? String == "switch")
    #expect(commands[0]["command"] as? String == "on")
}

@Test func deviceIDIsPathEscaped() {
    let r = SmartThingsAPI.commandRequest(deviceID: "a/b c", token: "t")
    #expect(r?.url?.absoluteString == "https://api.smartthings.com/v1/devices/a/b%20c/commands")
}

@Test func parsesDevicesWithLabelFallbacks() {
    let json = Data(#"""
    {"items": [
      {"deviceId": "d1", "label": "Living Room TV", "name": "samsung-tv"},
      {"deviceId": "d2", "label": "", "name": "Soundbar"},
      {"deviceId": "d3", "name": "bare"},
      {"label": "no id"},
      {"deviceId": "", "label": "empty id"}
    ]}
    """#.utf8)
    let devices = SmartThingsAPI.parseDevices(json)
    #expect(devices == [
        SmartThingsDevice(id: "d1", label: "living room tv"),
        SmartThingsDevice(id: "d2", label: "soundbar"),
        SmartThingsDevice(id: "d3", label: "bare"),
    ])
}

@Test func garbageDeviceListIsEmpty() {
    #expect(SmartThingsAPI.parseDevices(Data("nope".utf8)).isEmpty)
    #expect(SmartThingsAPI.parseDevices(Data(#"{"items": "x"}"#.utf8)).isEmpty)
}

@Test func notSetUpReasons() {
    var s = Settings()
    #expect(TVDriver.notSetUpReason(settings: s, tokenSet: false) == "add a smartthings token")
    #expect(TVDriver.notSetUpReason(settings: s, tokenSet: true) == "pick your tv")
    s.smartThingsDeviceID = "d1"
    #expect(TVDriver.notSetUpReason(settings: s, tokenSet: true) == nil)
    #expect(TVDriver.notSetUpReason(settings: s, tokenSet: false) == "add a smartthings token")
}

@Test func commandRequestCarriesArguments() throws {
    let r = try #require(SmartThingsAPI.commandRequest(deviceID: "d", token: "t", capability: "custom.launchapp",
                                                       command: "launchApp", arguments: ["111299001912"]))
    let launchBody = try #require(r.httpBody)
    let obj = try #require(try JSONSerialization.jsonObject(with: launchBody) as? [String: Any])
    let c = try #require((obj["commands"] as? [[String: Any]])?.first)
    #expect(c["capability"] as? String == "custom.launchapp")
    #expect(c["command"] as? String == "launchApp")
    #expect(c["arguments"] as? [String] == ["111299001912"])
}

@Test func statusReasons() {
    #expect(SmartThingsAPI.reason(forStatus: 401) == "token expired")
    #expect(SmartThingsAPI.reason(forStatus: 403) == "token lacks device control")
    #expect(SmartThingsAPI.reason(forStatus: 500) == "http 500")
    #expect(SmartThingsAPI.hint(forReason: "token expired") == "new smartthings tokens last 24h")
}
