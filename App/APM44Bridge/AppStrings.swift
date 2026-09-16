import Foundation

enum AppStrings {
    static var startBridge: String { t("start_bridge", "Start Bridge") }
    static var stopBridge: String { t("stop_bridge", "Stop Bridge") }
    static var restart: String { t("restart", "Restart") }
    static var quitApp: String { t("quit_app", "Quit APM44 Bridge") }
    static var output: String { t("output", "Output") }
    static var buffering: String { t("buffering", "Buffering") }
    static var quality: String { t("quality", "Quality") }
    static var chooseOutput: String { t("choose_output", "Choose output…") }
    static var noOutputDevices: String { t("no_output_devices", "No output devices") }
    static var noOutputDevicesHint: String {
        t("no_output_devices_hint", "Connect headphones or an audio interface")
    }
    static var unavailableSuffix: String { t("unavailable_suffix", "Unavailable") }
    static var unsupportedPrefix: String { t("unsupported_prefix", "Unsupported") }
    static var openAtLogin: String { t("open_at_login", "Open at login") }
    static var cubaseSetupGuide: String { t("cubase_setup_guide", "Cubase setup guide") }
    static var setup: String { t("setup", "Setup") }
    static var setupTitle: String { t("setup_title", "APM44 Bridge setup") }
    static var skipSetup: String { t("skip_setup", "Skip Setup") }
    static var done: String { t("done", "Done") }
    static var details: String { t("details", "Details") }
    static var bufferFill: String { t("buffer_fill", "Buffer fill") }
    static var knownLostFrames: String { t("known_lost_frames", "Known lost frames") }
    static var recoveries: String { t("recoveries", "Recoveries") }
    static var halDrops: String { t("hal_drops", "Driver drops") }
    static var outputStarved: String { t("output_starved", "Output starved") }
    static var partialShortages: String { t("partial_shortages", "Partial shortages") }
    static var rebuffersSrcResets: String { t("rebuffers_src_resets", "Rebuffers / converter resets") }
    static var driftRatio: String { t("drift_ratio", "Drift ratio") }
    static var metricsStale: String { t("metrics_stale", "Metrics stale") }
    static var outputNotSelected: String { t("output_not_selected", "Not selected") }
    static var selectedOutput: String { t("selected_output", "selected output") }
    static var chooseOutputToStart: String { t("choose_output_to_start", "Choose an output to start.") }
    static var bridgeNotFound: String {
        t("bridge_not_found", "Bridge not found — build or install apm44-bridge")
    }
    static var couldNotListDevices: String { t("could_not_list_devices", "Could not list audio devices") }
    static var previousOutputSelect: String {
        t("previous_output_select", "Previous output unavailable — select a device")
    }
    static var selectOutputDevice: String { t("select_output_device", "Select an output device") }
    static var selectedOutputGone: String {
        t("selected_output_gone", "Selected output is no longer available")
    }
    static var bridgeDidNotStop: String { t("bridge_did_not_stop", "Bridge did not stop") }
    static var waitingForDevicesAfterWake: String {
        t("waiting_for_devices_after_wake", "Waiting for audio devices after wake…")
    }
    static var outputDisconnectedSelect: String {
        t("output_disconnected_select", "Output disconnected — select a device")
    }
    static var outputDeviceDisconnected: String {
        t("output_device_disconnected", "Output device disconnected")
    }
    static var couldNotStart: String { t("could_not_start", "Bridge could not start.") }
    static var noDiagnostic: String { t("no_diagnostic", "no diagnostic available") }
    static var loginItemsApproval: String {
        t("login_items_approval", "Approval required in Login Items")
    }
    static var openSettings: String { t("open_settings", "Open Settings") }
    static var couldNotUpdateOpenAtLogin: String {
        t("could_not_update_open_at_login", "Could not update Open at login")
    }
    static var checkingUpdates: String { t("checking_updates", "Checking for updates…") }
    static var updateCancelled: String { t("update_cancelled", "Update cancelled.") }
    static var cubaseControlRoom: String { t("cubase_control_room", "Cubase Control Room") }
    static var cubaseControlRoomHint: String {
        t(
            "cubase_control_room_hint",
            "Assign Monitor 1 device ports to APM44 Bridge left and right"
        )
    }
    static var downloadInstaller: String { t("download_installer", "Download the installer") }
    static var reloadAudioDriver: String { t("reload_audio_driver", "Reload audio driver") }
    static var enterAdminPassword: String {
        t("enter_admin_password", "Requires an admin password")
    }
    static var halDriver: String { t("hal_driver", "Audio driver") }
    static var halRateTitle: String { t("hal_rate_title", "APM44 Bridge @ 44.1 kHz") }
    static var airPodsRateTitle: String { t("airpods_rate_title", "AirPods USB @ 48 kHz") }
    static var driverReadyDetail: String {
        t("driver_ready_detail", "APM44 Bridge visible in Audio MIDI Setup")
    }
    static var driverReloadHint: String {
        t("driver_reload_hint", "Installed, not loaded")
    }
    static var driverRestartHint: String {
        t("driver_restart_hint", "Restart the Mac once if it is still missing")
    }
    static var driverMissingDetail: String {
        t("driver_missing_detail", "Not installed")
    }
    static var driverNotDetected: String { t("driver_not_detected", "Driver not detected") }
    static var connectAirPods: String {
        t("connect_airpods", "Connect AirPods Max with USB-C cable")
    }
    static var bridgeStatus: String { t("bridge_status", "Bridge status") }
    static var signalPath: String { t("signal_path", "Signal path") }
    static var stopped: String { t("stopped", "Stopped") }
    static var starting: String { t("starting", "Starting…") }
    static var stopping: String { t("stopping", "Stopping…") }
    static var reconnecting: String { t("reconnecting", "Reconnecting…") }
    static var waitingForDAW: String { t("waiting_for_daw", "Waiting for DAW") }
    static var connected: String { t("connected", "Connected") }
    static var running: String { t("running", "Running") }
    static var low: String { t("preset_low", "Low") }
    static var balanced: String { t("preset_balanced", "Balanced") }
    static var safe: String { t("preset_safe", "Safe") }
    static var qualityStandard: String { t("quality_standard", "Standard") }
    static var qualityHigh: String { t("quality_high", "High") }
    static var qualityBest: String { t("quality_best", "Best (higher CPU)") }
    static var helpMenuSetup: String { t("help_menu_setup", "APM44 Bridge Setup") }
    static var settingsMenu: String { t("settings_menu", "APM44 Bridge Settings…") }
    static var milliseconds: String { t("milliseconds", "milliseconds") }
    static var errorStatus: String { t("error_status", "Error") }
    static var rateSupported48: String { t("48 kHz supported", "48 kHz supported") }
    static var rateUnsupported48: String { t("48 kHz unsupported", "48 kHz unsupported") }
    static var bufferUnknown: String { t("buffer unknown", "buffer unknown") }

