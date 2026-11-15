import CoreAudio
import Foundation

/// finds the bluetooth speaker among the mac's audio outputs and makes it the default. no dependencies.
public enum AudioRoute {
    /// pure: the device uid carries the bluetooth address with dashes, e.g. A1-B2-C3-D4-E5-F6:output
    static func uidMatches(_ uid: String, address: String) -> Bool {
        let wanted = address.uppercased().replacingOccurrences(of: ":", with: "-")
        guard !wanted.isEmpty else { return false }
        return uid.uppercased().contains(wanted)
    }

    /// polls the device list every 0.5 s until the speaker shows up as an output, or the timeout passes
    static func outputDeviceID(matchingAddress address: String, timeout: TimeInterval = 12) -> AudioDeviceID? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let id = findOutput(address: address) { return id }
            Thread.sleep(forTimeInterval: 0.5)
        } while Date() < deadline
        return nil
    }

    static func setDefaultOutput(_ id: AudioDeviceID) -> Bool {
        var device = id
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &device)
        return status == noErr
    }

    private static func findOutput(address: String) -> AudioDeviceID? {
        let outputs = allDevices().filter { hasOutput($0) }
        if let hit = outputs.first(where: { string($0, kAudioDevicePropertyDeviceUID).map { uidMatches($0, address: address) } ?? false }) {
            return hit
        }
        return outputs.first { id in
            var transport: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyTransportType,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &transport) == noErr,
                  transport == kAudioDeviceTransportTypeBluetooth else { return false }
            return (string(id, kAudioObjectPropertyName) ?? "").lowercased().contains("boom")
        }
    }

    private static func allDevices() -> [AudioDeviceID] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func hasOutput(_ id: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr && size > 0
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var ref: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &ref) == noErr, let ref else { return nil }
        return ref.takeRetainedValue() as String
    }
}
