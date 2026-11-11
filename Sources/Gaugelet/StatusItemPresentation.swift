import AppKit

/// The status item's observable text, independent of refresh timestamps.
struct StatusItemPresentation: Equatable, Sendable {
    let title: String
    let toolTip: String
    let accessibilityLabel: String

    static func make(
        state: UsageState,
        pinnedID: String,
        showPercentage: Bool,
        now: Date = Date()
    ) -> Self {
        switch state {
        case .loading:
            return Self(
                title: showPercentage ? "  —" : "",
                toolTip: "Gaugelet — connecting to Codex",
                accessibilityLabel: "Gaugelet, connecting to Codex"
            )
        case .unavailable:
            return Self(
                title: showPercentage ? "  —" : "",
                toolTip: "Gaugelet — live usage unavailable",
                accessibilityLabel: "Gaugelet, live usage unavailable"
            )
        case .live(let snapshot), .stale(let snapshot, _, _), .demo(let snapshot):
            let limit = snapshot.menuBarLimit(pinnedID: pinnedID)
            let value = statusValue(snapshot: snapshot, limit: limit, now: now)
            let label = accessibilityLabel(snapshot: snapshot, limit: limit)
            switch state {
            case .stale:
                return Self(
                    title: showPercentage ? "  ! \(value)" : "  !",
                    toolTip: "Gaugelet — showing stale usage; open for details",
                    accessibilityLabel: "\(label), stale"
                )
            case .demo:
                return Self(
                    title: showPercentage ? "  D \(value)" : "  D",
                    toolTip: "Gaugelet — demo data",
                    accessibilityLabel: "\(label), demo data"
                )
            default:
                return Self(
                    title: showPercentage ? "  \(value)" : "",
                    toolTip: "Gaugelet — \(limit?.compactName ?? "Pinned limit unavailable")",
                    accessibilityLabel: label
                )
            }
        }
    }

    /// Only a visible capped allowance's countdown can change without new data.
    static func nextUpdateDate(
        state: UsageState,
        pinnedID: String,
        showPercentage: Bool,
        now: Date = Date()
    ) -> Date? {
        guard showPercentage,
              let snapshot = state.snapshot, snapshot.isSignedIn,
              let limit = snapshot.menuBarLimit(pinnedID: pinnedID),
              limit.blockedReason == nil, limit.isCapped,
              let resetDate = limit.resetDate
        else { return nil }

        let remaining = resetDate.timeIntervalSince(now)
        guard remaining.isFinite, remaining >= 120 else { return nil }

        let unit: TimeInterval
        if remaining >= 86_400 {
            unit = 86_400
        } else if remaining >= 3_600 {
            unit = 3_600
        } else {
            unit = 60
        }
        let boundary = resetDate.addingTimeInterval(-floor(remaining / unit) * unit)
        // The formatter rounds down. Cross the boundary before rendering again,
        // including when `now` is exactly an hour, day, or minute boundary.
        return boundary.addingTimeInterval(0.001)
    }

    private static func statusValue(snapshot: UsageSnapshot, limit: UsageLimit?, now: Date) -> String {
        guard snapshot.isSignedIn, let limit else { return "—" }
        if limit.blockedReason != nil { return "blocked" }
        if limit.isCapped { return limit.resetDate?.gaugeletCountdownValue(from: now) ?? "0%" }
        return "\(limit.clampedRemainingPercent)%"
    }

    private static func accessibilityLabel(snapshot: UsageSnapshot, limit: UsageLimit?) -> String {
        guard snapshot.isSignedIn else { return "Gaugelet, not connected" }
        guard let limit else { return "Gaugelet, selected allowance unavailable" }
        if let blockedReason = limit.blockedReason {
            return "Gaugelet, \(limit.displayName), \(blockedReason.lowercased())"
        }
        return "Gaugelet, \(limit.displayName), \(limit.clampedRemainingPercent) percent left"
    }
}

@MainActor
protocol StatusItemPresentationTarget: AnyObject {
    var title: String { get set }
    var toolTip: String? { get set }
    func setAccessibilityLabel(_ label: String?)
}

extension NSStatusBarButton: StatusItemPresentationTarget {}

/// Avoids AppKit invalidation for fields whose displayed value is unchanged.
@MainActor
final class StatusItemPresenter {
    private weak var lastTarget: (any StatusItemPresentationTarget)?
    private var lastPresentation: StatusItemPresentation?

    @discardableResult
    func apply(_ presentation: StatusItemPresentation, to target: any StatusItemPresentationTarget) -> Int {
        let previous = lastTarget === target ? lastPresentation : nil
        // Store first so a synchronous appearance notification cannot reapply it.
        lastTarget = target
        lastPresentation = presentation
        var changedCount = 0
        if previous?.title != presentation.title {
            target.title = presentation.title
            changedCount += 1
        }
        if previous?.toolTip != presentation.toolTip {
            target.toolTip = presentation.toolTip
            changedCount += 1
        }
        if previous?.accessibilityLabel != presentation.accessibilityLabel {
            target.setAccessibilityLabel(presentation.accessibilityLabel)
            changedCount += 1
        }
        return changedCount
    }
}
