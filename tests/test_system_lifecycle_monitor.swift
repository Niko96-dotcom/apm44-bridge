import AppKit
import XCTest
@testable import APM44Bridge

final class SystemLifecycleMonitorTests: XCTestCase {
    func testRoutesWorkspaceSleepAndWakeNotifications() {
        let center = NotificationCenter()
        var sleepCount = 0
        var wakeCount = 0
        let monitor = SystemLifecycleMonitor(
            notificationCenter: center,
            onWillSleep: { sleepCount += 1 },
            onDidWake: { wakeCount += 1 }
        )
        monitor.start()

        center.post(name: NSWorkspace.willSleepNotification, object: nil)
        center.post(name: NSWorkspace.didWakeNotification, object: nil)

        XCTAssertEqual(sleepCount, 1)
        XCTAssertEqual(wakeCount, 1)

        monitor.stop()
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        XCTAssertEqual(wakeCount, 1)
    }
}
