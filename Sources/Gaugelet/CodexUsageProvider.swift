import Darwin
import Foundation

enum CodexUsageError: LocalizedError, Sendable {
    case codexNotFound
    case launchFailed(String)
    case emptyResponse
    case invalidResponse
    case serverError(String)
    case noRateLimits
    case timedOut
    case responseTooLarge

    var errorDescription: String? {
        switch self {
        case .codexNotFound:
            "Codex CLI was not found. Install Codex, sign in, and then retry."
        case .launchFailed(let message):
            "Codex App Server could not start (\(message))."
        case .emptyResponse:
            "Codex App Server returned no usage response."
        case .invalidResponse:
            "Codex App Server returned an unsupported response."
        case .serverError(let message):
            message
        case .noRateLimits:
            "No ChatGPT rate-limit windows were returned."
        case .timedOut:
            "Codex App Server did not respond within 12 seconds."
        case .responseTooLarge:
            "Codex App Server returned more data than Gaugelet can safely process."
        }
    }
}

protocol UsageProviding: Sendable {
    func fetchSnapshot() async throws -> UsageSnapshot
    func fetchActivity() async throws -> UsageActivity
}

extension UsageProviding {
    func fetchActivity() async throws -> UsageActivity { throw CodexUsageError.invalidResponse }
}

struct CodexUsageProvider: UsageProviding, Sendable {
    private static let maximumResponseBytes = 1_048_576
    private static let maximumRateLimitWindows = 128

    private let executableOverride: URL?
    private let argumentsOverride: [String]?

    init(executableURL: URL? = nil, arguments: [String]? = nil) {
        executableOverride = executableURL
        argumentsOverride = arguments
    }

    func fetchSnapshot() async throws -> UsageSnapshot {
        try Self.parseSnapshot(from: await fetchResponse(method: "account/rateLimits/read"))
    }

    func fetchActivity() async throws -> UsageActivity {
        try Self.parseActivity(from: await fetchResponse(method: "account/usage/read"))
    }

    private func fetchResponse(method: String) async throws -> Data {
        let cancellation = ProcessCancellationCoordinator()
        let executableOverride = executableOverride
        let argumentsOverride = argumentsOverride
        let worker = Task.detached(priority: .utility) {
            try Self.fetchResponseSynchronously(
                method: method,
                cancellation: cancellation,
                executableOverride: executableOverride,
                argumentsOverride: argumentsOverride
            )
        }

        return try await withTaskCancellationHandler {
            let snapshot = try await worker.value
            try Task.checkCancellation()
            return snapshot
        } onCancel: {
            cancellation.cancel()
            worker.cancel()
        }
    }

    private static func fetchResponseSynchronously(
        method: String,
        cancellation: ProcessCancellationCoordinator,
        executableOverride: URL?,
        argumentsOverride: [String]?
    ) throws -> Data {
        try cancellation.checkCancellation()

        let executableURL = try executableOverride ?? locateCodexExecutable()
        let process = Process()
        let input = Pipe()
        let output = Pipe()

        process.executableURL = executableURL
        process.arguments = argumentsOverride ?? ["app-server", "--listen", "stdio://"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        var environment = ProcessInfo.processInfo.environment
        environment["RUST_LOG"] = "error"
        process.environment = environment

        do {
            try process.run()
        } catch {
            throw CodexUsageError.launchFailed(error.localizedDescription)
        }

        let controller = ProcessTerminationController(process: process)
        let timeout = DispatchWorkItem {
            controller.stop(markedAsTimeout: true)
        }
        defer {
            timeout.cancel()
            try? input.fileHandleForWriting.close()
            controller.stop()
            cancellation.detach(controller)
        }

        try cancellation.attach(controller)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 12, execute: timeout)

        let requests = [
            [
                "method": "initialize",
                "id": 1,
                "params": [
                    "clientInfo": [
                        "name": "gaugelet_macos",
                        "title": "Gaugelet",
                        "version": clientVersion
                    ]
                ]
            ] as [String: Any],
            [
                "method": "initialized",
                "params": [:]
            ] as [String: Any],
            [
                "method": method,
                "id": 2
            ] as [String: Any]
        ]

        let payload = try requests
            .map { try JSONSerialization.data(withJSONObject: $0) }
            .reduce(into: Data()) { data, line in
                data.append(line)
                data.append(0x0A)
            }

        do {
            try input.fileHandleForWriting.write(contentsOf: payload)
        } catch {
            if process.isRunning { process.terminate() }
            throw CodexUsageError.launchFailed(error.localizedDescription)
        }

        var responseData = Data()
        var exceededMaximumResponseSize = false
        while process.isRunning {
            let chunk = output.fileHandleForReading.availableData
            if chunk.isEmpty { break }

            if responseData.count + chunk.count > maximumResponseBytes {
                exceededMaximumResponseSize = true
                break
            }
            responseData.append(chunk)

            if Self.containsResponse(id: 2, in: responseData) {
                break
            }
        }

        try? input.fileHandleForWriting.close()
        timeout.cancel()
        controller.stop()
        process.waitUntilExit()

        try cancellation.checkCancellation()

        if exceededMaximumResponseSize {
            throw CodexUsageError.responseTooLarge
        }

        if controller.didTimeOut, !Self.containsResponse(id: 2, in: responseData) {
            throw CodexUsageError.timedOut
        }

        guard !responseData.isEmpty else {
            throw CodexUsageError.emptyResponse
        }

        return responseData
    }

