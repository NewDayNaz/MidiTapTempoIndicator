import Foundation

struct MIDIMonitorEntry: Identifiable, Equatable {
    enum Kind: String, Equatable {
        case inbound
        case echoIgnored
        case outbound
        case tap
        case tempoReset
        case learned

        var label: String {
            switch self {
            case .inbound: return "IN"
            case .echoIgnored: return "ECHO"
            case .outbound: return "OUT"
            case .tap: return "TAP"
            case .tempoReset: return "RESET"
            case .learned: return "LEARN"
            }
        }
    }

    let id: UUID
    let date: Date
    let kind: Kind
    let summary: String

    init(id: UUID = UUID(), date: Date = Date(), kind: Kind, summary: String) {
        self.id = id
        self.date = date
        self.kind = kind
        self.summary = summary
    }

    var timeLabel: String {
        Self.timeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

final class MIDIMonitor: ObservableObject {
    static let defaultCapacity = 50

    @Published private(set) var entries: [MIDIMonitorEntry] = []

    private let capacity: Int

    init(capacity: Int = MIDIMonitor.defaultCapacity) {
        self.capacity = max(1, capacity)
    }

    func append(kind: MIDIMonitorEntry.Kind, summary: String, at date: Date = Date()) {
        entries.insert(MIDIMonitorEntry(date: date, kind: kind, summary: summary), at: 0)
        if entries.count > capacity {
            entries.removeLast(entries.count - capacity)
        }
    }

    func clear() {
        entries.removeAll()
    }
}
