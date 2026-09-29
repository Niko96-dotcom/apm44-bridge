import XCTest
@testable import APM44Bridge

@MainActor
final class BridgeSettingsPersistenceTests: XCTestCase {
    private let presetKey = "apm44.latencyPreset"
    private let qualityKey = "apm44.srcQualityOverride"
    private var suiteNames: [String] = []

    override func tearDown() {
        for name in suiteNames {
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        }
        suiteNames.removeAll()
        super.tearDown()
    }

    private func makeSuite() throws -> UserDefaults {
        let name = "apm44.settings-persistence.\(UUID().uuidString)"
        suiteNames.append(name)
        return try XCTUnwrap(UserDefaults(suiteName: name))
    }

    func testEveryLatencyPresetIsStoredAndReloaded() throws {
        for preset in LatencyPreset.allCases {
            let suite = try makeSuite()
            let settings = BridgeSettings(defaults: suite)

            settings.latencyPreset = preset

            XCTAssertEqual(suite.string(forKey: presetKey), preset.rawValue, "\(preset)")
            let reloaded = BridgeSettings(defaults: suite)
            XCTAssertEqual(reloaded.latencyPreset, preset, "\(preset)")
            XCTAssertNil(reloaded.srcQualityOverride, "\(preset)")
            XCTAssertEqual(reloaded.effectiveSrcQuality, preset.defaultSrcQuality, "\(preset)")
        }
    }

    func testEveryExplicitQualityOverrideIsStoredAndReloaded() throws {
        for preset in LatencyPreset.allCases {
            for quality in SrcQuality.allCases {
                let suite = try makeSuite()
                let settings = BridgeSettings(defaults: suite)
                settings.latencyPreset = preset

                settings.srcQualityOverride = quality

                XCTAssertEqual(suite.string(forKey: qualityKey), quality.rawValue, "\(preset)/\(quality)")
                let reloaded = BridgeSettings(defaults: suite)
                XCTAssertEqual(reloaded.latencyPreset, preset, "\(preset)/\(quality)")
                XCTAssertEqual(reloaded.srcQualityOverride, quality, "\(preset)/\(quality)")
                XCTAssertEqual(reloaded.effectiveSrcQuality, quality, "\(preset)/\(quality)")
            }
        }
    }

    func testClearingTheOverrideRemovesTheKeyAndRestoresThePresetQuality() throws {
        for preset in LatencyPreset.allCases {
            let suite = try makeSuite()
            let settings = BridgeSettings(defaults: suite)
            settings.latencyPreset = preset
            // Pick a quality that differs from the preset's own, so restoring is observable.
            let override = SrcQuality.allCases.first { $0 != preset.defaultSrcQuality }!
            settings.srcQualityOverride = override
            XCTAssertEqual(suite.string(forKey: qualityKey), override.rawValue, "\(preset)")

            settings.srcQualityOverride = nil

            XCTAssertNil(suite.object(forKey: qualityKey), "\(preset)")
            XCTAssertEqual(settings.effectiveSrcQuality, preset.defaultSrcQuality, "\(preset)")
            let reloaded = BridgeSettings(defaults: suite)
            XCTAssertNil(reloaded.srcQualityOverride, "\(preset)")
            XCTAssertEqual(reloaded.effectiveSrcQuality, preset.defaultSrcQuality, "\(preset)")
        }
    }

    func testFreshSuiteUsesTheDocumentedDefaults() throws {
        let suite = try makeSuite()

        let settings = BridgeSettings(defaults: suite)

        XCTAssertEqual(settings.latencyPreset, .safe)
        XCTAssertNil(settings.srcQualityOverride)
        XCTAssertEqual(settings.effectiveSrcQuality, .best)
        XCTAssertNil(suite.object(forKey: presetKey))
        XCTAssertNil(suite.object(forKey: qualityKey))
    }

    func testInvalidStoredPresetFallsBackToSafeAndQualityToThePreset() throws {
        for invalid in ["", "ultra", "SAFE", "Balanced"] {
            let suite = try makeSuite()
            suite.set(invalid, forKey: presetKey)
            suite.set(invalid, forKey: qualityKey)

            let settings = BridgeSettings(defaults: suite)

            XCTAssertEqual(settings.latencyPreset, .safe, "preset \(invalid.debugDescription)")
            XCTAssertNil(settings.srcQualityOverride, "quality \(invalid.debugDescription)")
            XCTAssertEqual(settings.effectiveSrcQuality, .best, invalid.debugDescription)
        }
    }

    func testNonStringStoredValuesFallBackToDefaults() throws {
        let suite = try makeSuite()
        suite.set(3, forKey: presetKey)
        suite.set(true, forKey: qualityKey)

        let settings = BridgeSettings(defaults: suite)

        XCTAssertEqual(settings.latencyPreset, .safe)
        XCTAssertNil(settings.srcQualityOverride)
    }

    func testInvalidQualityDoesNotDisturbAValidStoredPreset() throws {
        let suite = try makeSuite()
        suite.set(LatencyPreset.low.rawValue, forKey: presetKey)
        suite.set("lossless", forKey: qualityKey)

        let settings = BridgeSettings(defaults: suite)

        XCTAssertEqual(settings.latencyPreset, .low)
        XCTAssertNil(settings.srcQualityOverride)
        XCTAssertEqual(settings.effectiveSrcQuality, LatencyPreset.low.defaultSrcQuality)
    }
}
