import Foundation
import XCTest
@testable import Gaugelet

final class UsageModelsTests: XCTestCase {
    func testRemainingFractionClampsToValidRange() {
        let now = Date()
        let high = UsageLimit(id: "high", name: "High", remainingPercent: 130, resetDate: now)
        let low = UsageLimit(id: "low", name: "Low", remainingPercent: -10, resetDate: now)

        XCTAssertEqual(high.clampedRemainingPercent, 100)
        XCTAssertEqual(high.remainingFraction, 1)
        XCTAssertEqual(low.clampedRemainingPercent, 0)
        XCTAssertEqual(low.remainingFraction, 0)
    }

    func testClosestLimitUsesLowestRemainingAllowance() {
        let now = Date()
        let snapshot = UsageSnapshot(
            planName: "ChatGPT plan",
            limits: [
                UsageLimit(id: "weekly", name: "Weekly", remainingPercent: 55, resetDate: now),
                UsageLimit(id: "five-hour", name: "5-hour", remainingPercent: 18, resetDate: now)
            ],
            lastUpdated: now,
            isSignedIn: true,
            note: "",
            source: .demo,
            sourceDetail: ""
        )

        XCTAssertEqual(snapshot.closestLimit?.id, "five-hour")
        XCTAssertEqual(snapshot.otherLimits.map(\.id), ["weekly"])
    }

    func testUsageLabelsMatchPlainChatGPTLanguage() {
        let general = UsageLimit(
            id: "general",
            name: "Weekly limit",
            remainingPercent: 37,
            resetDate: nil
        )
        let model = UsageLimit(
            id: "spark",
            name: "GPT-5.3-Codex-Spark · 5-hour",
            remainingPercent: 100,
            resetDate: nil
        )

        XCTAssertNil(general.displayContext)
        XCTAssertEqual(general.displayName, "Weekly usage limit")
        XCTAssertEqual(model.displayContext, "GPT-5.3-Codex-Spark")
        XCTAssertEqual(model.displayName, "5 hour usage limit")
    }

    func testDemoExercisesThreeCounterPresentation() {
        let snapshot = DemoUsageProvider.snapshot(for: .comfortable)

        XCTAssertEqual(snapshot.limits.count, 3)
        XCTAssertEqual(
            Set(snapshot.limits.map(\.id)),
            Set(["five-hour", "weekly", "codex-spark-weekly"])
        )
    }

    func testParsesDocumentedAppServerRateLimitShape() throws {
        let response = """
        {"id":1,"result":{"userAgent":"Codex"}}
        {"id":2,"result":{"rateLimits":{"limitId":"codex","limitName":null,"primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1893456000},"secondary":null},"rateLimitsByLimitId":{"codex":{"limitId":"codex","limitName":null,"primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1893456000},"secondary":null},"spark":{"limitId":"spark","limitName":"Codex Spark","primary":{"usedPercent":80,"windowDurationMins":10080,"resetsAt":1894060800},"secondary":null}}}}
        """

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = try CodexUsageProvider.parseSnapshot(
            from: Data(response.utf8),
            now: now
        )

        XCTAssertEqual(snapshot.source, .codexAppServer)
        XCTAssertEqual(snapshot.limits.count, 2)
        XCTAssertEqual(snapshot.closestLimit?.name, "Codex Spark · Weekly")
        XCTAssertEqual(snapshot.closestLimit?.remainingPercent, 20)
        XCTAssertEqual(snapshot.lastUpdated, now)
    }

    func testPreservesDistinctOverallBucketAlongsideModelBuckets() throws {
        let response = """
        {"id":2,"result":{"rateLimits":{"limitId":"overall","limitName":"Overall","primary":{"usedPercent":20,"windowDurationMins":10080,"resetsAt":1894060800},"secondary":null},"rateLimitsByLimitId":{"codex":{"limitId":"codex","limitName":null,"primary":{"usedPercent":40,"windowDurationMins":300,"resetsAt":1893456000},"secondary":null},"spark":{"limitId":"spark","limitName":"Codex Spark","primary":{"usedPercent":60,"windowDurationMins":10080,"resetsAt":1894060800},"secondary":null}}}}
        """

        let snapshot = try CodexUsageProvider.parseSnapshot(from: Data(response.utf8))

        XCTAssertEqual(snapshot.limits.map(\.id), ["spark-primary", "codex-primary", "overall-primary"])
        XCTAssertEqual(snapshot.limits.map(\.name), [
            "Codex Spark · Weekly",
            "Codex · 5-hour",
            "Overall · Weekly"
        ])
    }

    func testParsesWindowsWithoutResetOrDurationWithoutInventingValues() throws {
        let response = """
        {"id":2,"result":{"rateLimits":{"limitId":"codex","limitName":null,"primary":{"usedPercent":37},"secondary":{"usedPercent":52,"windowDurationMins":null,"resetsAt":null}}}}
        """

        let snapshot = try CodexUsageProvider.parseSnapshot(from: Data(response.utf8))

        XCTAssertEqual(snapshot.limits.count, 2)
        XCTAssertTrue(snapshot.limits.allSatisfy { $0.resetDate == nil })
        XCTAssertEqual(snapshot.limits.first(where: { $0.id == "codex-primary" })?.name, "Codex · Primary")
        XCTAssertEqual(snapshot.limits.first(where: { $0.id == "codex-primary" })?.remainingPercent, 63)
        XCTAssertEqual(
            snapshot.limits.first(where: { $0.id == "codex-secondary" })?.name,
            "Codex · Secondary"
        )
    }