    static var noUpdateAvailable: String { t("no_update_available", "No update is available.") }
    static var updateFeedUnverified: String {
        t(
            "update_feed_unverified",
            "Update check blocked: the signed update feed could not be verified."
        )
    }
    static var updateCancelledBeforeReplace: String {
        t(
            "update_cancelled_before_replace",
            "Update installation was cancelled before APM44 Bridge could be replaced."
        )
    }
    static var updateCheckFailedRetry: String {
        t("update_check_failed_retry", "Update check failed. Try again later.")
    }

    static func updateCheckFailed(detail: String) -> String {
        format("update_check_failed %@", "Update check failed: %@", detail)
    }

    static func previousOutputUnavailable(name: String) -> String {
        format(
            "previous_output_unavailable %@",
            "Previous output %@ is unavailable — choose another device",
            name
        )
    }

    static func selectedOutputIncompatible(issue: String) -> String {
        format("selected_output_incompatible %@", "Selected output is not compatible: %@", issue)
    }

    static func namedIssue(_ name: String, issue: String) -> String {
        format("named_issue %@ %@", "%@: %@", name, issue)
    }

    static func bridgeCouldNotStart(detail: String) -> String {
        format("bridge_could_not_start %@", "Bridge could not start: %@", detail)
    }

    static func reconnectingAttempt(current: Int, max: Int) -> String {
        format(
            "reconnecting_attempt %lld %lld",
            "Reconnecting… (attempt %lld of %lld)",
            Int64(current),
            Int64(max)
        )
    }

    static func waitingForOutput(_ name: String) -> String {
        format("waiting_for_output %@", "Output disconnected — waiting for %@…", name)
    }

