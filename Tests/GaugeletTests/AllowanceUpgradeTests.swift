import Foundation
import XCTest
@testable import Gaugelet

final class AllowanceUpgradeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func snapshot(_ values: [(String, Int)], account: String? = "account-a") -> UsageSnapshot {
        var snapshot = UsageSnapshot(planName: "ChatGPT Pro", limits: values.map {
            UsageLimit(id: $0.0, name: $0.0, remainingPercent: $0.1, resetDate: now.addingTimeInterval(60),
                       bucketID: $0.0.hasPrefix("codex-") ? "codex" : "spark", windowDurationMins: 300)
        }, lastUpdated: now, isSignedIn: true, note: "", source: .codexAppServer, sourceDetail: "Test")
        snapshot.accountID = account
        return snapshot
    }

    private func response(_ result: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["id": 2, "result": result])
    }

    func testBucketSwitchAndSimultaneousCrossingsEachAlert() {
        let before = snapshot([("codex-primary", 25), ("spark-primary", 30)])
        let after = snapshot([("codex-primary", 19), ("spark-primary", 15)])
        XCTAssertNotEqual(before.closestLimit?.id, after.closestLimit?.id)
        let alerts = UsageNotificationPolicy.alerts(previous: before, current: after, warningThreshold: 20)
        XCTAssertEqual(alerts.count, 2)
        XCTAssertEqual(Set(alerts.map(\.identifier)).count, 2)
        XCTAssertTrue(UsageNotificationPolicy.alerts(previous: after, current: after, warningThreshold: 20).isEmpty)
    }

    func testRecoveryRequiresOptInAndNewBucketDoesNotAlert() {
        let before = snapshot([("codex-primary", 0)])
        let after = snapshot([("codex-primary", 80), ("spark-primary", 0)])
        XCTAssertTrue(UsageNotificationPolicy.alerts(previous: before, current: after, warningThreshold: 20).isEmpty)
        let alerts = UsageNotificationPolicy.alerts(previous: before, current: after, warningThreshold: 20, notifyOnRestore: true)
        XCTAssertEqual(alerts.map(\.kind), [.restored])
    }

    func testAccountSwitchDoesNotGenerateFalseAlerts() {
        let before = snapshot([("codex-primary", 80)])
        let after = snapshot([("codex-primary", 0)], account: "account-b")
        XCTAssertTrue(UsageNotificationPolicy.alerts(previous: before, current: after, warningThreshold: 20).isEmpty)
    }

    func testOrderAndPinnedCounterDoNotFollowMostConstrained() {
        let before = snapshot([("spark-primary", 5), ("codex-secondary", 40), ("codex-primary", 60)])
        let after = snapshot([("codex-primary", 0), ("spark-primary", 95), ("codex-secondary", 20)])
        XCTAssertEqual(before.orderedLimits.map(\.id), ["codex-primary", "codex-secondary", "spark-primary"])
        XCTAssertEqual(before.orderedLimits.map(\.id), after.orderedLimits.map(\.id))
        XCTAssertEqual(before.menuBarLimit(pinnedID: "")?.id, "codex-primary")
        XCTAssertEqual(after.menuBarLimit(pinnedID: "spark-primary")?.remainingPercent, 95)
        XCTAssertNil(after.menuBarLimit(pinnedID: "missing"))
        XCTAssertNil(GaugeletMenuBarPresentation.iconState(for: .live(after), pinnedID: "missing").percent)
    }

    func testResetCountIsAuthoritativeEvenWhenDetailsAreCapped() throws {
        let data = try response(["rateLimits": [:], "rateLimitResetCredits": [
            "availableCount": 5,
            "credits": [["status": "available", "expiresAt": 1_900_000_000],
                        ["status": "redeemed", "expiresAt": 1_850_000_000],
                        ["status": "available", "expiresAt": 1_700_000_000]]
        ]])
        let result = try CodexUsageProvider.parseSnapshot(from: data, now: now)
        XCTAssertTrue(result.limits.isEmpty)
        XCTAssertEqual(result.resetCredits?.availableCount, 5)
        XCTAssertEqual(result.resetCredits?.earliestKnownExpiry, Date(timeIntervalSince1970: 1_900_000_000))
    }

    func testResetZeroMissingAndMalformedAreDifferent() throws {
        for count: Any in [0, NSNull(), true, -1, 1.5] {
            let data = try response(["rateLimits": ["primary": ["usedPercent": 25]],
                                     "rateLimitResetCredits": ["availableCount": count]])
            let result = try CodexUsageProvider.parseSnapshot(from: data)
            if let number = count as? Int, !(count is Bool), number == 0 {
                XCTAssertEqual(result.resetCredits?.availableCount, 0)
            } else { XCTAssertNil(result.resetCredits) }
        }
    }

    func testCreditsOnlyResponseAndMalformedBalanceDoNotInventQuota() throws {
        let data = try response(["rateLimits": ["limitId": "codex", "credits": ["hasCredits": true, "unlimited": false, "balance": "45.25"]]])
        let result = try CodexUsageProvider.parseSnapshot(from: data)
        XCTAssertTrue(result.limits.isEmpty)
        XCTAssertEqual(result.credits.first?.displayValue, "45.25")
        let malformed = try response(["rateLimits": ["credits": ["hasCredits": true, "unlimited": false, "balance": "NaN"]]])
        XCTAssertEqual(try CodexUsageProvider.parseSnapshot(from: malformed).credits.first?.displayValue, "Available")
    }

    func testDailyActivityPreservesMissingVsZeroAndRejectsBadRows() throws {
        let data = try response(["summary": ["lifetimeTokens": NSNull()], "dailyUsageBuckets": [
            ["startDate": "2026-09-01", "tokens": 0], ["startDate": "2026-09-03", "tokens": 50],
            ["startDate": "2026-09-03", "tokens": 80], ["startDate": "2026-02-30", "tokens": 12],
            ["startDate": "2026-09-04", "tokens": true], ["startDate": "2026-09-05", "tokens": -1]
        ]])
        let result = try CodexUsageProvider.parseActivity(from: data)
        XCTAssertNil(result.lifetimeTokens)
        XCTAssertEqual(result.days, [ActivityDay(date: "2026-09-01", tokens: 0), ActivityDay(date: "2026-09-03", tokens: 50)])
        let missing = try CodexUsageProvider.parseActivity(from: response(["summary": [:]]))
        XCTAssertNil(missing.days)
        let empty = try CodexUsageProvider.parseActivity(from: response(["summary": [:], "dailyUsageBuckets": []]))
        XCTAssertEqual(empty.days, [])
    }

    @MainActor func testAutomaticRefreshCoalescesAndRefreshesAtReset() async throws {
        var time = now
        let provider = UpgradeTestProvider(value: snapshot([("codex-primary", 50)]))
        let defaults = defaults()
        let store = UsageStore(defaults: defaults, provider: provider, now: { time })
        store.refreshIfNeeded()
        store.refreshIfNeeded()
        try await settled(store)
        var count = await provider.calls
        XCTAssertEqual(count, 1)
        time.addTimeInterval(30)
        store.refreshIfDue()
        count = await provider.calls
        XCTAssertEqual(count, 1)
        time.addTimeInterval(31)
        store.refreshIfDue()
        try await settled(store)
        count = await provider.calls
        XCTAssertEqual(count, 2)
        store.refreshIfDue()
        count = await provider.calls
        XCTAssertEqual(count, 2)
        store.cancelRefresh()
    }

    @MainActor func testActivityIsOptInAndFailureDoesNotHideAllowance() async throws {
        let provider = UpgradeTestProvider(value: snapshot([("codex-primary", 50)]))
        let store = UsageStore(defaults: defaults(), provider: provider)
        store.refresh()
        try await settled(store)
        var count = await provider.activityCalls
        XCTAssertEqual(count, 0)
        XCTAssertEqual(store.activityState, .disabled)
        store.activityEnabled = true
        for _ in 0..<100 where store.activityState == .loading { try await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertEqual(store.activityState, .unavailable)
        guard case .live = store.state else { return XCTFail("Optional activity must not break allowance") }
        count = await provider.activityCalls
        XCTAssertEqual(count, 1)
        store.activityEnabled = false
        XCTAssertEqual(store.activityState, .disabled)
        store.cancelRefresh()
    }

    @MainActor func testStaleAndDemoDoNotTriggerRestorationAlerts() async throws {
        let provider = UpgradeTestProvider(value: snapshot([("codex-primary", 0)]))
        let store = UsageStore(defaults: defaults(), provider: provider)
        store.usageNotificationsEnabled = true
        store.notifyOnRestore = true
        var alerts: [GaugeletUsageAlert] = []
        store.onUsageAlert = { alerts.append($0) }
        store.refresh()
        try await settled(store)
        await provider.setFailure()
        store.refresh()
        try await settled(store)
        guard case .stale = store.state else { return XCTFail("Expected stale") }
        XCTAssertTrue(alerts.isEmpty)
        store.sourcePreference = .demo
        XCTAssertTrue(alerts.isEmpty)
        store.cancelRefresh()
    }

    func testLiveReadOnlyProviderWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["GAUGELET_LIVE_CHECK"] == "1" else {
            throw XCTSkip("Opt-in live integration check")
        }
        let provider = CodexUsageProvider()
        let result = try await provider.fetchSnapshot()
        XCTAssertTrue(result.isSignedIn)
        XCTAssertFalse(result.limits.isEmpty)
        let activity = try await provider.fetchActivity()
        XCTAssertNotNil(activity.days)
    }

    func testOverflowIsVisibleAndBounded() throws {
        var buckets: [String: Any] = [:]
        for index in 0..<140 { buckets["bucket-\(index)"] = ["primary": ["usedPercent": 10]] }
        let result = try CodexUsageProvider.parseSnapshot(from: response(["rateLimitsByLimitId": buckets]))
        XCTAssertEqual(result.limits.count, 128)
        XCTAssertEqual(result.omittedLimitCount, 12)
    }

    @MainActor private func settled(_ store: UsageStore) async throws {
        for _ in 0..<1000 where store.isRefreshing { try await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertFalse(store.isRefreshing)
    }

    private func defaults() -> UserDefaults {
        let name = "gaugelet.upgrade.tests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }
}

private actor UpgradeTestProvider: UsageProviding {
    let value: UsageSnapshot
    var calls = 0
    var activityCalls = 0
    var fail = false
    init(value: UsageSnapshot) { self.value = value }
    func setFailure() { fail = true }
    func fetchSnapshot() async throws -> UsageSnapshot {
        calls += 1
        if fail { throw CodexUsageError.timedOut }
        return value
    }
    func fetchActivity() async throws -> UsageActivity {
        activityCalls += 1
        throw CodexUsageError.invalidResponse
    }
}
