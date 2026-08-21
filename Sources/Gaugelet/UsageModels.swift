import Foundation

enum DemoScenario: String, CaseIterable, Identifiable, Sendable {
    case comfortable
    case low
    case capped
    case signedOut

    var id: String { rawValue }

    var title: String {
        switch self {
        case .comfortable: "Comfortable"
        case .low: "Running low"
        case .capped: "Limit reached"
        case .signedOut: "Signed out"
        }
    }
}

enum UsageTone: Equatable, Sendable {
    case comfortable
    case warning
    case critical
    case unavailable
}

enum UsageSource: Equatable, Sendable {
    case codexAppServer
    case demo

    var badgeTitle: String {
        switch self {
        case .codexAppServer: "LIVE"
        case .demo: "DEMO"
        }
    }
}

enum UsageSourcePreference: String, CaseIterable, Identifiable, Sendable {
    case codexAppServer
    case demo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .codexAppServer: "Codex (live)"
        case .demo: "Demo data"
        }
    }
}

enum GaugeletIconStyle: String, CaseIterable, Identifiable, Sendable {
    case core
    case aurora
    case ember
    case moss
    case monochrome
    case eightBit
    case pride

    var id: String { rawValue }

    var title: String {
        switch self {
        case .core: "Core"
        case .aurora: "Dark Dracula"
        case .ember: "Ember"
        case .moss: "Moss"
        case .monochrome: "Mono"
        case .eightBit: "8-Bit"
        case .pride: "Pride"
        }
    }

    var resourceName: String {
        switch self {
        case .core: "Core"
        case .aurora: "Aurora"
        case .ember: "Ember"
        case .moss: "Moss"
        case .monochrome: "Monochrome"
        case .eightBit: "8Bit"
        case .pride: "Pride"
        }
    }

    var accentPalette: GaugeletAccentPalette {
        switch self {
        case .core:
            GaugeletAccentPalette(lightRGB: 0x1D72C7, darkRGB: 0x60BAF4)
        case .aurora:
            // Dracula's official Comment and Purple colors. Comment is used in
            // light mode because it keeps a readable contrast ratio on white.
            GaugeletAccentPalette(lightRGB: 0x6272A4, darkRGB: 0xBD93F9)
        case .ember:
            GaugeletAccentPalette(lightRGB: 0x6B5600, darkRGB: 0xFFD166)
        case .moss:
            GaugeletAccentPalette(lightRGB: 0x277247, darkRGB: 0x73D69A)
        case .monochrome:
            GaugeletAccentPalette(lightRGB: 0x4D5158, darkRGB: 0xD1D5DB)
        case .eightBit:
            GaugeletAccentPalette(lightRGB: 0x0F6795, darkRGB: 0x55C8F7)
        case .pride:
            GaugeletAccentPalette(lightRGB: 0xDB1F7E, darkRGB: 0x5FFBF1)
        }
    }
}

struct GaugeletAccentPalette: Equatable, Sendable {
    let lightRGB: UInt32
    let darkRGB: UInt32
}

struct GaugeletUsageAlert: Equatable, Sendable {
    enum Kind: String, Sendable {
        case runningLow
        case limitReached
    }

    let kind: Kind
    let identifier: String
    let title: String
    let body: String
}

struct UsageLimit: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let remainingPercent: Int
    let resetDate: Date?
    let blockedReason: String?

    init(
        id: String,
        name: String,
        remainingPercent: Int,
        resetDate: Date?,
        blockedReason: String? = nil
    ) {
        self.id = id
        self.name = name
        self.remainingPercent = remainingPercent
        self.resetDate = resetDate
        self.blockedReason = blockedReason
    }

    var clampedRemainingPercent: Int {
        min(max(remainingPercent, 0), 100)
    }

    var remainingFraction: Double {
        guard !isBlocked else { return 0 }
        return Double(clampedRemainingPercent) / 100
    }

    var isCapped: Bool {
        clampedRemainingPercent == 0
    }

    var isBlocked: Bool {
        isCapped || blockedReason != nil
    }

    var effectiveRemainingPercent: Int {
        isBlocked ? 0 : clampedRemainingPercent
    }

    var displayContext: String? {
        let components = name.components(separatedBy: " · ")
        guard components.count > 1 else { return nil }
        return components.dropLast().joined(separator: " · ")
    }

    var displayName: String {
        let components = name.components(separatedBy: " · ")
        let rawWindow = components.last ?? name
        let readableWindow = rawWindow
            .replacingOccurrences(of: "-hour", with: " hour", options: [.caseInsensitive])
            .replacingOccurrences(of: "-day", with: " day", options: [.caseInsensitive])
            .replacingOccurrences(of: "-week", with: " week", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = readableWindow.lowercased()

        if lowercased.hasSuffix(" usage limit") {
            return readableWindow
        }
        if lowercased.hasSuffix(" limit") {
            return String(readableWindow.dropLast(" limit".count)) + " usage limit"
        }
        return readableWindow + " usage limit"
    }

    func tone(warningThreshold: Int) -> UsageTone {
        if isBlocked { return .critical }
        if clampedRemainingPercent <= warningThreshold { return .warning }
        return .comfortable
    }

    func resetDescription(from now: Date = Date()) -> String {
        resetDate?.gaugeletRelativeReset(from: now) ?? "Reset time unavailable"
    }
}

