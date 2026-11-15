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
        XCTAssertEqual(snapshot.planName, "Grok")
        XCTAssertEqual(snapshot.limits.map(\.id), ["cursor:grok-included"])
        XCTAssertEqual(snapshot.limits.first?.remainingPercent, 60)
        XCTAssertEqual(snapshot.limits.first?.contextNote, "Grok sign-in · weekly credits")
    }

    func testGrokCreditsResponseKeepsTheWeeklyPoolAndProductBreakdown() throws {
        let body = Data(#"""
        {
          "subscriptionTier": "SuperGrok",
          "config": {
            "currentPeriod": {
              "type": "USAGE_PERIOD_TYPE_WEEKLY",
              "start": "2026-07-07T10:46:52.885620+00:00",
              "end": "2026-07-14T10:46:52.885620+00:00"
            },
            "creditUsagePercent": 46,
            "productUsage": [
              { "product": "GrokBuild", "usagePercent": 41 },
              { "product": "API", "usagePercent": 5 }
            ],
            "prepaidBalance": { "val": 1840 },
            "onDemandCap": { "val": 5000 },
            "onDemandUsed": { "val": 1250 },
            "isUnifiedBillingUser": true
          }
        }
        """#.utf8)

        let snapshot = try CursorPlanParser.parseGrokCredits(body, now: Date(timeIntervalSince1970: 1_800_000_000))

        XCTAssertEqual(snapshot.planName, "SuperGrok")
        XCTAssertEqual(snapshot.billingShape, .weeklyPool)
        XCTAssertEqual(
            snapshot.limits.map(\.id),
            ["cursor:grok-included", "cursor:grok-product:grokbuild", "cursor:grok-product:api", "cursor:grok-on-demand"]
        )
        XCTAssertEqual(snapshot.limits.map(\.remainingPercent), [54, 59, 95, 75])
        XCTAssertEqual(snapshot.credits.first?.id, "grok:prepaid")
        XCTAssertEqual(snapshot.credits.first?.displayValue, "$18.40")
        XCTAssertEqual(
            snapshot.limits.first?.resetDate,
            FixtureDate.fractional.date(from: "2026-07-14T10:46:52.885620+00:00")
        )
    }

    func testGrokMonthlyCentsAndAZeroUsagePeriodStayExplicit() throws {
        let monthly = Data(#"""
        {"config":{"monthlyLimit":{"val":15000},"used":{"val":2931},"billingPeriodStart":"2026-07-01T00:00:00Z","billingPeriodEnd":"2026-08-01T00:00:00Z"}}
        """#.utf8)
        let monthlySnapshot = try CursorPlanParser.parseGrokCredits(monthly)
        XCTAssertEqual(monthlySnapshot.billingShape, .legacyCycle)
        XCTAssertEqual(monthlySnapshot.limits.map(\.id), ["cursor:grok-included"])
        XCTAssertEqual(monthlySnapshot.limits.first?.remainingPercent, 80)

        let emptyPeriod = Data(#"""
        {"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","start":"2026-07-07T00:00:00Z","end":"2026-07-14T00:00:00Z"}}}
        """#.utf8)
        let emptySnapshot = try CursorPlanParser.parseGrokCredits(emptyPeriod)
        XCTAssertEqual(emptySnapshot.limits.first?.remainingPercent, 100)
        XCTAssertEqual(emptySnapshot.billingShape, .weeklyPool)

        let unknown = Data(#"{"unexpected":true,"secretValue":"do-not-show"}"#.utf8)
        XCTAssertThrowsError(try CursorPlanParser.parseGrokCredits(unknown)) { error in
            let message = (error as? CursorPlanError)?.errorDescription ?? ""
            XCTAssertTrue(message.contains("creditUsagePercent"))
            XCTAssertTrue(message.contains("unexpected"))
            XCTAssertFalse(message.contains("do-not-show"))
        }
    }

    func testGrokAuthFileUsesTheNestedKeyAndReportsNamesWithoutValues() throws {
        let secret = "grok-session-token"
        let refresh = "refresh-secret-value"
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let auth = directory.appendingPathComponent("auth.json")
        let nested = """
        {"https://auth.x.ai::b1a00492-073a-47ea-816f-4c329264a828":{"key":"\(secret)","refresh_token":"\(refresh)","expires_at":"2030-01-01T00:00:00Z","auth_mode":"oidc","user_id":"user-42","email":"hidden@example.com"}}
        """
        try Data(nested.utf8).write(to: auth)
        let locator = CursorCredentialLocator(
            cursorDatabaseURL: directory.appendingPathComponent("missing.vscdb"),
            grokAuthURL: auth
        )
        let credential = try locator.grokCredential(now: Date(timeIntervalSince1970: 1_800_000_000))
        guard case .token(let token, let userID) = credential else {
            return XCTFail("Expected the nested Grok key")
        }
        XCTAssertEqual(token, secret)
        XCTAssertEqual(userID, "user-42")
        XCTAssertNotEqual(token, refresh)

        let expired = """
        {"https://auth.x.ai::b1a00492-073a-47ea-816f-4c329264a828":{"key":"\(secret)","refresh_token":"\(refresh)","expires_at":"2020-01-02T00:00:00Z","auth_mode":"oidc"}}
        """
        let expiredCredential = CursorPlanParser.grokCredential(
            from: Data(expired.utf8),
            now: Date(timeIntervalSince1970: 1_800_000_000),
            pathLabel: "~/.grok/auth.json"
        )
        guard case .unusable(let expiredMessage) = expiredCredential else {
            return XCTFail("Expected an expired Grok sign-in")
        }
        XCTAssertTrue(expiredMessage.contains("~/.grok/auth.json"))
        XCTAssertTrue(expiredMessage.contains("expires_at"))
        XCTAssertTrue(expiredMessage.contains("https://auth.x.ai::"))
        XCTAssertTrue(expiredMessage.contains("Keys present:"))
        XCTAssertTrue(expiredMessage.contains("key"))
        XCTAssertFalse(expiredMessage.contains(secret))
        XCTAssertFalse(expiredMessage.contains(refresh))
        XCTAssertNil(try CursorCredentialLocator(cursorDatabaseURL: directory.appendingPathComponent("missing.vscdb"), grokAuthURL: authFile(directory, body: expired)).grokAccessToken(now: Date(timeIntervalSince1970: 1_800_000_000)))

        let apiKey = #"{"xai::api_key":{"key":"xai-secret-key","auth_mode":"api_key"}}"#
        let apiCredential = CursorPlanParser.grokCredential(
            from: Data(apiKey.utf8),
            now: Date(timeIntervalSince1970: 1_800_000_000),
            pathLabel: "~/.grok/auth.json"
        )
        guard case .unusable(let apiMessage) = apiCredential else {
            return XCTFail("Expected an API key to be refused")
        }
        XCTAssertTrue(apiMessage.contains("xai::api_key"))
        XCTAssertFalse(apiMessage.contains("xai-secret-key"))

        let flat = #"{"access_token":"flat-session-token","refresh_token":"do-not-use"}"#
        let flatCredential = CursorPlanParser.grokCredential(
            from: Data(flat.utf8),
            now: Date(timeIntervalSince1970: 1_800_000_000),
            pathLabel: "~/.grok/auth.json"
        )
        guard case .token(let flatToken, _) = flatCredential else {
            return XCTFail("Expected a legacy flat token")
        }
        XCTAssertEqual(flatToken, "flat-session-token")
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

    func testProviderShowsCursorAndGrokAsSeparateRows() async throws {
        let transport = SequenceTransport(responses: [
            CursorPlanHTTPResponse(statusCode: 200, body: try periodJSON(
                start: weeklyStart,
                end: weeklyEnd,
                total: 28,
                auto: 28,
                api: 0,
                prepaidCents: nil
            )),
            CursorPlanHTTPResponse(statusCode: 200, body: Data(#"""
            {"subscriptionTier":"SuperGrok","config":{"creditUsagePercent":40,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2026-10-25T06:32:13.504Z"}}}
            """#.utf8))
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
        let headers = await transport.getHeaders

        XCTAssertEqual(snapshot.limits.first { $0.id == "cursor:included" }?.remainingPercent, 72)
        XCTAssertEqual(snapshot.limits.first { $0.id == "cursor:grok-included" }?.remainingPercent, 60)
        XCTAssertEqual(snapshot.planName, "X Subscription")
        XCTAssertTrue(snapshot.note.contains("not added"))
        XCTAssertEqual(
            snapshot.accountID,
            CursorPlanParser.sessionIdentity(for: ["cursor-session-token", "grok-session-token"])
        )
        XCTAssertNotEqual(snapshot.accountID, "cursor-session-token")
        XCTAssertFalse(snapshot.accountID?.contains("cursor-session-token") == true)
        XCTAssertFalse(snapshot.accountID?.contains("grok-session-token") == true)
        XCTAssertEqual(requested, [CursorPlanParser.currentPeriodURL, CursorPlanParser.grokBillingURL])
        XCTAssertEqual(headers.first?["x-userid"], "user-42")
        XCTAssertEqual(headers.first?["X-XAI-Token-Auth"], "xai-grok-cli")
        XCTAssertFalse(headers.contains { $0.values.contains("grok-session-token") })
    }

    func testRejectedCursorSessionShowsGrokWhenThatSignInWorks() async throws {
        let transport = SequenceTransport(responses: [
            CursorPlanHTTPResponse(statusCode: 401, body: Data()),
            CursorPlanHTTPResponse(statusCode: 200, body: Data(#"""
            {"config":{"creditUsagePercent":40,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2026-10-25T06:32:13.504Z"}}}
            """#.utf8))
        ])
        let provider = CursorPlanProvider(
            locator: CursorCredentialLocator(
                cursorDatabaseURL: try makeCursorDatabase(token: "expired-token"),
                grokAuthURL: try makeGrokAuth(token: "grok-session-token")
            ),
            transport: transport,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )

        let snapshot = try await provider.fetchSnapshot()
        let requested = await transport.requested

        XCTAssertTrue(snapshot.isSignedIn)
        XCTAssertEqual(snapshot.source, .grokPlan)
        XCTAssertEqual(snapshot.limits.first?.id, "cursor:grok-included")
        XCTAssertTrue(snapshot.note.contains("Cursor rejected"))
        XCTAssertEqual(requested, [CursorPlanParser.currentPeriodURL, CursorPlanParser.grokBillingURL])
    }

    func testRejectedCursorSessionStaysSignedOutWithoutAGrokSignIn() async throws {
        let transport = SequenceTransport(responses: [
            CursorPlanHTTPResponse(statusCode: 401, body: Data())
        ])
        let provider = CursorPlanProvider(
            locator: CursorCredentialLocator(
                cursorDatabaseURL: try makeCursorDatabase(token: "expired-token"),
                grokAuthURL: URL(fileURLWithPath: "/tmp/gaugelet-missing-grok-auth.json")
            ),
            transport: transport
        )

        let snapshot = try await provider.fetchSnapshot()
        let requested = await transport.requested

        XCTAssertFalse(snapshot.isSignedIn)
        XCTAssertNil(snapshot.accountID)
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

    func testOversizedResetTimestampStaysUnavailable() throws {
        let body = Data(#"""
        {"billingCycleStart":"2026-10-18T00:00:00Z","billingCycleEnd":"1e308","planUsage":{"totalPercentUsed":28}}
        """#.utf8)
        let snapshot = try CursorPlanParser.parseCurrentPeriod(body)
        XCTAssertEqual(snapshot.limits.first?.remainingPercent, 72)
        XCTAssertNil(snapshot.limits.first?.resetDate)
        XCTAssertEqual(snapshot.limits.first?.resetDescription(), "Reset time unavailable")
        XCTAssertNil(CursorPlanParser.parseDate("1e308"))
        XCTAssertNil(CursorPlanParser.parseDate(1e308))
        XCTAssertEqual(
            CursorPlanParser.parseDate(1_800_000_000),
            Date(timeIntervalSince1970: 1_800_000_000)
        )
        XCTAssertEqual(
            CursorPlanParser.parseDate(1_800_000_000_000),
            Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    func testSessionIdentityFollowsTheAccountAndNotTheRawToken() {
        let first = jwt(subject: "user-123")
        let refreshed = jwt(subject: "user-123", signature: "other-signature")
        let other = jwt(subject: "user-456")

        XCTAssertEqual(CursorPlanParser.sessionIdentity(for: first), "sub:user-123")
        XCTAssertEqual(CursorPlanParser.sessionIdentity(for: first), CursorPlanParser.sessionIdentity(for: refreshed))
        XCTAssertNotEqual(CursorPlanParser.sessionIdentity(for: first), CursorPlanParser.sessionIdentity(for: other))
        XCTAssertNotEqual(CursorPlanParser.sessionIdentity(for: first), first)

        let opaque = CursorPlanParser.sessionIdentity(for: "cursor-session-token")
        XCTAssertEqual(opaque?.hasPrefix("sha256:"), true)
        XCTAssertNotEqual(opaque, "cursor-session-token")
        XCTAssertFalse(opaque?.contains("cursor-session-token") == true)
        XCTAssertNotEqual(opaque, CursorPlanParser.sessionIdentity(for: "grok-session-token"))
        XCTAssertNil(CursorPlanParser.sessionIdentity(for: "bad token"))
    }

    func testGrokFallbackCarriesTheGrokSessionIdentity() async throws {
        let transport = SequenceTransport(responses: [
            CursorPlanHTTPResponse(statusCode: 200, body: Data(#"""
            {"config":{"creditUsagePercent":40,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2026-10-25T06:32:13.504Z"}}}
            """#.utf8))
        ])
        let provider = CursorPlanProvider(
            locator: CursorCredentialLocator(
                cursorDatabaseURL: URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("\(UUID().uuidString)-missing.vscdb"),
                grokAuthURL: try makeGrokAuth(token: "grok-session-token")
            ),
            transport: transport
        )

        let snapshot = try await provider.fetchSnapshot()
        XCTAssertEqual(snapshot.source, .grokPlan)
        XCTAssertEqual(snapshot.accountID, CursorPlanParser.sessionIdentity(for: "grok-session-token"))
        XCTAssertFalse(snapshot.accountID?.contains("grok-session-token") == true)
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

    private func jwt(subject: String, signature: String = "sig") -> String {
        func segment(_ json: String) -> String {
            Data(json.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return [
            segment(#"{"alg":"none"}"#),
            segment(#"{"sub":"\#(subject)"}"#),
            signature
        ].joined(separator: ".")
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
        let body = """
        {"https://auth.x.ai::b1a00492-073a-47ea-816f-4c329264a828":{"key":"\(token)","refresh_token":"do-not-use","expires_at":"2030-01-01T00:00:00Z","auth_mode":"oidc","user_id":"user-42"}}
        """
        return try authFile(folder, body: body)
    }

    private func authFile(_ directory: URL, body: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let auth = directory.appendingPathComponent("auth.json")
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
    private(set) var getHeaders: [[String: String]] = []

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
        getHeaders.append(extraHeaders)
        guard !responses.isEmpty else { throw CursorPlanError.invalidResponse }
        return responses.removeFirst()
    }
}
