import Combine
import Foundation

/// Each hosting surface owns its visibility so closing one cannot stop another.
@MainActor
final class UsagePresentationVisibility: ObservableObject {
    @Published var isVisible = false
}

enum UsagePresentationText {
    /// A plain string lets the dashboard's visible timeline own all date updates.
    static func elapsedCheckValue(lastUpdated: Date, now: Date) -> String {
        let elapsed = max(now.timeIntervalSince(lastUpdated), 0)
        if elapsed >= 86_400 { return "\(Int(elapsed / 86_400))d" }
        if elapsed >= 3_600 { return "\(Int(elapsed / 3_600))h" }
        if elapsed >= 60 { return "\(Int(elapsed / 60))m" }
        return "\(Int(elapsed))s"
    }

    static func readOnlyHelp(policy: UsageRefreshPolicy) -> String {
        let activeMinutes = Int(policy.interval / 60)
        let acMinutes = Int(UsageRefreshPolicy.acPower.interval / 60)
        let batteryMinutes = Int(UsageRefreshPolicy.battery.interval / 60)
        let lowPowerMinutes = Int(UsageRefreshPolicy.lowPower.interval / 60)
        return "ChatGPT Work and Codex allowance. Background checks every \(activeMinutes) minutes now: \(acMinutes) on AC power, \(batteryMinutes) on battery, \(lowPowerMinutes) in Low Power Mode. Also refreshes on wake, open, and reset."
    }
}
