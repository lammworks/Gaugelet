import Foundation
import XCTest
@testable import Gaugelet

final class UsageStoreTests: XCTestCase {
    @MainActor
    func testLiveSourceStartsLoadingWithoutDemoSnapshot() {
        let defaults = makeDefaults()

        let store = UsageStore(defaults: defaults, provider: ControlledUsageProvider())

        XCTAssertEqual(store.state, .loading)
        XCTAssertNil(store.snapshot)
    }

    @MainActor
    func testNewInstallDefaultsHoverToOpenOff() {
        let defaults = makeDefaults()
        defaults.removeObject(forKey: "hoverToOpen")

        let store = UsageStore(defaults: defaults, provider: ControlledUsageProvider())

        XCTAssertFalse(store.hoverToOpen)
    }

    @MainActor
    func testSavedHoverPreferenceIsPreserved() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "hoverToOpen")

        let store = UsageStore(defaults: defaults, provider: ControlledUsageProvider())

        XCTAssertTrue(store.hoverToOpen)
    }

    @MainActor
    func testInAppIconDefaultsToCoreAndPersistsSelection() {
        let defaults = makeDefaults()
        defaults.removeObject(forKey: "iconStyle")

        let firstStore = UsageStore(defaults: defaults, provider: ControlledUsageProvider())
        XCTAssertEqual(firstStore.iconStyle, .core)

        for style in GaugeletIconStyle.allCases {
            firstStore.iconStyle = style
            let restoredStore = UsageStore(defaults: defaults, provider: ControlledUsageProvider())
            XCTAssertEqual(restoredStore.iconStyle, style)
        }
    }

    func testInAppIconCatalogIncludesEverySupportedStyle() {
        XCTAssertEqual(
            GaugeletIconStyle.allCases,
            [.core, .aurora, .ember, .moss, .monochrome, .eightBit, .pride]
        )
        XCTAssertEqual(
            GaugeletIconStyle.allCases.map(\.title),
            ["Core", "Dark Dracula", "Ember", "Moss", "Mono", "8-Bit", "Pride"]
        )
        XCTAssertEqual(
            GaugeletIconStyle.allCases.map { "GaugeletIcon-\($0.resourceName)-256" },
            [
                "GaugeletIcon-Core-256",
                "GaugeletIcon-Aurora-256",
                "GaugeletIcon-Ember-256",
                "GaugeletIcon-Moss-256",
                "GaugeletIcon-Monochrome-256",
                "GaugeletIcon-8Bit-256",
                "GaugeletIcon-Pride-256"
            ]
        )
    }

    @MainActor
    func testInitialFailureBecomesUnavailableWithoutDemoData() async {
        let defaults = makeDefaults()
        let provider = ControlledUsageProvider()
        let store = UsageStore(defaults: defaults, provider: provider)

        store.refresh()
        await provider.waitForRequestCount(1)
        await provider.resolve(0, with: .failure("not signed in"))
        await waitForStoreUpdate()

        guard case .unavailable(let message) = store.state else {
            return XCTFail("Expected unavailable state, got \(store.state)")
        }
        XCTAssertTrue(message.contains("not signed in"))
        XCTAssertNil(store.snapshot)
    }

    @MainActor
    func testFailureAfterSuccessKeepsOnlyLastKnownLiveSnapshotAsStale() async {
        let defaults = makeDefaults()
        let provider = ControlledUsageProvider()
        let store = UsageStore(defaults: defaults, provider: provider)
        let live = makeSnapshot(id: "live", remainingPercent: 73)

        store.refresh()
        await provider.waitForRequestCount(1)
        await provider.resolve(0, with: .success(live))
        await waitForStoreUpdate()
        XCTAssertEqual(store.state, .live(live))

        store.refresh()
        await provider.waitForRequestCount(2)
        await provider.resolve(1, with: .failure("temporary failure"))
        await waitForStoreUpdate()

        guard case .stale(let snapshot, let message, _) = store.state else {
            return XCTFail("Expected stale state, got \(store.state)")
        }
        XCTAssertEqual(snapshot, live)
        XCTAssertTrue(message.contains("temporary failure"))
        XCTAssertEqual(store.snapshot, live)
    }

    @MainActor
    func testReadingOlderThanStaleLifetimeBecomesUnavailable() async {
        let defaults = makeDefaults()
        let provider = ControlledUsageProvider()
        var currentTime = Date(timeIntervalSince1970: 1_800_000_000)
        let store = UsageStore(
            defaults: defaults,
            provider: provider,
            staleDataLifetime: 15 * 60,
            now: { currentTime }
        )

        store.refresh()
        await provider.waitForRequestCount(1)
        await provider.resolve(0, with: .success(makeSnapshot(id: "live", remainingPercent: 73)))
        await waitForStoreUpdate()

        currentTime.addTimeInterval(15 * 60 + 1)
        store.refresh()
        await provider.waitForRequestCount(2)
        await provider.resolve(1, with: .failure("extended outage"))
        await waitForStoreUpdate()

        guard case .unavailable(let message) = store.state else {
            return XCTFail("Expected unavailable state after stale lifetime, got \(store.state)")
        }
        XCTAssertTrue(message.contains("extended outage"))
        XCTAssertNil(store.snapshot)
    }

    @MainActor
    func testSourceTransitionClearsLastKnownLiveSnapshot() async {
        let defaults = makeDefaults()
        let provider = ControlledUsageProvider()
        let store = UsageStore(defaults: defaults, provider: provider)

        store.refresh()
        await provider.waitForRequestCount(1)
        await provider.resolve(0, with: .success(makeSnapshot(id: "live", remainingPercent: 73)))
        await waitForStoreUpdate()

        store.sourcePreference = .demo
        store.sourcePreference = .codexAppServer
        await provider.waitForRequestCount(2)
        await provider.resolve(1, with: .failure("not connected"))
        await waitForStoreUpdate()

        guard case .unavailable = store.state else {
            return XCTFail("Expected unavailable state after source transition, got \(store.state)")
        }
        XCTAssertNil(store.snapshot)
    }

    @MainActor
    func testLateLiveResultCannotOverwriteExplicitDemoSelection() async {
        let defaults = makeDefaults()
        let provider = ControlledUsageProvider()
        let store = UsageStore(defaults: defaults, provider: provider)

        store.refresh()
        await provider.waitForRequestCount(1)
        store.sourcePreference = .demo

        guard case .demo = store.state else {
            return XCTFail("Expected explicit demo state")
        }

        await provider.resolve(0, with: .success(makeSnapshot(id: "late", remainingPercent: 9)))
        await waitForStoreUpdate()

        guard case .demo(let snapshot) = store.state else {
            return XCTFail("Late live result overwrote demo state")
        }
        XCTAssertEqual(snapshot.source, .demo)
    }

    @MainActor
    func testOlderLiveRequestCannotOverwriteNewerResult() async {
        let defaults = makeDefaults()
        let provider = ControlledUsageProvider()
        let store = UsageStore(defaults: defaults, provider: provider)
        let old = makeSnapshot(id: "old", remainingPercent: 11)
        let new = makeSnapshot(id: "new", remainingPercent: 88)

        store.refresh()
        await provider.waitForRequestCount(1)
        store.refresh()
        await provider.waitForRequestCount(2)

        await provider.resolve(1, with: .success(new))
        await waitForStoreUpdate()
        XCTAssertEqual(store.state, .live(new))

        await provider.resolve(0, with: .success(old))
        await waitForStoreUpdate()
        XCTAssertEqual(store.state, .live(new))
    }

    @MainActor
    func testWritesPreferencesToInjectedDefaults() {
        let defaults = makeDefaults()
        let store = UsageStore(defaults: defaults, provider: ControlledUsageProvider())

        store.showPercentageInMenuBar = false
        store.hoverToOpen = false
        store.warningThreshold = 35
        store.scenario = .capped
        store.sourcePreference = .demo

        XCTAssertEqual(defaults.object(forKey: "showPercentageInMenuBar") as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: "hoverToOpen") as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: "warningThreshold") as? Int, 35)
        XCTAssertEqual(defaults.string(forKey: "demoScenario"), DemoScenario.capped.rawValue)
        XCTAssertEqual(defaults.string(forKey: "sourcePreference"), UsageSourcePreference.demo.rawValue)
        guard case .demo(let snapshot) = store.state else {
            return XCTFail("Explicit demo selection did not publish demo data")
        }
        XCTAssertEqual(snapshot.source, .demo)
    }

    @MainActor
    func testUsageNotificationsDefaultToOffAndPersist() {
        let defaults = makeDefaults()
        let store = UsageStore(defaults: defaults, provider: ControlledUsageProvider())

        XCTAssertFalse(store.usageNotificationsEnabled)
        store.usageNotificationsEnabled = true

        let restoredStore = UsageStore(defaults: defaults, provider: ControlledUsageProvider())
        XCTAssertTrue(restoredStore.usageNotificationsEnabled)
    }

    func testNotificationPolicyAlertsOnlyWhenALiveLimitCrossesTheThreshold() {
        let alert = UsageNotificationPolicy.alert(
            previous: makeSnapshot(id: "five-hour", remainingPercent: 35),
            current: makeSnapshot(id: "five-hour", remainingPercent: 20),
            warningThreshold: 20
        )

        XCTAssertEqual(alert?.kind, .runningLow)
        XCTAssertEqual(alert?.title, "Usage running low")
        XCTAssertTrue(alert?.body.contains("20%") == true)

        XCTAssertNil(UsageNotificationPolicy.alert(
            previous: makeSnapshot(id: "five-hour", remainingPercent: 20),
            current: makeSnapshot(id: "five-hour", remainingPercent: 15),
            warningThreshold: 20
        ))
    }

    func testNotificationPolicyPrioritizesLimitReachedAndRejectsDemoData() {
        let reached = UsageNotificationPolicy.alert(
            previous: makeSnapshot(id: "five-hour", remainingPercent: 20),
            current: makeSnapshot(id: "five-hour", remainingPercent: 0),
            warningThreshold: 20
        )
        XCTAssertEqual(reached?.kind, .limitReached)
        XCTAssertEqual(reached?.title, "Usage limit reached")

        let demo = DemoUsageProvider.snapshot(for: .low)
        XCTAssertNil(UsageNotificationPolicy.alert(
            previous: demo,
            current: demo,
            warningThreshold: 20
        ))
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "com.lammworks.gaugelet.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(UsageSourcePreference.codexAppServer.rawValue, forKey: "sourcePreference")
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    @MainActor
    private func waitForStoreUpdate() async {
        for _ in 0..<20 {
            await Task.yield()
        }
    }
}

