import Foundation
import Testing
@testable import ArriqKit

@Test func addressToBytes() {
    #expect(SpeakerWake.addressBytes("A1:B2:C3:D4:E5:F6") == [0xA1, 0xB2, 0xC3, 0xD4, 0xE5, 0xF6])
    #expect(SpeakerWake.addressBytes("a1:b2:c3:d4:e5:f6") == [0xA1, 0xB2, 0xC3, 0xD4, 0xE5, 0xF6])
    #expect(SpeakerWake.addressBytes("10:94") == nil)
    #expect(SpeakerWake.addressBytes("A1:B2:C3:D4:E5:ZZ") == nil)
    #expect(SpeakerWake.addressBytes("1:94:97:2E:57:36") == nil)
    #expect(SpeakerWake.addressBytes("") == nil)
}

@Test func payloadIsHostAddressThenOne() {
    let p = SpeakerWake.payload(hostAddress: "00:11:22:33:44:55")
    #expect(p.map { Array($0) } == [0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x01])
    #expect(SpeakerWake.payload(hostAddress: "not an address") == nil)
}

@Test func advertisementMatchesWakeService() {
    #expect(SpeakerWake.advertisementMatches(serviceUUIDs: ["FE61"], manufacturerData: nil, speaker: []))
    #expect(SpeakerWake.advertisementMatches(serviceUUIDs: [SpeakerWake.serviceUUID], manufacturerData: nil, speaker: []))
    #expect(!SpeakerWake.advertisementMatches(serviceUUIDs: ["180F"], manufacturerData: nil, speaker: []))
}

@Test func advertisementMatchesSpeakerBytesInManufacturerData() {
    let speaker: [UInt8] = [0xA1, 0xB2, 0xC3, 0xD4, 0xE5, 0xF6]
    let md = Data([0x4C, 0x00, 0xA1, 0xB2, 0xC3, 0xD4, 0xE5, 0xF6, 0x01])
    #expect(SpeakerWake.advertisementMatches(serviceUUIDs: [], manufacturerData: md, speaker: speaker))
    let other = Data([0x4C, 0x00, 0xA1, 0xB2, 0xC3, 0xD4, 0xE5, 0xF7])
    #expect(!SpeakerWake.advertisementMatches(serviceUUIDs: [], manufacturerData: other, speaker: speaker))
    #expect(!SpeakerWake.advertisementMatches(serviceUUIDs: [], manufacturerData: Data([1, 2]), speaker: speaker))
    #expect(!SpeakerWake.advertisementMatches(serviceUUIDs: [], manufacturerData: md, speaker: [0xA1]))
}

@Test func speakerAddressIsNormalizedLiberally() {
    #expect(SpeakerWake.normalize("a1:b2:c3:d4:e5:f6") == "A1:B2:C3:D4:E5:F6")
    #expect(SpeakerWake.normalize(" A1-B2-C3-D4-E5-F6 ") == "A1:B2:C3:D4:E5:F6")
    #expect(SpeakerWake.normalize("a1b2c3d4e5f6") == "A1:B2:C3:D4:E5:F6")
    #expect(SpeakerWake.normalize("") == nil)
    #expect(SpeakerWake.normalize("a1:b2:c3:d4:e5") == nil)
    #expect(SpeakerWake.normalize("a1:b2:c3:d4:e5:zz") == nil)
}
