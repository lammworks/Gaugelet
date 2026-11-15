import CryptoKit
import Foundation

enum CursorPlanError: LocalizedError, Equatable, Sendable {
    case notSignedIn
    case unauthorized
    case invalidResponse
    case noUsage
    case timedOut
    case responseTooLarge
    case sessionUnreadable

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            "Open Cursor and sign in, then retry."
        case .unauthorized:
            "Cursor rejected the saved sign-in. Open Cursor and sign in again."
        case .invalidResponse:
            "Cursor returned an unsupported usage response."
        case .noUsage:
            "No Cursor plan usage was returned."
        case .timedOut:
            "Cursor did not respond within 12 seconds."
        case .responseTooLarge:
            "Cursor returned more data than Gaugelet can safely process."
        case .sessionUnreadable:
            "Cursor’s saved sign-in could not be read. Open Cursor and retry."
        }
    }
}

enum CursorPlanRead: Equatable, Sendable {
    case snapshot(UsageSnapshot)
    case signedOut(UsageSnapshot)
    case retryFallback
    case failed(CursorPlanError)
}

struct CursorPlanHTTPResponse: Equatable, Sendable {
    let statusCode: Int
    let body: Data
}

protocol CursorPlanTransport: Sendable {
    func post(url: URL, bearerToken: String, extraHeaders: [String: String], body: Data) async throws -> CursorPlanHTTPResponse
    func get(url: URL, bearerToken: String, extraHeaders: [String: String]) async throws -> CursorPlanHTTPResponse
}

struct CursorCredentialLocator: Sendable {
    var cursorDatabaseURL: URL
    var grokAuthURL: URL

    static func live() -> CursorCredentialLocator {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return CursorCredentialLocator(
            cursorDatabaseURL: home
                .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb"),
            grokAuthURL: home.appendingPathComponent(".grok/auth.json")
        )
    }

    func cursorAccessToken() throws -> String? {
        guard FileManager.default.fileExists(atPath: cursorDatabaseURL.path) else { return nil }
        let query = "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken' LIMIT 1;"
        let fallback = "SELECT value FROM cursorDiskKV WHERE key = 'cursorAuth/accessToken' LIMIT 1;"
        if let token = try token(from: cursorDatabaseURL, sql: query) { return token }
        return try token(from: cursorDatabaseURL, sql: fallback)
    }

    func grokAccessToken() throws -> String? {
        guard FileManager.default.fileExists(atPath: grokAuthURL.path) else { return nil }
        let values = try grokAuthURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, (values.fileSize ?? 0) <= 262_144 else {
            throw CursorPlanError.sessionUnreadable
        }
        let data = try Data(contentsOf: grokAuthURL)
        guard data.count <= 262_144,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw CursorPlanError.sessionUnreadable }
        for key in ["access_token", "accessToken", "token"] {
            if let token = CursorPlanParser.acceptedToken(json[key] as? String) { return token }
        }
        return nil
    }

    private func token(from databaseURL: URL, sql: String) throws -> String? {
        let process = Process()
        let output = Pipe()
        let input = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        // The query is the process input, not a second argument. Some sqlite3
        // builds run only one command-line statement, which would skip the SELECT.
        process.arguments = [Self.sqliteURI(for: databaseURL)]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = input
        do {
            try process.run()
        } catch {
            throw CursorPlanError.sessionUnreadable
        }
        let script = Data(".timeout 300\n\(sql)\n".utf8)
        do {
            try input.fileHandleForWriting.write(contentsOf: script)
            try input.fileHandleForWriting.close()
        } catch {
            process.terminate()
            throw CursorPlanError.sessionUnreadable
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard data.count <= 16_384 else { throw CursorPlanError.sessionUnreadable }
        let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if process.terminationStatus != 0 {
            if raw?.isEmpty != false { return nil }
            throw CursorPlanError.sessionUnreadable
        }
        guard let raw, !raw.isEmpty else { return nil }
        guard let token = CursorPlanParser.acceptedToken(raw) else {
            throw CursorPlanError.sessionUnreadable
        }
        return token
    }

    static func sqliteURI(for url: URL) -> String {
        let path = url.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? url.path
        return "file://\(path)?mode=ro"
    }
}