struct UsageSnapshot: Equatable, Sendable {
    let planName: String
    let limits: [UsageLimit]
    let lastUpdated: Date
    let isSignedIn: Bool
    let note: String
    let source: UsageSource
    let sourceDetail: String

    var closestLimit: UsageLimit? {
        limits.min {
            if $0.effectiveRemainingPercent == $1.effectiveRemainingPercent {
                switch ($0.resetDate, $1.resetDate) {
                case let (.some(lhs), .some(rhs)):
                    return lhs < rhs
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                case (.none, .none):
                    return $0.id < $1.id
                }
            }
            return $0.effectiveRemainingPercent < $1.effectiveRemainingPercent
        }
    }

    var otherLimits: [UsageLimit] {
        guard let closestLimit else { return limits }
        return limits.filter { $0.id != closestLimit.id }
    }
}

enum UsageState: Equatable, Sendable {
    case loading
    case live(UsageSnapshot)
    case stale(snapshot: UsageSnapshot, errorMessage: String, failedAt: Date)
    case unavailable(errorMessage: String)
    case demo(UsageSnapshot)

    var snapshot: UsageSnapshot? {
        switch self {
        case .loading, .unavailable:
            nil
        case .live(let snapshot), .demo(let snapshot):
            snapshot
        case .stale(let snapshot, _, _):
            snapshot
        }
    }

    var badgeTitle: String {
        switch self {
        case .loading: "CONNECTING"
        case .live(let snapshot): snapshot.source.badgeTitle
        case .stale: "STALE"
        case .unavailable: "OFFLINE"
        case .demo: "DEMO"
        }
    }

    var sourceDetail: String {
        switch self {
        case .loading:
            "Connecting to Codex. No usage value is available yet."
        case .live(let snapshot), .demo(let snapshot):
            snapshot.sourceDetail
        case .stale(let snapshot, let errorMessage, _):
            "Showing the last live reading from \(snapshot.lastUpdated.formatted(date: .omitted, time: .shortened)). \(errorMessage)"
        case .unavailable(let errorMessage):
            errorMessage
        }
    }
}

enum UsageNotificationPolicy {
    static func alert(
        previous: UsageSnapshot?,
        current: UsageSnapshot?,
        warningThreshold: Int
    ) -> GaugeletUsageAlert? {
        guard
            let previous,
            let current,
            previous.source == .codexAppServer,
            current.source == .codexAppServer,
            previous.isSignedIn,
            current.isSignedIn,
            let previousLimit = previous.closestLimit,
            let currentLimit = current.closestLimit,
            previousLimit.id == currentLimit.id
        else {
            return nil
        }

        let identifier = "gaugelet.usage.\(currentLimit.id)"
        if currentLimit.isBlocked && !previousLimit.isBlocked {
            return GaugeletUsageAlert(
                kind: .limitReached,
                identifier: identifier,
                title: "Usage limit reached",
                body: "\(currentLimit.displayName) is unavailable until it resets."
            )
        }

        let threshold = min(max(warningThreshold, 5), 50)
        if
            !currentLimit.isBlocked,
            currentLimit.clampedRemainingPercent <= threshold,
            previousLimit.clampedRemainingPercent > threshold
        {
            return GaugeletUsageAlert(
                kind: .runningLow,
                identifier: identifier,
                title: "Usage running low",
                body: "\(currentLimit.displayName) has \(currentLimit.clampedRemainingPercent)% remaining."
            )
        }

        return nil
    }
}

