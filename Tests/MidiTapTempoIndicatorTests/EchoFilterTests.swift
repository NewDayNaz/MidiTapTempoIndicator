import XCTest
@testable import MidiTapTempoIndicator

final class EchoFilterTests: XCTestCase {
    func testIgnoresMatchingRecentSend() {
        let filter = EchoFilter()
        filter.window = 0.05
        let now = Date()
        filter.recordSend(channel: 0, controller: 46, value: 127, at: now)
        XCTAssertTrue(filter.shouldIgnore(channel: 0, controller: 46, value: 127, at: now.addingTimeInterval(0.01)))
    }

    func testDoesNotIgnoreAfterWindow() {
        let filter = EchoFilter()
        filter.window = 0.05
        let now = Date()
        filter.recordSend(channel: 0, controller: 46, value: 127, at: now)
        XCTAssertFalse(filter.shouldIgnore(channel: 0, controller: 46, value: 127, at: now.addingTimeInterval(0.1)))
    }

    func testDifferentValueIsNotIgnored() {
        let filter = EchoFilter()
        filter.recordSend(channel: 0, controller: 46, value: 127)
        XCTAssertFalse(filter.shouldIgnore(channel: 0, controller: 46, value: 0))
    }
}