    static func reconnectingTo(_ name: String) -> String {
        format("reconnecting_to %@", "Reconnecting to %@…", name)
    }

    static func outputUnavailableAfterWake(_ name: String) -> String {
        format("output_unavailable_after_wake %@", "Output unavailable after wake — waiting for %@…", name)
    }

    static func pathHal(output: String) -> String {
        format("path_hal %@", "DAW → APM44 Bridge @ 44.1 kHz → %@", output)
    }

    static func pathBlackHole(output: String) -> String {
        format("path_blackhole %@", "DAW → BlackHole @ 44.1 kHz → %@", output)
    }

    static func bufferTarget(_ ms: Int) -> String {
        format("buffer_target %lld", "~%lld ms", Int64(ms))
    }

    static func bufferTargetMinimum(_ ms: Int) -> String {
        format("buffer_target_minimum %lld", "~%lld ms (path minimum)", Int64(ms))
    }

    static var stoppedLatencyHint: String {
        t("stopped_latency_hint", "Device, DAW, and hardware latency are additional")
    }

    static func nominalRateHint(_ rate: Int) -> String {
        format("nominal_rate_hint %lld", "Nominal %lld Hz — set 44100 in Audio MIDI Setup", Int64(rate))
    }

    static func deviceRate(_ name: String, rate: Int) -> String {
        format("device_rate %@ %lld", "%@ @ %lld Hz", name, Int64(rate))
    }

    static func outputAt48k(_ name: String) -> String {
        format("output_at_48k %@", "%@ @ 48 kHz", name)
    }

    static func latencyBadge(_ ms: Int) -> String {
        format("latency_badge %lld", "~%lld ms", Int64(ms))
    }

    static func bridgeBuffering(_ ms: Int) -> String {
        format("bridge_buffering %lld", "~%lld ms bridge buffering", Int64(ms))
    }

    static func fillMilliseconds(_ value: String) -> String {
        format("fill_milliseconds %@", "%@ milliseconds", value)
    }

    static func updateAvailable(_ version: String) -> String {
        format("update_available %@", "Update available — APM44 Bridge %@", version)
    }

    static func updateReady(_ version: String) -> String {
        format(
            "update_ready %@",
            "APM44 Bridge %@ is ready to install — Sparkle will ask for administrator authorization.",
            version
        )
    }

    static func installingUpdate(_ version: String) -> String {
        format("installing_update %@", "Installing APM44 Bridge %@…", version)
    }

    static func frameBuffer(_ frames: Int) -> String {
        format("%lld-frame buffer", "%lld-frame buffer", Int64(frames))
    }

    static func deviceDetail(
        transport: String,
        rate: Int,
        rateSupport: String,
        channels: Int,
        buffer: String
    ) -> String {
        format(
            "device_detail %@ %lld %@ %lld %@",
            "%@ • %lld Hz current • %@ • %lld ch • %@",
            transport,
            Int64(rate),
            rateSupport,
            Int64(channels),
            buffer
        )
    }

    static func versionLabel(_ version: String) -> String {
        format("version_label %@", "APM44 Bridge %@", version)
    }

    static func menuBarStatus(status: String, device: String) -> String {
        format("menu_bar_status %@ %@", "APM44 Bridge %@, output %@", status, device)
    }

    static func lastExit(_ status: Int) -> String {
        format("last_exit %lld", " (last exit %lld)", Int64(status))
    }

    static func stoppedAfterUnstableLaunches(_ max: Int, detail: String) -> String {
        format(
            "stopped_after_unstable %lld %@",
            "Bridge stopped after %lld unstable launches%@ — click Start to try again",
            Int64(max),
            detail
        )
    }

    static func ipcFailed() -> String {
        t(
            "ipc_failed",
            "APM44 driver IPC failed. Reinstall the matching driver and reload Core Audio."
        )
    }

    static func compatibility(_ english: String) -> String {
        t(english, english)
    }

    private static func t(_ key: String, _ defaultValue: String) -> String {
        NSLocalizedString(key, tableName: "Localizable", bundle: .main, value: defaultValue, comment: "")
    }

    private static func format(_ key: String, _ defaultValue: String, _ arguments: CVarArg...) -> String {
        let template = NSLocalizedString(
            key,
            tableName: "Localizable",
            bundle: .main,
            value: defaultValue,
            comment: ""
        )
        return String(format: template, locale: .current, arguments: arguments)
    }
}
