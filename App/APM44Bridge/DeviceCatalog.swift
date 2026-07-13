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
        outputFormatBits: Int = 0
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
    }

    var id: String { uid }

    var sortRank: Int {
        let lower = name.lowercased()
        if lower.contains("airpods") { return 0 }
        if lower.contains("usb") { return 1 }
        return 2
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
                    outputFormatBits: outputFormatBits
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
        if let airpods = devices.first(where: {
            $0.name.localizedCaseInsensitiveContains("AirPods")
        }) {
            return airpods
        }
        return devices.first
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
