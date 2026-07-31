import Combine
import Foundation

final class TempoState: ObservableObject {
    @Published var currentBPM: Double?

    func setBPM(_ bpm: Double?, minBPM: Double, maxBPM: Double) {
        guard let bpm else {
            currentBPM = nil
            return
        }
        currentBPM = min(maxBPM, max(minBPM, bpm))
    }

    func adjustBPM(by delta: Double, minBPM: Double, maxBPM: Double) {
        let base = currentBPM ?? 120
        setBPM(base + delta, minBPM: minBPM, maxBPM: maxBPM)
    }
}
