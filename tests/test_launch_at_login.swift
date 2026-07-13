import ServiceManagement
import XCTest
@testable import APM44Bridge

@MainActor
final class LaunchAtLoginControllerTests: XCTestCase {
    func testMapsRequiresApprovalAsDistinctObservableState() {
        XCTAssertEqual(
            LaunchAtLoginController.map(.requiresApproval),
            .requiresApproval
        )
    }

    func testMapsEnabledAndDisabledStates() {
        XCTAssertEqual(LaunchAtLoginController.map(.enabled), .enabled)
        XCTAssertEqual(LaunchAtLoginController.map(.notRegistered), .disabled)
        XCTAssertEqual(LaunchAtLoginController.map(.notFound), .unavailable)
    }
}
