import Foundation

enum MIDIMessageKind: String, Codable, CaseIterable {
    case noteOn
    case controlChange
}

struct MIDIMapping: Codable, Equatable, Identifiable {
    var id: UUID
    var kind: MIDIMessageKind
    var note: UInt8
    var velocity: UInt8
    var channel: UInt8

    /// Default tap mapping (CC 46, channel 1 / zero-based 0).
    static let `default` = MIDIMapping(
        id: UUID(uuidString: "00000000-0000-4000-8000-000000000046")!,
        kind: .controlChange,
        note: 46,
        velocity: 127,
        channel: 0
    )

    init(
        id: UUID = UUID(),
        kind: MIDIMessageKind,
        note: UInt8,
        velocity: UInt8,
        channel: UInt8 = 0
    ) {
        self.id = id
        self.kind = kind
        self.note = note
        self.velocity = velocity
        self.channel = min(15, channel)
    }

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

    var summaryLabel: String {
        "\(noteLabel) ch\(Int(channel) + 1)"
    }

    /// True when this message is a press for the mapped control (ignores releases / zero).
    func matchesPress(kind messageKind: MIDIMessageKind, number: UInt8, value: UInt8, channel: UInt8) -> Bool {
        guard self.kind == messageKind, note == number, self.channel == channel, value > 0 else { return false }
        return true
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, note, velocity, channel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try container.decode(MIDIMessageKind.self, forKey: .kind)
        note = try container.decode(UInt8.self, forKey: .note)
        velocity = try container.decode(UInt8.self, forKey: .velocity)
        channel = try container.decodeIfPresent(UInt8.self, forKey: .channel) ?? 0
    }
}

struct MIDIEndpointInfo: Identifiable, Hashable {
    let uniqueID: Int32
    let name: String

    var id: Int32 { uniqueID }
}

enum LearnTarget: Equatable {
    case tapInput
    case ledOutput(UUID)
}
