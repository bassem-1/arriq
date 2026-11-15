import AppKit
import Foundation

// Public calls are made on the main thread; callbacks are delivered on the main queue.
// Public signatures are fixed (the ui agent codes against them).

public final class ArriqEngine: @unchecked Sendable {
    public internal(set) var snapshot = EngineSnapshot.initial
    public var onChange: (@Sendable (EngineSnapshot) -> Void)?
    public var onSettingsChange: (@Sendable (Settings) -> Void)?  // engine edits settings itself (lampIP, homeGatewayMAC)
    public var onFire: (@Sendable () -> Void)?                    // every time arrival actions start

    // main-thread state
    internal var settings = Settings()
    internal var presence = PresenceState()
    internal var ntfyFilter = NtfyFilter()
    internal var stamps: [DeviceKind: Int] = [:]
    internal var tokenSet = false
    internal var adjustStamp = 0
    /// existence check for the smartthings token; a closure so a test can see whether start() asks
    internal var tokenProbe: @Sendable () -> Bool = { TokenStore.exists() }
    internal let dryRun: Bool

    private let ntfy = NtfyClient()
    private let home = HomeDetector()
    private var tickTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var running = false

    public convenience init() {
        self.init(dryRun: ProcessInfo.processInfo.environment["ARRIQ_DRY_RUN"] == "1")
    }

    /// dry run: drivers log instead of touching the network or bluetooth, and no ntfy stream is opened
    init(dryRun: Bool) {
        self.dryRun = dryRun
        home.onProbe = { [weak self] mac in self?.homeProbed(mac) }
    }

    public func apply(_ new: Settings) {
        let topicChanged = new.phoneTopic != settings.phoneTopic
        settings = new
        refreshReadiness()
        // no home saved yet: look again, so the first readable gateway mac is adopted
        if running && settings.homeGatewayMAC == nil { home.refresh() }
        if running && topicChanged && !dryRun { startNtfy() }
        publish()
    }

    public func start() {
        guard !running else { return }
        // the keychain is never touched here: the phone stream and home detection come first
        FileLog.write("engine start · enabled \(settings.enabled) · topic \(FileLog.mask(settings.phoneTopic)) · home saved \(settings.homeGatewayMAC != nil) · dry run \(dryRun)")
        running = true
        if !dryRun { startNtfy() }
        observeWake()
        home.start()
        refreshReadiness()
        if !dryRun { checkToken() }
        publish()
    }

