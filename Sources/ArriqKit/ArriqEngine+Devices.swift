import Foundation

// device runs: fire, delay, status, log. all on the main thread.
extension ArriqEngine {
    func fireDevices() {
        onFire?()
        for kind in DeviceKind.allCases where settings.setting(for: kind).enabled {
            startDevice(kind, after: Double(settings.setting(for: kind).delaySeconds))
        }
    }

    func startDevice(_ kind: DeviceKind, after delay: Double) {
        let stamp = (stamps[kind] ?? 0) + 1
        stamps[kind] = stamp
        let settingsAtStart = settings
        let go: () -> Void = { [weak self] in
            // an off (or a newer run) since this was scheduled wins: a delayed on never lands after an off
            guard let self, self.stamps[kind] == stamp else { return }
            self.runDevice(kind, stamp: stamp, settings: settingsAtStart)
        }
        if delay <= 0 {
            go()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: go)
        }
    }

    func runDevice(_ kind: DeviceKind, stamp: Int, settings used: Settings) {
        if let reason = TVDriver.notSetUpReason(settings: used, tokenSet: tokenSet), kind == .tv {
            appendLog("tv skipped · \(reason)")
            setStatus(kind, .notSetUp(reason))
            publish()
            return
        }
        setStatus(kind, .working)
        FileLog.write("\(kind) start · \(used.setting(for: kind).delaySeconds)s delay done")
        publish()
        let dry = dryRun
        Task {
            let outcome = await ArriqEngine.driver(kind, settings: used, dryRun: dry)
            DispatchQueue.main.async { [weak self] in
                self?.finishDevice(kind, stamp: stamp, outcome: outcome)
            }
        }
    }

    func finishDevice(_ kind: DeviceKind, stamp: Int, outcome: DeviceOutcome) {
        if let ip = outcome.lampIP, ip != settings.lampIP {
            settings.lampIP = ip
            onSettingsChange?(settings)
        }
        appendLog(outcome.text)
        if let hint = outcome.hint { appendLog(hint) }
        ArriqLog.drivers.info("\(String(describing: kind), privacy: .public) ok=\(outcome.ok, privacy: .public)")
        setStatus(kind, outcome.ok ? .done : .failed(Self.reason(outcome.text)))
        if outcome.ok { snapshot.power[kind] = true }
        publish()
        if kind == .speaker, outcome.ok, settings.musicEnabled { runMusic(stamp: stamp) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self, self.stamps[kind] == stamp else { return }
            self.setStatus(kind, self.readiness(kind))
            self.publish()
        }
    }

    /// on demand off: cancels any pending arrival run for this device, then switches it off.
    /// ends at the device's resting state (ready / not set up) or failed.
    func stopDevice(_ kind: DeviceKind) {
        let stamp = (stamps[kind] ?? 0) + 1
        stamps[kind] = stamp
        let used = settings
        if kind == .tv, let reason = TVDriver.notSetUpReason(settings: used, tokenSet: tokenSet) {
            appendLog("tv off skipped · \(reason)")
            setStatus(kind, .notSetUp(reason))
            publish()
            return
        }
        setStatus(kind, .working)
        publish()
        let dry = dryRun
        Task {
            let outcome = await ArriqEngine.offDriver(kind, settings: used, dryRun: dry)
            // the speaker carries the music: pausing it is part of switching the speaker off
            let music: DeviceOutcome? = kind == .speaker && used.musicEnabled
                ? await MusicDriver.pause(dryRun: dry) : nil
            DispatchQueue.main.async { [weak self] in
                guard let self, self.stamps[kind] == stamp else { return }
                if let ip = outcome.lampIP, ip != self.settings.lampIP {
                    self.settings.lampIP = ip
                    self.onSettingsChange?(self.settings)
                }
                for o in [outcome, music].compactMap({ $0 }) {
                    self.appendLog(o.text)
                    if let hint = o.hint { self.appendLog(hint) }
                }
                self.setStatus(kind, outcome.ok ? self.readiness(kind) : .failed(Self.reason(outcome.text)))
                if outcome.ok { self.snapshot.power[kind] = false }
                self.publish()
            }
        }
    }

    /// sends the current brightness and colour to the lamp, only while arriq knows it is on.
    /// overlapping calls collapse: the newest settings win, older replies are dropped.
    func adjustLampNow() {
        guard snapshot.power[.lamp] == true else { return }
        adjustStamp += 1
        let stamp = adjustStamp
        let used = settings
        let dry = dryRun
        Task {
            let outcome = await LampDriver.adjust(settings: used, dryRun: dry)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.adjustStamp == stamp else { return }
                if let ip = outcome.lampIP, ip != self.settings.lampIP {
                    self.settings.lampIP = ip
                    self.onSettingsChange?(self.settings)
                }
                // a drag sends many of these: log failures, keep successes out of the log
                if !outcome.ok {
                    self.appendLog(outcome.text)
                    if let hint = outcome.hint { self.appendLog(hint) }
                }
                FileLog.write(outcome.text)
                self.publish()
            }
        }
    }

    static func offDriver(_ kind: DeviceKind, settings: Settings, dryRun: Bool) async -> DeviceOutcome {
        switch kind {
        case .lamp: return await LampDriver.off(settings: settings, dryRun: dryRun)
        case .speaker: return await SpeakerDriver.off(settings: settings, dryRun: dryRun)
        case .tv: return await TVDriver.off(settings: settings, dryRun: dryRun)
        }
    }

    /// starts the playlist once the speaker is on; a failure shows on the speaker status
    func runMusic(stamp: Int) {
        let used = settings
        let dry = dryRun
        Task {
            let outcome = await MusicDriver.run(settings: used, dryRun: dry)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.stamps[.speaker] == stamp else { return }
                self.appendLog(outcome.text)
                if let hint = outcome.hint { self.appendLog(hint) }
                if !outcome.ok { self.setStatus(.speaker, .failed(Self.reason(outcome.text))) }
                self.publish()
            }
        }
    }

    static func driver(_ kind: DeviceKind, settings: Settings, dryRun: Bool) async -> DeviceOutcome {
        switch kind {
        case .lamp: return await LampDriver.run(settings: settings, dryRun: dryRun)
        case .speaker: return await SpeakerDriver.run(settings: settings, dryRun: dryRun)
        case .tv: return await TVDriver.run(settings: settings, dryRun: dryRun)
        }
    }

    /// the part after the last " · " of a log line, for the failed status
    static func reason(_ text: String) -> String {
        text.components(separatedBy: " · ").last ?? text
    }

    func readiness(_ kind: DeviceKind) -> DeviceStatus {
        if kind == .tv, let reason = TVDriver.notSetUpReason(settings: settings, tokenSet: tokenSet) {
            return .notSetUp(reason)
        }
        return .ready
    }

    func status(_ kind: DeviceKind) -> DeviceStatus {
        switch kind {
        case .lamp: return snapshot.lamp
        case .speaker: return snapshot.speaker
        case .tv: return snapshot.tv
        }
    }

    func setStatus(_ kind: DeviceKind, _ s: DeviceStatus) {
        switch kind {
        case .lamp: snapshot.lamp = s
        case .speaker: snapshot.speaker = s
        case .tv: snapshot.tv = s
        }
    }

    func appendLog(_ text: String) {
        FileLog.write(text)
        snapshot.log.append(LogLine(text: text))
        if snapshot.log.count > 200 {
            snapshot.log.removeFirst(snapshot.log.count - 200)
        }
    }
}
