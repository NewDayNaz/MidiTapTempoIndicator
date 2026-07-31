import Combine
import CoreMIDI
import Foundation

final class MIDIManager: ObservableObject {
    @Published private(set) var sources: [MIDIEndpointInfo] = []
    @Published private(set) var destinations: [MIDIEndpointInfo] = []
    @Published private(set) var setupError: String?
    @Published private(set) var inputConnectionStatus: String?
    @Published private(set) var outputConnectionStatus: String?
    @Published private(set) var inputConnected = false
    @Published private(set) var outputConnected = false
    @Published private(set) var deviceWarningMessage: String?
    @Published var learningTarget: LearnTarget?
    @Published var lastLearnedMessage: String?
    @Published private(set) var lastReceivedMessage: String?

    var onControllerActivity: (() -> Void)?
    var onTapPress: (() -> Void)?

    var isLearning: Bool { learningTarget != nil }

    private let settingsStore: SettingsStore
    private let echoFilter = EchoFilter()
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

    func beginLearning(_ target: LearnTarget) {
        learningTarget = target
        switch target {
        case .tapInput:
            lastLearnedMessage = "Press the tap tempo button on your controller…"
        case .ledOutput:
            lastLearnedMessage = "Press the control whose LED should blink…"
        }
    }

    func cancelLearning() {
        learningTarget = nil
        lastLearnedMessage = nil
    }

    func sendLEDValue(_ value: UInt8) {
        for mapping in settingsStore.ledOutputs {
            sendMapping(mapping, value: value)
        }
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
        echoFilter.recordSend(channel: channel & 0x0F, controller: controller & 0x7F, value: value & 0x7F)
    }

    private func sendMapping(_ mapping: MIDIMapping, value: UInt8) {
        switch mapping.kind {
        case .controlChange:
            sendControlChange(controller: mapping.note, value: value, channel: mapping.channel)
        case .noteOn:
            // Drive LED via CC using the same number — common for pad/button controllers.
            sendControlChange(controller: mapping.note, value: value, channel: mapping.channel)
        }
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
            inputConnected = false
            outputConnected = false
            deviceWarningMessage = setupError
            return
        }

        inputConnected = false
        if let selectedID = settingsStore.selectedSourceUniqueID {
            if connectedSourceID == selectedID,
               let source = sources.first(where: { $0.uniqueID == selectedID }) {
                inputConnectionStatus = "Listening to \(source.name)."
                inputConnected = true
            } else if let source = sources.first(where: { $0.uniqueID == selectedID }) {
                inputConnectionStatus = "\(source.name) is unavailable. Refresh devices or choose another input."
            } else {
                inputConnectionStatus = "Selected MIDI input is unavailable."
            }
        } else {
            inputConnectionStatus = sources.isEmpty ? "No MIDI inputs found." : "No MIDI input selected."
        }

        outputConnected = false
        if let selectedID = settingsStore.selectedDestinationUniqueID {
            if connectedDestinationID == selectedID,
               let destination = destinations.first(where: { $0.uniqueID == selectedID }) {
                outputConnectionStatus = "Sending LEDs to \(destination.name)."
                outputConnected = true
            } else if let destination = destinations.first(where: { $0.uniqueID == selectedID }) {
                outputConnectionStatus = "\(destination.name) is unavailable. Refresh devices or choose another output."
            } else {
                outputConnectionStatus = "Selected MIDI output is unavailable."
            }
        } else {
            outputConnectionStatus = destinations.isEmpty ? "No MIDI outputs found." : "No MIDI output selected."
        }

        if !inputConnected && settingsStore.selectedSourceUniqueID != nil {
            deviceWarningMessage = "MIDI input disconnected"
        } else if !outputConnected && settingsStore.selectedDestinationUniqueID != nil {
            deviceWarningMessage = "MIDI output disconnected"
        } else {
            deviceWarningMessage = nil
        }
    }

    private func handleMessages(_ messages: [MIDIParsedMessage]) {
        let filtered = messages.filter { message in
            switch message {
            case let .controlChange(channel, controller, value):
                return !echoFilter.shouldIgnore(channel: channel, controller: controller, value: value)
            case let .noteOn(channel, note, velocity):
                return !echoFilter.shouldIgnoreNote(channel: channel, note: note, velocity: velocity)
            }
        }
        guard !filtered.isEmpty else { return }

        onControllerActivity?()

        for message in filtered {
            switch message {
            case let .noteOn(channel, note, velocity):
                handleNoteOn(channel: channel, note: note, velocity: velocity)
            case let .controlChange(channel, controller, value):
                handleControlChange(channel: channel, controller: controller, value: value)
            }
        }
    }

    private func handleNoteOn(channel: UInt8, note: UInt8, velocity: UInt8) {
        lastReceivedMessage = "Note \(note) (\(MIDIMapping(kind: .noteOn, note: note, velocity: velocity, channel: channel).noteLabel)) ch\(Int(channel) + 1), value \(velocity)"

        if let learningTarget, velocity > 0 {
            applyLearned(MIDIMapping(kind: .noteOn, note: note, velocity: velocity, channel: channel), to: learningTarget)
            return
        }

        if settingsStore.tapInput.matchesPress(kind: .noteOn, number: note, value: velocity, channel: channel) {
            onTapPress?()
        }
    }

    private func handleControlChange(channel: UInt8, controller: UInt8, value: UInt8) {
        lastReceivedMessage = "CC \(controller) ch\(Int(channel) + 1), value \(value)"

        if let learningTarget, value > 0 {
            applyLearned(MIDIMapping(kind: .controlChange, note: controller, velocity: value, channel: channel), to: learningTarget)
            return
        }

        if settingsStore.tapInput.matchesPress(kind: .controlChange, number: controller, value: value, channel: channel) {
            onTapPress?()
        }
    }

    private func applyLearned(_ mapping: MIDIMapping, to target: LearnTarget) {
        switch target {
        case .tapInput:
            settingsStore.tapInput = mapping
            lastLearnedMessage = "Learned tap \(mapping.summaryLabel), value \(mapping.velocity)"
        case let .ledOutput(id):
            var updated = mapping
            updated.id = id
            settingsStore.updateLEDOutput(updated)
            lastLearnedMessage = "Learned LED \(mapping.summaryLabel), value \(mapping.velocity)"
        }
        learningTarget = nil
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
