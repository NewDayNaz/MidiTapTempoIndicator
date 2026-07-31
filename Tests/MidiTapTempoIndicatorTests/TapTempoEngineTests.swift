import XCTest
@testable import MidiTapTempoIndicator

final class TapTempoEngineTests: XCTestCase {
    func testNeedsTwoTapsForBPM() {
        var engine = TapTempoEngine(minBPM: 40, maxBPM: 240)
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertNil(engine.registerTap(at: start))
        XCTAssertNil(engine.currentBPM)
    }

    func testCalculatesBPMFromInterval() {
        var engine = TapTempoEngine(minBPM: 40, maxBPM: 240)
        let start = Date(timeIntervalSince1970: 1_000)
        _ = engine.registerTap(at: start)
        // 500ms interval => 120 BPM
        let bpm = engine.registerTap(at: start.addingTimeInterval(0.5))
        XCTAssertEqual(bpm!, 120, accuracy: 0.01)
    }

    func testAveragesMultipleIntervals() {
        var engine = TapTempoEngine(minBPM: 40, maxBPM: 240)
        let start = Date(timeIntervalSince1970: 1_000)
        _ = engine.registerTap(at: start)
        _ = engine.registerTap(at: start.addingTimeInterval(0.5))
        let bpm = engine.registerTap(at: start.addingTimeInterval(1.0))
        XCTAssertEqual(bpm!, 120, accuracy: 0.01)
    }

    func testResetsHistoryAfterLongGap() {
        var engine = TapTempoEngine(minBPM: 40, maxBPM: 240)
        let start = Date(timeIntervalSince1970: 1_000)
        _ = engine.registerTap(at: start)
        _ = engine.registerTap(at: start.addingTimeInterval(0.5))
        XCTAssertEqual(engine.currentBPM!, 120, accuracy: 0.01)

        // Gap larger than historyTimeout should start a new measurement.
        let afterGap = start.addingTimeInterval(0.5 + engine.historyTimeout + 0.1)
        let bpm = engine.registerTap(at: afterGap)
        XCTAssertEqual(bpm!, 120, accuracy: 0.01)
        XCTAssertEqual(engine.timestamps.count, 1)
    }

    func testClampsToMaxBPM() {
        var engine = TapTempoEngine(minBPM: 40, maxBPM: 180)
        let start = Date(timeIntervalSince1970: 1_000)
        _ = engine.registerTap(at: start)
        // 200ms => 300 BPM raw, clamped to 180
        let bpm = engine.registerTap(at: start.addingTimeInterval(0.2))
        XCTAssertEqual(bpm!, 180, accuracy: 0.01)
    }

    func testClampsToMinBPM() {
        var engine = TapTempoEngine(minBPM: 60, maxBPM: 240)
        let start = Date(timeIntervalSince1970: 1_000)
        _ = engine.registerTap(at: start)
        // 1.2s => 50 BPM raw, still within history timeout, clamped to 60
        let bpm = engine.registerTap(at: start.addingTimeInterval(1.2))
        XCTAssertEqual(bpm!, 60, accuracy: 0.01)
    }
}
