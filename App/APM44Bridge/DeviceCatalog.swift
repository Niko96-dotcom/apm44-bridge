import Foundation

struct AudioDeviceRow: Identifiable, Equatable {
    let uid: String
    let name: String
    let nominalRate: Double
    let hasInput: Bool
    let hasOutput: Bool

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
            rows.append(
                AudioDeviceRow(
                    uid: String(parts[0]),
                    name: String(parts[1]),
                    nominalRate: rate,
                    hasInput: hasInput,
                    hasOutput: hasOutput
                )
            )
        }
        return rows.sorted {
            if $0.sortRank != $1.sortRank { return $0.sortRank < $1.sortRank }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
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
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "DeviceCatalog",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "apm44-bridge --list-devices failed"]
            )
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        return parseListDevicesOutput(text)
    }
}
