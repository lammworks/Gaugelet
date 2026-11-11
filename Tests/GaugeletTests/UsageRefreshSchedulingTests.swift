import Foundation
import XCTest
@testable import Gaugelet

final class UsageRefreshSchedulingTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testPowerPolicyIntervalsAndLowPowerPrecedence() {
        XCTAssertEqual(UsageRefreshPolicy.acPower.interval, 300)
        XCTAssertEqual(UsageRefreshPolicy.battery.interval, 600)
        XCTAssertEqual(UsageRefreshPolicy.lowPower.interval, 900)
        for source in [UsagePowerSource.acPower, .battery, .ups, .unknown] {
            XCTAssertEqual(UsageRefreshPolicy.resolve(powerSource: source, isLowPowerModeEnabled: true), .lowPower)
        }
        XCTAssertEqual(UsageRefreshPolicy.resolve(powerSource: .acPower, isLowPowerModeEnabled: false), .acPower)
        XCTAssertEqual(UsageRefreshPolicy.resolve(powerSource: .unknown, isLowPowerModeEnabled: false), .acPower)
        XCTAssertEqual(UsageRefreshPolicy.resolve(powerSource: .battery, isLowPowerModeEnabled: false), .battery)
        XCTAssertEqual(UsageRefreshPolicy.resolve(powerSource: .ups, isLowPowerModeEnabled: false), .battery)
    }

    @MainActor
    func testDeadlineUsesPolicyAndLastAttemptRatherThanPolicyChangeTime() async {
        var time = start
        let provider = SchedulingUsageProvider(snapshot: makeSnapshot())
        let store = UsageStore(defaults: makeDefaults(), provider: provider, now: { time })
        XCTAssertEqual(store.nextAutomaticRefreshDate, start)

        store.refresh()
        XCTAssertNil(store.nextAutomaticRefreshDate)
        await settled(store)
        XCTAssertEqual(store.nextAutomaticRefreshDate, start.addingTimeInterval(300))
        XCTAssertEqual(store.nextAutomaticRefreshTolerance, 5)

        time.addTimeInterval(360)
        store.refreshPolicy = .battery
        XCTAssertEqual(store.nextAutomaticRefreshDate, start.addingTimeInterval(600))
        store.refreshIfDue()
        var calls = await provider.calls
        XCTAssertEqual(calls, 1)

        store.refreshPolicy = .lowPower
        XCTAssertEqual(store.nextAutomaticRefreshDate, start.addingTimeInterval(900))
        store.refreshPolicy = .acPower
        store.refreshIfDue()
        store.refreshIfDue()
        await settled(store)
        calls = await provider.calls
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(store.nextAutomaticRefreshDate, time.addingTimeInterval(300))
        store.cancelRefresh()
    }

    @MainActor
    func testAdaptiveAutomaticDeadlinesDoNotFetchEarly() async {
        for policy in [UsageRefreshPolicy.acPower, .battery, .lowPower] {
            var time = start
            let provider = SchedulingUsageProvider(snapshot: makeSnapshot())
            let store = UsageStore(defaults: makeDefaults(), provider: provider, now: { time })
            store.refreshPolicy = policy
            store.refresh()
            await settled(store)
            time = start.addingTimeInterval(policy.interval - 1)
            store.refreshIfDue()
            var calls = await provider.calls
            XCTAssertEqual(calls, 1)
            time.addTimeInterval(1)
            store.refreshIfDue()
            await settled(store)
            calls = await provider.calls
            XCTAssertEqual(calls, 2)
            store.cancelRefresh()
        }
    }

    @MainActor
    func testEarliestResetOverridesLowPowerAndCachedResetIsConsumed() async {
        var time = start
        let snapshot = makeSnapshot(resetOffsets: [200, 90])
        let provider = SchedulingUsageProvider(snapshot: snapshot)
        let store = UsageStore(defaults: makeDefaults(), provider: provider, now: { time })
        store.refreshPolicy = .lowPower
        store.refresh()
        await settled(store)
        XCTAssertEqual(store.nextAutomaticRefreshDate, start.addingTimeInterval(90))
        XCTAssertEqual(store.nextAutomaticRefreshTolerance, 0)

        time.addTimeInterval(90)
        store.refreshIfDue()
        await settled(store)
        XCTAssertEqual(store.nextAutomaticRefreshDate, start.addingTimeInterval(200))
        store.refreshIfDue()
        var calls = await provider.calls
        XCTAssertEqual(calls, 2)

        time = start.addingTimeInterval(200)
        store.refreshIfDue()
        await settled(store)
        XCTAssertEqual(store.nextAutomaticRefreshDate, time.addingTimeInterval(900))
        XCTAssertEqual(store.nextAutomaticRefreshTolerance, 5)
        store.refreshIfDue()
        calls = await provider.calls
        XCTAssertEqual(calls, 3)
        store.cancelRefresh()
    }

    @MainActor
    func testOpenWakeAndManualRefreshBypassLowPowerInterval() async {
        var time = start
        let provider = SchedulingUsageProvider(snapshot: makeSnapshot())
        let store = UsageStore(defaults: makeDefaults(), provider: provider, now: { time })
        store.refreshPolicy = .lowPower
        store.refresh()
        await settled(store)
        time.addTimeInterval(59)
        store.refreshIfNeeded()
        var calls = await provider.calls
        XCTAssertEqual(calls, 1)
        time.addTimeInterval(1)
        store.refreshIfNeeded()
        await settled(store)
        time.addTimeInterval(1)
        store.refreshIfNeeded(maximumAge: 0)
        await settled(store)
        store.refresh()
        await settled(store)
        calls = await provider.calls
        XCTAssertEqual(calls, 4)
        XCTAssertEqual(store.nextAutomaticRefreshDate, time.addingTimeInterval(900))
        store.cancelRefresh()
    }

    @MainActor
    func testAutomaticTriggersCoalesceAndManualRefreshStillSupersedes() async {
        let provider = SuspendedSchedulingProvider()
        let store = UsageStore(defaults: makeDefaults(), provider: provider, now: { self.start })
        store.refresh()
        guard await provider.waitForCalls(1) else { return XCTFail("Initial request did not start") }
        store.refreshIfDue()
        store.refreshIfNeeded(maximumAge: 0)
        XCTAssertNil(store.nextAutomaticRefreshDate)
        var calls = await provider.calls
        XCTAssertEqual(calls, 1)

        store.refresh()
        guard await provider.waitForCalls(2) else { return XCTFail("Manual refresh did not supersede") }
        let newSnapshot = makeSnapshot(percent: 81)
        await provider.resolve(1, snapshot: newSnapshot)
        await settled(store)
        await provider.resolve(0, snapshot: makeSnapshot(percent: 12))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(store.snapshot, newSnapshot)
        calls = await provider.calls
        XCTAssertEqual(calls, 2)
        store.cancelRefresh()
    }

    @MainActor
    func testDemoAndDisabledActivityHaveNoAutomaticProviderWork() async {
        let provider = SchedulingUsageProvider(snapshot: makeSnapshot())
        let store = UsageStore(defaults: makeDefaults(), provider: provider, now: { self.start })
        store.refresh()
        await settled(store)
        var activityCalls = await provider.activityCalls
        XCTAssertEqual(activityCalls, 0)
        store.sourcePreference = .demo
        XCTAssertNil(store.nextAutomaticRefreshDate)
        store.refreshPolicy = .lowPower
        store.scenario = .capped
        store.refreshIfDue()
        store.refreshIfNeeded(maximumAge: 0)
        let calls = await provider.calls
        activityCalls = await provider.activityCalls
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(activityCalls, 0)
        XCTAssertEqual(store.activityState, .disabled)

        store.sourcePreference = .codexAppServer
        await settled(store)
        XCTAssertEqual(store.nextAutomaticRefreshDate, start.addingTimeInterval(900))
        store.cancelRefresh()
    }

    @MainActor
    func testFailureRetainsRetryDeadlineWithoutExtendingStaleLifetime() async {
        var time = start
        let provider = SchedulingUsageProvider(snapshot: makeSnapshot())
        let store = UsageStore(defaults: makeDefaults(), provider: provider, now: { time })
        store.refreshPolicy = .lowPower
        store.refresh()
        await settled(store)
        await provider.failRequests()
        time.addTimeInterval(900)
        store.refreshIfDue()
        await settled(store)
        guard case .unavailable = store.state else { return XCTFail("Expired data must not outlive 15 minutes") }
        XCTAssertEqual(store.nextAutomaticRefreshDate, time.addingTimeInterval(900))
        XCTAssertEqual(store.nextAutomaticRefreshTolerance, 5)
        store.cancelRefresh()
    }

    @MainActor
    func testScheduleCallbackCoversLifecycleAndIgnoresUnchangedPolicy() async {
        let provider = SchedulingUsageProvider(snapshot: makeSnapshot())
        let store = UsageStore(defaults: makeDefaults(), provider: provider, now: { self.start })
        var events: [(refreshing: Bool, deadline: Date?)] = []
        store.onRefreshScheduleChange = {
            events.append((store.isRefreshing, store.nextAutomaticRefreshDate))
        }
        store.refreshPolicy = .battery
        store.refreshPolicy = .battery
        XCTAssertEqual(events.count, 1)
        store.refresh()
        XCTAssertTrue(events.last?.refreshing == true)
        XCTAssertNil(events.last?.deadline)
        await settled(store)
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events.last?.deadline, start.addingTimeInterval(600))
        store.cancelRefresh()
        XCTAssertEqual(events.count, 4)
        store.sourcePreference = .demo
        XCTAssertEqual(events.count, 5)
        XCTAssertNil(events.last?.deadline)
        store.onRefreshScheduleChange = nil
    }

    @MainActor
    private func settled(_ store: UsageStore, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<1_000 where store.isRefreshing { await Task.yield() }
        XCTAssertFalse(store.isRefreshing, "Refresh did not settle", file: file, line: line)
    }

    private func makeDefaults() -> UserDefaults {
        let name = "com.lammworks.gaugelet.scheduling-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.set(UsageSourcePreference.codexAppServer.rawValue, forKey: "sourcePreference")
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private func makeSnapshot(resetOffsets: [TimeInterval] = [], percent: Int = 68) -> UsageSnapshot {
        UsageSnapshot(
            planName: "Test",
            limits: (resetOffsets.isEmpty ? [nil] : resetOffsets.map(Optional.some)).enumerated().map { index, offset in
                UsageLimit(id: "limit-\(index)", name: "Limit \(index)", remainingPercent: percent,
                           resetDate: offset.map { start.addingTimeInterval($0) })
            },
            lastUpdated: start, isSignedIn: true, note: "", source: .codexAppServer, sourceDetail: ""
        )
    }
}

private actor SchedulingUsageProvider: UsageProviding {
    private let snapshot: UsageSnapshot
    private var failing = false
    private(set) var calls = 0
    private(set) var activityCalls = 0

    init(snapshot: UsageSnapshot) { self.snapshot = snapshot }
    func failRequests() { failing = true }
    func fetchSnapshot() async throws -> UsageSnapshot {
        calls += 1
        if failing { throw CodexUsageError.timedOut }
        return snapshot
    }
    func fetchActivity() async throws -> UsageActivity {
        activityCalls += 1
        throw CodexUsageError.invalidResponse
    }
}

private actor SuspendedSchedulingProvider: UsageProviding {
    private var continuations: [CheckedContinuation<UsageSnapshot, Never>?] = []
    var calls: Int { continuations.count }
    func fetchSnapshot() async throws -> UsageSnapshot {
        await withCheckedContinuation { continuations.append($0) }
    }
    func waitForCalls(_ count: Int) async -> Bool {
        for _ in 0..<1_000 {
            if calls >= count { return true }
            await Task.yield()
        }
        return false
    }
    func resolve(_ index: Int, snapshot: UsageSnapshot) {
        let continuation = continuations[index]
        continuations[index] = nil
        continuation?.resume(returning: snapshot)
    }
}
