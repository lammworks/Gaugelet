import Foundation

enum UsagePowerSource: Sendable {
    case acPower
    case battery
    case ups
    case unknown
}

enum UsageRefreshPolicy: Equatable, Sendable {
    case acPower
    case battery
    case lowPower

    var interval: TimeInterval {
        switch self {
        case .acPower: 5 * 60
        case .battery: 10 * 60
        case .lowPower: 15 * 60
        }
    }

    static func resolve(
        powerSource: UsagePowerSource,
        isLowPowerModeEnabled: Bool
    ) -> UsageRefreshPolicy {
        if isLowPowerModeEnabled { return .lowPower }
        switch powerSource {
        case .battery, .ups: return .battery
        case .acPower, .unknown: return .acPower
        }
    }
}