enum DemoUsageProvider {
    static func snapshot(for scenario: DemoScenario, now: Date = Date()) -> UsageSnapshot {
        switch scenario {
        case .comfortable:
            UsageSnapshot(
                planName: "ChatGPT plan",
                limits: [
                    UsageLimit(
                        id: "five-hour",
                        name: "5-hour limit",
                        remainingPercent: 68,
                        resetDate: now.addingTimeInterval(2 * 60 * 60 + 14 * 60)
                    ),
                    UsageLimit(
                        id: "weekly",
                        name: "Weekly limit",
                        remainingPercent: 42,
                        resetDate: now.addingTimeInterval(3 * 24 * 60 * 60 + 8 * 60 * 60)
                    ),
                    UsageLimit(
                        id: "codex-spark-weekly",
                        name: "Codex Spark · Weekly",
                        remainingPercent: 88,
                        resetDate: now.addingTimeInterval(5 * 24 * 60 * 60 + 3 * 60 * 60)
                    )
                ],
                lastUpdated: now,
                isSignedIn: true,
                note: "You have room for normal use.",
                source: .demo,
                sourceDetail: "Demo data only. No account information is being read."
            )

        case .low:
            UsageSnapshot(
                planName: "ChatGPT plan",
                limits: [
                    UsageLimit(
                        id: "five-hour",
                        name: "5-hour limit",
                        remainingPercent: 16,
                        resetDate: now.addingTimeInterval(47 * 60)
                    ),
                    UsageLimit(
                        id: "weekly",
                        name: "Weekly limit",
                        remainingPercent: 31,
                        resetDate: now.addingTimeInterval(2 * 24 * 60 * 60 + 5 * 60 * 60)
                    ),
                    UsageLimit(
                        id: "codex-spark-weekly",
                        name: "Codex Spark · Weekly",
                        remainingPercent: 64,
                        resetDate: now.addingTimeInterval(4 * 24 * 60 * 60 + 9 * 60 * 60)
                    )
                ],
                lastUpdated: now,
                isSignedIn: true,
                note: "Consider lighter tasks until this limit resets.",
                source: .demo,
                sourceDetail: "Demo data only. No account information is being read."
            )

        case .capped:
            UsageSnapshot(
                planName: "ChatGPT plan",
                limits: [
                    UsageLimit(
                        id: "five-hour",
                        name: "5-hour limit",
                        remainingPercent: 0,
                        resetDate: now.addingTimeInterval(28 * 60)
                    ),
                    UsageLimit(
                        id: "weekly",
                        name: "Weekly limit",
                        remainingPercent: 28,
                        resetDate: now.addingTimeInterval(2 * 24 * 60 * 60)
                    ),
                    UsageLimit(
                        id: "codex-spark-weekly",
                        name: "Codex Spark · Weekly",
                        remainingPercent: 52,
                        resetDate: now.addingTimeInterval(4 * 24 * 60 * 60)
                    )
                ],
                lastUpdated: now,
                isSignedIn: true,
                note: "This limit is unavailable until the reset.",
                source: .demo,
                sourceDetail: "Demo data only. No account information is being read."
            )

        case .signedOut:
            UsageSnapshot(
                planName: "Not connected",
                limits: [],
                lastUpdated: now,
                isSignedIn: false,
                note: "Open ChatGPT to review account usage.",
                source: .demo,
                sourceDetail: "Demo data only. No account information is being read."
            )
        }
    }

}

extension Date {
    func gaugeletRelativeReset(from now: Date = Date()) -> String {
        let remaining = max(timeIntervalSince(now), 0)
        let minutes = Int(remaining / 60)

        if minutes < 1 { return "Resets shortly" }
        if minutes < 60 { return "Resets in \(minutes)m" }

        let hours = minutes / 60
        let leftoverMinutes = minutes % 60

        if hours < 24 {
            if leftoverMinutes == 0 { return "Resets in \(hours)h" }
            return "Resets in \(hours)h \(leftoverMinutes)m"
        }

        let days = hours / 24
        let leftoverHours = hours % 24
        if leftoverHours == 0 { return "Resets in \(days)d" }
        return "Resets in \(days)d \(leftoverHours)h"
    }
}
