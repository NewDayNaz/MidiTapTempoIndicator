import XCTest
@testable import MidiTapTempoIndicator

final class SettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        suiteName = "MidiTapTempoIndicatorTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
    }

    func testDefaultTapMapping() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.tapInput.note, MIDIMapping.default.note)
        XCTAssertEqual(store.ledOutputs.count, 1)
        XCTAssertTrue(store.blinkEnabled)
        XCTAssertEqual(store.controllerIdleTimeout, SettingsStore.defaultControllerIdleTimeout)
        XCTAssertEqual(store.beatSubdivision, .quarter)
    }

    func testMigratesLegacyTapMapping() {
        let legacy = MIDIMapping(kind: .controlChange, note: 41, velocity: 127, channel: 0)
        defaults.set(try! JSONEncoder().encode(legacy), forKey: "tapMapping")
        defaults.set(2, forKey: "midiChannel")

        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.tapInput.note, 41)
        XCTAssertEqual(store.tapInput.channel, 2)
        XCTAssertEqual(store.ledOutputs.count, 1)
        XCTAssertEqual(store.ledOutputs[0].note, 41)
    }

    func testPersistsTapInputAndLEDOutputs() {
        let store = SettingsStore(defaults: defaults)
        store.tapInput = MIDIMapping(kind: .controlChange, note: 41, velocity: 127, channel: 3)
        store.addLEDOutput()
        XCTAssertEqual(store.ledOutputs.count, 2)

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.tapInput.note, 41)
        XCTAssertEqual(reloaded.tapInput.channel, 3)
        XCTAssertEqual(reloaded.ledOutputs.count, 2)
    }

    func testClampsControllerIdleTimeout() {
        defaults.set(999.0, forKey: "controllerIdleTimeout")
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.controllerIdleTimeout, SettingsStore.controllerIdleTimeoutRange.upperBound)
    }

    func testControllerIdleTimeoutSecondsConversion() {
        let store = SettingsStore(defaults: defaults)
        store.controllerIdleTimeout = 5
        XCTAssertEqual(store.controllerIdleTimeoutSeconds, 300, accuracy: 0.001)
    }

    func testExportImportRoundTrip() throws {
        let store = SettingsStore(defaults: defaults)
        store.lastBPM = 118
        store.beatSubdivision = .eighth
        store.tapInput = MIDIMapping(kind: .controlChange, note: 50, velocity: 100, channel: 1)

        let data = try store.exportSettingsData()

        let otherSuiteName = "MidiTapTempoIndicatorTests.import.\(UUID().uuidString)"
        let otherDefaults = UserDefaults(suiteName: otherSuiteName)!
        let other = SettingsStore(defaults: otherDefaults)
        try other.importSettingsData(data)

        XCTAssertEqual(other.lastBPM, 118)
        XCTAssertEqual(other.beatSubdivision, .eighth)
        XCTAssertEqual(other.tapInput.note, 50)
        XCTAssertEqual(other.tapInput.channel, 1)
        otherDefaults.removePersistentDomain(forName: otherSuiteName)
    }

    func testUseSameDeviceMatchesByName() {
        let store = SettingsStore(defaults: defaults)
        store.selectedSourceUniqueID = 1
        let sources = [MIDIEndpointInfo(uniqueID: 1, name: "Controller")]
        let destinations = [MIDIEndpointInfo(uniqueID: 99, name: "Controller")]
        store.useSameDeviceForInputAndOutput(sources: sources, destinations: destinations)
        XCTAssertEqual(store.selectedDestinationUniqueID, 99)
    }

    func testPersistsMultipleTempoResets() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertTrue(store.tempoResets.isEmpty)
        store.addTempoReset()
        store.addTempoReset()
        store.updateTempoReset(MIDIMapping(id: store.tempoResets[0].id, kind: .controlChange, note: 58, velocity: 127, channel: 0))
        store.updateTempoReset(MIDIMapping(id: store.tempoResets[1].id, kind: .controlChange, note: 59, velocity: 127, channel: 0))

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.tempoResets.count, 2)
        XCTAssertEqual(reloaded.tempoResets.map(\.note), [58, 59])
    }

    func testImportSettingsWithoutTempoResetsDefaultsEmpty() throws {
        let legacyJSON = """
        {
          "tapInput": {"id":"00000000-0000-4000-8000-000000000046","kind":"controlChange","note":46,"velocity":127,"channel":0},
          "ledOutputs": [{"id":"00000000-0000-4000-8000-000000000046","kind":"controlChange","note":46,"velocity":127,"channel":0}],
          "blinkEnabled": true,
          "minBPM": 40,
          "maxBPM": 240,
          "controllerIdleTimeout": 5,
          "ledOnValue": 127,
          "ledOffValue": 0,
          "beatSubdivision": "quarter"
        }
        """.data(using: .utf8)!

        let store = SettingsStore(defaults: defaults)
        store.addTempoReset()
        try store.importSettingsData(legacyJSON)
        XCTAssertTrue(store.tempoResets.isEmpty)
    }
}

final class MIDIMappingTests: XCTestCase {
    func testMatchesPressRequiresChannel() {
        let mapping = MIDIMapping(kind: .controlChange, note: 46, velocity: 127, channel: 1)
        XCTAssertTrue(mapping.matchesPress(kind: .controlChange, number: 46, value: 127, channel: 1))
        XCTAssertFalse(mapping.matchesPress(kind: .controlChange, number: 46, value: 127, channel: 0))
        XCTAssertFalse(mapping.matchesPress(kind: .controlChange, number: 46, value: 0, channel: 1))
    }
}

final class TempoStateTests: XCTestCase {
    func testNudgeClampsToRange() {
        let state = TempoState()
        state.currentBPM = 240
        state.adjustBPM(by: 5, minBPM: 40, maxBPM: 240)
        XCTAssertEqual(state.currentBPM, 240)
        state.adjustBPM(by: -1, minBPM: 40, maxBPM: 240)
        XCTAssertEqual(state.currentBPM, 239)
    }
}

final class ControllerActivityMonitorTests: XCTestCase {
    func testAnyActivityKeepsActiveWithinTimeout() {
        let monitor = ControllerActivityMonitor(timeout: 2)
        XCTAssertFalse(monitor.isActive())
        monitor.noteActivity(at: Date())
        XCTAssertTrue(monitor.isActive())
    }

    func testBecomesInactiveAfterTimeout() {
        let monitor = ControllerActivityMonitor(timeout: 0.2)
        let past = Date().addingTimeInterval(-1)
        monitor.noteActivity(at: past)
        XCTAssertFalse(monitor.isActive(at: Date()))
    }
}
