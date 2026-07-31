import Foundation

struct TapTempoEngine {
    var minBPM: Double
    var maxBPM: Double
    var maxIntervalCount: Int

    private(set) var timestamps: [Date] = []
    private(set) var currentBPM: Double?

    init(
        minBPM: Double = SettingsStore.defaultMinBPM,
        maxBPM: Double = SettingsStore.defaultMaxBPM,
        maxIntervalCount: Int = 8
    ) {
        self.minBPM = minBPM
        self.maxBPM = maxBPM
        self.maxIntervalCount = max(1, maxIntervalCount)
    }

    /// Maximum gap between taps before history is discarded (based on minimum BPM).
    var historyTimeout: TimeInterval {
        (60.0 / max(minBPM, 1)) * 1.5
    }

    @discardableResult
    mutating func registerTap(at date: Date = Date()) -> Double? {
        if let last = timestamps.last, date.timeIntervalSince(last) > historyTimeout {
            timestamps = [date]
            return currentBPM
        }

        timestamps.append(date)

        let maxTimestamps = maxIntervalCount + 1
        if timestamps.count > maxTimestamps {
            timestamps.removeFirst(timestamps.count - maxTimestamps)
        }

        guard timestamps.count >= 2 else {
            return currentBPM
        }

        let intervals = zip(timestamps.dropFirst(), timestamps).map { later, earlier in
            later.timeIntervalSince(earlier)
        }
        .filter { $0 > 0 }

        guard !intervals.isEmpty else { return currentBPM }

        let averageInterval = intervals.reduce(0, +) / Double(intervals.count)
        let rawBPM = 60.0 / averageInterval
        let clamped = min(maxBPM, max(minBPM, rawBPM))
        currentBPM = clamped
        return clamped
    }

    mutating func reset() {
        timestamps = []
        currentBPM = nil
    }

    mutating func updateLimits(minBPM: Double, maxBPM: Double) {
        self.minBPM = minBPM
        self.maxBPM = maxBPM
        if let currentBPM {
            self.currentBPM = min(maxBPM, max(minBPM, currentBPM))
        }
    }
}
