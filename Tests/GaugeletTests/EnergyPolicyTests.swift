import XCTest
@testable import Gaugelet

final class EnergyPolicyTests: XCTestCase {
    func testACProfileKeepsFiveMinuteRefresh() {
        let policy = GaugeletEnergyPolicy.resolve(
            usingBatteryPower: false,
            hasInternalBattery: false,
            lowPowerModeEnabled: false
        )
        XCTAssertEqual(policy.mode, .ac)
        XCTAssertFalse(policy.hasInternalBattery)
        XCTAssertEqual(policy.timerInterval, 60)
        XCTAssertEqual(policy.timerTolerance, 15)
        XCTAssertEqual(policy.backgroundRefreshInterval, 5 * 60)
    }

    func testBatteryProfileLengthensIdleWork() {
        let policy = GaugeletEnergyPolicy.resolve(
            usingBatteryPower: true,
            hasInternalBattery: true,
            lowPowerModeEnabled: false
        )
        XCTAssertEqual(policy.mode, .battery)
        XCTAssertTrue(policy.hasInternalBattery)
        XCTAssertEqual(policy.timerInterval, 180)
        XCTAssertEqual(policy.timerTolerance, 45)
        XCTAssertEqual(policy.backgroundRefreshInterval, 10 * 60)
    }

    func testLowPowerModeOverridesBatteryAndAC() {
        let onAC = GaugeletEnergyPolicy.resolve(
            usingBatteryPower: false,
            hasInternalBattery: true,
            lowPowerModeEnabled: true
        )
        let onBattery = GaugeletEnergyPolicy.resolve(
            usingBatteryPower: true,
            hasInternalBattery: true,
            lowPowerModeEnabled: true
        )
        XCTAssertEqual(onAC.mode, .lowPower)
        XCTAssertEqual(onBattery.mode, .lowPower)
        XCTAssertEqual(onAC.timerInterval, 300)
        XCTAssertEqual(onAC.backgroundRefreshInterval, 15 * 60)
        XCTAssertGreaterThan(onAC.timerTolerance, 0)
    }

    func testDesktopMacWithoutBatteryStillUsesACCadence() {
        let policy = GaugeletEnergyPolicy.resolve(
            usingBatteryPower: false,
            hasInternalBattery: false,
            lowPowerModeEnabled: false
        )
        XCTAssertEqual(policy, .default)
        XCTAssertGreaterThan(policy.timerTolerance, 0, "Tolerance keeps the idle timer App Nap friendly on always-AC Macs.")
    }
}
