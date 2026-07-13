import Foundation

struct AudioDeviceRow: Identifiable, Equatable {
    let uid: String
    let name: String
    let nominalRate: Double
    let hasInput: Bool
    let hasOutput: Bool
    let isAlive: Bool
    let outputChannels: Int
    let bufferFrameSize: Int
    let transportType: UInt32
    let outputFormatId: UInt32
    let outputFormatBits: Int
    let supports48000: Bool

    init(
        uid: String,
        name: String,
        nominalRate: Double,
        hasInput: Bool,
        hasOutput: Bool,
        isAlive: Bool = true,
        outputChannels: Int = 2,
        bufferFrameSize: Int = 0,
        transportType: UInt32 = 0,
        outputFormatId: UInt32 = 0,
        outputFormatBits: Int = 0,
        supports48000: Bool = true
    ) {
        self.uid = uid
        self.name = name
        self.nominalRate = nominalRate
        self.hasInput = hasInput
        self.hasOutput = hasOutput
        self.isAlive = isAlive
        self.outputChannels = outputChannels
        self.bufferFrameSize = bufferFrameSize
        self.transportType = transportType
        self.outputFormatId = outputFormatId
        self.outputFormatBits = outputFormatBits
        self.supports48000 = supports48000
    }

    var id: String { uid }

    var sortRank: Int {
        if !isMonitoringCompatible { return 100 }
        let lower = name.lowercased()
        if lower.contains("airpods") && isUSB { return 0 }
        if lower.contains("airpods") { return 1 }
        if isUSB { return 2 }
        if lower.contains("usb") { return 3 }
        return 4
    }

    var isUSB: Bool { transportType == 1_970_496_032 } // 'usb '

    var transportLabel: String {
        switch transportType {
        case 1_970_496_032: return "USB"       // 'usb '
        case 1_651_275_109: return "Bluetooth" // 'blue'
        case 1_651_271_009: return "Bluetooth LE" // 'blea'
        case 1_651_274_862: return "Built-in"  // 'bltn'
        case 1_751_412_073: return "HDMI"      // 'hdmi'
        case 1_685_090_932: return "DisplayPort" // 'dprt'
        case 1_986_622_068: return "Virtual"   // 'virt'
        case 0: return "Unknown transport"
        default: return fourCCTransport
        }
    }

    var compatibilityIssue: String? {
        if !isAlive { return "Disconnected" }
        if !hasOutput || outputChannels < 2 { return "Stereo output unavailable" }
        if !supports48000 { return "48 kHz is not supported" }
        if abs(nominalRate - 48_000) > 1 { return "Set the current rate to 48 kHz" }
        if outputFormatId != 0 && outputFormatId != 1_819_304_813 { // 'lpcm'
            return "Linear PCM output is required"
        }
        if outputFormatBits != 0 && outputFormatBits != 32 {
            return "32-bit float output is required"
        }
        return nil
    }

    var isMonitoringCompatible: Bool { compatibilityIssue == nil }

    var pickerLabel: String {
        if let issue = compatibilityIssue {
            return "\(name) — Unsupported: \(issue)"
        }
        return "\(name) — \(transportLabel)"
    }

    var detailLabel: String {
        let supportedRate = supports48000 ? "48 kHz supported" : "48 kHz unsupported"
        let buffer = bufferFrameSize > 0 ? "\(bufferFrameSize)-frame buffer" : "buffer unknown"
        return "\(transportLabel) • \(Int(nominalRate)) Hz current • \(supportedRate) • \(outputChannels) ch • \(buffer)"
    }

    private var fourCCTransport: String {
        let scalars = [24, 16, 8, 0].compactMap { shift -> UnicodeScalar? in
            let value = UInt8((transportType >> UInt32(shift)) & 0xff)
            guard value >= 0x20, value <= 0x7e else { return nil }
            return UnicodeScalar(value)
        }
        return scalars.count == 4 ? String(String.UnicodeScalarView(scalars)) : "Other"
    }
}

