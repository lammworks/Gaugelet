import Foundation
import XCTest
@testable import Gaugelet

final class UsagePowerMonitorTests: XCTestCase {
    @MainActor
    func testRefreshEmitsOnlyEffectivePolicyChanges() {
        var policy: UsageRefreshPolicy = .acPower
        var changes: [UsageRefreshPolicy] = []
        let monitor = UsagePowerMonitor(
            onPolicyChange: { changes.append($0) },
            readPolicy: { policy }
        )

        XCTAssertEqual(monitor.currentPolicy, .acPower)
        monitor.refresh()
        policy = .battery
        monitor.refresh()
        monitor.refresh()
        policy = .lowPower
        monitor.refresh()

        XCTAssertEqual(monitor.currentPolicy, .lowPower)
        XCTAssertEqual(changes, [.battery, .lowPower])
    }

    @MainActor
    func testPowerStateNotificationRereadsPolicy() async {
        let notificationCenter = NotificationCenter()
        var policy: UsageRefreshPolicy = .acPower
        let changed = expectation(description: "Policy changed")
        let monitor = UsagePowerMonitor(
            onPolicyChange: { value in
                XCTAssertEqual(value, .lowPower)
                changed.fulfill()
            },
            readPolicy: { policy },
            notificationCenter: notificationCenter
        )
        monitor.start()
        monitor.start()
        defer { monitor.stop() }

        policy = .lowPower
        notificationCenter.post(
            name: .NSProcessInfoPowerStateDidChange,
            object: ProcessInfo.processInfo
        )
        await fulfillment(of: [changed], timeout: 1)
        XCTAssertEqual(monitor.currentPolicy, .lowPower)
    }

    @MainActor
    func testStopDiscardsQueuedNotificationsAndRestartRereadsPolicy() async {
        let notificationCenter = NotificationCenter()
        var policy: UsageRefreshPolicy = .acPower
        var changes: [UsageRefreshPolicy] = []
        let monitor = UsagePowerMonitor(
            onPolicyChange: { changes.append($0) },
            readPolicy: { policy },
            notificationCenter: notificationCenter
        )
        monitor.start()
        policy = .battery
        notificationCenter.post(
            name: .NSProcessInfoPowerStateDidChange,
            object: ProcessInfo.processInfo
        )
        monitor.stop()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(changes.isEmpty)
        XCTAssertEqual(monitor.currentPolicy, .acPower)

        monitor.start()
        XCTAssertEqual(monitor.currentPolicy, .battery)
        XCTAssertEqual(changes, [.battery])
        monitor.stop()
        monitor.stop()
    }

    @MainActor
    func testMonitoringDoesNotRetainMonitor() {
        var monitor: UsagePowerMonitor? = UsagePowerMonitor(
            onPolicyChange: { _ in },
            readPolicy: { .acPower },
            notificationCenter: NotificationCenter()
        )
        let monitorWasReleased = { [weak monitor] in monitor == nil }
        monitor?.start()
        monitor = nil

        XCTAssertTrue(monitorWasReleased())
    }
}
