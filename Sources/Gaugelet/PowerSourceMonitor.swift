import Foundation
import IOKit.ps

/// Observes AC vs battery power and Low Power Mode without polling.
final class PowerSourceMonitor: @unchecked Sendable {
    private var powerRunLoopSource: CFRunLoopSource?
    private var lowPowerObserver: NSObjectProtocol?
    private var onChange: (@MainActor (GaugeletEnergyPolicy) -> Void)?
    private let lock = NSLock()
    private var _policy: GaugeletEnergyPolicy = .default

    var policy: GaugeletEnergyPolicy {
        lock.lock()
        defer { lock.unlock() }
        return _policy
    }

    @MainActor
    func start(onChange: @escaping @MainActor (GaugeletEnergyPolicy) -> Void) {
        stop()
        self.onChange = onChange
        let initial = Self.currentPolicy()
        setPolicy(initial)
        onChange(initial)

        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let monitor = Unmanaged<PowerSourceMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.handlePowerChange()
        }

        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            powerRunLoopSource = source
        }

        lowPowerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handlePowerChange()
        }
    }

    @MainActor
    func stop() {
        if let source = powerRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            powerRunLoopSource = nil
        }
        if let lowPowerObserver {
            NotificationCenter.default.removeObserver(lowPowerObserver)
            self.lowPowerObserver = nil
        }
        onChange = nil
    }

    private func handlePowerChange() {
        let next = Self.currentPolicy()
        guard next != policy else { return }
        setPolicy(next)
        Task { @MainActor in
            self.onChange?(next)
        }
    }

    private func setPolicy(_ policy: GaugeletEnergyPolicy) {
        lock.lock()
        _policy = policy
        lock.unlock()
    }

    static func currentPolicy(
        processInfo: ProcessInfo = .processInfo
    ) -> GaugeletEnergyPolicy {
        let snapshot = readPowerSources()
        return GaugeletEnergyPolicy.resolve(
            usingBatteryPower: snapshot.usingBatteryPower,
            hasInternalBattery: snapshot.hasInternalBattery,
            lowPowerModeEnabled: processInfo.isLowPowerModeEnabled
        )
    }

    private struct PowerSourceSnapshot: Equatable {
        var usingBatteryPower: Bool
        var hasInternalBattery: Bool
    }

    private static func readPowerSources() -> PowerSourceSnapshot {
        var hasInternalBattery = false

        guard
            let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else {
            let providing = IOPSGetProvidingPowerSourceType(nil)?.takeUnretainedValue() as String?
            return PowerSourceSnapshot(
                usingBatteryPower: providing == kIOPSBatteryPowerValue,
                hasInternalBattery: false
            )
        }

        for source in list {
            guard
                let description = IOPSGetPowerSourceDescription(blob, source)?
                    .takeUnretainedValue() as? [String: Any]
            else { continue }

            if let type = description[kIOPSTypeKey] as? String,
               type == kIOPSInternalBatteryType {
                hasInternalBattery = true
            }
        }

        let providing = IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue() as String?
        return PowerSourceSnapshot(
            usingBatteryPower: providing == kIOPSBatteryPowerValue,
            hasInternalBattery: hasInternalBattery
        )
    }
}
