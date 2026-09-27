import XCTest
@testable import APM44Bridge

private func makeChecklist(
    driverStatus: DriverStatus = .ready,
    didAttemptReload: Bool = false,
    halNominalRate: Double? = 44100,
    devices: [AudioDeviceRow] = [],
    appBuildID: String? = "0.12.7+aaa",
    driverBuildID: String? = "0.12.7+aaa"
) -> FirstRunChecklist {
    FirstRunChecklist(
        driverStatus: driverStatus,
        didAttemptReload: didAttemptReload,
        halNominalRate: halNominalRate,
        devices: devices,
        appBuildID: appBuildID,
        driverBuildID: driverBuildID
    )
}

private func makeDevice(name: String, rate: Double) -> AudioDeviceRow {
    AudioDeviceRow(
        uid: "uid-\(name)-\(Int(rate))",
        name: name,
        nominalRate: rate,
        hasInput: false,
        hasOutput: true
    )
}

final class FirstRunChecklistDriverTests: XCTestCase {
    func testReadyDriver() {
        let checklist = makeChecklist(driverStatus: .ready)
        XCTAssertTrue(checklist.driverReady)
        XCTAssertEqual(checklist.driverDetail, AppStrings.driverReadyDetail)
        XCTAssertEqual(checklist.driverAction, .none)
    }

    func testBuildMismatchDetailAndAction() {
        let checklist = makeChecklist(
            driverStatus: .buildMismatch,
            appBuildID: "0.12.7+aaa",
            driverBuildID: "0.12.7+bbb"
        )
        XCTAssertFalse(checklist.driverReady)
        XCTAssertEqual(checklist.driverAction, .downloadInstaller)
        XCTAssertEqual(
            checklist.driverDetail,
            AppStrings.driverBuildMismatchDetail(app: "0.12.7+aaa", driver: "0.12.7+bbb")
        )
    }

    func testBuildMismatchMissingDriverIDUsesPlaceholder() {
        let checklist = makeChecklist(
            driverStatus: .buildMismatch,
            appBuildID: "0.12.7+aaa",
            driverBuildID: nil
        )
        XCTAssertEqual(
            checklist.driverDetail,
            AppStrings.driverBuildMismatchDetail(
                app: "0.12.7+aaa",
                driver: AppStrings.buildIDMissingPlaceholder
            )
        )
        XCTAssertTrue(checklist.driverDetail.contains(AppStrings.buildIDMissingPlaceholder))
        XCTAssertTrue(checklist.driverDetail.contains("0.12.7+aaa"))
    }

    func testInstalledNotLoadedBeforeReloadAttempt() {
        let checklist = makeChecklist(
            driverStatus: .installedNotLoaded,
            didAttemptReload: false
        )
        XCTAssertFalse(checklist.driverReady)
        XCTAssertEqual(checklist.driverAction, .reloadDriver)
        XCTAssertEqual(checklist.driverDetail, AppStrings.driverReloadHint)
    }

    func testInstalledNotLoadedAfterReloadAttempt() {
        let checklist = makeChecklist(
            driverStatus: .installedNotLoaded,
            didAttemptReload: true
        )
        XCTAssertFalse(checklist.driverReady)
        XCTAssertEqual(checklist.driverAction, .reloadDriver)
        XCTAssertEqual(checklist.driverDetail, AppStrings.driverRestartHint)
    }

    func testNotInstalled() {
        let checklist = makeChecklist(driverStatus: .notInstalled)
        XCTAssertFalse(checklist.driverReady)
        XCTAssertEqual(checklist.driverAction, .downloadInstaller)
        XCTAssertEqual(checklist.driverDetail, AppStrings.driverMissingDetail)
    }
}

final class FirstRunChecklistRateTests: XCTestCase {
    func testHalRate44100IsOkWithEmptyDetail() {
        let checklist = makeChecklist(halNominalRate: 44100)
        XCTAssertTrue(checklist.halRateOk)
        XCTAssertEqual(checklist.halRateDetail, "")
    }

    func testHalRate48000IsNotOkWithHint() {
        let checklist = makeChecklist(halNominalRate: 48000)
        XCTAssertFalse(checklist.halRateOk)
        XCTAssertEqual(checklist.halRateDetail, AppStrings.nominalRateHint(48000))
    }

    func testHalRateNilMeansNotDetected() {
        let checklist = makeChecklist(halNominalRate: nil)
        XCTAssertFalse(checklist.halRateOk)
        XCTAssertEqual(checklist.halRateDetail, AppStrings.driverNotDetected)
    }

    func testAirPodsAt48000IsOk() {
        let devices = [makeDevice(name: "AirPods Max", rate: 48000)]
        let checklist = makeChecklist(devices: devices)
        XCTAssertTrue(checklist.airPodsRateOk)
        XCTAssertEqual(
            checklist.airPodsRateDetail,
            AppStrings.deviceRate("AirPods Max", rate: 48000)
        )
    }

    func testAirPodsAt44100IsNotOk() {
        let devices = [makeDevice(name: "AirPods Max", rate: 44100)]
        let checklist = makeChecklist(devices: devices)
        XCTAssertFalse(checklist.airPodsRateOk)
        XCTAssertEqual(
            checklist.airPodsRateDetail,
            AppStrings.deviceRate("AirPods Max", rate: 44100)
        )
    }

    func testAirPodsAbsent() {
        let checklist = makeChecklist(devices: [])
        XCTAssertFalse(checklist.airPodsRateOk)
        XCTAssertEqual(checklist.airPodsRateDetail, AppStrings.connectAirPods)
    }
}

final class FirstRunChecklistSetupTests: XCTestCase {
    func testSetupCompleteOnlyWhenAllThreeAreOk() {
        let complete = makeChecklist(
            driverStatus: .ready,
            halNominalRate: 44100,
            devices: [makeDevice(name: "AirPods Max", rate: 48000)]
        )
        XCTAssertTrue(complete.setupComplete)

        let badDriver = makeChecklist(
            driverStatus: .notInstalled,
            halNominalRate: 44100,
            devices: [makeDevice(name: "AirPods Max", rate: 48000)]
        )
        XCTAssertFalse(badDriver.setupComplete)

        let badHal = makeChecklist(
            driverStatus: .ready,
            halNominalRate: 48000,
            devices: [makeDevice(name: "AirPods Max", rate: 48000)]
        )
        XCTAssertFalse(badHal.setupComplete)

        let badAirPods = makeChecklist(
            driverStatus: .ready,
            halNominalRate: 44100,
            devices: [makeDevice(name: "AirPods Max", rate: 44100)]
        )
        XCTAssertFalse(badAirPods.setupComplete)
    }
}
