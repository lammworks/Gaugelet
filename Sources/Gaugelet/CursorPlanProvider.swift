import CommonCrypto
import CryptoKit
import Foundation
import LocalAuthentication
import Security

enum CursorPlanError: LocalizedError, Equatable, Sendable {
    case notSignedIn
    case unauthorized
    case invalidResponse
    case noUsage
    case timedOut
    case responseTooLarge
    case sessionUnreadable
    case grokResponse(String)
    case requestFailed(Int)

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
        case .grokResponse(let message):
            message
        case .requestFailed(let status):
            "The Cursor usage request failed (HTTP \(status))."
        }
    }
}

enum GrokCredential: Equatable, Sendable {
    case missing
    case token(String, userID: String?)
    case unusable(message: String)
}

enum CursorTokenResolution: Equatable, Sendable {
    case missing(hint: String)
    case ready(token: String, source: String)
    case blocked(title: String, hint: String)
}

enum CursorKeychainResult: Sendable {
    case password(Data)
    case missing
    case denied
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
    /// Set on the locator copy for one fetch. A later refresh cannot change it.
    var allowsKeychainPrompt = false
    var cursorKeychainPassword: @Sendable (String, Bool) -> CursorKeychainResult = { appName, allowPrompt in
        CursorKeychain.safeStoragePassword(forAppName: appName, allowPrompt: allowPrompt)
    }

