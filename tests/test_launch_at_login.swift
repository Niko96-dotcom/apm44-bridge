import ServiceManagement
import XCTest
@testable import APM44Bridge

@MainActor
final class LaunchAtLoginControllerTests: XCTestCase {
    func testMapsEnabledAndDisabledStates() {
        XCTAssertEqual(LaunchAtLoginController.map(.enabled), .enabled)
        XCTAssertEqual(LaunchAtLoginController.map(.notRegistered), .disabled)
        XCTAssertEqual(LaunchAtLoginController.map(.notFound), .unavailable)
        XCTAssertEqual(
            LaunchAtLoginController.map(.requiresApproval),
            .requiresApproval
        )
    }
}
