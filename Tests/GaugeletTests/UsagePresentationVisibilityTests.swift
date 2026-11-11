import Foundation
import XCTest
@testable import Gaugelet

final class UsagePresentationVisibilityTests: XCTestCase {
    func testElapsedCheckTextUsesOnlyInjectedTimeAndHandlesClockChanges() {
        let checked = Date(timeIntervalSince1970: 1_800_000_000)
        let cases: [(TimeInterval, String)] = [
            (-30, "0s"), (0, "0s"), (59, "59s"), (60, "1m"),
            (3_599, "59m"), (3_600, "1h"), (86_399, "23h"), (86_400, "1d")
        ]
        for (elapsed, expected) in cases {
            XCTAssertEqual(
                UsagePresentationText.elapsedCheckValue(lastUpdated: checked, now: checked.addingTimeInterval(elapsed)),
                expected
            )
        }
    }

    func testReadOnlyHelpReportsTheActivePowerPolicy() {
        let policies: [UsageRefreshPolicy] = [.acPower, .battery, .lowPower]
        for policy in policies {
            let help = UsagePresentationText.readOnlyHelp(policy: policy)
            XCTAssertTrue(help.contains("every \(Int(policy.interval / 60)) minutes now"))
            XCTAssertTrue(help.contains("\(Int(UsageRefreshPolicy.acPower.interval / 60)) on AC power"))
            XCTAssertTrue(help.contains("\(Int(UsageRefreshPolicy.battery.interval / 60)) on battery"))
            XCTAssertTrue(help.contains("\(Int(UsageRefreshPolicy.lowPower.interval / 60)) in Low Power Mode"))
        }
    }
}
