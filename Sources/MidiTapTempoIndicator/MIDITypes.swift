import Foundation

enum MIDIMessageKind: String, Codable, CaseIterable {
    case noteOn
    case controlChange
}

struct MIDIMapping: Codable, Equatable {
    var kind: MIDIMessageKind
    var note: UInt8
    var velocity: UInt8

    /// Default tap mapping (CC 46).
    static let `default` = MIDIMapping(kind: .controlChange, note: 46, velocity: 127)

    var noteLabel: String {
        switch kind {
        case .noteOn:
            let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
            let octave = Int(note) / 12 - 1
            let name = names[Int(note) % 12]
            return "\(name)\(octave)"
        case .controlChange:
            return "CC \(note)"
        }
    }

    /// True when this message is a press for the mapped control (ignores releases / zero).
    func matchesPress(kind messageKind: MIDIMessageKind, number: UInt8, value: UInt8) -> Bool {
        guard self.kind == messageKind, note == number, value > 0 else { return false }
        return true
    }
}

struct MIDIEndpointInfo: Identifiable, Hashable {
    let uniqueID: Int32
    let name: String

    var id: Int32 { uniqueID }
}
