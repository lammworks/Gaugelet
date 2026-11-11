import Foundation
import XCTest
@testable import Gaugelet

final class StatusItemPresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testPreservesTitlesTooltipsAndAccessibilityAcrossStates() {
        let snapshot = snapshot()
        let cases: [(UsageState, String, String, String)] = [
            (.loading, "  —", "Gaugelet — connecting to Codex", "Gaugelet, connecting to Codex"),
            (.unavailable(errorMessage: "offline"), "  —", "Gaugelet — live usage unavailable", "Gaugelet, live usage unavailable"),
            (.live(snapshot), "  37%", "Gaugelet — Weekly", "Gaugelet, Weekly usage limit, 37 percent left"),
            (.stale(snapshot: snapshot, errorMessage: "offline", failedAt: now), "  ! 37%", "Gaugelet — showing stale usage; open for details", "Gaugelet, Weekly usage limit, 37 percent left, stale"),
            (.demo(snapshot), "  D 37%", "Gaugelet — demo data", "Gaugelet, Weekly usage limit, 37 percent left, demo data")
        ]
        for (state, title, toolTip, label) in cases {
            let presentation = make(state)
            XCTAssertEqual(presentation.title, title)
            XCTAssertEqual(presentation.toolTip, toolTip)
            XCTAssertEqual(presentation.accessibilityLabel, label)
        }
    }

    func testHidingPercentagePreservesStaleAndDemoMarkers() {
        let snapshot = snapshot()
        XCTAssertEqual(make(.loading, showPercentage: false).title, "")
        XCTAssertEqual(make(.live(snapshot), showPercentage: false).title, "")
        XCTAssertEqual(make(.stale(snapshot: snapshot, errorMessage: "", failedAt: now), showPercentage: false).title, "  !")
        XCTAssertEqual(make(.demo(snapshot), showPercentage: false).title, "  D")
    }

    func testSelectedBlockedMissingAndSignedOutAllowances() {
        let blocked = UsageLimit(id: "blocked", name: "Spark · 5-hour", remainingPercent: 70, resetDate: nil, blockedReason: "Workspace credits depleted")
        let snapshot = snapshot(limits: [blocked])
        XCTAssertEqual(make(.live(snapshot), pinnedID: "blocked").title, "  blocked")
        XCTAssertEqual(make(.live(snapshot), pinnedID: "blocked").accessibilityLabel, "Gaugelet, 5 hour usage limit, workspace credits depleted")
        XCTAssertEqual(make(.live(snapshot), pinnedID: "missing").title, "  —")
        XCTAssertEqual(make(.live(snapshot), pinnedID: "missing").toolTip, "Gaugelet — Pinned limit unavailable")
        XCTAssertEqual(make(.live(snapshot), pinnedID: "missing").accessibilityLabel, "Gaugelet, selected allowance unavailable")
        XCTAssertEqual(make(.live(self.snapshot(isSignedIn: false))).title, "  —")
        XCTAssertEqual(make(.live(self.snapshot(isSignedIn: false))).accessibilityLabel, "Gaugelet, not connected")
    }

    func testOnlyVisibleTextAffectsPresentationEquality() {
        let original = snapshot()
        let later = snapshot(lastUpdated: now.addingTimeInterval(60))
        XCTAssertEqual(make(.live(original)), make(.live(later)))
        XCTAssertEqual(
            make(.stale(snapshot: original, errorMessage: "first", failedAt: now)),
            make(.stale(snapshot: later, errorMessage: "second", failedAt: now.addingTimeInterval(60)))
        )
    }

    func testCountdownSchedulesOnlyWhenDisplayedValueWillChange() throws {
        let cases: [(TimeInterval, String, TimeInterval, String)] = [
            (125, "2m", 5.001, "1m"),
            (3_630, "1h", 30.001, "59m"),
            (7_230, "2h", 30.001, "1h"),
            (86_430, "1d", 30.001, "23h"),
            (172_830, "2d", 30.001, "1d"),
            (120, "2m", 0.001, "1m"),
            (3_600, "1h", 0.001, "59m"),
            (86_400, "1d", 0.001, "23h")
        ]
        for (remaining, current, delay, next) in cases {
            let state = cappedState(remaining: remaining)
            XCTAssertEqual(make(state).title, "  \(current)")
            let date = try XCTUnwrap(StatusItemPresentation.nextUpdateDate(state: state, pinnedID: "", showPercentage: true, now: now))
            XCTAssertEqual(date.timeIntervalSince(now), delay, accuracy: 0.000_01)
            XCTAssertEqual(StatusItemPresentation.make(state: state, pinnedID: "", showPercentage: true, now: date).title, "  \(next)")
        }
        for remaining in [119.0, 60, 0, -60] {
            XCTAssertNil(StatusItemPresentation.nextUpdateDate(state: cappedState(remaining: remaining), pinnedID: "", showPercentage: true, now: now))
        }
    }

    func testNoCountdownTimerForHiddenBlockedOrUnavailableValue() {
        let capped = cappedState(remaining: 7_230)
        XCTAssertNil(StatusItemPresentation.nextUpdateDate(state: capped, pinnedID: "", showPercentage: false, now: now))
        XCTAssertNil(StatusItemPresentation.nextUpdateDate(state: capped, pinnedID: "missing", showPercentage: true, now: now))
        XCTAssertNil(StatusItemPresentation.nextUpdateDate(state: .live(snapshot()), pinnedID: "", showPercentage: true, now: now))
        XCTAssertNil(StatusItemPresentation.nextUpdateDate(state: .loading, pinnedID: "", showPercentage: true, now: now))
        let blocked = UsageLimit(id: "weekly", name: "Weekly", remainingPercent: 0, resetDate: now.addingTimeInterval(7_230), blockedReason: "Blocked")
        XCTAssertNil(StatusItemPresentation.nextUpdateDate(state: .live(snapshot(limits: [blocked])), pinnedID: "", showPercentage: true, now: now))
        let noReset = UsageLimit(id: "weekly", name: "Weekly", remainingPercent: 0, resetDate: nil)
        XCTAssertEqual(make(.live(snapshot(limits: [noReset]))).title, "  0%")
        XCTAssertNil(StatusItemPresentation.nextUpdateDate(state: .live(snapshot(limits: [noReset])), pinnedID: "", showPercentage: true, now: now))
    }

    @MainActor
    func testEquivalentEventsDoNotMutateStatusItemAgain() {
        let presenter = StatusItemPresenter()
        let target = PresentationSpy()
        let presentation = make(.live(snapshot()))
        XCTAssertEqual(presenter.apply(presentation, to: target), 3)
        for _ in 0..<1_000 {
            XCTAssertEqual(presenter.apply(presentation, to: target), 0)
        }
        XCTAssertEqual(target.titleWrites, 1)
        XCTAssertEqual(target.toolTipWrites, 1)
        XCTAssertEqual(target.accessibilityWrites, 1)
        XCTAssertEqual(presenter.apply(make(.live(snapshot()), showPercentage: false), to: target), 1)
        XCTAssertEqual(target.titleWrites, 2)
        XCTAssertEqual(target.toolTipWrites, 1)
        XCTAssertEqual(target.accessibilityWrites, 1)
    }

    @MainActor
    func testNewTargetReceivesPresentationAndSynchronousFeedbackIsDeduplicated() {
        let presenter = StatusItemPresenter()
        let target = PresentationSpy()
        let presentation = make(.loading)
        target.onTitleChanged = { XCTAssertEqual(presenter.apply(presentation, to: target), 0) }
        XCTAssertEqual(presenter.apply(presentation, to: target), 3)
        let replacement = PresentationSpy()
        XCTAssertEqual(presenter.apply(presentation, to: replacement), 3)
        XCTAssertEqual(replacement.titleWrites, 1)
        XCTAssertEqual(replacement.toolTipWrites, 1)
        XCTAssertEqual(replacement.accessibilityWrites, 1)
    }

    private func make(_ state: UsageState, pinnedID: String = "", showPercentage: Bool = true) -> StatusItemPresentation {
        StatusItemPresentation.make(state: state, pinnedID: pinnedID, showPercentage: showPercentage, now: now)
    }

    private func cappedState(remaining: TimeInterval) -> UsageState {
        .live(snapshot(limits: [UsageLimit(id: "weekly", name: "Weekly", remainingPercent: 0, resetDate: now.addingTimeInterval(remaining))]))
    }

    private func snapshot(limits: [UsageLimit]? = nil, isSignedIn: Bool = true, lastUpdated: Date? = nil) -> UsageSnapshot {
        UsageSnapshot(
            planName: "ChatGPT plan",
            limits: limits ?? [UsageLimit(id: "weekly", name: "Weekly", remainingPercent: 37, resetDate: nil)],
            lastUpdated: lastUpdated ?? now,
            isSignedIn: isSignedIn,
            note: "",
            source: .codexAppServer,
            sourceDetail: ""
        )
    }
}

@MainActor
private final class PresentationSpy: StatusItemPresentationTarget {
    var title = "" {
        didSet {
            titleWrites += 1
            onTitleChanged?()
        }
    }
    var toolTip: String? { didSet { toolTipWrites += 1 } }
    var titleWrites = 0
    var toolTipWrites = 0
    var accessibilityWrites = 0
    var onTitleChanged: (() -> Void)?

    func setAccessibilityLabel(_ label: String?) {
        accessibilityWrites += 1
    }
}
