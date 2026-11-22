import Foundation

/// Adaptive refresh and timer cadence based on power source and Low Power Mode.
///
/// Desktop Macs without a battery stay on the AC profile, but still use
/// App Nap–friendly timer tolerances and skip unchanged status-item redraws.
struct GaugeletEnergyPolicy: Equatable, Sendable {
    enum PowerMode: String, Equatable, Sendable {
        case ac
        case battery
        case lowPower
    }

    let mode: PowerMode
    /// True when IOKit reports at least one internal battery power source.
    let hasInternalBattery: Bool

    /// How often the idle timer wakes to decide whether a provider refresh is due.
    var timerInterval: TimeInterval {
        switch mode {
        case .ac: 60
        case .battery: 180
        case .lowPower: 300
        }
    }

    /// Timer tolerance so the run loop can coalesce wakes (App Nap friendly).
    var timerTolerance: TimeInterval {
        switch mode {
        case .ac: 15
        case .battery: 45
        case .lowPower: 90
        }
    }

    /// Minimum age before `refreshIfDue` starts a background provider fetch.
    var backgroundRefreshInterval: TimeInterval {
        switch mode {
        case .ac: 5 * 60
        case .battery: 10 * 60
        case .lowPower: 15 * 60
        }
    }

    static let `default` = GaugeletEnergyPolicy(mode: .ac, hasInternalBattery: false)

    static func resolve(
        usingBatteryPower: Bool,
        hasInternalBattery: Bool,
        lowPowerModeEnabled: Bool
    ) -> GaugeletEnergyPolicy {
        let mode: PowerMode
        if lowPowerModeEnabled {
            mode = .lowPower
        } else if usingBatteryPower {
            mode = .battery
        } else {
            mode = .ac
        }
        return GaugeletEnergyPolicy(mode: mode, hasInternalBattery: hasInternalBattery)
    }
}
