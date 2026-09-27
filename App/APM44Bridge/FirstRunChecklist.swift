import Foundation

/// Action rendered under the driver checklist row. Side effects
/// (reload/finish) stay in the view.
enum FirstRunDriverAction: Equatable {
    case none
    case downloadInstaller
    case reloadDriver
}

/// Pure, synchronous checklist model for `FirstRunPreflightView`.
///
/// Built from raw values (never live Core Audio calls) so it is
/// unit-testable. The view builds one from its `@State` plus live
/// `HalDriverDetector` calls and renders it.
struct FirstRunChecklist {
    let driverStatus: DriverStatus
    let didAttemptReload: Bool
    let halNominalRate: Double?
    let devices: [AudioDeviceRow]
    let appBuildID: String?
    let driverBuildID: String?


    var driverReady: Bool {
        driverStatus == .ready
    }

    var driverDetail: String {
        switch driverStatus {
        case .ready:
            return AppStrings.driverReadyDetail
        case .buildMismatch:
            return buildMismatchDetail
        case .installedNotLoaded:
            return didAttemptReload ? AppStrings.driverRestartHint : AppStrings.driverReloadHint
        case .notInstalled:
            return AppStrings.driverMissingDetail
        }
    }

    var driverAction: FirstRunDriverAction {
        switch driverStatus {
        case .ready:
            return .none
        case .buildMismatch:
            return .downloadInstaller
        case .installedNotLoaded:
            return .reloadDriver
        case .notInstalled:
            return .downloadInstaller
        }
    }

    private var buildMismatchDetail: String {
        let appID = HalDriverDetector.normalizedBuildID(appBuildID)
            ?? AppStrings.buildIDMissingPlaceholder
        let driverID = HalDriverDetector.normalizedBuildID(driverBuildID)
            ?? AppStrings.buildIDMissingPlaceholder
        return AppStrings.driverBuildMismatchDetail(app: appID, driver: driverID)
    }

    var halRateOk: Bool {
        guard let rate = halNominalRate else { return false }
        return abs(rate - 44100) < 1
    }

    var halRateDetail: String {
        if let rate = halNominalRate {
            if abs(rate - 44100) < 1 {
                return ""
            }
            return AppStrings.nominalRateHint(Int(rate))
        }
        return AppStrings.driverNotDetected
    }

    private var airPodsRow: AudioDeviceRow? {
        devices.first { $0.name.localizedCaseInsensitiveContains("AirPods") }
    }

    var airPodsRateOk: Bool {
        guard let row = airPodsRow else { return false }
        return abs(row.nominalRate - 48000) < 1
    }

    var airPodsRateDetail: String {
        if let row = airPodsRow {
            return AppStrings.deviceRate(row.name, rate: Int(row.nominalRate))
        }
        return AppStrings.connectAirPods
    }

    var setupComplete: Bool {
        driverStatus == .ready && halRateOk && airPodsRateOk
    }
}