struct URLSessionCursorPlanTransport: CursorPlanTransport {
    func post(url: URL, bearerToken: String, extraHeaders: [String: String], body: Data) async throws -> CursorPlanHTTPResponse {
        try await send(url: url, method: "POST", bearerToken: bearerToken, extraHeaders: extraHeaders, body: body)
    }

    func get(url: URL, bearerToken: String, extraHeaders: [String: String]) async throws -> CursorPlanHTTPResponse {
        try await send(url: url, method: "GET", bearerToken: bearerToken, extraHeaders: extraHeaders, body: nil)
    }

    private func send(
        url: URL,
        method: String,
        bearerToken: String,
        extraHeaders: [String: String],
        body: Data?
    ) async throws -> CursorPlanHTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("Gaugelet", forHTTPHeaderField: "User-Agent")
        for (field, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        do {
        let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw CursorPlanError.invalidResponse }
            guard data.count <= CursorPlanParser.maximumResponseBytes else { throw CursorPlanError.responseTooLarge }
            return CursorPlanHTTPResponse(statusCode: http.statusCode, body: data)
        } catch let error as CursorPlanError {
            throw error
        } catch let error as URLError where error.code == .timedOut {
            throw CursorPlanError.timedOut
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw CursorPlanError.timedOut
        }
    }
}

protocol CursorPlanFetching: Sendable {
    func fetchSnapshot() async throws -> UsageSnapshot
}

struct CursorPlanProvider: CursorPlanFetching, Sendable {
    private let locator: CursorCredentialLocator
    private let transport: any CursorPlanTransport
    private let now: @Sendable () -> Date

