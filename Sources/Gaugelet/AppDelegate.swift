import AppKit
import Sparkle
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    private let store = UsageStore()
    private let notificationManager = GaugeletNotificationManager()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: GaugeletSparkleConfiguration.isReleaseConfigured(
            infoDictionary: Bundle.main.infoDictionary
        ),
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    private var hoverResponder: StatusHoverResponder?
    private var openWorkItem: DispatchWorkItem?
    private var closeWorkItem: DispatchWorkItem?
    private let refreshTimer = DeadlineTimer()
    private let popoverVisibility = UsagePresentationVisibility()
    private let qaVisibility = UsagePresentationVisibility()
    private var isSleeping = false
    private var isTerminating = false
    private lazy var powerMonitor = UsagePowerMonitor { [weak self] policy in
        self?.store.refreshPolicy = policy
    }
    private let statusPresenter = StatusItemPresenter()
    private let countdownTimer = DeadlineTimer()
    private var qaWindow: NSWindow?
    private var isPinned = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        qaLog("applicationDidFinishLaunching")
        GaugeletSystemIcon.clearLegacyFinderOverride()
        configureStatusItem()
        configurePopover()

        store.onStatusPresentationChange = { [weak self] in
            self?.updateStatusItem()
        }
        store.onRefreshScheduleChange = { [weak self] in
            self?.scheduleAutomaticRefresh()
        }
        store.onNotificationPreferenceChanged = { [weak self] enabled in
            self?.notificationPreferenceChanged(enabled)
        }
        store.onUsageAlert = { [weak self] alert in
            self?.deliverUsageAlert(alert)
        }
        powerMonitor.start()
        store.refreshPolicy = powerMonitor.currentPolicy
        updateStatusItem()
        store.refresh()

        let workspaceNotifications = NSWorkspace.shared.notificationCenter
        workspaceNotifications.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        workspaceNotifications.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)

        if ProcessInfo.processInfo.environment["GAUGELET_OPEN_ON_LAUNCH"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.showQAPreviewWindow()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        isTerminating = true
        openWorkItem?.cancel()
        closeWorkItem?.cancel()
        refreshTimer.cancel()
        powerMonitor.stop()
        countdownTimer.cancel()
        EnergyDiagnostics.shared.report()
        store.cancelRefresh()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = GaugeletAppIcon.menuBarImage(
            for: store.iconStyle,
            mode: .loading,
            isDark: isStatusBarDark(button)
        )
        EnergyDiagnostics.shared.record(.imageAssignments)
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleProportionallyDown
        button.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
        button.target = self
        button.action = #selector(statusItemPressed(_:))
        button.sendAction(on: [.leftMouseUp])
        button.toolTip = "Gaugelet — ChatGPT plan usage"

        let responder = StatusHoverResponder(
            onEntered: { [weak self] in self?.statusItemEntered() },
            onExited: { [weak self] in self?.statusItemExited() }
        )
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: responder,
            userInfo: nil
        )
        button.addTrackingArea(trackingArea)
        hoverResponder = responder
        qaLog("status item configured")
    }

    private func configurePopover() {
        let rootView = UsagePopoverRoot(
            store: store,
            visibility: popoverVisibility,
            onHoverChanged: { [weak self] isHovering in
                self?.popoverHoverChanged(isHovering)
            },
            onCheckForUpdates: { [weak self] in
                self?.checkForUpdates()
            },
            usesStandaloneGlass: false
        )

        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.delegate = self
        popover.contentSize = NSSize(width: 336, height: 466)
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        popover.contentViewController = hostingController
    }

    private func updateStatusItem() {
        guard !isSleeping, !isTerminating, let button = statusItem.button else { return }
        let now = Date()
        let presentation = StatusItemPresentation.make(
            state: store.state,
            pinnedID: store.pinnedLimitID,
            showPercentage: store.showPercentageInMenuBar,
            now: now
        )
        EnergyDiagnostics.shared.record(.statusUpdates)
        let mutations = statusPresenter.apply(presentation, to: button)
        EnergyDiagnostics.shared.record(.statusMutations, count: mutations)
        countdownTimer.set(deadline: StatusItemPresentation.nextUpdateDate(
            state: store.state,
            pinnedID: store.pinnedLimitID,
            showPercentage: store.showPercentageInMenuBar,
            now: now
        )) { [weak self] in
            self?.updateStatusItem()
        }
    }

    private func notificationPreferenceChanged(_ enabled: Bool) {
        guard enabled else { return }

        Task { [weak self] in
            guard let self else { return }
            let granted = await notificationManager.requestAuthorization()
            guard !granted, store.usageNotificationsEnabled else { return }
            store.usageNotificationsEnabled = false
        }
    }

    private func deliverUsageAlert(_ alert: GaugeletUsageAlert) {
        guard store.usageNotificationsEnabled else { return }

        Task { [notificationManager] in
            await notificationManager.deliver(alert)
        }
    }

    private func checkForUpdates() {
        guard GaugeletSparkleConfiguration.isReleaseConfigured(
            infoDictionary: Bundle.main.infoDictionary
        ) else {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Updates are not configured in this development build."
            alert.informativeText = "Replace the release-blocking Sparkle public-key placeholder before packaging Gaugelet."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        updaterController.checkForUpdates(nil)
    }

    private func isStatusBarDark(_ button: NSStatusBarButton) -> Bool {
        button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    private func scheduleAutomaticRefresh() {
        guard !isSleeping, !isTerminating else {
            refreshTimer.cancel()
            return
        }
        refreshTimer.set(
            deadline: store.nextAutomaticRefreshDate,
            tolerance: store.nextAutomaticRefreshTolerance
        ) { [weak self] in
            guard let self, !self.isSleeping, !self.isTerminating else { return }
            EnergyDiagnostics.shared.record(.automaticRefreshes)
            self.store.refreshIfDue()
            self.scheduleAutomaticRefresh()
        }
    }

    @objc private func willSleep() {
        isSleeping = true
        refreshTimer.cancel()
        countdownTimer.cancel()
        openWorkItem?.cancel()
        closeWorkItem?.cancel()
        popoverVisibility.isVisible = false
        qaVisibility.isVisible = false
        // Bounded in-flight requests and stale-data expiry keep their existing lifecycle.
    }

    @objc private func didWake() {
        powerMonitor.refresh()
        isSleeping = false
        store.refreshIfNeeded(maximumAge: 0)
        updateStatusItem()
        popoverVisibility.isVisible = popover.isShown
        updateQAVisibility()
        scheduleAutomaticRefresh()
    }

    @objc
    private func statusItemPressed(_ sender: NSStatusBarButton) {
        openWorkItem?.cancel()
        closeWorkItem?.cancel()

        if popover.isShown {
            if isPinned {
                popover.performClose(sender)
            } else {
                isPinned = true
                popover.contentViewController?.view.window?.makeKey()
            }
            return
        }

        showPopover(pinned: true)
    }

    private func statusItemEntered() {
        closeWorkItem?.cancel()
        guard store.hoverToOpen, !popover.isShown else { return }

        openWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.showPopover(pinned: false)
        }
        openWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    private func statusItemExited() {
        openWorkItem?.cancel()
        scheduleHoverClose()
    }

    private func popoverHoverChanged(_ isHovering: Bool) {
        if isHovering {
            closeWorkItem?.cancel()
        } else {
            scheduleHoverClose()
        }
    }

    private func scheduleHoverClose() {
        guard popover.isShown, !isPinned else { return }

        closeWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.isPinned else { return }
            self.popover.performClose(nil)
        }
        closeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }

    private func showPopover(pinned: Bool) {
        store.refreshIfNeeded()
        guard let button = statusItem.button else {
            qaLog("status item button unavailable")
            return
        }
        isPinned = pinned
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        qaLog("popover show requested")

        if pinned {
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showQAPreviewWindow() {
        let rootView = UsagePopoverRoot(
            store: store,
            visibility: qaVisibility,
            onHoverChanged: { _ in },
            onCheckForUpdates: { [weak self] in
                self?.checkForUpdates()
            },
            usesStandaloneGlass: true,
            initiallyShowsSettings: ProcessInfo.processInfo.environment["GAUGELET_QA_VIEW"] == "settings"
        )
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 336, height: 466),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.delegate = self
        window.title = "Gaugelet Preview"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.contentViewController = hostingController
        window.center()
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        qaWindow = window
        updateQAVisibility()
        qaLog("QA preview window shown (visible: \(window.isVisible))")

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self, weak window] in
            window?.orderFrontRegardless()
            self?.qaLog("QA preview window refreshed (visible: \(window?.isVisible == true))")
        }
    }

    func popoverDidShow(_ notification: Notification) {
        popoverVisibility.isVisible = !isSleeping
    }

    func popoverWillClose(_ notification: Notification) {
        popoverVisibility.isVisible = false
    }

    func popoverDidClose(_ notification: Notification) {
        popoverVisibility.isVisible = false
        isPinned = false
        closeWorkItem?.cancel()
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        updateQAVisibility()
    }

    func windowWillClose(_ notification: Notification) {
        qaVisibility.isVisible = false
    }

    private func updateQAVisibility() {
        qaVisibility.isVisible = !isSleeping && qaWindow?.isVisible == true
            && qaWindow?.occlusionState.contains(.visible) == true
    }

    private func qaLog(_ message: String) {
        guard ProcessInfo.processInfo.environment["GAUGELET_OPEN_ON_LAUNCH"] == "1" else { return }
        FileHandle.standardError.write(Data("Gaugelet QA: \(message)\n".utf8))
    }
}

private final class StatusHoverResponder: NSResponder {
    private let onEntered: () -> Void
    private let onExited: () -> Void

    init(onEntered: @escaping () -> Void, onExited: @escaping () -> Void) {
        self.onEntered = onEntered
        self.onExited = onExited
        super.init()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func mouseEntered(with event: NSEvent) {
        onEntered()
    }

    override func mouseExited(with event: NSEvent) {
        onExited()
    }
}
