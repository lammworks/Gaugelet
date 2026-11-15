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

enum UsagePlan: String, Equatable, Sendable, CaseIterable, Identifiable {
    case chatgpt
    case cursor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chatgpt: "ChatGPT"
        case .cursor: "Cursor"
        }
    }

    var subtitle: String {
        switch self {
        case .chatgpt: "ChatGPT plan usage"
        case .cursor: "Grok and Cursor plan usage"
        }
    }
}

enum UsageBillingShape: Equatable, Sendable {
    case chatGPT
    case weeklyPool
    case legacyCycle
}

enum UsageSource: Equatable, Sendable {
    case codexAppServer
    case cursorPlan
    case grokPlan
    case demo

    var badgeTitle: String {
        switch self {
        case .codexAppServer, .cursorPlan, .grokPlan: "LIVE"
        case .demo: "DEMO"
        }
    }

    var isLiveAccount: Bool {
        self != .demo
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
        case restored
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
    let bucketID: String?
    let windowDurationMins: Int?

    init(
        id: String,
        name: String,
        remainingPercent: Int,
        resetDate: Date?,
        blockedReason: String? = nil,
        bucketID: String? = nil,
        windowDurationMins: Int? = nil,
        contextNote: String? = nil
    ) {
        self.id = id
        self.name = name
        self.remainingPercent = remainingPercent
        self.resetDate = resetDate
        self.blockedReason = blockedReason
        self.bucketID = bucketID
        self.windowDurationMins = windowDurationMins
        self.contextNote = contextNote
    }

    let contextNote: String?

    var isShared: Bool { ["codex", "overall"].contains(bucketID?.lowercased() ?? "") }

    var compactName: String {
        if isShared {
            let window = name.components(separatedBy: " · ").last ?? name
            return "\(bucketID?.lowercased() == "overall" ? "Overall" : "Shared") · \(window)"
        }
        return name
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
        if lowercased.hasSuffix(" usage") {
            return readableWindow + " limit"
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

    var accountID: String? = nil
    var resetCredits: EarnedResetCredits? = nil
    var credits: [CreditBalance] = []
    var omittedLimitCount: Int = 0
    var plan: UsagePlan = .chatgpt
    var billingShape: UsageBillingShape = .chatGPT

    // Ordering never depends on consumption or reset timestamps.
    var orderedLimits: [UsageLimit] {
        limits.sorted {
            if $0.isShared != $1.isShared { return $0.isShared }
            let leftBucket = $0.bucketID ?? $0.id
            let rightBucket = $1.bucketID ?? $1.id
            if leftBucket != rightBucket { return leftBucket < rightBucket }
            return $0.id < $1.id
        }
    }

    func menuBarLimit(pinnedID: String) -> UsageLimit? {
        if !pinnedID.isEmpty { return limits.first { $0.id == pinnedID } }
        return orderedLimits.first
    }

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
        case .live(let snapshot):
            snapshot.isSignedIn ? snapshot.source.badgeTitle : "SIGNED OUT"
        case .stale: "STALE"
        case .unavailable: "OFFLINE"
        case .demo: "DEMO"
        }
    }

    var sourceDetail: String {
        detail(for: .chatgpt)
    }

    func detail(for plan: UsagePlan) -> String {
        switch self {
        case .loading:
            switch plan {
            case .chatgpt:
                "Connecting to Codex. No usage value is available yet."
            case .cursor:
                "Connecting to Cursor. No usage value is available yet."
            }
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
    static func alerts(
        previous: UsageSnapshot?, current: UsageSnapshot?, warningThreshold: Int,
        notifyOnRestore: Bool = false
    ) -> [GaugeletUsageAlert] {
        guard let previous, let current,
              previous.source.isLiveAccount, previous.source == current.source,
              previous.plan == current.plan,
              previous.isSignedIn, current.isSignedIn,
              let previousAccount = previous.accountID, !previousAccount.isEmpty,
              previousAccount == current.accountID
        else { return [] }
        let threshold = min(max(warningThreshold, 5), 50)
        return current.orderedLimits.compactMap { limit in
            guard let old = previous.limits.first(where: { $0.id == limit.id }) else { return nil }
            let kind: GaugeletUsageAlert.Kind
            let title: String
            let body: String
            if limit.isBlocked && !old.isBlocked {
                kind = .limitReached
                title = "Usage limit reached"
                body = "\(limit.compactName): \(limit.blockedReason ?? "allowance exhausted")."
            } else if !limit.isBlocked && limit.clampedRemainingPercent <= threshold && old.clampedRemainingPercent > threshold {
                kind = .runningLow
                title = "Usage running low"
                body = "\(limit.compactName) has \(limit.clampedRemainingPercent)% remaining."
            } else if notifyOnRestore && old.isBlocked && !limit.isBlocked {
                kind = .restored
                title = "Allowance restored"
                body = "\(limit.compactName) is available again · \(limit.clampedRemainingPercent)% left."
            } else { return nil }
            return GaugeletUsageAlert(
                kind: kind,
                identifier: "gaugelet.usage.\(current.plan.rawValue).\(limit.id).\(kind.rawValue)",
                title: title,
                body: body
            )
        }
    }

    static func alert(previous: UsageSnapshot?, current: UsageSnapshot?, warningThreshold: Int) -> GaugeletUsageAlert? {
        alerts(previous: previous, current: current, warningThreshold: warningThreshold).first
    }
}

struct EarnedResetCredits: Equatable, Sendable {
    let availableCount: Int
    let earliestKnownExpiry: Date?
}

struct CreditBalance: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let balance: String?
    let hasCredits: Bool
    let unlimited: Bool
    var detail: String? = nil
    var usesPlainLabel: Bool = false

    var label: String {
        usesPlainLabel ? name : "\(name) credits"
    }

    var displayValue: String {
        if unlimited { return "Unlimited" }
        if let balance { return balance }
        return hasCredits ? "Available" : "None available"
    }
}

struct ActivityDay: Identifiable, Equatable, Sendable {
    let date: String
    let tokens: Int
    var id: String { date }
}

struct UsageActivity: Equatable, Sendable {
    let days: [ActivityDay]?
    let lifetimeTokens: Int?
    let lastUpdated: Date
}

enum ActivityState: Equatable {
    case disabled
    case loading
    case available(UsageActivity)
    case unavailable
}

enum DemoUsageProvider {
    static func snapshot(for scenario: DemoScenario, now: Date = Date()) -> UsageSnapshot {
        var value = baseSnapshot(for: scenario, now: now)
        guard scenario != .signedOut else { return value }
        value.resetCredits = EarnedResetCredits(availableCount: 2, earliestKnownExpiry: now.addingTimeInterval(7 * 86_400))
        value.credits = [CreditBalance(id: "demo", name: "Demo", balance: "40", hasCredits: true, unlimited: false)]
        return value
    }

    static func cursorSnapshot(for scenario: DemoScenario, now: Date = Date()) -> UsageSnapshot {
        switch scenario {
        case .comfortable:
            cursorSnapshot(
                remaining: 72,
                reset: now.addingTimeInterval(4 * 24 * 60 * 60 + 6 * 60 * 60),
                signedIn: true,
                note: "You have room in the shared weekly pool.",
                additional: "$18.40",
                now: now
            )
        case .low:
            cursorSnapshot(
                remaining: 16,
                reset: now.addingTimeInterval(2 * 24 * 60 * 60 + 4 * 60 * 60),
                signedIn: true,
                note: "The shared weekly pool is running low.",
                additional: "$4.00",
                now: now
            )
        case .capped:
            cursorSnapshot(
                remaining: 0,
                reset: now.addingTimeInterval(18 * 60 * 60),
                signedIn: true,
                note: "The shared weekly pool is used up.",
                additional: "$0.50",
                now: now
            )
        case .signedOut:
            var snapshot = cursorSnapshot(
                remaining: 0,
                reset: nil,
                signedIn: false,
                note: "Open Cursor and sign in.",
                additional: nil,
                now: now
            )
            snapshot.limits = []
            snapshot.credits = []
            return snapshot
        }
    }

    private static func cursorSnapshot(
        remaining: Int,
        reset: Date?,
        signedIn: Bool,
        note: String,
        additional: String?,
        now: Date
    ) -> UsageSnapshot {
        var snapshot = UsageSnapshot(
            planName: signedIn ? "X Subscription" : "Not connected",
            limits: [
                UsageLimit(
                    id: "cursor:included",
                    name: "Included usage",
                    remainingPercent: remaining,
                    resetDate: reset,
                    bucketID: "a-included",
                    contextNote: "Weekly pool · Grok and Cursor"
                ),
                UsageLimit(
                    id: "cursor:models",
                    name: "Cursor models",
                    remainingPercent: remaining,
                    resetDate: reset,
                    bucketID: "b-models",
                    contextNote: "Grok and Composer · same weekly pool"
                )
            ],
            lastUpdated: now,
            isSignedIn: signedIn,
            note: note,
            source: .demo,
            sourceDetail: "Demo data only. No account information is being read."
        )
        snapshot.plan = .cursor
        snapshot.billingShape = .weeklyPool
        if signedIn {
            var credits = [
                CreditBalance(
                    id: "cursor:other-models",
                    name: "Other models",
                    balance: "Prepaid",
                    hasCredits: true,
                    unlimited: false,
                    detail: "Third-party models",
                    usesPlainLabel: true
                )
            ]
            if let additional {
                credits.append(
                    CreditBalance(
                        id: "cursor:additional",
                        name: "Additional usage",
                        balance: additional,
                        hasCredits: true,
                        unlimited: false,
                        detail: "Prepaid credit · does not reset weekly",
                        usesPlainLabel: true
                    )
                )
            }
            snapshot.credits = credits
        }
        return snapshot
    }

    static func activity(now: Date = Date()) -> UsageActivity {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let values = [12000, 34000, 18000, 0, 48000, 21000, 28000]
        return UsageActivity(days: values.enumerated().map { index, tokens in
            ActivityDay(date: formatter.string(from: now.addingTimeInterval(Double(index - 6) * 86_400)), tokens: tokens)
        }, lifetimeTokens: 161000, lastUpdated: now)
    }

    private static func baseSnapshot(for scenario: DemoScenario, now: Date = Date()) -> UsageSnapshot {
        switch scenario {
        case .comfortable:
            UsageSnapshot(
                planName: "ChatGPT plan",
                limits: [
                    UsageLimit(
                        id: "five-hour",
                        name: "Shared · 5-hour",
                        remainingPercent: 68,
                        resetDate: now.addingTimeInterval(2 * 60 * 60 + 14 * 60),
                        bucketID: "codex"
                    ),
                    UsageLimit(
                        id: "weekly",
                        name: "Shared · Weekly",
                        remainingPercent: 42,
                        resetDate: now.addingTimeInterval(3 * 24 * 60 * 60 + 8 * 60 * 60),
                        bucketID: "codex"
                    ),
                    UsageLimit(
                        id: "codex-spark-weekly",
                        name: "Codex Spark · Weekly",
                        remainingPercent: 88,
                        resetDate: now.addingTimeInterval(5 * 24 * 60 * 60 + 3 * 60 * 60),
                        bucketID: "spark"
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
                        name: "Shared · 5-hour",
                        remainingPercent: 16,
                        resetDate: now.addingTimeInterval(47 * 60),
                        bucketID: "codex"
                    ),
                    UsageLimit(
                        id: "weekly",
                        name: "Shared · Weekly",
                        remainingPercent: 31,
                        resetDate: now.addingTimeInterval(2 * 24 * 60 * 60 + 5 * 60 * 60),
                        bucketID: "codex"
                    ),
                    UsageLimit(
                        id: "codex-spark-weekly",
                        name: "Codex Spark · Weekly",
                        remainingPercent: 64,
                        resetDate: now.addingTimeInterval(4 * 24 * 60 * 60 + 9 * 60 * 60),
                        bucketID: "spark"
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
                        name: "Shared · 5-hour",
                        remainingPercent: 0,
                        resetDate: now.addingTimeInterval(28 * 60),
                        bucketID: "codex"
                    ),
                    UsageLimit(
                        id: "weekly",
                        name: "Shared · Weekly",
                        remainingPercent: 28,
                        resetDate: now.addingTimeInterval(2 * 24 * 60 * 60),
                        bucketID: "codex"
                    ),
                    UsageLimit(
                        id: "codex-spark-weekly",
                        name: "Codex Spark · Weekly",
                        remainingPercent: 52,
                        resetDate: now.addingTimeInterval(4 * 24 * 60 * 60),
                        bucketID: "spark"
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
    func gaugeletWholeMinutes(from now: Date) -> Int? {
        let interval = timeIntervalSince(now)
        guard interval.isFinite else { return nil }
        let minutes = max(interval, 0) / 60
        guard minutes.isFinite else { return nil }
        return Int(exactly: minutes.rounded(.down))
    }

    func gaugeletRelativeReset(from now: Date = Date()) -> String {
        guard let minutes = gaugeletWholeMinutes(from: now) else {
            return "Reset time unavailable"
        }

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
