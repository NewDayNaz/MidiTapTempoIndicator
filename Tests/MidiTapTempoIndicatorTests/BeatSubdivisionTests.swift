import XCTest
@testable import MidiTapTempoIndicator

final class BeatSubdivisionTests: XCTestCase {
    func testQuarterIntervalIsHalfBeat() {
        let interval = BeatSubdivision.quarter.timerInterval(bpm: 120)
        XCTAssertEqual(interval, 0.25, accuracy: 0.0001)
    }

    func testEighthIntervalIsQuarterBeat() {
        let interval = BeatSubdivision.eighth.timerInterval(bpm: 120)
        XCTAssertEqual(interval, 0.125, accuracy: 0.0001)
    }

    func testDownbeatIntervalIsOneBeat() {
        let interval = BeatSubdivision.downbeat.timerInterval(bpm: 120)
        XCTAssertEqual(interval, 0.5, accuracy: 0.0001)
    }
}