    init(
        locator: CursorCredentialLocator = .live(),
        transport: any CursorPlanTransport = URLSessionCursorPlanTransport(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.locator = locator
        self.transport = transport
        self.now = now
    }

    func fetchSnapshot() async throws -> UsageSnapshot {
        let currentTime = now()
        let locator = locator
        let cursorToken = try await Task.detached {
            try locator.cursorAccessToken()
        }.value
        if let cursorToken {
            return try await fetchCursor(token: cursorToken, now: currentTime)
        }
        let grokToken = try await Task.detached {
            try locator.grokAccessToken()
        }.value
        if let grokToken {
            return try await fetchGrok(token: grokToken, now: currentTime)
        }
        return CursorPlanParser.signedOutSnapshot(now: currentTime, source: .cursorPlan)
    }

    private func fetchCursor(token: String, now: Date) async throws -> UsageSnapshot {
        let primary: CursorPlanHTTPResponse?
        do {
            primary = try await postPeriod(
                url: CursorPlanParser.currentPeriodURL,
                token: token,
                extraHeaders: ["Content-Type": "application/json"]
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            primary = nil
        }
        if let primary {
            switch CursorPlanParser.interpret(statusCode: primary.statusCode, body: primary.body, now: now, source: .cursorPlan) {
            case .snapshot(let snapshot):
                return identified(snapshot, token: token)
            case .signedOut(let snapshot):
                return snapshot
            case .retryFallback, .failed:
                break
            }
        }

        let fallback = try await postPeriod(
            url: CursorPlanParser.fallbackPeriodURL,
            token: token,
            extraHeaders: [
                "Content-Type": "application/json",
                "Connect-Protocol-Version": "1"
            ]
        )
        switch CursorPlanParser.interpret(statusCode: fallback.statusCode, body: fallback.body, now: now, source: .cursorPlan) {
        case .snapshot(let snapshot):
            return identified(snapshot, token: token)
        case .signedOut(let snapshot):
            return snapshot
        case .retryFallback:
            throw CursorPlanError.invalidResponse
        case .failed(let error):
            throw error
        }
    }

    private func postPeriod(url: URL, token: String, extraHeaders: [String: String]) async throws -> CursorPlanHTTPResponse {
        try await transport.post(
            url: url,
            bearerToken: token,
            extraHeaders: extraHeaders,
            body: Data("{}".utf8)
        )
    }

    private func fetchGrok(token: String, now: Date) async throws -> UsageSnapshot {
        let response = try await transport.get(
            url: CursorPlanParser.grokBillingURL,
            bearerToken: token,
            extraHeaders: ["X-XAI-Token-Auth": "xai-grok-cli"]
        )
        switch CursorPlanParser.interpretGrok(statusCode: response.statusCode, body: response.body, now: now) {
        case .snapshot(let snapshot):
            return identified(snapshot, token: token)
        case .signedOut(let snapshot):
            return snapshot
        case .retryFallback:
            throw CursorPlanError.invalidResponse
        case .failed(let error):
            throw error
        }
    }

    private func identified(_ snapshot: UsageSnapshot, token: String) -> UsageSnapshot {
        guard snapshot.isSignedIn, let accountID = CursorPlanParser.sessionIdentity(for: token) else {
            return snapshot
        }
        var identified = snapshot
        identified.accountID = accountID
        return identified
    }
}

enum CursorPlanParser {
    static let maximumResponseBytes = 1_048_576
    static let currentPeriodURL = URL(string: "https://cursor.com/api/dashboard/get-current-period-usage")!
    static let fallbackPeriodURL = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage")!
    static let grokBillingURL = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!

    static func snapshot(
        currentPeriod: Data?,
        usageSummary: Data?,
        grokCredits: Data?,
        hasCursorSession: Bool,
        now: Date = Date()
    ) throws -> UsageSnapshot {
        // usageSummary is intentionally unused. A monthly summary can report 0%
        // while the current-period payload has the real weekly pool.
        _ = usageSummary
        if hasCursorSession {
            guard let currentPeriod else {
                return signedOutSnapshot(now: now, source: .cursorPlan)
            }
            switch interpret(statusCode: 200, body: currentPeriod, now: now, source: .cursorPlan) {
            case .snapshot(let snapshot), .signedOut(let snapshot):
                return snapshot
            case .retryFallback:
                throw CursorPlanError.invalidResponse
            case .failed(let error):
                throw error
            }
        }
        if let grokCredits {
            switch interpretGrok(statusCode: 200, body: grokCredits, now: now) {
            case .snapshot(let snapshot), .signedOut(let snapshot):
                return snapshot
            case .retryFallback:
                throw CursorPlanError.invalidResponse
            case .failed(let error):
                throw error
            }
        }
        return signedOutSnapshot(now: now, source: .cursorPlan)
    }

    static func interpret(
        statusCode: Int,
        body: Data,
        now: Date,
        source: UsageSource
    ) -> CursorPlanRead {
        if statusCode == 401 || statusCode == 403 {
            return .signedOut(signedOutSnapshot(
                now: now,
                source: source,
                detail: "Cursor rejected the saved sign-in. Open Cursor and sign in again."
            ))
        }
        guard (200..<300).contains(statusCode) else { return .retryFallback }
        guard body.count <= maximumResponseBytes else { return .failed(.responseTooLarge) }
        do {
            return .snapshot(try parseCurrentPeriod(body, now: now, source: source))
        } catch let error as CursorPlanError {
            return .failed(error)
        } catch {
            return .failed(.invalidResponse)
        }
    }

    static func interpretGrok(statusCode: Int, body: Data, now: Date) -> CursorPlanRead {
        if statusCode == 401 || statusCode == 403 {
            return .signedOut(signedOutSnapshot(
                now: now,
                source: .grokPlan,
                detail: "Grok rejected the saved sign-in. Open Grok and sign in again."
            ))
        }
        guard (200..<300).contains(statusCode) else { return .failed(.invalidResponse) }
        guard body.count <= maximumResponseBytes else { return .failed(.responseTooLarge) }
        do {
            return .snapshot(try parseGrokCredits(body, now: now))
        } catch let error as CursorPlanError {
            return .failed(error)
        } catch {
            return .failed(.invalidResponse)
        }
    }

    static func parseCurrentPeriod(_ data: Data, now: Date = Date(), source: UsageSource = .cursorPlan) throws -> UsageSnapshot {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CursorPlanError.invalidResponse
        }
        let payload = (json["result"] as? [String: Any]) ?? json
        let planUsage = payload["planUsage"] as? [String: Any] ?? [:]
        let start = parseDate(payload["billingCycleStart"])
        let end = parseDate(payload["billingCycleEnd"])
        let weekly = isWeekly(start: start, end: end)
        let totalRemaining = remainingPercent(used: finiteNumber(planUsage["totalPercentUsed"]))
            ?? remainingPercent(
                usedCents: finiteNumber(planUsage["includedSpend"]),
                limitCents: finiteNumber(planUsage["limit"])
            )
        guard let totalRemaining else { throw CursorPlanError.noUsage }

        var limits = [
            UsageLimit(
                id: "cursor:included",
                name: "Included usage",
                remainingPercent: totalRemaining,
                resetDate: end,
                bucketID: "a-included",
                contextNote: weekly ? "Weekly pool · Grok and Cursor" : "Included this billing cycle"
            )
        ]

        if let auto = finiteNumber(planUsage["autoPercentUsed"]),
           let autoRemaining = remainingPercent(used: auto),
           weekly || isDistinct(auto, from: finiteNumber(planUsage["totalPercentUsed"])) {
            limits.append(
                UsageLimit(
                    id: "cursor:models",
                    name: weekly ? "Cursor models" : "Auto",
                    remainingPercent: autoRemaining,
                    resetDate: end,
                    bucketID: "b-models",
                    contextNote: weekly ? "Grok and Composer · same weekly pool" : "Auto"
                )
            )
        }

        if !weekly,
           let api = finiteNumber(planUsage["apiPercentUsed"]),
           let apiRemaining = remainingPercent(used: api),
           isDistinct(api, from: finiteNumber(planUsage["totalPercentUsed"])),
           isDistinct(api, from: finiteNumber(planUsage["autoPercentUsed"])) {
            limits.append(
                UsageLimit(
                    id: "cursor:api",
                    name: "API",
                    remainingPercent: apiRemaining,
                    resetDate: end,
                    bucketID: "c-api",
                    contextNote: "API"
                )
            )
        }

        if let spend = spendCapLimit(from: payload["spendLimitUsage"], reset: end) {
            limits.append(spend)
        }

        var credits: [CreditBalance] = []
        if weekly, finiteNumber(planUsage["apiPercentUsed"]) != nil {
            credits.append(
                CreditBalance(
                    id: "cursor:other-models",
                    name: "Other models",
                    balance: "Prepaid",
                    hasCredits: true,
                    unlimited: false,
                    detail: "Third-party models",
                    usesPlainLabel: true
                )
            )
        }
        if let prepaid = prepaidCredit(from: payload) {
            credits.append(prepaid)
        }

        var snapshot = UsageSnapshot(
            planName: weekly ? "X Subscription" : legacyPlanName(from: payload),
            limits: limits,
            lastUpdated: now,
            isSignedIn: true,
            note: weekly ? "Shared weekly pool for Grok and Cursor." : "Cursor plan usage for this billing cycle.",
            source: source,
            sourceDetail: "Grok and Cursor plan usage. Read-only via the local Cursor sign-in."
        )
        snapshot.plan = .cursor
        snapshot.billingShape = weekly ? .weeklyPool : .legacyCycle
        snapshot.credits = credits
        return snapshot
    }

    static func parseGrokCredits(_ data: Data, now: Date = Date()) throws -> UsageSnapshot {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CursorPlanError.invalidResponse
        }
        let config = json["config"] as? [String: Any] ?? json
        let period = config["currentPeriod"] as? [String: Any] ?? json["currentPeriod"] as? [String: Any]
        guard let used = finiteNumber(config["creditUsagePercent"]) ?? finiteNumber(json["creditUsagePercent"]),
              let remaining = remainingPercent(used: used)
        else { throw CursorPlanError.noUsage }

        let start = parseDate(period?["start"]) ?? parseDate(config["billingPeriodStart"])
        let end = parseDate(period?["end"]) ?? parseDate(config["billingPeriodEnd"])
        let type = (period?["type"] as? String) ?? (config["currentPeriodType"] as? String) ?? ""
        let weekly = type.uppercased().contains("WEEK") || isWeekly(start: start, end: end)
        var snapshot = UsageSnapshot(
            planName: weekly ? "X Subscription" : "Grok plan",
            limits: [
                UsageLimit(
                    id: "cursor:included",
                    name: "Included usage",
                    remainingPercent: remaining,
                    resetDate: end,
                    bucketID: "a-included",
                    contextNote: weekly ? "Weekly pool · Grok and Cursor" : "Included usage"
                )
            ],
            lastUpdated: now,
            isSignedIn: true,
            note: "Shared weekly pool for Grok and Cursor.",
            source: .grokPlan,
            sourceDetail: "Grok and Cursor plan usage. Read-only via the local Grok sign-in."
        )
        snapshot.plan = .cursor
        snapshot.billingShape = weekly ? .weeklyPool : .legacyCycle
        if let prepaid = prepaidCredit(from: json) ?? prepaidCredit(from: config) {
            snapshot.credits = [prepaid]
        }
        return snapshot
    }

