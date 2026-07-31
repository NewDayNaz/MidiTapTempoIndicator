import Foundation

/// Suppresses inbound MIDI that matches recently sent LED traffic (device echo).
final class EchoFilter {
    struct Event: Equatable {
        var channel: UInt8
        var controller: UInt8
        var value: UInt8
        var timestamp: Date
    }

    var window: TimeInterval = 0.05

    private var recent: [Event] = []
    private let lock = NSLock()

    func recordSend(channel: UInt8, controller: UInt8, value: UInt8, at date: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        pruneLocked(now: date)
        recent.append(Event(channel: channel, controller: controller, value: value, timestamp: date))
    }

    func shouldIgnore(channel: UInt8, controller: UInt8, value: UInt8, at date: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        pruneLocked(now: date)
        return recent.contains {
            $0.channel == channel && $0.controller == controller && $0.value == value
        }
    }

    /// Note-on echoes use the note number in the controller field for matching.
    func shouldIgnoreNote(channel: UInt8, note: UInt8, velocity: UInt8, at date: Date = Date()) -> Bool {
        shouldIgnore(channel: channel, controller: note, value: velocity, at: date)
    }

    private func pruneLocked(now: Date) {
        recent.removeAll { now.timeIntervalSince($0.timestamp) > window }
    }
}