    func testDeduplicatesUnidentifiedBackwardCompatibleBucketWhenWindowsMatch() throws {
        let response = """
        {"id":2,"result":{"rateLimits":{"limitId":null,"primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1893456000},"secondary":null},"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1893456000},"secondary":null},"spark":{"limitId":"spark","limitName":"Codex Spark","primary":{"usedPercent":80,"windowDurationMins":10080,"resetsAt":1894060800},"secondary":null}}}}
        """

        let snapshot = try CodexUsageProvider.parseSnapshot(from: Data(response.utf8))

        XCTAssertEqual(snapshot.limits.map(\.id), ["spark-primary", "codex-primary"])
    }

    func testPreservesServerReportedBlockedState() throws {
        let response = """
        {"id":2,"result":{"rateLimits":{"limitId":"codex","limitName":"Codex","planType":"plus","primary":{"usedPercent":30,"windowDurationMins":300,"resetsAt":null},"secondary":null,"rateLimitReachedType":"workspace_member_credits_depleted"}}}
        """

        let snapshot = try CodexUsageProvider.parseSnapshot(from: Data(response.utf8))

        XCTAssertEqual(snapshot.planName, "ChatGPT Plus")
        XCTAssertEqual(snapshot.closestLimit?.remainingPercent, 70)
        XCTAssertEqual(snapshot.closestLimit?.blockedReason, "Workspace credits depleted")
        XCTAssertTrue(snapshot.closestLimit?.isBlocked == true)
        XCTAssertEqual(snapshot.closestLimit?.remainingFraction, 0)
    }

    func testNearCapKeepsOnePercentFloorUntilActuallyCapped() throws {
        let nearCap = """
        {"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":99.6},"secondary":null}}}
        """
        let capped = """
        {"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":100},"secondary":null}}}
        """

        let nearCapSnapshot = try CodexUsageProvider.parseSnapshot(from: Data(nearCap.utf8))
        let cappedSnapshot = try CodexUsageProvider.parseSnapshot(from: Data(capped.utf8))

        XCTAssertEqual(nearCapSnapshot.closestLimit?.remainingPercent, 1)
        XCTAssertFalse(nearCapSnapshot.closestLimit?.isCapped == true)
        XCTAssertEqual(cappedSnapshot.closestLimit?.remainingPercent, 0)
        XCTAssertTrue(cappedSnapshot.closestLimit?.isCapped == true)
    }

    func testRejectsBooleanAndOutOfRangeUsagePercentages() {
        let invalidValues = ["true", "-1", "100.1"]

        for invalidValue in invalidValues {
            let response = """
            {"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":\(invalidValue)},"secondary":null}}}
            """

            XCTAssertThrowsError(try CodexUsageProvider.parseSnapshot(from: Data(response.utf8))) { error in
                guard
                    let codexError = error as? CodexUsageError,
                    case .noRateLimits = codexError
                else {
                    return XCTFail("Expected noRateLimits for \(invalidValue), got \(error)")
                }
            }
        }
    }

    func testRetainsAdditionalWindowsAndSanitizesDisplayNames() throws {
        var buckets: [String: Any] = [:]
        for index in 0..<10 {
            buckets["bucket-\(index)"] = [
                "limitName": "  A very long\nlimit name \(String(repeating: "x", count: 120))  ",
                "primary": ["usedPercent": index],
                "secondary": ["usedPercent": index + 1]
            ]
        }
        let message: [String: Any] = [
            "id": 2,
            "result": ["rateLimitsByLimitId": buckets]
        ]
        let response = try JSONSerialization.data(withJSONObject: message)

        let snapshot = try CodexUsageProvider.parseSnapshot(from: response)

        XCTAssertEqual(snapshot.limits.count, 20)
        XCTAssertEqual(snapshot.otherLimits.count, 19)
        XCTAssertFalse(snapshot.otherLimits.contains { $0.id == snapshot.closestLimit?.id })
        XCTAssertEqual(snapshot.closestLimit?.id, "bucket-9-secondary")
        XCTAssertEqual(snapshot.closestLimit?.remainingPercent, 90)
        XCTAssertTrue(snapshot.limits.allSatisfy { $0.name.count <= 80 + " · 100-minute".count })
        XCTAssertTrue(snapshot.limits.allSatisfy { !$0.name.contains("\n") })
    }

    func testRejectsMalformedOptionalDurationAndResetMetadata() throws {
        let invalidMetadata = [
            (duration: "true", reset: "true"),
            (duration: "-5", reset: "4102444801"),
            (duration: "2.5", reset: "1893456000.5")
        ]

        for metadata in invalidMetadata {
            let response = """
            {"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":37,"windowDurationMins":\(metadata.duration),"resetsAt":\(metadata.reset)},"secondary":null}}}
            """

            let snapshot = try CodexUsageProvider.parseSnapshot(from: Data(response.utf8))

            XCTAssertEqual(snapshot.closestLimit?.name, "Codex")
            XCTAssertNil(snapshot.closestLimit?.resetDate)
        }
    }

    func testCancellingFetchStopsInjectedProcessPromptly() async {
        let provider = CodexUsageProvider(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["30"]
        )
        let startedAt = Date()
        let task = Task {
            try await provider.fetchSnapshot()
        }

        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Cancelled fetch unexpectedly returned a snapshot")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 2)
    }

    func testImmediatelyCancelledFetchDoesNotReturnData() async {
        let provider = CodexUsageProvider(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["30"]
        )
        let task = Task {
            try await provider.fetchSnapshot()
        }

        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Immediately cancelled fetch unexpectedly returned a snapshot")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    func testResetLabelUsesCompactUnits() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let reset = now.addingTimeInterval(2 * 60 * 60 + 14 * 60)

        XCTAssertEqual(reset.gaugeletRelativeReset(from: now), "Resets in 2h 14m")
        XCTAssertEqual(reset.gaugeletCountdownValue(from: now), "2h")
    }
}