    static func live() -> CursorCredentialLocator {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let override = ProcessInfo.processInfo.environment["GROK_HOME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let grokRoot: URL
        if let override, !override.isEmpty, override.count <= 1_024, !override.contains("\0") {
            grokRoot = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            grokRoot = home.appendingPathComponent(".grok")
        }
        return CursorCredentialLocator(
            cursorDatabaseURL: home
                .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb"),
            grokAuthURL: grokRoot.appendingPathComponent("auth.json")
        )
    }

    func cursorAccessToken() throws -> String? {
        switch try cursorResolution() {
        case .ready(let token, _):
            return token
        case .missing, .blocked:
            return nil
        }
    }

    func cursorResolution() throws -> CursorTokenResolution {
        let databases = cursorDatabaseCandidates()
        var sawDatabase = false
        for database in databases {
            guard FileManager.default.fileExists(atPath: database.path) else { continue }
            sawDatabase = true
            let stored = try storedAccessToken(in: database)
            guard let stored else { continue }
            return resolveStoredToken(
                stored,
                source: sourceLabel(for: database),
                appName: appName(for: database)
            )
        }
        if sawDatabase {
            return .missing(hint: "No cursorAuth/accessToken in the Cursor desktop state.vscdb. Open the Cursor desktop app and sign in.")
        }
        return .missing(hint: "No Cursor desktop database at ~/Library/Application Support/Cursor/User/globalStorage/state.vscdb. Open the Cursor desktop app and sign in.")
    }

    private func cursorDatabaseCandidates() -> [URL] {
        let primary = cursorDatabaseURL
        let parent = primary.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let siblings = ["Cursor Nightly", "Cursor Insiders"].map {
            parent.deletingLastPathComponent()
                .appendingPathComponent($0, isDirectory: true)
                .appendingPathComponent("User", isDirectory: true)
                .appendingPathComponent("globalStorage", isDirectory: true)
                .appendingPathComponent("state.vscdb")
        }
        return [primary] + siblings.filter { $0.path != primary.path }
    }

    private func appName(for database: URL) -> String {
        let folder = database
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .lastPathComponent
        return folder.localizedCaseInsensitiveContains("cursor") ? folder : "Cursor"
    }

    private func sourceLabel(for database: URL) -> String {
        "\(appName(for: database)) desktop state.vscdb cursorAuth/accessToken"
    }

    private func storedAccessToken(in database: URL) throws -> String? {
        let query = "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken' LIMIT 1;"
        let fallback = "SELECT value FROM cursorDiskKV WHERE key = 'cursorAuth/accessToken' LIMIT 1;"
        if let token = try token(from: database, sql: query) { return token }
        return try token(from: database, sql: fallback)
    }

    private func resolveStoredToken(_ stored: String, source: String, appName: String) -> CursorTokenResolution {
        guard CursorSafeStorage.isSealed(stored) else {
            guard CursorPlanParser.acceptedToken(stored) != nil else {
                return .blocked(
                    title: "Token unreadable",
                    hint: "\(appName) desktop stored cursorAuth/accessToken, but it was not a usable sign-in. Open the Cursor desktop app."
                )
            }
            return .ready(token: stored, source: source)
        }
        let service = "\(appName) Safe Storage"
        let account = "\(appName) Key"
        switch cursorKeychainPassword(appName, allowsKeychainPrompt) {
        case .password(let password) where !password.isEmpty:
            guard let token = CursorSafeStorage.unseal(stored, password: password),
                  CursorPlanParser.acceptedToken(token) != nil
            else {
                return .blocked(
                    title: "Token sealed",
                    hint: "\(appName) desktop stored a sealed sign-in in state.vscdb, but it could not be unsealed with the \(service) key. Open the Cursor desktop app."
                )
            }
            return .ready(token: token, source: "\(source), unsealed")
        case .password:
            return .blocked(
                title: "Token sealed",
                hint: "\(appName) desktop stored a sealed sign-in in state.vscdb. The Keychain item “\(service)” (account “\(account)”) was empty. Open the Cursor desktop app."
            )
        case .missing:
            return .blocked(
                title: "Token sealed",
                hint: "\(appName) desktop stored a sealed sign-in in state.vscdb (cursor-safe-storage:v1). The Keychain item “\(service)” (account “\(account)”) was not found. Open the Cursor desktop app."
            )
        case .denied:
            return .blocked(
                title: "Token sealed",
                hint: "\(appName) desktop stored a sealed sign-in in state.vscdb (cursor-safe-storage:v1). macOS did not allow Gaugelet to read the Keychain item “\(service)” (account “\(account)”). Allow Gaugelet to read that item, then refresh."
            )
        }
    }

    func grokAccessToken(now: Date = Date()) throws -> String? {
        switch try grokCredential(now: now) {
        case .missing, .unusable:
            return nil
        case .token(let token, _):
            return token
        }
    }

    func grokCredential(now: Date = Date()) throws -> GrokCredential {
        let pathLabel = Self.grokPathLabel(for: grokAuthURL)
        guard FileManager.default.fileExists(atPath: grokAuthURL.path) else { return .missing }
        let values: URLResourceValues
        do {
            values = try grokAuthURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        } catch {
            return .unusable(message: CursorPlanParser.grokAuthMessage(
                pathLabel,
                problem: "the file could not be read. Gaugelet does not read the macOS keychain"
            ))
        }
        guard values.isRegularFile == true else {
            return .unusable(message: CursorPlanParser.grokAuthMessage(
                pathLabel,
                problem: "the path is not a regular file. Gaugelet does not read the macOS keychain"
            ))
        }
        guard (values.fileSize ?? 0) <= 262_144 else {
            return .unusable(message: CursorPlanParser.grokAuthMessage(
                pathLabel,
                problem: "the file is larger than Gaugelet will read"
            ))
        }
        let data: Data
        do {
            data = try Data(contentsOf: grokAuthURL)
        } catch {
            return .unusable(message: CursorPlanParser.grokAuthMessage(
                pathLabel,
                problem: "the file could not be read. Gaugelet does not read the macOS keychain"
            ))
        }
        return CursorPlanParser.grokCredential(from: data, now: now, pathLabel: pathLabel)
    }

    static func grokPathLabel(for url: URL) -> String {
        let components = url.pathComponents
        if components.count >= 2,
           components[components.count - 1] == "auth.json",
           components[components.count - 2] == ".grok" {
            return "~/.grok/auth.json"
        }
        return "$GROK_HOME/auth.json"
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
        guard data.count <= 65_536 else { throw CursorPlanError.sessionUnreadable }
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

enum CursorKeychain {
    static func safeStoragePassword(forAppName appName: String, allowPrompt: Bool) -> CursorKeychainResult {
        safeStoragePassword(forAppName: appName, allowPrompt: allowPrompt, lookup: lookup)
    }

    static func safeStoragePassword(
        forAppName appName: String,
        allowPrompt: Bool,
        lookup: (String, Bool) -> CursorKeychainResult
    ) -> CursorKeychainResult {
        let quiet = lookup(appName, false)
        if allowPrompt, case .denied = quiet {
            return lookup(appName, true)
        }
        return quiet
    }

    /// Query used for one Safe Storage item. A quiet read sets both
    /// `LAContext.interactionNotAllowed` and `kSecUseAuthenticationUIFail`.
    /// The context flag only suppresses LocalAuthentication UI. The Keychain
    /// flag is what stops the login-keychain Allow dialog.
    static func matchingQuery(service: String, account: String, prompt: Bool) -> [String: Any] {
        let context = LAContext()
        context.interactionNotAllowed = !prompt
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]
        if !prompt {
            query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        }
        return query
    }

    static func candidateItems(forAppName appName: String) -> [(service: String, account: String)] {
        let service = "\(appName) Safe Storage"
        return [(service, "\(appName) Key"), (service, appName)]
    }

    private static func lookup(appName: String, prompt: Bool) -> CursorKeychainResult {
        var sawDenial = false
        for item in candidateItems(forAppName: appName) {
            switch genericPassword(service: item.service, account: item.account, prompt: prompt) {
            case .password(let password):
                return .password(password)
            case .missing:
                continue
            case .denied:
                sawDenial = true
            }
        }
        return sawDenial ? .denied : .missing
    }

    private static func genericPassword(service: String, account: String, prompt: Bool) -> CursorKeychainResult {
        let query = matchingQuery(service: service, account: account, prompt: prompt)
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, !data.isEmpty else { return .missing }
            return .password(data)
        case errSecItemNotFound:
            return .missing
        case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled:
            return .denied
        default:
            return .denied
        }
    }
}

enum CursorSafeStorage {
    static let marker = "cursor-safe-storage:v1:"

    static func isSealed(_ value: String) -> Bool {
        value.hasPrefix(marker)
    }

