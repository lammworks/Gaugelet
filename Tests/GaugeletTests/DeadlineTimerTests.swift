import Foundation
import XCTest
@testable import Gaugelet

final class DeadlineTimerTests: XCTestCase {
    @MainActor
    func testCanceledAndReplacedCallbacksCannotRun() {
        var callbacks: [@MainActor () -> Void] = []
        var cancellations = 0
        var calls = 0
        let timer = DeadlineTimer { _, _, callback in
            callbacks.append(callback)
            return { cancellations += 1 }
        }
        timer.set(deadline: Date()) { calls += 1 }
        timer.set(deadline: Date()) { calls += 10 }
        callbacks[0]()
        XCTAssertEqual(calls, 0)
        callbacks[1]()
        callbacks[1]()
        XCTAssertEqual(calls, 10)
        XCTAssertEqual(cancellations, 1)
        timer.set(deadline: Date()) { calls += 100 }
        timer.cancel()
        callbacks[2]()
        XCTAssertEqual(calls, 10)
        XCTAssertEqual(cancellations, 2)
    }

    @MainActor
    func testNilDeadlineCancelsWithoutSchedulingAndPreservesTolerance() {
        var scheduled: [(Date, TimeInterval)] = []
        var cancellations = 0
        let timer = DeadlineTimer { date, tolerance, _ in
            scheduled.append((date, tolerance))
            return { cancellations += 1 }
        }
        let deadline = Date(timeIntervalSince1970: 100)
        timer.set(deadline: deadline, tolerance: 5) {}
        timer.set(deadline: nil) {}
        XCTAssertEqual(scheduled.count, 1)
        XCTAssertEqual(scheduled.first?.0, deadline)
        XCTAssertEqual(scheduled.first?.1, 5)
        XCTAssertEqual(cancellations, 1)
    }
}
