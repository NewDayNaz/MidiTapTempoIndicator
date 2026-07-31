import Foundation

enum MIDIParsedMessage: Equatable {
    case noteOn(note: UInt8, velocity: UInt8)
    case controlChange(controller: UInt8, value: UInt8)
}

enum MIDIParser {
    static func parse(_ bytes: [UInt8]) -> [MIDIParsedMessage] {
        var messages: [MIDIParsedMessage] = []
        var index = 0
        var runningStatus: UInt8?

        while index < bytes.count {
            let byte = bytes[index]

            if byte >= 0xF0 {
                runningStatus = nil
                switch byte {
                case 0xF0:
                    index += 1
                    while index < bytes.count && bytes[index] != 0xF7 { index += 1 }
                    if index < bytes.count { index += 1 }
                case 0xF1, 0xF3:
                    index = min(index + 2, bytes.count)
                case 0xF2:
                    index = min(index + 3, bytes.count)
                default:
                    index += 1
                }
                continue
            }

            if byte >= 0x80 {
                runningStatus = byte
                index += 1
                let messageType = byte & 0xF0
                if messageType == 0xC0 || messageType == 0xD0 {
                    index = min(index + 1, bytes.count)
                }
                continue
            }

            guard let status = runningStatus else {
                index += 1
                continue
            }

            let messageType = status & 0xF0
            switch messageType {
            case 0x90:
                guard index + 1 < bytes.count else { return messages }
                messages.append(.noteOn(note: byte, velocity: bytes[index + 1]))
                index += 2
            case 0x80:
                index = min(index + 2, bytes.count)
            case 0xB0:
                guard index + 1 < bytes.count else { return messages }
                messages.append(.controlChange(controller: byte, value: bytes[index + 1]))
                index += 2
            case 0xE0:
                index = min(index + 2, bytes.count)
            default:
                index += 1
                runningStatus = nil
            }
        }
        return messages
    }
}
