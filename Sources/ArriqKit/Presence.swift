import Foundation

/// why a trigger that would have fired did not
public enum PresenceBlock: Equatable, Sendable {
    case cooldown
}

/// pure presence machine. the phone arrival is the anchor of every trigger.
/// returns the next state and whether a trigger fires (cooldown already applied).
public func reduce(_ s: PresenceState, _ e: PresenceEvent, now: Date, config: PresenceConfig) -> (PresenceState, trigger: Bool) {
    let r = reduceDetailed(s, e, now: now, config: config)
    return (r.state, r.trigger)
}

/// same as `reduce`, and also says when the cooldown kept a trigger from firing (for the log)
public func reduceDetailed(_ s: PresenceState, _ e: PresenceEvent, now: Date, config: PresenceConfig)
    -> (state: PresenceState, trigger: Bool, blocked: PresenceBlock?) {
    var s = s
    var fire = false
    var blocked: PresenceBlock? = nil
    switch e {
    case .phoneLeft:
        s.phoneHome = false
        s.armedUntil = nil
    case .macHome(let home):
        s.macHome = home
        if home {
            if let until = s.armedUntil, until > now, s.phoneHome == true {
                fire = true
                s.armedUntil = nil
            }
        } else {
            s.armedUntil = nil
        }
    case .phoneArrived:
        // duplicate arrivals are ignored
        if s.phoneHome != true {
            s.phoneHome = true
            if s.macHome {
                fire = true
            } else {
                s.armedUntil = now.addingTimeInterval(config.pairWindow)
            }
        }
    case .tick:
        if let until = s.armedUntil, until <= now { s.armedUntil = nil }
    }
    if fire {
        if let last = s.lastTrigger, now.timeIntervalSince(last) < config.cooldown {
            fire = false
            blocked = .cooldown
            s.armedUntil = nil
        } else {
            s.lastTrigger = now
        }
    }
    return (s, fire, blocked)
}