    static func unseal(_ stored: String, password: Data) -> String? {
        guard isSealed(stored) else { return nil }
        let encoded = String(stored.dropFirst(marker.count))
        guard let blob = Data(base64Encoded: encoded),
              blob.starts(with: Data("v10".utf8)),
              blob.count > 3 + 16
        else { return nil }
        let ciphertext = Data(blob.dropFirst(3))
        guard let key = derivedKey(password: password) else { return nil }
        let iv = Data(repeating: 0x20, count: Int(kCCBlockSizeAES128))
        guard let plain = decryptAES128CBC(ciphertext, key: key, iv: iv),
              let text = String(data: plain, encoding: .utf8)
        else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func derivedKey(password: Data) -> Data? {
        let salt = Data("saltysalt".utf8)
        var key = Data(count: Int(kCCKeySizeAES128))
        let status = key.withUnsafeMutableBytes { keyBytes in
            password.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.bindMemory(to: Int8.self).baseAddress,
                        password.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        UInt32(1003),
                        keyBytes.bindMemory(to: UInt8.self).baseAddress,
                        16
                    )
                }
            }
        }
        return status == kCCSuccess ? key : nil
    }

    private static func decryptAES128CBC(_ ciphertext: Data, key: Data, iv: Data) -> Data? {
        var output = Data(count: ciphertext.count + Int(kCCBlockSizeAES128))
        var written = 0
        let status = output.withUnsafeMutableBytes { outputBytes in
            ciphertext.withUnsafeBytes { cipherBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            kCCKeySizeAES128,
                            ivBytes.baseAddress,
                            cipherBytes.baseAddress,
                            ciphertext.count,
                            outputBytes.baseAddress,
                            outputBytes.count,
                            &written
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess, written > 0 else { return nil }
        return output.prefix(written)
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
    func fetchSnapshot(allowKeychainPrompt: Bool) async throws -> UsageSnapshot
}

extension CursorPlanFetching {
    func fetchSnapshot(allowKeychainPrompt: Bool) async throws -> UsageSnapshot {
        try await fetchSnapshot()
    }
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
        try await fetchSnapshot(allowKeychainPrompt: false)
    }

    func fetchSnapshot(allowKeychainPrompt: Bool) async throws -> UsageSnapshot {
        let currentTime = now()
        var locator = locator
        locator.allowsKeychainPrompt = allowKeychainPrompt
        let cursorResolution = try await Task.detached {
            try locator.cursorResolution()
        }.value
        let cursorToken: String?
        let cursorSource: String
        var cursorProblem: (title: String, hint: String)?
        switch cursorResolution {
        case .ready(let token, let source):
            cursorToken = token
            cursorSource = source
        case .missing(let hint):
            cursorToken = nil
            cursorSource = ""
            cursorProblem = ("Not signed in", hint)
        case .blocked(let title, let hint):
            cursorToken = nil
            cursorSource = ""
            cursorProblem = (title, hint)
        }
        let grok = try await Task.detached {
            try locator.grokCredential(now: currentTime)
        }.value

        let cursorSnapshot: UsageSnapshot?
        let cursorFailure: Error?
        if let cursorToken {
            do {
                let fetched = try await fetchCursor(token: cursorToken, now: currentTime)
                if fetched.snapshot.isSignedIn {
                    cursorSnapshot = fetched.snapshot
                    cursorFailure = nil
                } else {
                    cursorSnapshot = nil
                    cursorFailure = nil
                    cursorProblem = (
                        "Request failed",
                        "Cursor desktop token was read from \(cursorSource). The usage request failed (HTTP \(fetched.statusCode)). Open the Cursor desktop app if this continues."
                    )
                }
            } catch let error as CursorPlanError where error == .timedOut {
                cursorSnapshot = nil
                cursorFailure = error
                cursorProblem = (
                    "Timed out",
                    "Cursor desktop token was read from \(cursorSource). The usage request timed out after 12 seconds."
                )
            } catch {
                cursorSnapshot = nil
                cursorFailure = error
                cursorProblem = (
                    "Request failed",
                    "Cursor desktop token was read from \(cursorSource). \(error.localizedDescription) Open the Cursor desktop app if this continues."
                )
            }
        } else {
            cursorSnapshot = nil
            cursorFailure = nil
        }

        if let cursorSnapshot, cursorSnapshot.isSignedIn {
            return await attachingGrok(
                to: cursorSnapshot,
                credential: grok,
                cursorToken: cursorToken,
                now: currentTime
            )
        }

        // A timeout or unsupported payload stays a thrown failure when Grok
        // cannot stand in, so the last good reading can remain stale.
        if let cursorFailure {
            if case .token(let token, let userID) = grok,
               let cursorProblem,
               let grokSnapshot = try? await fetchGrok(token: token, userID: userID, now: currentTime),
               grokSnapshot.isSignedIn
            {
                return identified(
                    CursorPlanParser.withCursorStatus(grokSnapshot, title: cursorProblem.title, hint: cursorProblem.hint),
                    tokens: [token]
                )
            }
            throw cursorFailure
        }

        if case .token(let token, let userID) = grok {
            do {
                let grokSnapshot = try await fetchGrok(token: token, userID: userID, now: currentTime)
                if grokSnapshot.isSignedIn {
                    let reading = cursorProblem.map {
                        CursorPlanParser.withCursorStatus(grokSnapshot, title: $0.title, hint: $0.hint)
                    } ?? grokSnapshot
                    return identified(reading, tokens: [token])
                }
                if let cursorSnapshot {
                    return CursorPlanParser.withGrokPanel(cursorSnapshot, rejectedGrokLogin())
                }
                return CursorPlanParser.withGrokPanel(grokSnapshot, rejectedGrokLogin())
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? "Grok usage could not be read."
                if let cursorSnapshot {
                    return identified(
                        CursorPlanParser.withGrokPanel(
                            CursorPlanParser.withNotice(cursorSnapshot, notice: message),
                            .status(message)
                        ),
                        tokens: cursorToken.map { [$0] } ?? []
                    )
                }
                throw error
            }
        }

        if let cursorSnapshot {
            return CursorPlanParser.withGrokPanel(cursorSnapshot, grokLoginPanel(grok))
        }

        if let cursorProblem, cursorProblem.title != "Not signed in" {
            return CursorPlanParser.withCursorStatus(
                CursorPlanParser.withGrokPanel(
                    CursorPlanParser.signedOutSnapshot(
                        now: currentTime,
                        source: .cursorPlan,
                        detail: cursorProblem.hint
                    ),
                    grokLoginPanel(grok)
                ),
                title: cursorProblem.title,
                hint: cursorProblem.hint
            )
        }

        return CursorPlanParser.withGrokPanel(
            CursorPlanParser.signedOutSnapshot(
                now: currentTime,
                source: .grokPlan,
                detail: "Run `grok login` in Terminal. Gaugelet does not refresh tokens."
            ),
            grokLoginPanel(grok) ?? missingGrokLogin()
        )
    }

    private var grokPathLabel: String {
        CursorCredentialLocator.grokPathLabel(for: locator.grokAuthURL)
    }

    private func missingGrokLogin() -> GrokPanel {
        let path = grokPathLabel
        return .login(
            reason: "No Grok sign-in was found in \(path). Run `grok login`, then refresh. Gaugelet does not read the keychain.",
            pathLabel: path
        )
    }

    private func rejectedGrokLogin() -> GrokPanel {
        let path = grokPathLabel
        return .login(
            reason: "The Grok sign-in in \(path) was rejected. Run `grok login`, then refresh. Gaugelet does not refresh tokens.",
            pathLabel: path
        )
    }

    private func grokLoginPanel(_ credential: GrokCredential) -> GrokPanel? {
        switch credential {
        case .missing:
            return missingGrokLogin()
        case .token:
            return nil
        case .unusable(let message):
            return .login(reason: message, pathLabel: grokPathLabel)
        }
    }

    private func attachingGrok(
        to cursorSnapshot: UsageSnapshot,
        credential: GrokCredential,
        cursorToken: String?,
        now: Date
    ) async -> UsageSnapshot {
        switch credential {
        case .missing:
            return identified(
                CursorPlanParser.withGrokPanel(cursorSnapshot, missingGrokLogin()),
                tokens: cursorToken.map { [$0] } ?? []
            )
        case .unusable(let message):
            return identified(
                CursorPlanParser.withGrokPanel(cursorSnapshot, grokLoginPanel(.unusable(message: message))),
                tokens: cursorToken.map { [$0] } ?? []
            )
        case .token(let token, let userID):
            do {
                let grokSnapshot = try await fetchGrok(token: token, userID: userID, now: now)
                guard grokSnapshot.isSignedIn else {
                    return identified(
                        CursorPlanParser.withGrokPanel(cursorSnapshot, rejectedGrokLogin()),
                        tokens: cursorToken.map { [$0] } ?? []
                    )
                }
                let identity = cursorToken.map { [$0] } ?? []
                return identified(CursorPlanParser.combine(cursor: cursorSnapshot, grok: grokSnapshot), tokens: identity)
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? "Grok usage could not be read."
                return identified(
                    CursorPlanParser.withGrokPanel(
                        CursorPlanParser.withNotice(cursorSnapshot, notice: message),
                        .status(message)
                    ),
                    tokens: cursorToken.map { [$0] } ?? []
                )
            }
        }
    }

    private struct CursorFetchResult {
        var snapshot: UsageSnapshot
        var statusCode: Int
    }

    private func fetchCursor(token: String, now: Date) async throws -> CursorFetchResult {
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
            case .snapshot(let snapshot), .signedOut(let snapshot):
                return CursorFetchResult(snapshot: snapshot, statusCode: primary.statusCode)
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
        case .snapshot(let snapshot), .signedOut(let snapshot):
            return CursorFetchResult(snapshot: snapshot, statusCode: fallback.statusCode)
        case .retryFallback:
            throw CursorPlanError.requestFailed(fallback.statusCode)
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

    private func fetchGrok(token: String, userID: String?, now: Date) async throws -> UsageSnapshot {
        var headers = ["X-XAI-Token-Auth": "xai-grok-cli"]
        if let userID {
            headers["x-userid"] = userID
        }
        let response = try await transport.get(
            url: CursorPlanParser.grokBillingURL,
            bearerToken: token,
            extraHeaders: headers
        )
        switch CursorPlanParser.interpretGrok(statusCode: response.statusCode, body: response.body, now: now) {
        case .snapshot(let snapshot), .signedOut(let snapshot):
            return snapshot
        case .retryFallback:
            throw CursorPlanError.grokResponse(CursorPlanParser.grokHTTPMessage(statusCode: response.statusCode))
        case .failed(let error):
            throw error
        }
    }

    private func identified(_ snapshot: UsageSnapshot, tokens: [String]) -> UsageSnapshot {
        guard snapshot.isSignedIn, let accountID = CursorPlanParser.sessionIdentity(for: tokens) else {
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
                detail: "Grok rejected the saved sign-in in ~/.grok/auth.json. Run `grok login`, then refresh. Gaugelet does not refresh tokens."
            ))
        }
        guard (200..<300).contains(statusCode) else {
            return .failed(.grokResponse(grokHTTPMessage(statusCode: statusCode)))
        }
        guard body.count <= maximumResponseBytes else { return .failed(.responseTooLarge) }
        do {
            return .snapshot(try parseGrokCredits(body, now: now))
        } catch let error as CursorPlanError {
            return .failed(error)
        } catch {
            return .failed(.grokResponse(grokHTTPMessage(statusCode: statusCode)))
        }
    }

    static func grokHTTPMessage(statusCode: Int) -> String {
        "Grok usage request failed (HTTP \(statusCode)). Gaugelet called GET https://cli-chat-proxy.grok.com/v1/billing?format=credits."
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
            throw CursorPlanError.grokResponse(
                "Grok returned a usage response that was not a JSON object. Gaugelet called GET https://cli-chat-proxy.grok.com/v1/billing?format=credits."
            )
        }
        let config = json["config"] as? [String: Any] ?? json
        let period = config["currentPeriod"] as? [String: Any] ?? json["currentPeriod"] as? [String: Any]
        let start = parseDate(period?["start"]) ?? parseDate(config["billingPeriodStart"])
        let end = parseDate(period?["end"]) ?? parseDate(config["billingPeriodEnd"])
        let type = (period?["type"] as? String) ?? (config["currentPeriodType"] as? String) ?? ""
        let weekly = type.uppercased().contains("WEEK") || isWeekly(start: start, end: end)
        let hasPeriod = period != nil || start != nil || end != nil

        let reportedPercent = config["creditUsagePercent"] ?? json["creditUsagePercent"]
        let usedPercent = finiteNumber(reportedPercent)
        let monthlyUsed = centValue(config["used"])
        let monthlyLimit = centValue(config["monthlyLimit"])
        let onDemandUsed = centValue(config["onDemandUsed"] ?? json["onDemandUsed"])
        let onDemandCap = centValue(config["onDemandCap"] ?? json["onDemandCap"])

        var limits: [UsageLimit] = []
        if reportedPercent != nil {
            guard let usedPercent, usedPercent.isFinite, usedPercent >= 0,
                  let remaining = remainingPercent(used: min(usedPercent, 100))
            else { throw CursorPlanError.grokResponse(grokShapeMessage(json)) }
            limits.append(grokIncludedLimit(remaining: remaining, reset: end, weekly: weekly))
        } else if let monthlyUsed, let monthlyLimit, monthlyLimit > 0,
                  let remaining = remainingPercent(usedCents: monthlyUsed, limitCents: monthlyLimit) {
            limits.append(grokIncludedLimit(remaining: remaining, reset: end, weekly: weekly))
        } else if hasPeriod {
            // The credits API omits the percent at the start of a period. That is zero usage, not an estimate.
            limits.append(grokIncludedLimit(remaining: 100, reset: end, weekly: weekly))
        }

        let products = (config["productUsage"] as? [Any] ?? json["productUsage"] as? [Any] ?? []).prefix(16)
        var shares: [GrokProductShare] = []
        for item in products {
            guard let row = item as? [String: Any] else { continue }
            let rawName = (row["product"] as? String) ?? (row["productName"] as? String) ?? ""
            guard let name = grokProductName(rawName),
                  let percent = finiteNumber(row["usagePercent"] ?? row["usage_percent"]),
                  percent.isFinite, percent >= 0, percent <= 100
            else { continue }
            shares.append(
                GrokProductShare(
                    id: grokProductID(rawName, existing: shares.map(\.id)),
                    name: name,
                    usedPercent: Int(percent.rounded()),
                    detail: grokProductNote(rawName)
                )
            )
        }

        if let onDemandCap, onDemandCap > 0, let onDemandUsed, onDemandUsed >= 0,
           let remaining = remainingPercent(usedCents: onDemandUsed, limitCents: onDemandCap) {
            limits.append(
                UsageLimit(
                    id: "cursor:grok-on-demand",
                    name: "Grok on-demand",
                    remainingPercent: remaining,
                    resetDate: end,
                    bucketID: "i-grok-ondemand",
                    contextNote: "On-demand cap"
                )
            )
        }

        guard !limits.isEmpty else {
            throw CursorPlanError.grokResponse(grokShapeMessage(json))
        }

        let tier = displayLabel(
            (json["subscriptionTier"] as? String)
                ?? (json["subscription_tier"] as? String)
                ?? (config["subscriptionTier"] as? String)
                ?? ""
        )
        var snapshot = UsageSnapshot(
            planName: tier ?? (weekly ? "Grok" : "Grok plan"),
            limits: limits,
            lastUpdated: now,
            isSignedIn: true,
            note: "",
            source: .grokPlan,
            sourceDetail: "Grok plan usage. Read-only via the local Grok sign-in in ~/.grok/auth.json."
        )
        snapshot.plan = .cursor
        snapshot.billingShape = weekly ? .weeklyPool : .legacyCycle
        if let prepaid = prepaidCredit(from: config, id: "grok:prepaid") ?? prepaidCredit(from: json, id: "grok:prepaid") {
            snapshot.credits = [prepaid]
        }
        snapshot.grokProductShares = shares
        return snapshot
    }

    static func grokCredential(from data: Data, now: Date, pathLabel: String) -> GrokCredential {
        guard data.count <= 262_144 else {
            return .unusable(message: grokAuthMessage(pathLabel, problem: "the file is larger than Gaugelet will read"))
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .unusable(message: grokAuthMessage(
                pathLabel,
                problem: "the file is not a JSON object. Gaugelet does not read the macOS keychain"
            ))
        }
        return grokCredential(in: json, now: now, pathLabel: pathLabel)
    }

    static func grokCredential(in json: [String: Any], now: Date, pathLabel: String) -> GrokCredential {
        let candidates = nestedGrokCandidates(json)
        var sawAPIKey = candidates.contains { $0.rank == 3 }
        for candidate in candidates where candidate.rank < 3 {
            if isWebLogin(candidate.entry) { continue }
            if tokenIsAPIKey(candidate.entry) {
                sawAPIKey = true
                continue
            }
            if isExpired(candidate.entry, now: now) {
                if candidate.rank == 0 {
                    return .unusable(message: grokAuthMessage(
                        pathLabel,
                        problem: "expires_at is in the past. Gaugelet does not refresh tokens",
                        json: json
                    ))
                }
                continue
            }
            if let token = entryToken(candidate.entry) {
                return .token(token, userID: safeUserID(candidate.entry["user_id"] ?? candidate.entry["userId"]))
            }
        }
        if sawAPIKey, flatToken(json) == nil {
            return .unusable(message: grokAuthMessage(
                pathLabel,
                problem: "only an xAI API key was found (xai::api_key, or a key that starts with xai-). Plan usage needs the sign-in from `grok login`",
                json: json
            ))
        }
        if let token = flatToken(json) {
            return .token(token, userID: safeUserID(json["user_id"] ?? json["userId"]))
        }
        return .unusable(message: grokAuthMessage(
            pathLabel,
            problem: "no access token was found. Expected `key` under an https://auth.x.ai entry, or a top-level access_token. Gaugelet does not read the macOS keychain",
            json: json
        ))
    }

    static func grokAuthMessage(_ pathLabel: String, problem: String, json: [String: Any]? = nil) -> String {
        var message = "Grok sign-in in \(pathLabel): \(problem)."
        if let json {
            message += " Keys present: \(grokKeySummary(json))."
        }
        message += " Run `grok login`, then refresh. Gaugelet does not read the keychain."
        if message.count > 420 {
            return String(message.prefix(417)) + "..."
        }
        return message
    }

    static func grokKeySummary(_ json: [String: Any]) -> String {
        var parts: [String] = []
        let keys = json.keys.sorted()
        for key in keys {
            guard parts.count < 8, let label = publicJSONKey(key) else { continue }
            if let object = json[key] as? [String: Any] {
                let fields = object.keys.sorted().compactMap { publicFieldName($0) }.prefix(12)
                parts.append(fields.isEmpty ? label : "\(label) (\(fields.joined(separator: ", ")))")
            } else {
                parts.append(label)
            }
        }
        let hidden = keys.count - parts.count
        if parts.isEmpty {
            return hidden > 0 ? "\(hidden) unrecognized key\(hidden == 1 ? "" : "s")" : "none"
        }
        if hidden > 0 {
            parts.append("\(hidden) unrecognized")
        }
        return parts.joined(separator: "; ")
    }

    static func withNotice(_ snapshot: UsageSnapshot, notice: String) -> UsageSnapshot {
        copy(
            snapshot,
            note: joinedNotice(snapshot.note, notice),
            sourceDetail: joinedNotice(snapshot.sourceDetail, notice)
        )
    }

    static func withGrokPanel(_ snapshot: UsageSnapshot, _ panel: GrokPanel?) -> UsageSnapshot {
        var updated = copy(snapshot)
        updated.grokPanel = panel
        return updated
    }

    static func withCursorStatus(_ snapshot: UsageSnapshot, title: String, hint: String) -> UsageSnapshot {
        var limits = snapshot.limits.filter { $0.id != "cursor:session" }
        limits.insert(
            UsageLimit(
                id: "cursor:session",
                name: "Cursor",
                remainingPercent: 100,
                resetDate: nil,
                blockedReason: title,
                bucketID: "a-cursor-session",
                contextNote: hint
            ),
            at: 0
        )
        var updated = copy(snapshot, limits: limits, note: "")
        updated.cursorStatusTitle = title
        updated.cursorStatusHint = hint
        return updated
    }

    private static func copy(
        _ snapshot: UsageSnapshot,
        limits: [UsageLimit]? = nil,
        note: String? = nil,
        sourceDetail: String? = nil
    ) -> UsageSnapshot {
        var copy = UsageSnapshot(
            planName: snapshot.planName,
            limits: limits ?? snapshot.limits,
            lastUpdated: snapshot.lastUpdated,
            isSignedIn: snapshot.isSignedIn,
            note: note ?? snapshot.note,
            source: snapshot.source,
            sourceDetail: sourceDetail ?? snapshot.sourceDetail
        )
        copy.accountID = snapshot.accountID
        copy.resetCredits = snapshot.resetCredits
        copy.credits = snapshot.credits
        copy.omittedLimitCount = snapshot.omittedLimitCount
        copy.plan = snapshot.plan
        copy.billingShape = snapshot.billingShape
        copy.grokPanel = snapshot.grokPanel
        copy.grokProductShares = snapshot.grokProductShares
        copy.cursorStatusTitle = snapshot.cursorStatusTitle
        copy.cursorStatusHint = snapshot.cursorStatusHint
        return copy
    }

    static func combine(cursor: UsageSnapshot, grok: UsageSnapshot) -> UsageSnapshot {
        let notice = "Grok sign-in credits are listed separately and are not added to the Cursor percent."
        var snapshot = UsageSnapshot(
            planName: cursor.planName,
            limits: cursor.limits + grok.limits,
            lastUpdated: cursor.lastUpdated,
            isSignedIn: true,
            note: joinedNotice(cursor.note, notice),
            source: cursor.source,
            sourceDetail: "Cursor plan from the local Cursor sign-in, plus Grok credits from ~/.grok/auth.json. Read-only."
        )
        snapshot.plan = .cursor
        snapshot.billingShape = cursor.billingShape
        snapshot.grokPanel = cursor.grokPanel ?? grok.grokPanel
        snapshot.grokProductShares = grok.grokProductShares
        var credits = cursor.credits
        for credit in grok.credits where !credits.contains(where: { $0.id == credit.id }) {
            credits.append(credit)
        }
        snapshot.credits = credits
        return snapshot
    }

    static func sessionIdentity(for tokens: [String]) -> String? {
        let identities = tokens.compactMap { sessionIdentity(for: $0) }
        guard let first = identities.first else { return nil }
        guard identities.count > 1 else { return first }
        let digest = SHA256.hash(data: Data(identities.joined(separator: "\n").utf8))
        let hex = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        return "mix:\(hex)"
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

    private static func prepaidCredit(from payload: [String: Any], id: String = "cursor:additional") -> CreditBalance? {
        let numberKeys = ["prepaidBalanceCents", "prepaidCreditCents", "additionalUsageCreditCents", "creditBalanceCents"]
        let centKeys = ["prepaidBalance", "prepaid_balance", "prepaidBalanceCents"]
        let cents = centKeys.compactMap { centValue(payload[$0]) }.first
            ?? numberKeys.compactMap { finiteNumber(payload[$0]) }.first
        guard let cents, let display = dollarString(cents: cents) else { return nil }
        return CreditBalance(
            id: id,
            name: id == "cursor:additional" ? "Additional usage" : "Grok prepaid",
            balance: display,
            hasCredits: cents != 0,
            unlimited: false,
            detail: "Prepaid credit · does not reset weekly",
            usesPlainLabel: true
        )
    }

    private static func grokIncludedLimit(remaining: Int, reset: Date?, weekly: Bool) -> UsageLimit {
        UsageLimit(
            id: "cursor:grok-included",
            name: "Weekly pool",
            remainingPercent: remaining,
            resetDate: reset,
            bucketID: "g-grok",
            contextNote: weekly ? "One shared weekly plan" : "Grok sign-in"
        )
    }

    private static func normalizedProductKey(_ raw: String) -> String {
        String(raw.lowercased().unicodeScalars.compactMap { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : nil
        })
    }

    private static func grokProductName(_ raw: String) -> String? {
        switch normalizedProductKey(raw) {
        case "grokbuild", "build":
            return "Grok Build"
        case "grokbot", "bot":
            return "Grok Bot"
        case "grokchat", "chat":
            return "Grok Chat"
        case "grokvoice", "voice":
            return "Grok Voice"
        case "grokimagine", "imagine":
            return "Grok Imagine"
        case "grokappbuilder", "appbuilder":
            return "Grok App Builder"
        case "bugbot":
            return "Bugbot"
        case "cursor":
            return "Cursor"
        default:
            return displayLabel(raw)
        }
    }

    private static func grokProductNote(_ raw: String) -> String {
        switch normalizedProductKey(raw) {
        case "grokbuild", "build":
            return "Coding CLI. Same weekly plan, not a separate allowance."
        case "grokbot", "bot":
            return "Grok app"
        case "grokchat", "chat":
            return "grok.com chat"
        case "grokvoice", "voice":
            return "Voice"
        case "grokimagine", "imagine":
            return "Images"
        case "grokappbuilder", "appbuilder":
            return "App builder"
        case "bugbot":
            return "Share of this weekly plan"
        case "cursor":
            return "Share of this weekly plan, not the Cursor app meter"
        default:
            return "Share of this weekly plan"
        }
    }

    private static func grokProductID(_ name: String, existing: [String]) -> String {
        let slug = String(name.lowercased().map { character in
            character.isLetter || character.isNumber ? character : "-"
        }).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let clipped = String(slug.prefix(24))
        let base = "cursor:grok-product:\(clipped.isEmpty ? "other" : clipped)"
        guard existing.contains(base) else { return base }
        return "\(base)-\(existing.count)"
    }

    private static func grokShapeMessage(_ json: [String: Any]) -> String {
        "Grok returned a usage response without a readable percent. Gaugelet called GET https://cli-chat-proxy.grok.com/v1/billing?format=credits and expected config.creditUsagePercent or config.currentPeriod. Keys present: \(grokKeySummary(json))."
    }

    private struct GrokAuthCandidate {
        let rank: Int
        let scope: String
        let entry: [String: Any]
    }

    private static func nestedGrokCandidates(_ json: [String: Any]) -> [GrokAuthCandidate] {
        json.compactMap { element -> GrokAuthCandidate? in
            let scope = element.key
            let value = element.value
            guard let entry = value as? [String: Any] else { return nil }
            let rank: Int
            if scope.hasPrefix("https://auth.x.ai::") || scope == "https://auth.x.ai" {
                rank = 0
            } else if scope == "xai::api_key" {
                rank = 3
            } else if scope == "https://accounts.x.ai/sign-in" {
                rank = 2
            } else if scope.hasPrefix("https://") {
                rank = 1
            } else {
                return nil
            }
            return GrokAuthCandidate(rank: rank, scope: scope, entry: entry)
        }
        .sorted { lhs, rhs in
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            return lhs.scope < rhs.scope
        }
    }

    private static func isWebLogin(_ entry: [String: Any]) -> Bool {
        let mode = (entry["auth_mode"] as? String)?.lowercased()
        return mode == "web_login" || mode == "grok"
    }

    private static func tokenIsAPIKey(_ entry: [String: Any]) -> Bool {
        guard let token = entryToken(entry) else { return false }
        return token.hasPrefix("xai-")
    }

    private static func isExpired(_ entry: [String: Any], now: Date) -> Bool {
        guard entry["expires_at"] != nil || entry["expiresAt"] != nil else { return false }
        guard let date = parseDate(entry["expires_at"]) ?? parseDate(entry["expiresAt"]) else { return false }
        return date <= now
    }

    private static func entryToken(_ entry: [String: Any]) -> String? {
        for key in ["key", "access_token", "accessToken", "token"] {
            if let token = acceptedToken(entry[key] as? String) { return token }
        }
        return nil
    }

    private static func flatToken(_ json: [String: Any]) -> String? {
        for key in ["access_token", "accessToken", "token", "key"] {
            guard let token = acceptedToken(json[key] as? String), !token.hasPrefix("xai-") else { continue }
            return token
        }
        return nil
    }

    private static func safeUserID(_ value: Any?) -> String? {
        guard let raw = value as? String else { return nil }
        let userID = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...128).contains(userID.count),
              userID.range(of: "^[A-Za-z0-9_.:@|-]+$", options: .regularExpression) != nil
        else { return nil }
        return userID
    }

    private static func publicJSONKey(_ key: String) -> String? {
        if key == "xai::api_key" { return key }
        if key.hasPrefix("https://"),
           key.count <= 160,
           !key.contains(".."),
           !key.lowercased().contains("token="),
           key.unicodeScalars.allSatisfy({ (0x21...0x7e).contains($0.value) }) {
            return key
        }
        if !key.contains(":"), publicFieldName(key) != nil { return key }
        return nil
    }

    private static func publicFieldName(_ key: String) -> String? {
        guard key.count <= 40,
              key.range(of: "^[A-Za-z][A-Za-z0-9_]*$", options: .regularExpression) != nil
        else { return nil }
        return key
    }

    private static func centValue(_ value: Any?) -> Double? {
        if let object = value as? [String: Any] {
            if object.isEmpty { return 0 }
            return finiteNumber(object["val"])
        }
        return finiteNumber(value)
    }

    private static func joinedNotice(_ base: String, _ notice: String) -> String {
        let trimmed = notice.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return base }
        if base.contains(trimmed) { return base }
        let combined = base.isEmpty ? trimmed : "\(base) \(trimmed)"
        guard combined.count > 500 else { return combined }
        return String(combined.prefix(497)) + "..."
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
