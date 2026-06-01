import Foundation

enum BridgeBinaryLocator {
    static func resolve() -> URL? {
        if let env = ProcessInfo.processInfo.environment["APM44_BRIDGE_PATH"],
           !env.isEmpty {
            let url = URL(fileURLWithPath: env)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }

        if let bundled = Bundle.main.url(forAuxiliaryExecutable: "apm44-bridge"),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }

        let macOSBinary = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/apm44-bridge")
        if FileManager.default.isExecutableFile(atPath: macOSBinary.path) {
            return macOSBinary
        }

        if let devRoot = devRepoRoot() {
            let url = devRoot
                .appendingPathComponent("build/BridgeDaemon/apm44-bridge")
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }

        return nil
    }

    private static func devRepoRoot() -> URL? {
        if let root = ProcessInfo.processInfo.environment["APM44_DEV_REPO_ROOT"],
           !root.isEmpty {
            return URL(fileURLWithPath: root)
        }
        #if DEBUG
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 {
            url.deleteLastPathComponent()
        }
        let candidate = url.appendingPathComponent("build/BridgeDaemon/apm44-bridge")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return url
        }
        #endif
        return nil
    }
}