private enum ControlledOutcome: Sendable {
    case success(UsageSnapshot)
    case failure(String)
}

private struct ControlledProviderError: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

private actor ControlledUsageProvider: UsageProviding {
    private var continuations: [CheckedContinuation<ControlledOutcome, Never>?] = []

    func fetchSnapshot() async throws -> UsageSnapshot {
        let outcome = await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }

        switch outcome {
        case .success(let snapshot):
            return snapshot
        case .failure(let message):
            throw ControlledProviderError(message: message)
        }
    }

    func waitForRequestCount(_ expectedCount: Int) async {
        while continuations.count < expectedCount {
            await Task.yield()
        }
    }

    func resolve(_ index: Int, with outcome: ControlledOutcome) {
        guard continuations.indices.contains(index), let continuation = continuations[index] else {
            XCTFail("No pending request at index \(index)")
            return
        }
        continuations[index] = nil
        continuation.resume(returning: outcome)
    }
}

private func makeSnapshot(id: String, remainingPercent: Int) -> UsageSnapshot {
    UsageSnapshot(
        planName: "ChatGPT Plus",
        limits: [
            UsageLimit(
                id: id,
                name: "5-hour limit",
                remainingPercent: remainingPercent,
                resetDate: Date(timeIntervalSince1970: 1_900_000_000)
            )
        ],
        lastUpdated: Date(timeIntervalSince1970: 1_800_000_000 + Double(remainingPercent)),
        isSignedIn: true,
        note: "",
        source: .codexAppServer,
        sourceDetail: "Live test data"
    )
}
