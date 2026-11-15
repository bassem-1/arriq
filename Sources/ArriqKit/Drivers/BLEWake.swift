import CoreBluetooth
import Foundation

/// one-shot ble wake: find the speaker, connect, write the host address + 0x01.
/// run() blocks the caller; all corebluetooth callbacks arrive on a private queue.
final class BLEWake: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private enum Stage: Int { case power, scan, connect, discover, write, finished }

    private let queue = DispatchQueue(label: "io.github.arriq.ble")
    private let speaker: [UInt8]
    private let payload: Data
    private let done = DispatchSemaphore(value: 0)
    private var central: CBCentralManager?
    private var device: CBPeripheral?
    private var stage: Stage = .power
    private var result: (ok: Bool, reason: String) = (false, "timed out")

    init(speaker: [UInt8], payload: Data) {
        self.speaker = speaker
        self.payload = payload
        super.init()
    }

    func run(scanTimeout: TimeInterval) -> (ok: Bool, reason: String) {
        queue.async {
            self.central = CBCentralManager(delegate: self, queue: self.queue)
            self.queue.asyncAfter(deadline: .now() + scanTimeout) {
                if self.stage.rawValue < Stage.connect.rawValue {
                    self.finish(false, self.stage == .power ? "bluetooth off" : "not found")
                }
            }
            // watchdog for a stalled connect or discovery
            self.queue.asyncAfter(deadline: .now() + scanTimeout + 60) {
                self.finish(false, "timed out")
            }
        }
        _ = done.wait(timeout: .now() + scanTimeout + 75)
        return result
    }

    private func finish(_ ok: Bool, _ reason: String) {
        guard stage != .finished else { return }
        stage = .finished
        result = (ok, reason)
        if let c = central {
            c.stopScan()
            if let d = device { c.cancelPeripheralConnection(d) }
        }
        done.signal()
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            guard stage == .power else { return }
            stage = .scan
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        case .unauthorized: finish(false, "bluetooth not allowed")
        case .unsupported: finish(false, "bluetooth unsupported")
        case .poweredOff: finish(false, "bluetooth off")
        default: break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard stage == .scan else { return }
        let uuids = ((advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []).map { $0.uuidString }
        let manufacturer = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        guard SpeakerWake.advertisementMatches(serviceUUIDs: uuids, manufacturerData: manufacturer, speaker: speaker) else { return }
        stage = .connect
        central.stopScan()
        device = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard stage == .connect else { return }
        stage = .discover
        peripheral.discoverServices([CBUUID(string: SpeakerWake.serviceUUID)])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        finish(false, "connect failed")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        finish(false, "disconnected")
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard stage == .discover, error == nil,
              let service = peripheral.services?.first(where: { $0.uuid == CBUUID(string: SpeakerWake.serviceUUID) }) else {
            finish(false, "service missing")
            return
        }
        peripheral.discoverCharacteristics([CBUUID(string: SpeakerWake.characteristicUUID)], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard stage == .discover, error == nil,
              let ch = service.characteristics?.first(where: { $0.uuid == CBUUID(string: SpeakerWake.characteristicUUID) }) else {
            finish(false, "characteristic missing")
            return
        }
        stage = .write
        peripheral.writeValue(payload, for: ch, type: .withResponse)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard stage == .write else { return }
        finish(error == nil, error == nil ? "wake sent" : "write failed")
    }
}