enum DeviceCatalog {
    static func parseListDevicesOutput(_ text: String) -> [AudioDeviceRow] {
        var rows: [AudioDeviceRow] = []
        let lines = text.split(whereSeparator: \.isNewline)
        for line in lines {
            let lineStr = String(line)
            if lineStr.hasPrefix("UID\t") { continue }
            let parts = lineStr.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count >= 4 else { continue }
            let io = String(parts[3])
            let hasInput = io.contains("I")
            let hasOutput = io.contains("O")
            guard hasOutput else { continue }
            let rate = Double(parts[2]) ?? 0
            let isAlive = parts.count > 4 ? parts[4] != "0" : true
            let outputChannels = parts.count > 5 ? Int(parts[5]) ?? 0 : 2
            let bufferFrameSize = parts.count > 6 ? Int(parts[6]) ?? 0 : 0
            let transportType = parts.count > 7 ? UInt32(parts[7]) ?? 0 : 0
            let outputFormatId = parts.count > 8 ? UInt32(parts[8]) ?? 0 : 0
            let outputFormatBits = parts.count > 9 ? Int(parts[9]) ?? 0 : 0
            let supports48000 = parts.count > 10 ? parts[10] != "0" : true
            rows.append(
                AudioDeviceRow(
                    uid: String(parts[0]),
                    name: String(parts[1]),
                    nominalRate: rate,
                    hasInput: hasInput,
                    hasOutput: hasOutput,
                    isAlive: isAlive,
                    outputChannels: outputChannels,
                    bufferFrameSize: bufferFrameSize,
                    transportType: transportType,
                    outputFormatId: outputFormatId,
                    outputFormatBits: outputFormatBits,
                    supports48000: supports48000
                )
            )
        }
        let sorted = rows.sorted {
            if $0.sortRank != $1.sortRank { return $0.sortRank < $1.sortRank }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return filterMonitoringOutputs(sorted)
    }

    static func filterMonitoringOutputs(_ devices: [AudioDeviceRow]) -> [AudioDeviceRow] {
        devices.filter { !isDeniedMonitoringDevice(uid: $0.uid, name: $0.name) }
    }

    static func isDeniedMonitoringDevice(uid: String, name: String) -> Bool {
        let lowerName = name.lowercased()
        let lowerUID = uid.lowercased()
        let nameDenylist = ["apm44 bridge", "blackhole", "loopback", "soundflower"]
        if nameDenylist.contains(where: { lowerName.contains($0) }) { return true }
        if lowerUID.contains("blackhole") || lowerUID.contains("apm44") || lowerUID.hasPrefix("bh-") {
            return true
        }
        return false
    }

    static func preferredDefault(from devices: [AudioDeviceRow]) -> AudioDeviceRow? {
        let compatible = devices.filter(\.isMonitoringCompatible)
        if let usbAirPods = compatible.first(where: {
            $0.isUSB && $0.name.localizedCaseInsensitiveContains("AirPods")
        }) { return usbAirPods }
        if let airPods = compatible.first(where: {
            $0.name.localizedCaseInsensitiveContains("AirPods")
        }) { return airPods }
        if let usb = compatible.first(where: \.isUSB) { return usb }
        return compatible.first
    }

    static func refresh(binaryURL: URL) throws -> [AudioDeviceRow] {
        let process = Process()
        process.executableURL = binaryURL
        process.arguments = ["--list-devices"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        // Drain stdout before waiting. A child that fills the ~64 KB pipe
        // buffer blocks on write until the reader consumes it, so reading
        // only after waitUntilExit() can deadlock on a large device list.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "DeviceCatalog",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "apm44-bridge --list-devices failed"]
            )
        }
        let text = String(data: data, encoding: .utf8) ?? ""
        return parseListDevicesOutput(text)
    }
}