    /// keychain existence check on a background queue; it never prompts and never blocks the main thread
    func checkToken() {
        let probe = tokenProbe
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let present = probe()
            DispatchQueue.main.async {
                guard let self else { return }
                FileLog.write("token check · present \(present)")
                self.tokenSet = present
                self.refreshReadiness()
                self.publish()
            }
        }
    }

    public func stop() {
        running = false
        ntfy.stop()
        home.stop()
        tickTimer?.invalidate()
        tickTimer = nil
        if let o = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(o)
            wakeObserver = nil
        }
        snapshot.listening = false
        publish()
    }

    public func fireNow() {
        fireDevices()
        publish()
    }

    public func test(_ kind: DeviceKind) {
        startDevice(kind, after: 0)
        publish()
    }

    /// switches one device off now, cancelling its pending arrival run
    public func turnOff(_ kind: DeviceKind) {
        stopDevice(kind)
    }

    /// switches one device on now, regardless of its on-arrival switch (the same run as an arrival, no delay)
    public func turnOn(_ kind: DeviceKind) {
        startDevice(kind, after: 0)
        publish()
    }

    /// switches every device on now, no delays
    public func turnOnAll() {
        appendLog("all on")
        for kind in DeviceKind.allCases { startDevice(kind, after: 0) }
        publish()
    }

    /// live lamp brightness / colour, while the lamp is on
    public func adjustLamp() {
        adjustLampNow()
    }

    /// switches every device off now, whether or not it is used on arrival
    public func turnOffAll() {
        appendLog("all off")
        for kind in DeviceKind.allCases { stopDevice(kind) }
    }

    /// runs only the music step, for the test button
    public func testMusic() {
        let stamp = (stamps[.speaker] ?? 0) + 1
        stamps[.speaker] = stamp
        runMusic(stamp: stamp)
    }

    /// saves the current gateway mac as home; nil when no gateway or arp entry is visible
    public func markHome() -> String? {
        guard let mac = HomeDetector.probe() else { return nil }
        settings.homeGatewayMAC = mac
        onSettingsChange?(settings)
        homeProbed(mac)
        return mac
    }

    public func setSmartThingsToken(_ token: String?) {
        let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let value: String? = trimmed.isEmpty ? nil : trimmed
        // the keychain write runs off the main thread; the state follows when it lands
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let saved = TokenStore.save(value)
            DispatchQueue.main.async {
                guard let self else { return }
                self.tokenSet = saved && value != nil
                FileLog.write("token save · stored \(self.tokenSet)")
                self.refreshReadiness()
                self.publish()
            }
        }
    }

    public func listSmartThingsDevices() async -> [SmartThingsDevice] {
        guard let token = TokenStore.load() else { return [] }
        return await SmartThingsAPI.listDevices(token: token)
    }

    public func simulate(_ event: PresenceEvent) {
        handle(event)
    }

    /// posts the body `test` to the phone topic; the ntfy stream hears it back as "heard from phone · test".
    public func sendTestSignal() {
        if dryRun {
            appendLog("dry run: test signal to phone")
            publish()
            return
        }
        guard let url = URL(string: phoneURL(for: settings)) else {
            appendLog("test signal failed · bad topic")
            publish()
            return
        }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.httpBody = Data("test".utf8)
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            let ok = error == nil && ((response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false)
            DispatchQueue.main.async {
                self?.appendLog(ok ? "test sent to phone topic" : "test signal failed · no network")
                self?.publish()
            }
        }.resume()
    }

    /// base url the phone posts to; append nothing. body "arrived" or "left".
    public func phoneURL(for settings: Settings) -> String { "https://ntfy.sh/\(settings.phoneTopic)" }

    // MARK: presence

    var presenceConfig: PresenceConfig {
        PresenceConfig(cooldown: Double(settings.cooldownMinutes) * 60,
                       pairWindow: Double(settings.pairWindowMinutes) * 60)
    }

    func handle(_ event: PresenceEvent, now: Date = Date()) {
        let previousTrigger = presence.lastTrigger
        let before = presence
        let (next, fire, blocked) = reduceDetailed(presence, event, now: now, config: presenceConfig)
        presence = next
        var note = ""
        if let blocked { note += " · blocked by \(blocked)" }
        if fire {
            if settings.enabled {
                fireDevices()
            } else {
                // nothing triggers while off; keep the cooldown clock where it was
                presence.lastTrigger = previousTrigger
                note += " · blocked by disabled"
            }
        }
        FileLog.write("presence · \(ArriqEngine.describe(event)) · \(ArriqEngine.describe(before)) -> \(ArriqEngine.describe(presence)) · trigger \(fire)\(note)")
        scheduleTick()
        publish()
    }

    static func describe(_ e: PresenceEvent) -> String {
        switch e {
        case .phoneArrived: return "phone arrived"
        case .phoneLeft: return "phone left"
        case .macHome(let home): return "mac \(home ? "home" : "away")"
        case .tick: return "tick"
        }
    }

    static func describe(_ s: PresenceState) -> String {
        let phone: String
        switch s.phoneHome {
        case .some(true): phone = "home"
        case .some(false): phone = "away"
        case .none: phone = "unknown"
        }
        return "[phone \(phone), mac \(s.macHome ? "home" : "away"), armed \(s.armedUntil != nil)]"
    }

    func scheduleTick() {
        guard presence.armedUntil != nil else {
            tickTimer?.invalidate()
            tickTimer = nil
            return
        }
        guard tickTimer == nil else { return }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.handle(.tick)
        }
    }

    func homeProbed(_ mac: String?) {
        snapshot.gatewayMAC = mac
        adoptHomeIfNeeded(mac)
        let atHome = NetParse.isHome(gatewayMAC: mac, homeMAC: settings.homeGatewayMAC)
        FileLog.write("home probe · gateway mac \(mac ?? "none") · saved \(settings.homeGatewayMAC ?? "none") · macHome \(atHome)")
        if atHome != presence.macHome {
            handle(.macHome(atHome))
        } else {
            publish()
        }
    }

    /// no home saved and a gateway mac readable: save it as home. a state update only, never a trigger.
    /// a saved home is never overwritten here.
    func adoptHomeIfNeeded(_ mac: String?) {
        guard let adopted = NetParse.homeToAdopt(saved: settings.homeGatewayMAC, current: mac) else { return }
        settings.homeGatewayMAC = adopted
        onSettingsChange?(settings)
        presence.macHome = true
        appendLog("home network set automatically · change it in the home tab")
    }

    func publish() {
        snapshot.phoneHome = presence.phoneHome
        snapshot.macHome = presence.macHome
        snapshot.armedUntil = presence.armedUntil
        snapshot.lastTrigger = presence.lastTrigger
        snapshot.smartThingsTokenSet = tokenSet
        onChange?(snapshot)
    }

    // MARK: phone (ntfy)

    func startNtfy() {
        FileLog.write("ntfy stream starting · \(FileLog.mask(settings.phoneTopic))")
        ntfy.start(
            topic: settings.phoneTopic,
            onListening: { [weak self] up in DispatchQueue.main.async { self?.setListening(up) } },
            onMessage: { [weak self] m in DispatchQueue.main.async { self?.phoneMessage(m) } }
        )
    }

    func setListening(_ up: Bool) {
        snapshot.listening = up
        publish()
    }

    func phoneMessage(_ m: NtfyMessage) {
        let now = Date()
        let age = Int(now.timeIntervalSince(m.time))
        let verdict = ntfyFilter.verdict(m, now: now)
        guard verdict == .accept else {
            FileLog.write("ntfy message · age \(age)s · body \(m.body.count) chars · dropped · \(verdict)")
            return
        }
        let signal = PhoneSignal.classify(m.body)
        FileLog.write("ntfy message · age \(age)s · body \(m.body.count) chars · accepted · signal \(signal.map { "\($0)" } ?? "none")")
        guard let signal else { return }
        switch signal {
        case .arrived:
            snapshot.lastPhoneSignal = m.time
            handle(.phoneArrived, now: now)
        case .left:
            snapshot.lastPhoneSignal = m.time
            handle(.phoneLeft, now: now)
        case .test:
            // a round trip only: proves the stream works, never feeds the presence machine
            snapshot.lastPhoneSignal = now
            appendLog("heard from phone · test")
            publish()
        }
    }

    func observeWake() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.wake()
        }
    }

    func wake() {
        if running && !dryRun { startNtfy() }
        home.refresh()
    }

    func refreshReadiness() {
        snapshot.smartThingsTokenSet = tokenSet
        switch snapshot.tv {
        case .ready, .notSetUp: setStatus(.tv, readiness(.tv))
        default: break
        }
    }
}
