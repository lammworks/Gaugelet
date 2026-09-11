import AppKit
import Foundation

@MainActor
final class UsageStore: ObservableObject {
    private enum DefaultsKey {
        static let scenario = "demoScenario"
        static let showPercentage = "showPercentageInMenuBar"
        static let hoverToOpen = "hoverToOpen"
        static let warningThreshold = "warningThreshold"
        static let sourcePreference = "sourcePreference"
        static let iconStyle = "iconStyle"
        static let usageNotificationsEnabled = "usageNotificationsEnabled"
    }

    @Published private(set) var state: UsageState
    @Published var scenario: DemoScenario {
        didSet {
            defaults.set(scenario.rawValue, forKey: DefaultsKey.scenario)
            if sourcePreference == .demo {
                refresh()
            }
        }
    }
    @Published var showPercentageInMenuBar: Bool {
        didSet {
            defaults.set(showPercentageInMenuBar, forKey: DefaultsKey.showPercentage)
            onStatusPresentationChange?()
        }
    }
    @Published var hoverToOpen: Bool {
        didSet {
            defaults.set(hoverToOpen, forKey: DefaultsKey.hoverToOpen)
        }
    }
    @Published var warningThreshold: Int {
        didSet {
            let clampedThreshold = min(max(warningThreshold, 5), 50)
            guard warningThreshold == clampedThreshold else {
                warningThreshold = clampedThreshold
                return
            }
            defaults.set(warningThreshold, forKey: DefaultsKey.warningThreshold)
            onStatusPresentationChange?()
        }
    }
    @Published var sourcePreference: UsageSourcePreference {
        didSet {
            if sourcePreference != oldValue {
                clearLastKnownGoodSnapshot()
            }
            defaults.set(sourcePreference.rawValue, forKey: DefaultsKey.sourcePreference)
            refresh()
        }
    }
    @Published var iconStyle: GaugeletIconStyle {
        didSet {
            defaults.set(iconStyle.rawValue, forKey: DefaultsKey.iconStyle)
            onStatusPresentationChange?()
        }
    }
    @Published var usageNotificationsEnabled: Bool {
        didSet {
            defaults.set(usageNotificationsEnabled, forKey: DefaultsKey.usageNotificationsEnabled)
            onNotificationPreferenceChanged?(usageNotificationsEnabled)
        }
    }
    @Published var pinnedLimitID: String {
        didSet {
            defaults.set(pinnedLimitID, forKey: "pinnedLimitID")
            onStatusPresentationChange?()
        }
    }
    @Published var notifyOnRestore: Bool {
        didSet { defaults.set(notifyOnRestore, forKey: "notifyOnRestore") }
    }
    @Published var activityEnabled: Bool {
        didSet {
            defaults.set(activityEnabled, forKey: "activityEnabled")
            refreshActivity()
        }
    }
    @Published private(set) var activityState: ActivityState = .disabled
    private var activityTask: Task<Void, Never>?
    private var activityGeneration: UInt64 = 0
    private var lastRefreshAttempt: Date?

    var menuBarLimit: UsageLimit? { snapshot?.menuBarLimit(pinnedID: pinnedLimitID) }

    @Published private(set) var isRefreshing = false

    var onStatusPresentationChange: (() -> Void)?
    var onNotificationPreferenceChanged: ((Bool) -> Void)?
    var onUsageAlert: ((GaugeletUsageAlert) -> Void)?
    var snapshot: UsageSnapshot? { state.snapshot }

    private let defaults: UserDefaults
    private let provider: any UsageProviding
    private let staleDataLifetime: TimeInterval
    private let now: () -> Date
    private var lastKnownGoodSnapshot: UsageSnapshot?
    private var lastKnownGoodReceivedAt: Date?
    private var refreshGeneration: UInt64 = 0
    private var refreshTask: Task<Void, Never>?
    private var staleExpiryTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        provider: any UsageProviding = CodexUsageProvider(),
        staleDataLifetime: TimeInterval = 15 * 60,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.provider = provider
        self.staleDataLifetime = max(staleDataLifetime, 0)
        self.now = now

