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
        XCTAssertEqual(store.tapMapping, .default)
        XCTAssertTrue(store.blinkEnabled)
        XCTAssertEqual(store.controllerIdleTimeout, SettingsStore.defaultControllerIdleTimeout)
    }

    func testPersistsTapMapping() {
        let store = SettingsStore(defaults: defaults)
        store.tapMapping = MIDIMapping(kind: .controlChange, note: 41, velocity: 127)

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.tapMapping.kind, .controlChange)
        XCTAssertEqual(reloaded.tapMapping.note, 41)
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

    func testClampsBPMRangeOnLoad() {
        defaults.set(10.0, forKey: "minBPM")
        defaults.set(400.0, forKey: "maxBPM")
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.minBPM, SettingsStore.bpmRange.lowerBound)
        XCTAssertEqual(store.maxBPM, SettingsStore.bpmRange.upperBound)
    }
}

final class MIDIMappingTests: XCTestCase {
    func testMatchesPressIgnoresZero() {
        let mapping = MIDIMapping(kind: .controlChange, note: 46, velocity: 127)
        XCTAssertTrue(mapping.matchesPress(kind: .controlChange, number: 46, value: 127))
        XCTAssertTrue(mapping.matchesPress(kind: .controlChange, number: 46, value: 1))
        XCTAssertFalse(mapping.matchesPress(kind: .controlChange, number: 46, value: 0))
        XCTAssertFalse(mapping.matchesPress(kind: .controlChange, number: 45, value: 127))
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
