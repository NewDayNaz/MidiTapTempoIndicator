import XCTest
@testable import MidiTapTempoIndicator

final class MIDIMonitorTests: XCTestCase {
    func testKeepsNewestEntriesWithinCapacity() {
        let monitor = MIDIMonitor(capacity: 3)
        monitor.append(kind: .inbound, summary: "one")
        monitor.append(kind: .inbound, summary: "two")
        monitor.append(kind: .inbound, summary: "three")
        monitor.append(kind: .inbound, summary: "four")

        XCTAssertEqual(monitor.entries.count, 3)
        XCTAssertEqual(monitor.entries.map(\.summary), ["four", "three", "two"])
    }

    func testClearRemovesEntries() {
        let monitor = MIDIMonitor(capacity: 10)
        monitor.append(kind: .tap, summary: "tap")
        monitor.clear()
        XCTAssertTrue(monitor.entries.isEmpty)
    }
}