    private static func locateCodexExecutable() throws -> URL {
        var candidates = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex"
        ]

        if let userHome = ProcessInfo.processInfo.environment["HOME"] {
            candidates.append("\(userHome)/.local/bin/codex")
        }

        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        throw CodexUsageError.codexNotFound
    }

    private static var clientVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1.0"
    }

    static func parseSnapshot(from responseData: Data, now: Date = Date()) throws -> UsageSnapshot {
        guard let responseText = String(data: responseData, encoding: .utf8) else {
            throw CodexUsageError.invalidResponse
        }

        var rateLimitResult: [String: Any]?

        for line in responseText.split(whereSeparator: \.isNewline) {
            guard
                let data = String(line).data(using: .utf8),
                let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let id = message["id"] as? NSNumber,
                id.intValue == 2
            else { continue }

            if let error = message["error"] as? [String: Any] {
                let detail = error["message"] as? String ?? "Codex could not read usage."
                throw CodexUsageError.serverError(detail)
            }

            rateLimitResult = message["result"] as? [String: Any]
            break
        }

        guard let rateLimitResult else {
            throw CodexUsageError.invalidResponse
        }

        let buckets = rateLimitBuckets(from: rateLimitResult)
        let returnedLimits = buckets
            .flatMap { limitWindows(from: $0.value, bucketID: $0.key) }
            .sorted {
                if $0.effectiveRemainingPercent == $1.effectiveRemainingPercent {
                    switch ($0.resetDate, $1.resetDate) {
                    case let (.some(lhs), .some(rhs)):
                        return lhs < rhs
                    case (.some, .none):
                        return true
                    case (.none, .some):
                        return false
                    case (.none, .none):
                        return $0.id < $1.id
                    }
                }
                return $0.effectiveRemainingPercent < $1.effectiveRemainingPercent
            }

        let limits = Array(returnedLimits.prefix(maximumRateLimitWindows))

        let resets = parseResetCredits(rateLimitResult["rateLimitResetCredits"], now: now)
        let credits = buckets.compactMap { parseCreditBalance($0.value["credits"], id: $0.key, name: $0.value["limitName"] as? String) }
        guard !limits.isEmpty || resets != nil || !credits.isEmpty else {
            throw CodexUsageError.noRateLimits
        }

        let closest = limits.first
        let note: String
        if closest?.isBlocked == true {
            note = "This limit is unavailable until the reset."
        } else if (closest?.remainingPercent ?? 100) <= 20 {
            note = "This is the closest active usage limit."
        } else {
            note = "Remaining allowance reported by Codex."
        }

        return UsageSnapshot(
            planName: planName(from: buckets),
            limits: limits,
            lastUpdated: now,
            isSignedIn: true,
            note: note,
            source: .codexAppServer,
            sourceDetail: "ChatGPT Work and Codex allowance. Read-only via Codex on this Mac.",
            accountID: displayLabel(rateLimitResult["accountId"] as? String ?? "", maximumLength: 256),
            resetCredits: resets,
            credits: credits,
            omittedLimitCount: max(returnedLimits.count - limits.count, 0)
        )
    }

    private static func parseResetCredits(_ raw: Any?, now: Date) -> EarnedResetCredits? {
        guard let value = raw as? [String: Any],
              let count = strictInteger(value["availableCount"], allowedRange: 0...1_000_000) else { return nil }
        let dates = (value["credits"] as? [[String: Any]] ?? []).prefix(100).compactMap { row -> Date? in
            guard row["status"] as? String == "available",
                  let timestamp = strictInteger(row["expiresAt"], allowedRange: 946_684_800...4_102_444_800) else { return nil }
            let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
            return date > now ? date : nil
        }
        return EarnedResetCredits(availableCount: count, earliestKnownExpiry: count > 0 ? dates.min() : nil)
    }

    private static func parseCreditBalance(_ raw: Any?, id: String, name: String?) -> CreditBalance? {
        guard let value = raw as? [String: Any],
              let has = value["hasCredits"] as? NSNumber, CFGetTypeID(has) == CFBooleanGetTypeID(),
              let unlimited = value["unlimited"] as? NSNumber, CFGetTypeID(unlimited) == CFBooleanGetTypeID() else { return nil }
        let rawBalance = value["balance"] as? String
        let balance: String?
        if let rawBalance, rawBalance.count <= 40,
           rawBalance.range(of: #"^\d+(\.\d+)?$"#, options: .regularExpression) != nil {
            balance = rawBalance
        } else { balance = nil }
        return CreditBalance(id: id, name: readableBucketLabel(name ?? id, maximumLength: 80) ?? "Credits",
                             balance: balance, hasCredits: has.boolValue, unlimited: unlimited.boolValue)
    }

    static func parseActivity(from data: Data, now: Date = Date()) throws -> UsageActivity {
        guard let text = String(data: data, encoding: .utf8) else { throw CodexUsageError.invalidResponse }
        for line in text.split(whereSeparator: \.isNewline) {
            guard let bytes = String(line).data(using: .utf8),
                  let message = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                  let id = message["id"] as? NSNumber, CFGetTypeID(id) != CFBooleanGetTypeID(), id.intValue == 2 else { continue }
            guard let result = message["result"] as? [String: Any], let summary = result["summary"] as? [String: Any] else {
                throw CodexUsageError.invalidResponse
            }
            let lifetime = strictInteger(summary["lifetimeTokens"], allowedRange: 0...9_000_000_000_000_000)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.isLenient = false
            let rawDays = result["dailyUsageBuckets"] as? [[String: Any]]
            var seen = Set<String>()
            let days = rawDays.map { rows in
                rows.prefix(366).compactMap { row -> ActivityDay? in
                    guard let date = row["startDate"] as? String, date.count == 10,
                          let parsed = formatter.date(from: date), formatter.string(from: parsed) == date,
                          let tokens = strictInteger(row["tokens"], allowedRange: 0...9_000_000_000_000_000),
                          seen.insert(date).inserted else { return nil }
                    return ActivityDay(date: date, tokens: tokens)
                }.sorted { $0.date < $1.date }
            }
            return UsageActivity(days: days.map { Array($0.suffix(7)) }, lifetimeTokens: lifetime, lastUpdated: now)
        }
        throw CodexUsageError.invalidResponse
    }

    private static func containsResponse(id expectedID: Int, in data: Data) -> Bool {
        guard let responseText = String(data: data, encoding: .utf8) else { return false }

        return responseText.split(whereSeparator: \.isNewline).contains { line in
            guard
                let lineData = String(line).data(using: .utf8),
                let message = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                let id = message["id"] as? NSNumber
            else { return false }

            return id.intValue == expectedID
        }
    }

    private static func rateLimitBuckets(from result: [String: Any]) -> [(key: String, value: [String: Any])] {
        var buckets: [(key: String, value: [String: Any])] = []

        if let multiBucket = result["rateLimitsByLimitId"] as? [String: Any], !multiBucket.isEmpty {
            buckets = multiBucket.keys.sorted().compactMap { key in
                guard let bucket = multiBucket[key] as? [String: Any] else { return nil }
                return (key, bucket)
            }
        }

        if let singleBucket = result["rateLimits"] as? [String: Any] {
            let explicitID = singleBucket["limitId"] as? String
            let key = explicitID ?? "overall"
            let alreadyIncluded = buckets.contains { bucketKey, bucket in
                let includedID = bucket["limitId"] as? String ?? bucketKey
                if let explicitID {
                    return includedID.caseInsensitiveCompare(explicitID) == .orderedSame
                }
                return sameRateLimitWindows(singleBucket, bucket)
            }

            // `rateLimits` is the backward-compatible single-bucket view. When
            // the same metered bucket is present in the multi-bucket response,
            // keep only the multi-bucket copy. If it is distinct, retain it as
            // the overall/account-level bucket instead of silently dropping it.
            if !alreadyIncluded {
                buckets.insert((key, singleBucket), at: 0)
            }
        }

        return buckets
    }

    private static func sameRateLimitWindows(_ lhs: [String: Any], _ rhs: [String: Any]) -> Bool {
        ["primary", "secondary"].allSatisfy { windowKey in
            let lhsWindow = lhs[windowKey] as? [String: Any]
            let rhsWindow = rhs[windowKey] as? [String: Any]

            guard let lhsWindow, let rhsWindow else {
                return lhsWindow == nil && rhsWindow == nil
            }

            return ["usedPercent", "windowDurationMins", "resetsAt"].allSatisfy { field in
                let lhsValue = lhsWindow[field] as? NSNumber
                let rhsValue = rhsWindow[field] as? NSNumber
                return lhsValue?.doubleValue == rhsValue?.doubleValue
            }
        }
    }

    private static func limitWindows(from bucket: [String: Any], bucketID: String) -> [UsageLimit] {
        let baseName = readableBucketLabel(
            (bucket["limitName"] as? String) ?? bucketID,
            maximumLength: 80
        )
        let hasSecondary = bucket["secondary"] is [String: Any]
        let blockedReason = blockedReason(from: bucket)

        return ["primary", "secondary"].compactMap { windowKey in
            guard
                let window = bucket[windowKey] as? [String: Any],
                let usedNumber = window["usedPercent"] as? NSNumber,
                CFGetTypeID(usedNumber) != CFBooleanGetTypeID()
            else { return nil }

            let usedPercent = usedNumber.doubleValue
            guard usedPercent.isFinite, (0...100).contains(usedPercent) else { return nil }

            // Preserve a 1% display floor until Codex reports an actual cap.
            // Rounding 99.6% used to 0% remaining would otherwise create a false
            // "limit reached" state at the exact moment accuracy matters most.
            let calculatedRemaining = Int((100 - usedPercent).rounded())
            let remaining = usedPercent >= 100
                ? 0
                : max(calculatedRemaining, 1)
            let durationMinutes = strictInteger(
                window["windowDurationMins"],
                allowedRange: 1...525_600
            )
            let resetTimestamp = strictInteger(
                window["resetsAt"],
                allowedRange: 946_684_800...4_102_444_800
            )
            let durationName = durationMinutes.map { durationLabel(minutes: $0) }
            let resetDate = resetTimestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            let name: String

            if let baseName {
                if let durationName {
                    name = "\(baseName) · \(durationName)"
                } else if hasSecondary {
                    name = "\(baseName) · \(windowKey.capitalized)"
                } else {
                    name = baseName
                }
            } else if let durationName {
                name = "\(durationName) limit"
            } else {
                name = windowKey == "primary" ? "Usage limit" : "Secondary usage limit"
            }

            return UsageLimit(
                id: "\(bucketID)-\(windowKey)",
                name: name,
                remainingPercent: min(max(remaining, 0), 100),
                resetDate: resetDate,
                blockedReason: blockedReason,
                bucketID: bucketID,
                windowDurationMins: durationMinutes
            )
        }
    }

    private static func readableBucketLabel(_ value: String, maximumLength: Int) -> String? {
        guard let collapsed = displayLabel(value, maximumLength: maximumLength) else { return nil }

        let words = collapsed
            .replacingOccurrences(of: "-", with: "_")
            .split(separator: "_", omittingEmptySubsequences: true)

        guard words.count > 1 else {
            guard collapsed == collapsed.lowercased() else { return collapsed }
            return collapsed.prefix(1).uppercased() + String(collapsed.dropFirst())
        }
        return words
            .map { word in
                let text = String(word)
                return text.isEmpty
                    ? text
                    : text.prefix(1).uppercased() + String(text.dropFirst())
            }
            .joined(separator: " ")
    }

    private static func planName(from buckets: [(key: String, value: [String: Any])]) -> String {
        guard
            let rawPlan = buckets.lazy.compactMap({ $0.value["planType"] as? String }).first,
            let safePlan = displayLabel(rawPlan, maximumLength: 48)
        else {
            return "ChatGPT plan"
        }

        let words = safePlan
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
        return words.isEmpty ? "ChatGPT plan" : "ChatGPT \(words)"
    }

    private static func blockedReason(from bucket: [String: Any]) -> String? {
        if (bucket["spendControlReached"] as? Bool) == true {
            return "Spending limit reached"
        }

        guard let reachedType = bucket["rateLimitReachedType"] as? String else { return nil }
        switch reachedType {
        case "workspace_owner_credits_depleted", "workspace_member_credits_depleted":
            return "Workspace credits depleted"
        case "workspace_owner_usage_limit_reached", "workspace_member_usage_limit_reached":
            return "Workspace usage limit reached"
        default:
            return "Rate limit reached"
        }
    }

    private static func durationLabel(minutes: Int) -> String {
        if minutes == 10_080 { return "Weekly" }
        if minutes % 10_080 == 0 { return "\(minutes / 10_080)-week" }
        if minutes % 1_440 == 0 { return "\(minutes / 1_440)-day" }
        if minutes % 60 == 0 { return "\(minutes / 60)-hour" }
        return "\(minutes)-minute"
    }

    private static func displayLabel(_ value: String, maximumLength: Int) -> String? {
        let collapsed = value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(maximumLength))
    }

    private static func strictInteger(_ value: Any?, allowedRange: ClosedRange<Int>) -> Int? {
        guard
            let number = value as? NSNumber,
            CFGetTypeID(number) != CFBooleanGetTypeID()
        else { return nil }

        let doubleValue = number.doubleValue
        guard
            doubleValue.isFinite,
            doubleValue.rounded(.towardZero) == doubleValue,
            doubleValue >= Double(allowedRange.lowerBound),
            doubleValue <= Double(allowedRange.upperBound)
        else { return nil }

        return Int(doubleValue)
    }
}

