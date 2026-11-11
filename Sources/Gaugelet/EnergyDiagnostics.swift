import Foundation

/// Opt-in local counters contain event names and counts, never usage/account payloads.
final class EnergyDiagnostics: @unchecked Sendable {
    static let shared = EnergyDiagnostics()
    enum Event: String {
        case statusUpdates, statusMutations, imageAssignments
        case automaticRefreshes, allowanceLaunches, activityLaunches, dashboardTicks
    }

    private let enabled = ProcessInfo.processInfo.environment["GAUGELET_ENERGY_DIAGNOSTICS"] == "1"
    private let lock = NSLock()
    private var counters: [String: Int] = [:]

    func record(_ event: Event, count: Int = 1) {
        guard enabled else { return }
        lock.lock()
        counters[event.rawValue, default: 0] += count
        lock.unlock()
    }

    func report() {
        guard enabled else { return }
        lock.lock()
        let snapshot = counters
        lock.unlock()
        guard let data = try? JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return }
        FileHandle.standardError.write(Data("Gaugelet energy counters: \(json)\n".utf8))
    }
}
