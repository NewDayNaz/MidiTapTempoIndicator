import Combine
import CoreMIDI
import Foundation

final class MIDIManager: ObservableObject {
    @Published private(set) var sources: [MIDIEndpointInfo] = []
    @Published private(set) var destinations: [MIDIEndpointInfo] = []
    @Published private(set) var setupError: String?
    @Published private(set) var inputConnectionStatus: String?
    @Published private(set) var outputConnectionStatus: String?
    @Published var isLearning = false
    @Published var lastLearnedMessage: String?
    @Published private(set) var lastReceivedMessage: String?

    var onControllerActivity: (() -> Void)?
    var onTapPress: (() -> Void)?

    private let settingsStore: SettingsStore
    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var outputPort = MIDIPortRef()
    private var connectedSourceID: Int32?
    private var connectedDestinationID: Int32?
    private var destinationEndpoint: MIDIEndpointRef = 0
    private var cancellables = Set<AnyCancellable>()
    private var isStarted = false

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        setupClient()
        refreshEndpoints()
        reconnectSelectedSource()
        reconnectSelectedDestination()

        settingsStore.$selectedSourceUniqueID
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reconnectSelectedSource()
            }
            .store(in: &cancellables)

        settingsStore.$selectedDestinationUniqueID
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reconnectSelectedDestination()
            }
            .store(in: &cancellables)
    }

    func stop() {
        guard isStarted else { return }
        disconnectAllSources()
        destinationEndpoint = 0
        connectedDestinationID = nil
        if inputPort != 0 {
            MIDIPortDispose(inputPort)
            inputPort = 0
        }
        if outputPort != 0 {
            MIDIPortDispose(outputPort)
            outputPort = 0
        }
        if client != 0 {
            MIDIClientDispose(client)
            client = 0
        }
        isStarted = false
    }

    func refreshEndpoints() {
        sources = enumerateEndpoints(count: MIDIGetNumberOfSources(), get: MIDIGetSource)
        destinations = enumerateEndpoints(count: MIDIGetNumberOfDestinations(), get: MIDIGetDestination)

        if settingsStore.selectedSourceUniqueID == nil, let first = sources.first {
            settingsStore.selectedSourceUniqueID = first.uniqueID
        }
        if settingsStore.selectedDestinationUniqueID == nil {
            if let matching = destinations.first(where: { $0.uniqueID == settingsStore.selectedSourceUniqueID }) {
                settingsStore.selectedDestinationUniqueID = matching.uniqueID
            } else if let first = destinations.first {
                settingsStore.selectedDestinationUniqueID = first.uniqueID
            }
        }

        updateConnectionStatus()
    }

    func beginLearning() {
        isLearning = true
        lastLearnedMessage = "Press the tap tempo button on your controller…"
    }

    func cancelLearning() {
        isLearning = false
        lastLearnedMessage = nil
    }

    func sendControlChange(controller: UInt8, value: UInt8, channel: UInt8) {
        guard outputPort != 0, destinationEndpoint != 0 else { return }
        let status: UInt8 = 0xB0 | (channel & 0x0F)
        var packet = MIDIPacket()
        packet.timeStamp = 0
        packet.length = 3
        packet.data.0 = status
        packet.data.1 = controller & 0x7F
        packet.data.2 = value & 0x7F
        var packetList = MIDIPacketList(numPackets: 1, packet: packet)
        MIDISend(outputPort, destinationEndpoint, &packetList)
    }

    private func setupClient() {
        let status = MIDIClientCreateWithBlock("MidiTapTempoIndicator" as CFString, &client) { [weak self] _ in
            DispatchQueue.main.async {
                self?.refreshEndpoints()
                self?.reconnectSelectedSource()
                self?.reconnectSelectedDestination()
            }
        }
        guard status == noErr else {
            setupError = "Could not initialize Core MIDI (error \(status))."
            fputs("MIDIClientCreateWithBlock failed: \(status)\n", stderr)
            return
        }

        let inputStatus = MIDIInputPortCreateWithBlock(client, "Input" as CFString, &inputPort) { [weak self] packetList, _ in
            let messages = Self.extractMessages(from: packetList)
            DispatchQueue.main.async {
                self?.handleMessages(messages)
            }
        }
        guard inputStatus == noErr else {
            setupError = "Could not open MIDI input port (error \(inputStatus))."
            fputs("MIDIInputPortCreateWithBlock failed: \(inputStatus)\n", stderr)
            return
        }

        let outputStatus = MIDIOutputPortCreate(client, "Output" as CFString, &outputPort)
        guard outputStatus == noErr else {
            setupError = "Could not open MIDI output port (error \(outputStatus))."
            fputs("MIDIOutputPortCreate failed: \(outputStatus)\n", stderr)
            return
        }
    }

    private func reconnectSelectedSource() {
        disconnectAllSources()

        guard let selectedID = settingsStore.selectedSourceUniqueID else {
            updateConnectionStatus()
            return
        }

        let count = MIDIGetNumberOfSources()
        for index in 0..<count {
            let endpoint = MIDIGetSource(index)
            guard let uniqueID = endpointUniqueID(endpoint), uniqueID == selectedID else { continue }
            let status = MIDIPortConnectSource(inputPort, endpoint, nil)
            if status == noErr {
                connectedSourceID = selectedID
            }
            updateConnectionStatus()
            return
        }
        connectedSourceID = nil
        updateConnectionStatus()
    }

    private func reconnectSelectedDestination() {
        destinationEndpoint = 0
        connectedDestinationID = nil

        guard let selectedID = settingsStore.selectedDestinationUniqueID else {
            updateConnectionStatus()
            return
        }

        let count = MIDIGetNumberOfDestinations()
        for index in 0..<count {
            let endpoint = MIDIGetDestination(index)
            guard let uniqueID = endpointUniqueID(endpoint), uniqueID == selectedID else { continue }
            destinationEndpoint = endpoint
            connectedDestinationID = selectedID
            updateConnectionStatus()
            return
        }
        updateConnectionStatus()
    }

    private func disconnectAllSources() {
        let count = MIDIGetNumberOfSources()
        for index in 0..<count {
            let endpoint = MIDIGetSource(index)
            MIDIPortDisconnectSource(inputPort, endpoint)
        }
        connectedSourceID = nil
    }

    private func updateConnectionStatus() {
        guard setupError == nil else {
            inputConnectionStatus = nil
            outputConnectionStatus = nil
            return
        }

        if let selectedID = settingsStore.selectedSourceUniqueID {
            if connectedSourceID == selectedID,
               let source = sources.first(where: { $0.uniqueID == selectedID }) {
                inputConnectionStatus = "Listening to \(source.name)."
            } else if let source = sources.first(where: { $0.uniqueID == selectedID }) {
                inputConnectionStatus = "\(source.name) is unavailable. Refresh devices or choose another input."
            } else {
                inputConnectionStatus = "Selected MIDI input is unavailable."
            }
        } else {
            inputConnectionStatus = sources.isEmpty ? "No MIDI inputs found." : "No MIDI input selected."
        }

        if let selectedID = settingsStore.selectedDestinationUniqueID {
            if connectedDestinationID == selectedID,
               let destination = destinations.first(where: { $0.uniqueID == selectedID }) {
                outputConnectionStatus = "Sending LEDs to \(destination.name)."
            } else if let destination = destinations.first(where: { $0.uniqueID == selectedID }) {
                outputConnectionStatus = "\(destination.name) is unavailable. Refresh devices or choose another output."
            } else {
                outputConnectionStatus = "Selected MIDI output is unavailable."
            }
        } else {
            outputConnectionStatus = destinations.isEmpty ? "No MIDI outputs found." : "No MIDI output selected."
        }
    }

    private func handleMessages(_ messages: [MIDIParsedMessage]) {
        guard !messages.isEmpty else { return }

        onControllerActivity?()

        for message in messages {
            switch message {
            case let .noteOn(note, velocity):
                handleNoteOn(note: note, velocity: velocity)
            case let .controlChange(controller, value):
                handleControlChange(controller: controller, value: value)
            }
        }
    }

    private func handleNoteOn(note: UInt8, velocity: UInt8) {
        lastReceivedMessage = "Note \(note) (\(MIDIMapping(kind: .noteOn, note: note, velocity: velocity).noteLabel)), value \(velocity)"

        if isLearning, velocity > 0 {
            settingsStore.tapMapping = MIDIMapping(kind: .noteOn, note: note, velocity: velocity)
            lastLearnedMessage = "Learned \(settingsStore.tapMapping.noteLabel), value \(velocity)"
            isLearning = false
            return
        }

        if settingsStore.tapMapping.matchesPress(kind: .noteOn, number: note, value: velocity) {
            onTapPress?()
        }
    }

    private func handleControlChange(controller: UInt8, value: UInt8) {
        lastReceivedMessage = "CC \(controller), value \(value)"

        if isLearning, value > 0 {
            settingsStore.tapMapping = MIDIMapping(kind: .controlChange, note: controller, velocity: value)
            lastLearnedMessage = "Learned CC \(controller), value \(value)"
            isLearning = false
            return
        }

        if settingsStore.tapMapping.matchesPress(kind: .controlChange, number: controller, value: value) {
            onTapPress?()
        }
    }

    private static func extractMessages(from packetList: UnsafePointer<MIDIPacketList>) -> [MIDIParsedMessage] {
        var messages: [MIDIParsedMessage] = []
        var packet = packetList.pointee.packet
        for _ in 0..<packetList.pointee.numPackets {
            let length = Int(packet.length)
            let bytes = withUnsafePointer(to: &packet.data) {
                $0.withMemoryRebound(to: UInt8.self, capacity: length) {
                    Array(UnsafeBufferPointer(start: $0, count: length))
                }
            }
            messages.append(contentsOf: MIDIParser.parse(bytes))
            packet = MIDIPacketNext(&packet).pointee
        }
        return messages
    }

    private func enumerateEndpoints(
        count: Int,
        get: (Int) -> MIDIEndpointRef
    ) -> [MIDIEndpointInfo] {
        var found: [MIDIEndpointInfo] = []
        for index in 0..<count {
            let endpoint = get(index)
            guard let name = endpointName(endpoint),
                  let uniqueID = endpointUniqueID(endpoint) else { continue }
            found.append(MIDIEndpointInfo(uniqueID: uniqueID, name: name))
        }
        return found
    }

    private func endpointName(_ endpoint: MIDIEndpointRef) -> String? {
        var param: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &param)
        guard status == noErr, let param else { return nil }
        return param.takeRetainedValue() as String
    }

    private func endpointUniqueID(_ endpoint: MIDIEndpointRef) -> Int32? {
        var uniqueID: Int32 = 0
        let status = MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID)
        guard status == noErr else { return nil }
        return uniqueID
    }
}
