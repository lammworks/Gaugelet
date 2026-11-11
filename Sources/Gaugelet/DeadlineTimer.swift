import Foundation

/// A single deadline, with a generation guard for callbacks already queued at cancellation.
@MainActor
final class DeadlineTimer {
    typealias Scheduler = (Date, TimeInterval, @escaping @MainActor () -> Void) -> (() -> Void)

    private let schedule: Scheduler
    private var cancelScheduled: (() -> Void)?
    private var generation: UInt64 = 0

    init(schedule: Scheduler? = nil) {
        self.schedule = schedule ?? Self.scheduleTimer
    }

    func set(deadline: Date?, tolerance: TimeInterval = 0, action: @escaping @MainActor () -> Void) {
        cancel()
        guard let deadline else { return }
        let scheduledGeneration = generation
        cancelScheduled = schedule(deadline, tolerance) { [weak self] in
            guard let self, self.generation == scheduledGeneration else { return }
            self.cancelScheduled = nil
            // A one-shot callback is consumed even if its underlying scheduler repeats it.
            self.generation &+= 1
            action()
        }
    }

    func cancel() {
        generation &+= 1
        cancelScheduled?()
        cancelScheduled = nil
    }

    private static func scheduleTimer(
        deadline: Date,
        tolerance: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> () -> Void {
        let timer = Timer(fire: deadline, interval: 0, repeats: false) { _ in
            Task { @MainActor in action() }
        }
        timer.tolerance = max(tolerance, 0)
        RunLoop.main.add(timer, forMode: .common)
        return { timer.invalidate() }
    }
}
