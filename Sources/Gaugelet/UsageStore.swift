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
        static let cursorUsageEnabled = "cursorUsageEnabled"
        static let selectedPlan = "selectedPlan"
    }

    @Published private(set) var state: UsageState
    @Published private(set) var cursorState: UsageState
    @Published var selectedPlan: UsagePlan {
        didSet {
            defaults.set(selectedPlan.rawValue, forKey: DefaultsKey.selectedPlan)
        }
    }
    @Published var cursorUsageEnabled: Bool {
        didSet {
            defaults.set(cursorUsageEnabled, forKey: DefaultsKey.cursorUsageEnabled)
            if cursorUsageEnabled {
                refreshCursor()
            } else {
                stopCursorRefresh()
                clearCursorSnapshot()
                if sourcePreference != .demo {
                    publishCursor(.unavailable(errorMessage: "Cursor plan usage is off."))
                }
            }
        }
    }
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
                clearCursorSnapshot()
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

    var menuBarLimit: UsageLimit? {
        if pinnedLimitID.hasPrefix("cursor:") {
            return cursorState.snapshot?.limits.first { $0.id == pinnedLimitID }
        }
        return snapshot?.menuBarLimit(pinnedID: pinnedLimitID)
    }

    var menuBarUsageState: UsageState {
        pinnedLimitID.hasPrefix("cursor:") ? cursorState : state
    }

    var presentedState: UsageState {
        selectedPlan == .cursor ? cursorState : state
    }

    var presentedIsRefreshing: Bool {
        selectedPlan == .cursor ? isRefreshingCursor : isRefreshing
    }

    var showsCursorEnable: Bool {
        selectedPlan == .cursor && sourcePreference != .demo && !cursorUsageEnabled
    }

    var menuBarChoices: [UsageLimit] {
        (snapshot?.orderedLimits ?? []) + (cursorState.snapshot?.orderedLimits ?? [])
    }

    @Published private(set) var isRefreshing = false
    @Published private(set) var isRefreshingCursor = false

    var onStatusPresentationChange: (() -> Void)?
    var onNotificationPreferenceChanged: ((Bool) -> Void)?
    var onUsageAlert: ((GaugeletUsageAlert) -> Void)?
    var snapshot: UsageSnapshot? { state.snapshot }

    private let defaults: UserDefaults
    private let provider: any UsageProviding
    private let cursorProvider: any CursorPlanFetching
    private let staleDataLifetime: TimeInterval
    private let now: () -> Date
    private var lastKnownGoodSnapshot: UsageSnapshot?
    private var lastKnownGoodReceivedAt: Date?
    private var refreshGeneration: UInt64 = 0
    private var refreshTask: Task<Void, Never>?
    private var staleExpiryTask: Task<Void, Never>?
    private var cursorLastKnownGoodSnapshot: UsageSnapshot?
    private var cursorLastKnownGoodReceivedAt: Date?
    private var cursorRefreshGeneration: UInt64 = 0
    private var cursorRefreshTask: Task<Void, Never>?
    private var cursorStaleExpiryTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        provider: any UsageProviding = CodexUsageProvider(),
        cursorProvider: any CursorPlanFetching = CursorPlanProvider(),
        staleDataLifetime: TimeInterval = 15 * 60,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.provider = provider
        self.cursorProvider = cursorProvider
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
        let savedPlan = defaults.string(forKey: DefaultsKey.selectedPlan)
            .flatMap(UsagePlan.init(rawValue:)) ?? .chatgpt
        let savedCursorUsage = defaults.object(forKey: DefaultsKey.cursorUsageEnabled) as? Bool ?? false

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
        selectedPlan = savedPlan
        cursorUsageEnabled = savedCursorUsage
        state = savedSource == .demo
            ? .demo(DemoUsageProvider.snapshot(for: savedScenario))
            : .loading
        cursorState = savedSource == .demo
            ? .demo(DemoUsageProvider.cursorSnapshot(for: savedScenario))
            : (savedCursorUsage ? .loading : .unavailable(errorMessage: "Cursor plan usage is off."))
    }

    func refreshPresented() {
        if selectedPlan == .cursor {
            refreshCursor()
        } else {
            refresh()
        }
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
            isRefreshingCursor = false
            publish(.demo(DemoUsageProvider.snapshot(for: scenario)))
            publishCursor(.demo(DemoUsageProvider.cursorSnapshot(for: scenario)))
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
        refreshCursor()
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
        stopCursorRefresh()
    }

    func open(_ link: GaugeletLink) {
        NSWorkspace.shared.open(link.url)
    }

    func openManageUsage(for snapshot: UsageSnapshot) {
        switch snapshot.billingShape {
        case .chatGPT:
            open(.usage)
        case .weeklyPool:
            open(.grokDashboard)
        case .legacyCycle:
            open(.cursorSpending)
        }
    }

    func quit() {
        NSApp.terminate(nil)
    }

    func refreshCursor() {
        guard sourcePreference != .demo else {
            isRefreshingCursor = false
            publishCursor(.demo(DemoUsageProvider.cursorSnapshot(for: scenario, now: now())))
            return
        }
        guard cursorUsageEnabled else {
            if case .unavailable = cursorState { return }
            publishCursor(.unavailable(errorMessage: "Cursor plan usage is off."))
            return
        }

        cursorRefreshGeneration &+= 1
        let generation = cursorRefreshGeneration
        cursorRefreshTask?.cancel()
        isRefreshingCursor = true
        if cursorState.snapshot?.source != .cursorPlan && cursorState.snapshot?.source != .grokPlan {
            publishCursor(.loading)
        }

        let cursorProvider = cursorProvider
        cursorRefreshTask = Task { [weak self] in
            let result: Result<UsageSnapshot, Error>
            do {
                result = .success(try await cursorProvider.fetchSnapshot())
            } catch {
                result = .failure(error)
            }
            guard !Task.isCancelled, let self else { return }
            self.completeCursorRefresh(result, generation: generation)
        }
    }

    private func completeCursorRefresh(
        _ result: Result<UsageSnapshot, Error>,
        generation: UInt64
    ) {
        guard generation == cursorRefreshGeneration, cursorUsageEnabled, sourcePreference != .demo else { return }
        isRefreshingCursor = false
        cursorRefreshTask = nil

        switch result {
        case .success(let snapshot):
            cursorLastKnownGoodSnapshot = snapshot.isSignedIn ? snapshot : nil
            cursorLastKnownGoodReceivedAt = snapshot.isSignedIn ? now() : nil
            publishCursor(.live(snapshot))
        case .failure(let error):
            let message = "Cursor usage is unavailable: \(error.localizedDescription)"
            let currentTime = now()
            if
                canRetainCursorStaleData(after: error),
                let cursorLastKnownGoodSnapshot,
                let cursorLastKnownGoodReceivedAt,
                currentTime.timeIntervalSince(cursorLastKnownGoodReceivedAt) < staleDataLifetime
            {
                publishCursor(.stale(
                    snapshot: cursorLastKnownGoodSnapshot,
                    errorMessage: message,
                    failedAt: currentTime
                ))
            } else {
                clearCursorSnapshot()
                publishCursor(.unavailable(errorMessage: message))
            }
        }
    }

    private func publishCursor(_ newState: UsageState) {
        cursorStaleExpiryTask?.cancel()
        cursorStaleExpiryTask = nil
        let notifications: [GaugeletUsageAlert]
        if case .live = newState {
            notifications = UsageNotificationPolicy.alerts(
                previous: cursorState.snapshot,
                current: newState.snapshot,
                warningThreshold: warningThreshold,
                notifyOnRestore: notifyOnRestore
            )
        } else {
            notifications = []
        }
        cursorState = newState

        if case .stale(let snapshot, let errorMessage, _) = newState {
            scheduleCursorStaleExpiry(snapshot: snapshot, errorMessage: errorMessage)
        }

        onStatusPresentationChange?()
        if usageNotificationsEnabled {
            notifications.forEach { onUsageAlert?($0) }
        }
    }

    private func scheduleCursorStaleExpiry(snapshot: UsageSnapshot, errorMessage: String) {
        guard let cursorLastKnownGoodReceivedAt else { return }
        let expiryDate = cursorLastKnownGoodReceivedAt.addingTimeInterval(staleDataLifetime)
        let delay = max(expiryDate.timeIntervalSince(now()), 0)
        let nanoseconds = UInt64(min(delay * 1_000_000_000, Double(UInt64.max)))

        cursorStaleExpiryTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            guard
                let self,
                case .stale(let currentSnapshot, _, _) = self.cursorState,
                currentSnapshot == snapshot
            else { return }
            self.clearCursorSnapshot()
            self.publishCursor(.unavailable(
                errorMessage: "\(errorMessage) The last successful reading is older than 15 minutes."
            ))
        }
    }

    private func canRetainCursorStaleData(after error: Error) -> Bool {
        if error is CancellationError { return false }
        guard let cursorError = error as? CursorPlanError else { return true }
        switch cursorError {
        case .notSignedIn, .unauthorized, .noUsage:
            return false
        case .invalidResponse, .timedOut, .responseTooLarge, .sessionUnreadable, .grokResponse:
            return true
        }
    }

    private func clearCursorSnapshot() {
        cursorLastKnownGoodSnapshot = nil
        cursorLastKnownGoodReceivedAt = nil
        cursorStaleExpiryTask?.cancel()
        cursorStaleExpiryTask = nil
    }

    private func stopCursorRefresh() {
        cursorRefreshGeneration &+= 1
        cursorRefreshTask?.cancel()
        cursorRefreshTask = nil
        isRefreshingCursor = false
        cursorStaleExpiryTask?.cancel()
        cursorStaleExpiryTask = nil
    }
}
