import Foundation
import IOBluetooth

/// ue boom 3: wake over ble, then wait briefly for the classic link. blocking work runs off the main queue.
public enum SpeakerDriver {
    public static func run(settings: Settings, dryRun: Bool) async -> DeviceOutcome {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: blocking(settings: settings, dryRun: dryRun))
            }
        }
    }

    static func blocking(settings: Settings, dryRun: Bool) -> DeviceOutcome {
        let address = settings.speakerAddress
        if dryRun {
            return DeviceOutcome(ok: true, text: "dry run: speaker wake · \(address)")
        }
        if isConnected(address) {
            return DeviceOutcome(ok: true, text: "speaker on")
        }
        guard let speaker = SpeakerWake.addressBytes(address) else { return fail("bad address") }
        guard let host = IOBluetoothHostController.default().addressAsString(),
              let payload = SpeakerWake.payload(hostAddress: host) else {
            return fail("no host address")
        }
        let result = BLEWake(speaker: speaker, payload: payload).run(scanTimeout: 15)
        guard result.ok else { return fail(result.reason) }
        // the write worked, so this succeeds either way; the classic link is only confirmation
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if isConnected(address) { return DeviceOutcome(ok: true, text: "speaker on") }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return DeviceOutcome(ok: true, text: "speaker on · link pending")
    }

    public static func off(settings: Settings, dryRun: Bool) async -> DeviceOutcome {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: blockingOff(settings: settings, dryRun: dryRun))
            }
        }
    }

    static func blockingOff(settings: Settings, dryRun: Bool) -> DeviceOutcome {
        let address = settings.speakerAddress
        if dryRun {
            return DeviceOutcome(ok: true, text: "dry run: speaker off · \(address)")
        }
        guard let speaker = SpeakerWake.addressBytes(address) else {
            return DeviceOutcome(ok: false, text: "speaker off failed · bad address")
        }
        if let host = IOBluetoothHostController.default().addressAsString(),
           let payload = SpeakerWake.payload(hostAddress: host, command: SpeakerWake.powerOff),
           BLEWake(speaker: speaker, payload: payload).run(scanTimeout: 6).ok {
            return DeviceOutcome(ok: true, text: "speaker off")
        }
        // no ble answer: closing the bluetooth link lets the speaker go to sleep on its own
        if let device = IOBluetoothDevice(addressString: address), device.isConnected() {
            device.closeConnection()
            return DeviceOutcome(ok: true, text: "speaker off · disconnected")
        }
        return DeviceOutcome(ok: true, text: "speaker off · already asleep")
    }

    static func fail(_ reason: String) -> DeviceOutcome {
        DeviceOutcome(ok: false, text: "speaker failed · \(reason)")
    }

    static func isConnected(_ address: String) -> Bool {
        IOBluetoothDevice(addressString: address)?.isConnected() ?? false
    }
}