        let savedScenario = defaults.string(forKey: DefaultsKey.scenario)
            .flatMap(DemoScenario.init(rawValue:)) ?? .comfortable
        let savedThreshold = defaults.object(forKey: DefaultsKey.warningThreshold) as? Int ?? 20
        let savedSource = defaults.string(forKey: DefaultsKey.sourcePreference)
            .flatMap(UsageSourcePreference.init(rawValue:)) ?? .codexAppServer
        let savedIconStyle = defaults.string(forKey: DefaultsKey.iconStyle)
            .flatMap { rawValue in
                if let style = GaugeletIconStyle(rawValue: rawValue) { return style }
                if rawValue == "dracula" || rawValue == "dark" { return .aurora }
                return nil
            } ?? .core

        pinnedLimitID = defaults.string(forKey: "pinnedLimitID") ?? ""
        notifyOnRestore = defaults.bool(forKey: "notifyOnRestore")
        activityEnabled = defaults.bool(forKey: "activityEnabled")
        scenario = savedScenario
        showPercentageInMenuBar = defaults.object(forKey: DefaultsKey.showPercentage) as? Bool ?? true
        hoverToOpen = defaults.object(forKey: DefaultsKey.hoverToOpen) as? Bool ?? false
        warningThreshold = min(max(savedThreshold, 5), 50)
        sourcePreference = savedSource
        iconStyle = savedIconStyle
        usageNotificationsEnabled = defaults.object(forKey: DefaultsKey.usageNotificationsEnabled) as? Bool ?? false
        state = savedSource == .demo
            ? .demo(DemoUsageProvider.snapshot(for: savedScenario))
            : .loading
    }

    func refreshIfNeeded(maximumAge: TimeInterval = 60) {
        guard !isRefreshing else { return }
        if let lastRefreshAttempt, now().timeIntervalSince(lastRefreshAttempt) < maximumAge { return }
        refresh()
    }

    func refreshIfDue() {
        guard !isRefreshing, sourcePreference == .codexAppServer else { return }
        let current = now()
        let lastAttempt = lastRefreshAttempt ?? .distantPast
        let resetDue = snapshot?.limits.contains {
            guard let reset = $0.resetDate else { return false }
            return reset > lastAttempt && reset <= current
        } ?? false
        if resetDue || current.timeIntervalSince(lastAttempt) >= 5 * 60 { refresh() }
    }

    func refresh() {
        lastRefreshAttempt = now()
        activityTask?.cancel()
        activityGeneration &+= 1
        activityState = activityEnabled ? .loading : .disabled
        refreshGeneration &+= 1
        let generation = refreshGeneration
        refreshTask?.cancel()

        if sourcePreference == .demo {
            isRefreshing = false
            publish(.demo(DemoUsageProvider.snapshot(for: scenario)))
            refreshActivity()
            return
        }

        isRefreshing = true
        if state.snapshot?.source != .codexAppServer {
            publish(.loading)
        }

        let provider = provider
        refreshTask = Task { [weak self] in
            let result: Result<UsageSnapshot, Error>
            do {
                result = .success(try await provider.fetchSnapshot())
            } catch {
                result = .failure(error)
            }

            guard !Task.isCancelled, let self else { return }
            self.completeRefresh(result, generation: generation)
        }
    }

    private func completeRefresh(
        _ result: Result<UsageSnapshot, Error>,
        generation: UInt64
    ) {
        guard generation == refreshGeneration, sourcePreference == .codexAppServer else { return }

        isRefreshing = false
        refreshTask = nil

        switch result {
        case .success(let snapshot):
            lastKnownGoodSnapshot = snapshot
            lastKnownGoodReceivedAt = now()
            publish(.live(snapshot))
            refreshActivity()
        case .failure(let error):
            activityState = activityEnabled ? .unavailable : .disabled
            let message = "Codex usage is unavailable: \(error.localizedDescription)"
            let currentTime = now()
            if
                canRetainStaleData(after: error),
                let lastKnownGoodSnapshot,
                let lastKnownGoodReceivedAt,
                currentTime.timeIntervalSince(lastKnownGoodReceivedAt) < staleDataLifetime
            {
                publish(.stale(
                    snapshot: lastKnownGoodSnapshot,
                    errorMessage: message,
                    failedAt: currentTime
                ))
            } else {
                clearLastKnownGoodSnapshot()
                publish(.unavailable(errorMessage: message))
            }
        }
    }

    private func publish(_ newState: UsageState) {
        staleExpiryTask?.cancel()
        staleExpiryTask = nil
        let notifications: [GaugeletUsageAlert]
        if case .live = newState {
            notifications = UsageNotificationPolicy.alerts(
                previous: state.snapshot, current: newState.snapshot,
                warningThreshold: warningThreshold, notifyOnRestore: notifyOnRestore
            )
        } else { notifications = [] }
        state = newState

        if case .stale(let snapshot, let errorMessage, _) = newState {
            scheduleStaleExpiry(snapshot: snapshot, errorMessage: errorMessage)
        }

        onStatusPresentationChange?()

        if usageNotificationsEnabled {
            notifications.forEach { onUsageAlert?($0) }
        }
    }

    private func refreshActivity() {
        activityTask?.cancel()
        activityGeneration &+= 1
        let generation = activityGeneration
        guard activityEnabled else { activityState = .disabled; return }
        if sourcePreference == .demo {
            activityState = .available(DemoUsageProvider.activity(now: now()))
            return
        }
        guard case .live = state else {
            activityState = .unavailable
            return
        }
        activityState = .loading
        let provider = provider
        activityTask = Task { [weak self] in
            let result = try? await provider.fetchActivity()
            guard !Task.isCancelled, let self, self.activityGeneration == generation, self.activityEnabled else { return }
            self.activityState = result.map(ActivityState.available) ?? .unavailable
            self.activityTask = nil
        }
    }

    private func scheduleStaleExpiry(snapshot: UsageSnapshot, errorMessage: String) {
        guard let lastKnownGoodReceivedAt else { return }
        let expiryDate = lastKnownGoodReceivedAt.addingTimeInterval(staleDataLifetime)
        let delay = max(expiryDate.timeIntervalSince(now()), 0)
        let nanoseconds = UInt64(min(delay * 1_000_000_000, Double(UInt64.max)))

        staleExpiryTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }

            guard
                let self,
                case .stale(let currentSnapshot, _, _) = self.state,
                currentSnapshot == snapshot
            else { return }

            self.clearLastKnownGoodSnapshot()
            self.publish(.unavailable(
                errorMessage: "\(errorMessage) The last successful reading is older than 15 minutes."
            ))
        }
    }

    private func canRetainStaleData(after error: Error) -> Bool {
        if error is CancellationError { return false }
        guard let codexError = error as? CodexUsageError else { return true }

        switch codexError {
        case .codexNotFound, .serverError, .noRateLimits:
            return false
        case .launchFailed, .emptyResponse, .invalidResponse, .timedOut, .responseTooLarge:
            return true
        }
    }

    private func clearLastKnownGoodSnapshot() {
        lastKnownGoodSnapshot = nil
        lastKnownGoodReceivedAt = nil
        staleExpiryTask?.cancel()
        staleExpiryTask = nil
    }

    func cancelRefresh() {
        activityGeneration &+= 1
        activityTask?.cancel()
        activityTask = nil
        refreshGeneration &+= 1
        refreshTask?.cancel()
        refreshTask = nil
        isRefreshing = false
        staleExpiryTask?.cancel()
        staleExpiryTask = nil
    }

    func open(_ link: GaugeletLink) {
        NSWorkspace.shared.open(link.url)
    }

    func quit() {
        NSApp.terminate(nil)
    }
}
