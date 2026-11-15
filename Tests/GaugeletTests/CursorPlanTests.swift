import Foundation
import XCTest
@testable import Gaugelet

final class CursorPlanTests: XCTestCase {
    private let weeklyStart = "2026-10-18T06:32:13.504Z"
    private let weeklyEnd = "2026-10-25T06:32:13.504Z"

    func testWeeklyPoolKeepsOneIncludedMeterAndPrepaidOtherModels() throws {
        let current = try periodJSON(
            start: weeklyStart,
            end: weeklyEnd,
            total: 1.112013719649788,
            auto: 1.112013719649788,
            api: 0,
            prepaidCents: 1840
        )
        let summary = Data(#"""
        {"membershipType":"unified_ultra","billingCycleStart":"2026-10-01T00:00:00.000Z","billingCycleEnd":"2026-11-01T00:00:00.000Z","individualUsage":{"plan":{"used":0,"limit":55395,"totalPercentUsed":0}}}
        """#.utf8)
        let grok = Data(#"""
        {"config":{"creditUsagePercent":50,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY"}}}
        """#.utf8)

        let snapshot = try CursorPlanParser.snapshot(
            currentPeriod: current,
            usageSummary: summary,
            grokCredits: grok,
            hasCursorSession: true,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertEqual(snapshot.plan, .cursor)
        XCTAssertEqual(snapshot.billingShape, .weeklyPool)
        XCTAssertEqual(snapshot.planName, "X Subscription")
        XCTAssertEqual(snapshot.limits.map(\.id), ["cursor:included", "cursor:models"])
        XCTAssertEqual(snapshot.limits.first?.remainingPercent, 99)
        XCTAssertEqual(snapshot.limits.first?.contextNote, "Weekly pool · Grok and Cursor")
        XCTAssertFalse(snapshot.limits.contains { $0.remainingPercent == 50 || $0.remainingPercent == 100 })
        XCTAssertNil(snapshot.limits.first { $0.id == "cursor:api" })
        XCTAssertEqual(
            snapshot.limits.first?.resetDate,
            FixtureDate.fractional.date(from: weeklyEnd)
        )
        XCTAssertEqual(snapshot.credits.first { $0.id == "cursor:other-models" }?.displayValue, "Prepaid")
        XCTAssertEqual(snapshot.credits.first { $0.id == "cursor:additional" }?.displayValue, "$18.40")
        XCTAssertEqual(snapshot.plan, .cursor)
    }

    func testLegacyMonthlyPlanShowsDistinctIncludedPools() throws {
        let current = try periodJSON(
            start: "2026-10-01T00:00:00.000Z",
            end: "2026-11-01T00:00:00.000Z",
            total: 40,
            auto: 20,
            api: 55,
            planName: "Pro",
            prepaidCents: nil
        )

        let snapshot = try CursorPlanParser.parseCurrentPeriod(current)

        XCTAssertEqual(snapshot.billingShape, .legacyCycle)
        XCTAssertEqual(snapshot.planName, "Cursor Pro")
        XCTAssertEqual(snapshot.limits.map(\.id), ["cursor:included", "cursor:models", "cursor:api"])
        XCTAssertEqual(snapshot.limits.map(\.name), ["Included usage", "Auto", "API"])
        XCTAssertEqual(snapshot.limits.map(\.remainingPercent), [60, 80, 45])
        XCTAssertTrue(snapshot.credits.isEmpty)
    }

    func testLegacyPlanOmitsPoolsThatRepeatTheIncludedPercent() throws {
        let current = try periodJSON(
            start: "2026-10-01T00:00:00.000Z",
            end: "2026-11-01T00:00:00.000Z",
            total: 30,
            auto: 30,
            api: 30,
            planName: nil,
            prepaidCents: nil
        )

        let snapshot = try CursorPlanParser.parseCurrentPeriod(current)

        XCTAssertEqual(snapshot.limits.map(\.id), ["cursor:included"])
        XCTAssertEqual(snapshot.planName, "Cursor plan")
    }

    func testMissingPercentsStayUnavailable() {
        let body = Data(#"{"billingCycleStart":"2026-10-18T00:00:00Z","billingCycleEnd":"2026-10-25T00:00:00Z","planUsage":{}}"#.utf8)
        XCTAssertThrowsError(try CursorPlanParser.parseCurrentPeriod(body)) { error in
            XCTAssertEqual(error as? CursorPlanError, .noUsage)
        }
    }

    func testRejectedTokenAndMissingSessionStaySignedOut() throws {
        let rejected = CursorPlanParser.interpret(
            statusCode: 401,
            body: Data("nope".utf8),
            now: Date(timeIntervalSince1970: 1_800_000_000),
            source: .cursorPlan
        )
        guard case .signedOut(let rejectedSnapshot) = rejected else {
            return XCTFail("Expected a signed-out reading")
        }
        XCTAssertFalse(rejectedSnapshot.isSignedIn)
        XCTAssertTrue(rejectedSnapshot.limits.isEmpty)

        let summary = Data(#"{"individualUsage":{"plan":{"totalPercentUsed":0,"limit":100}}}"#.utf8)
        let missing = try CursorPlanParser.snapshot(
            currentPeriod: nil,
            usageSummary: summary,
            grokCredits: nil,
            hasCursorSession: false
        )
        XCTAssertFalse(missing.isSignedIn)
        XCTAssertTrue(missing.limits.isEmpty)
    }

    func testGrokFallbackIsTheOnlyMeterWithoutACursorSession() throws {
        let grok = Data(#"""
        {"config":{"creditUsagePercent":40,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2026-10-25T06:32:13.504Z"}}}
        """#.utf8)
        let summary = Data(#"{"individualUsage":{"plan":{"totalPercentUsed":0}}}"#.utf8)
        let snapshot = try CursorPlanParser.snapshot(
            currentPeriod: nil,
            usageSummary: summary,
            grokCredits: grok,
            hasCursorSession: false
        )

        XCTAssertEqual(snapshot.source, .grokPlan)
        XCTAssertEqual(snapshot.billingShape, .weeklyPool)
        XCTAssertEqual(snapshot.limits.map(\.id), ["cursor:included"])
        XCTAssertEqual(snapshot.limits.first?.remainingPercent, 60)
    }

    func testSpendCapUsesReturnedRemainingAndSkipsAMissingCap() throws {
        var object = try JSONSerialization.jsonObject(with: periodJSON(
            start: weeklyStart,
            end: weeklyEnd,
            total: 10,
            auto: nil,
            api: nil,
            prepaidCents: nil
        )) as! [String: Any]
        object["spendLimitUsage"] = [
            "individualLimit": 10000,
            "individualRemaining": 2500
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        let snapshot = try CursorPlanParser.parseCurrentPeriod(data)
        XCTAssertEqual(snapshot.limits.first { $0.id == "cursor:spend-cap" }?.remainingPercent, 25)

        let withoutCap = try CursorPlanParser.parseCurrentPeriod(periodJSON(
            start: weeklyStart,
            end: weeklyEnd,
            total: 10,
            auto: nil,
            api: nil,
            prepaidCents: nil
        ))
        XCTAssertNil(withoutCap.limits.first { $0.id == "cursor:spend-cap" })
        XCTAssertTrue(withoutCap.credits.isEmpty)
    }

    func testIncludedSpendIsUsedOnlyWhenThePercentIsMissing() throws {
        let body = Data(#"""
        {"billingCycleStart":"2026-10-01T00:00:00.000Z","billingCycleEnd":"2026-11-01T00:00:00.000Z","planUsage":{"includedSpend":2500,"limit":10000}}
        """#.utf8)
        let snapshot = try CursorPlanParser.parseCurrentPeriod(body)
        XCTAssertEqual(snapshot.limits.map(\.id), ["cursor:included"])
        XCTAssertEqual(snapshot.limits.first?.remainingPercent, 75)
    }

    func testProviderUsesTheCurrentPeriodAndDoesNotCallGrokWhenCursorIsSignedIn() async throws {
        let transport = SequenceTransport(responses: [
            CursorPlanHTTPResponse(statusCode: 200, body: try periodJSON(
                start: weeklyStart,
                end: weeklyEnd,
                total: 28,
                auto: 28,
                api: 0,
                prepaidCents: nil
            ))
        ])
        let provider = CursorPlanProvider(
            locator: CursorCredentialLocator(
                cursorDatabaseURL: try makeCursorDatabase(token: "cursor-session-token"),
                grokAuthURL: try makeGrokAuth(token: "grok-session-token")
            ),
            transport: transport,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )

        let snapshot = try await provider.fetchSnapshot()
        let requested = await transport.requested

        XCTAssertEqual(snapshot.limits.first?.remainingPercent, 72)
        XCTAssertEqual(requested, [CursorPlanParser.currentPeriodURL])
    }

    func testRejectedCursorSessionDoesNotFallThroughToAnotherMeter() async throws {
        let transport = SequenceTransport(responses: [
            CursorPlanHTTPResponse(statusCode: 401, body: Data())
        ])
        let provider = CursorPlanProvider(
            locator: CursorCredentialLocator(
                cursorDatabaseURL: try makeCursorDatabase(token: "expired-token"),
                grokAuthURL: try makeGrokAuth(token: "grok-session-token")
            ),
            transport: transport
        )

        let snapshot = try await provider.fetchSnapshot()
        let requested = await transport.requested

        XCTAssertFalse(snapshot.isSignedIn)
        XCTAssertEqual(requested, [CursorPlanParser.currentPeriodURL])
    }

    func testUnavailableCurrentPeriodFallsBackWithoutUsingTheMonthlySummary() async throws {
        let transport = SequenceTransport(responses: [
            CursorPlanHTTPResponse(statusCode: 503, body: Data()),
            CursorPlanHTTPResponse(statusCode: 200, body: try periodJSON(
                start: weeklyStart,
                end: weeklyEnd,
                total: 12,
                auto: nil,
                api: nil,
                prepaidCents: nil
            ))
        ])
        let provider = CursorPlanProvider(
            locator: CursorCredentialLocator(
                cursorDatabaseURL: try makeCursorDatabase(token: "cursor-session-token"),
                grokAuthURL: URL(fileURLWithPath: "/tmp/gaugelet-missing-grok-auth.json")
            ),
            transport: transport
        )

        let snapshot = try await provider.fetchSnapshot()
        let requested = await transport.requested

        XCTAssertEqual(snapshot.limits.first?.remainingPercent, 88)
        XCTAssertEqual(snapshot.billingShape, .weeklyPool)
        XCTAssertEqual(requested, [CursorPlanParser.currentPeriodURL, CursorPlanParser.fallbackPeriodURL])
    }

    func testReadsOnlyTheCursorAccessToken() throws {
        let database = try makeCursorDatabase(token: "cursor-session-token")
        let locator = CursorCredentialLocator(
            cursorDatabaseURL: database,
            grokAuthURL: URL(fileURLWithPath: "/tmp/gaugelet-missing-grok-auth.json")
        )
        XCTAssertEqual(try locator.cursorAccessToken(), "cursor-session-token")
        XCTAssertNil(CursorPlanParser.acceptedToken("bad token"))
        XCTAssertNil(CursorPlanParser.acceptedToken("line\nbreak"))
    }

    func testGrokFileSuppliesATokenOnlyWhenCursorHasNoSession() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let auth = try makeGrokAuth(token: "grok-session-token", directory: directory)
        let locator = CursorCredentialLocator(
            cursorDatabaseURL: directory.appendingPathComponent("missing.vscdb"),
            grokAuthURL: auth
        )
        XCTAssertNil(try locator.cursorAccessToken())
        XCTAssertEqual(try locator.grokAccessToken(), "grok-session-token")
    }

    private func periodJSON(
        start: String,
        end: String,
        total: Double?,
        auto: Double?,
        api: Double?,
        planName: String? = nil,
        prepaidCents: Double?
    ) throws -> Data {
        var planUsage: [String: Any] = [:]
        if let total { planUsage["totalPercentUsed"] = total }
        if let auto { planUsage["autoPercentUsed"] = auto }
        if let api { planUsage["apiPercentUsed"] = api }
        var object: [String: Any] = [
            "billingCycleStart": start,
            "billingCycleEnd": end,
            "planUsage": planUsage
        ]
        if let planName { object["planName"] = planName }
        if let prepaidCents { object["prepaidBalanceCents"] = prepaidCents }
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func makeCursorDatabase(token: String) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = directory.appendingPathComponent("state.vscdb")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [
            database.path,
            """
            CREATE TABLE ItemTable (key TEXT, value TEXT);
            INSERT INTO ItemTable VALUES ('cursorAuth/accessToken', '\(token)');
            INSERT INTO ItemTable VALUES ('secret.other', 'do-not-read');
            """
        ]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return database
    }

    private func makeGrokAuth(token: String, directory: URL? = nil) throws -> URL {
        let folder = directory ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let auth = folder.appendingPathComponent("auth.json")
        let body = #"{"access_token":"\#(token)","refresh_token":"do-not-use"}"#
        try Data(body.utf8).write(to: auth)
        return auth
    }
}

private enum FixtureDate {
    static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

private actor SequenceTransport: CursorPlanTransport {
    private var responses: [CursorPlanHTTPResponse]
    private(set) var requested: [URL] = []

    init(responses: [CursorPlanHTTPResponse]) {
        self.responses = responses
    }

    func post(url: URL, bearerToken: String, extraHeaders: [String: String], body: Data) async throws -> CursorPlanHTTPResponse {
        requested.append(url)
        guard !responses.isEmpty else { throw CursorPlanError.invalidResponse }
        return responses.removeFirst()
    }

    func get(url: URL, bearerToken: String, extraHeaders: [String: String]) async throws -> CursorPlanHTTPResponse {
        requested.append(url)
        guard !responses.isEmpty else { throw CursorPlanError.invalidResponse }
        return responses.removeFirst()
    }
}