    static func signedOutSnapshot(
        now: Date,
        source: UsageSource,
        detail: String = "No Cursor or Grok session was found on this Mac."
    ) -> UsageSnapshot {
        var snapshot = UsageSnapshot(
            planName: "Not connected",
            limits: [],
            lastUpdated: now,
            isSignedIn: false,
            note: "Open Cursor and sign in.",
            source: source,
            sourceDetail: detail
        )
        snapshot.plan = .cursor
        return snapshot
    }

    static func acceptedToken(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, token.count <= 8_192, token.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            return nil
        }
        return token
    }

    static func sessionIdentity(for token: String) -> String? {
        guard acceptedToken(token) != nil else { return nil }
        if let subject = jwtSubject(token) {
            return "sub:\(subject)"
        }
        let digest = SHA256.hash(data: Data(token.utf8))
        let hex = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        return "sha256:\(hex)"
    }

    private static func spendCapLimit(from raw: Any?, reset: Date?) -> UsageLimit? {
        guard let spend = raw as? [String: Any] else { return nil }
        let individualLimit = finiteNumber(spend["individualLimit"])
        let pooledLimit = finiteNumber(spend["pooledLimit"])
        let limit = (individualLimit ?? 0) > 0 ? individualLimit : pooledLimit
        let remainingCents = (individualLimit ?? 0) > 0
            ? finiteNumber(spend["individualRemaining"])
            : finiteNumber(spend["pooledRemaining"])
        guard let limit, limit > 0, let remainingCents, let percent = remainingPercent(usedCents: limit - remainingCents, limitCents: limit) else {
            return nil
        }
        return UsageLimit(
            id: "cursor:spend-cap",
            name: "Spend cap",
            remainingPercent: percent,
            resetDate: reset,
            bucketID: "d-spend",
            contextNote: "On-demand cap"
        )
    }

    private static func prepaidCredit(from payload: [String: Any]) -> CreditBalance? {
        let keys = ["prepaidBalanceCents", "prepaidCreditCents", "additionalUsageCreditCents", "creditBalanceCents"]
        guard let cents = keys.compactMap({ finiteNumber(payload[$0]) }).first,
              let display = dollarString(cents: cents)
        else { return nil }
        return CreditBalance(
            id: "cursor:additional",
            name: "Additional usage",
            balance: display,
            hasCredits: cents != 0,
            unlimited: false,
            detail: "Prepaid credit · does not reset weekly",
            usesPlainLabel: true
        )
    }

    private static func legacyPlanName(from payload: [String: Any]) -> String {
        let raw = (payload["planName"] as? String)
            ?? ((payload["planInfo"] as? [String: Any])?["planName"] as? String)
            ?? (payload["membershipType"] as? String)
        guard let raw, let label = displayLabel(raw) else { return "Cursor plan" }
        if label.localizedCaseInsensitiveContains("cursor") { return label }
        return "Cursor \(label)"
    }

    private static func displayLabel(_ value: String) -> String? {
        let words = value
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .prefix(6)
            .map { word in
                let text = String(word)
                guard let first = text.first else { return text }
                return first.uppercased() + text.dropFirst()
            }
        let joined = words.joined(separator: " ")
        guard !joined.isEmpty else { return nil }
        return String(joined.prefix(48))
    }

    static func remainingPercent(used: Double?) -> Int? {
        guard let used, used.isFinite, (0...100).contains(used) else { return nil }
        if used >= 100 { return 0 }
        return max(Int((100 - used).rounded()), 1)
    }

    static func remainingPercent(usedCents: Double?, limitCents: Double?) -> Int? {
        guard let usedCents, let limitCents, usedCents.isFinite, limitCents.isFinite, limitCents > 0, usedCents >= 0 else {
            return nil
        }
        let used = (usedCents / limitCents) * 100
        if used >= 100 { return 0 }
        return max(Int((100 - min(used, 100)).rounded()), used <= 0 ? 100 : 1)
    }

    private static func isDistinct(_ value: Double, from other: Double?) -> Bool {
        guard let other else { return true }
        return abs(value - other) > 0.05
    }

    private static func isWeekly(start: Date?, end: Date?) -> Bool {
        guard let start, let end else { return false }
        let days = end.timeIntervalSince(start) / 86_400
        return (6.0...8.0).contains(days)
    }

    static func parseDate(_ value: Any?) -> Date? {
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            return date(from: number.doubleValue)
        }
        if let string = value as? String {
            if let number = Double(string) { return date(from: number) }
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: string) { return bounded(date) }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let date = plain.date(from: string) { return bounded(date) }
        }
        return nil
    }

    private static let minimumResetTimestamp: TimeInterval = 946_684_800
    private static let maximumResetTimestamp: TimeInterval = 4_102_444_800

    private static func date(from raw: Double) -> Date? {
        guard raw.isFinite, raw > 0 else { return nil }
        let seconds: Double
        if raw > 1_000_000_000_000 {
            seconds = raw / 1000
        } else if raw > 1_000_000_000 {
            seconds = raw
        } else {
            return nil
        }
        guard seconds.isFinite,
              seconds >= minimumResetTimestamp,
              seconds <= maximumResetTimestamp
        else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    private static func bounded(_ date: Date) -> Date? {
        let seconds = date.timeIntervalSince1970
        guard seconds.isFinite,
              seconds >= minimumResetTimestamp,
              seconds <= maximumResetTimestamp
        else { return nil }
        return date
    }

    private static func jwtSubject(_ token: String) -> String? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        guard let data = base64URLDecoded(String(parts[1])),
              data.count <= 8_192,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let subject = json["sub"] as? String {
            return acceptedSubject(subject)
        }
        if let number = json["sub"] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            let value = number.doubleValue
            guard value.isFinite, value > 0, value.rounded(.towardZero) == value, let exact = Int64(exactly: value) else {
                return nil
            }
            return acceptedSubject(String(exact))
        }
        return nil
    }

    private static func acceptedSubject(_ value: String) -> String? {
        let subject = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !subject.isEmpty,
              subject.count <= 256,
              subject.unicodeScalars.allSatisfy({ (0x21...0x7e).contains($0.value) })
        else { return nil }
        return subject
    }

    private static func base64URLDecoded(_ value: String) -> Data? {
        var payload = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder != 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: payload)
    }

    private static func finiteNumber(_ value: Any?) -> Double? {
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            let double = number.doubleValue
            return double.isFinite ? double : nil
        }
        if let string = value as? String, let double = Double(string), double.isFinite {
            return double
        }
        return nil
    }

    static func dollarString(cents: Double) -> String? {
        guard cents.isFinite, abs(cents) < 100_000_000_000 else { return nil }
        let sign = cents < 0 ? "-" : ""
        return "\(sign)$\(String(format: "%.2f", abs(cents) / 100))"
    }
}
