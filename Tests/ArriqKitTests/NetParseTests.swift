import Testing
@testable import ArriqKit

private let routeOutput = """
   route to: default
destination: default
       mask: default
    gateway: 192.168.1.1
  interface: en0
"""

@Test func gatewayFromRouteOutput() {
    #expect(NetParse.gateway(fromRoute: routeOutput) == "192.168.1.1")
}

@Test func gatewayMissingOrNotIPv4() {
    #expect(NetParse.gateway(fromRoute: "") == nil)
    #expect(NetParse.gateway(fromRoute: "route: writing to routing socket: not in table") == nil)
    #expect(NetParse.gateway(fromRoute: "    gateway: fe80::1%lo0") == nil)
}

@Test func macFromArpOutput() {
    #expect(NetParse.mac(fromARP: "? (192.168.1.1) at 0:1d:2:3e:4f:5 on en0 ifscope [ethernet]") == "00:1d:02:3e:4f:05")
    #expect(NetParse.mac(fromARP: "? (192.168.1.1) at AA:BB:CC:DD:EE:FF on en0") == "aa:bb:cc:dd:ee:ff")
}

@Test func incompleteArpIsNoMac() {
    #expect(NetParse.mac(fromARP: "? (192.168.1.9) at (incomplete) on en0 ifscope [ethernet]") == nil)
    #expect(NetParse.mac(fromARP: "") == nil)
    #expect(NetParse.mac(fromARP: "? (192.168.1.9) at") == nil)
}

@Test func normalizeMAC() {
    #expect(NetParse.normalizeMAC("AA:BB:CC:DD:EE:FF") == "aa:bb:cc:dd:ee:ff")
    #expect(NetParse.normalizeMAC("0:1:2:3:4:5") == "00:01:02:03:04:05")
    #expect(NetParse.normalizeMAC("aa:bb") == nil)
    #expect(NetParse.normalizeMAC("gg:bb:cc:dd:ee:ff") == nil)
    #expect(NetParse.normalizeMAC("1:2:3:4:5:6:7") == nil)
    #expect(NetParse.normalizeMAC("100:2:3:4:5:6") == nil)
}

@Test func ipv4Check() {
    #expect(NetParse.isIPv4("10.0.0.1"))
    #expect(NetParse.isIPv4("255.255.255.255"))
    #expect(!NetParse.isIPv4("256.1.1.1"))
    #expect(!NetParse.isIPv4("1.2.3"))
    #expect(!NetParse.isIPv4("a.b.c.d"))
    #expect(!NetParse.isIPv4("1.2.3.4.5"))
    #expect(!NetParse.isIPv4(""))
}

@Test func homeMatchNeedsBothMACs() {
    #expect(NetParse.isHome(gatewayMAC: "0:1d:2:3e:4f:5", homeMAC: "00:1d:02:3e:4f:05"))
    #expect(!NetParse.isHome(gatewayMAC: "00:1d:02:3e:4f:06", homeMAC: "00:1d:02:3e:4f:05"))
    #expect(!NetParse.isHome(gatewayMAC: nil, homeMAC: "00:1d:02:3e:4f:05"))
    #expect(!NetParse.isHome(gatewayMAC: "00:1d:02:3e:4f:05", homeMAC: nil))
    #expect(!NetParse.isHome(gatewayMAC: nil, homeMAC: nil))
}

@Test func homeIsAdoptedOnlyWhenNothingIsSaved() {
    // nothing saved and a readable gateway mac: adopt it, normalized
    #expect(NetParse.homeToAdopt(saved: nil, current: "0:1d:2:3e:4f:5") == "00:1d:02:3e:4f:05")
    // nothing saved and no mac readable: nothing
    #expect(NetParse.homeToAdopt(saved: nil, current: nil) == nil)
    #expect(NetParse.homeToAdopt(saved: nil, current: "(incomplete)") == nil)
    // a saved home is never overwritten
    #expect(NetParse.homeToAdopt(saved: "00:1d:02:3e:4f:05", current: "aa:bb:cc:dd:ee:ff") == nil)
    #expect(NetParse.homeToAdopt(saved: "00:1d:02:3e:4f:05", current: nil) == nil)
}

@Test func sameSubnetComparesUnderTheMask() {
    #expect(NetParse.sameSubnet("192.168.1.40", "192.168.1.1", mask: "255.255.255.0"))
    #expect(!NetParse.sameSubnet("192.168.2.40", "192.168.1.1", mask: "255.255.255.0"))
    #expect(NetParse.sameSubnet("10.200.1.5", "10.0.0.9", mask: "255.0.0.0"))
    #expect(!NetParse.sameSubnet("10.200.1.5", "10.0.0.9", mask: "255.255.0.0"))
    // bad input never matches
    #expect(!NetParse.sameSubnet("192.168.1", "192.168.1.1", mask: "255.255.255.0"))
    #expect(!NetParse.sameSubnet("192.168.1.2", "192.168.1.1", mask: "nope"))
}
