import Foundation
import IOKit.ps

@MainActor
final class UsagePowerMonitor {
    private let onPolicyChange: (UsageRefreshPolicy) -> Void
    private let readPolicy: @MainActor () -> UsageRefreshPolicy
    private let notificationCenter: NotificationCenter
    private var powerStateObserver: NSObjectProtocol?
    private var powerSourceRunLoopSource: CFRunLoopSource?
    private var powerSourceContext: PowerSourceCallbackContext?
    private var isMonitoring = false
    private var monitoringGeneration: UInt64 = 0

    private(set) var currentPolicy: UsageRefreshPolicy

    init(
        onPolicyChange: @escaping (UsageRefreshPolicy) -> Void,
        readPolicy: @escaping @MainActor () -> UsageRefreshPolicy = {
            UsagePowerMonitor.systemPolicy()
        },
        notificationCenter: NotificationCenter = .default
    ) {
        self.onPolicyChange = onPolicyChange
        self.readPolicy = readPolicy
        self.notificationCenter = notificationCenter
        currentPolicy = readPolicy()
    }

    func start() {
        guard !isMonitoring else { return }
        isMonitoring = true
        monitoringGeneration &+= 1
        let generation = monitoringGeneration
        let notifyChange: @Sendable () -> Void = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isMonitoring,
                      self.monitoringGeneration == generation else { return }
                self.refresh()
            }
        }

        powerStateObserver = notificationCenter.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: ProcessInfo.processInfo,
            queue: nil
        ) { _ in
            notifyChange()
        }

        let context = PowerSourceCallbackContext(onChange: notifyChange)
        powerSourceContext = context
        let contextPointer = Unmanaged.passUnretained(context).toOpaque()
        powerSourceRunLoopSource = IOPSNotificationCreateRunLoopSource({ rawContext in
            guard let rawContext else { return }
            let context = Unmanaged<PowerSourceCallbackContext>
                .fromOpaque(rawContext)
                .takeUnretainedValue()
            context.onChange()
        }, contextPointer)?.takeRetainedValue()
        if let powerSourceRunLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), powerSourceRunLoopSource, .commonModes)
        }
        refresh()
    }

    func stop() {
        isMonitoring = false
        monitoringGeneration &+= 1
        if let powerStateObserver {
            notificationCenter.removeObserver(powerStateObserver)
            self.powerStateObserver = nil
        }
        if let powerSourceRunLoopSource {
            CFRunLoopSourceInvalidate(powerSourceRunLoopSource)
            self.powerSourceRunLoopSource = nil
        }
        powerSourceContext = nil
    }

    func refresh() {
        let policy = readPolicy()
        guard policy != currentPolicy else { return }
        currentPolicy = policy
        onPolicyChange(policy)
    }

    deinit {
        if let powerStateObserver {
            notificationCenter.removeObserver(powerStateObserver)
        }
        // Keep the callback context alive until main-run-loop teardown completes.
        let cleanup = PowerSourceCleanup(
            source: powerSourceRunLoopSource,
            context: powerSourceContext
        )
        DispatchQueue.main.async {
            cleanup.invalidate()
        }
    }

    private static func systemPolicy() -> UsageRefreshPolicy {
        let source: UsagePowerSource
        if let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let providingSource = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() {
            switch providingSource as String {
            case kIOPMACPowerKey: source = .acPower
            case kIOPMBatteryPowerKey: source = .battery
            case kIOPMUPSPowerKey: source = .ups
            default: source = .unknown
            }
        } else {
            source = .unknown
        }
        return .resolve(
            powerSource: source,
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }
}

private final class PowerSourceCallbackContext: @unchecked Sendable {
    let onChange: @Sendable () -> Void

    init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
    }
}

// The immutable registration only crosses queues for teardown on its owning run loop.
private struct PowerSourceCleanup: @unchecked Sendable {
    let source: CFRunLoopSource?
    let context: PowerSourceCallbackContext?

    @MainActor
    func invalidate() {
        if let source { CFRunLoopSourceInvalidate(source) }
        withExtendedLifetime(context) {}
    }
}
