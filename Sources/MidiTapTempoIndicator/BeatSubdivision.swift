import Foundation

enum BeatSubdivision: String, Codable, CaseIterable, Identifiable {
    case quarter
    case eighth
    case downbeat

    var id: String { rawValue }

    var label: String {
        switch self {
        case .quarter: return "Quarter"
        case .eighth: return "Eighth"
        case .downbeat: return "Downbeat only"
        }
    }

    var detail: String {
        switch self {
        case .quarter: return "Flash once per beat"
        case .eighth: return "Flash twice per beat"
        case .downbeat: return "Short pulse every 4 beats (4/4)"
        }
    }

    /// Timer interval between LED state changes for the given BPM.
    func timerInterval(bpm: Double) -> TimeInterval {
        let beat = 60.0 / max(bpm, 1)
        switch self {
        case .quarter:
            return beat / 2.0
        case .eighth:
            return beat / 4.0
        case .downbeat:
            return beat
        }
    }
}