private final class ProcessCancellationCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private var controller: ProcessTerminationController?
    private var cancelled = false

    func attach(_ controller: ProcessTerminationController) throws {
        let shouldStop = lock.withLock {
            if cancelled { return true }
            self.controller = controller
            return false
        }

        if shouldStop {
            controller.stop()
            throw CancellationError()
        }
    }

    func detach(_ controller: ProcessTerminationController) {
        lock.withLock {
            if self.controller === controller {
                self.controller = nil
            }
        }
    }

    func cancel() {
        let controller = lock.withLock {
            cancelled = true
            return self.controller
        }
        controller?.stop()
    }

    func checkCancellation() throws {
        if lock.withLock({ cancelled }) {
            throw CancellationError()
        }
    }
}

private final class ProcessTerminationController: @unchecked Sendable {
    private let process: Process
    private let lock = NSLock()
    private var stopped = false
    private var timedOut = false

    init(process: Process) {
        self.process = process
    }

    var didTimeOut: Bool {
        lock.withLock { timedOut }
    }

    func stop(markedAsTimeout: Bool = false) {
        let shouldStop = lock.withLock {
            guard !stopped else { return false }
            stopped = true
            timedOut = markedAsTimeout
            return true
        }
        guard shouldStop, process.isRunning else { return }

        let processIdentifier = process.processIdentifier
        process.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) { [self] in
            guard process.isRunning else { return }
            kill(processIdentifier, SIGKILL)
        }
    }
}
