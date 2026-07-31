import Combine
import Foundation

enum SettingsTransferError: LocalizedError {
    case invalidFile

    var errorDescription: String? {
        switch self {
        case .invalidFile:
            return "The selected file does not contain valid settings."
        }
    }
}

struct SettingsSnapshot: Codable, Equatable {
    var selectedSourceUniqueID: Int32?
    var selectedDestinationUniqueID: Int32?
    var tapInput: MIDIMapping
    var ledOutputs: [MIDIMapping]
    var tempoResets: [MIDIMapping]
    var blinkEnabled: Bool
    var minBPM: Double
    var maxBPM: Double
    var controllerIdleTimeout: Double
    var ledOnValue: Int
    var ledOffValue: Int
    var beatSubdivision: BeatSubdivision
    var lastBPM: Double?

    enum CodingKeys: String, CodingKey {
        case selectedSourceUniqueID, selectedDestinationUniqueID
        case tapInput, ledOutputs, tempoResets
        case blinkEnabled, minBPM, maxBPM, controllerIdleTimeout
        case ledOnValue, ledOffValue, beatSubdivision, lastBPM
    }

    init(
        selectedSourceUniqueID: Int32?,
        selectedDestinationUniqueID: Int32?,
        tapInput: MIDIMapping,
        ledOutputs: [MIDIMapping],
        tempoResets: [MIDIMapping],
        blinkEnabled: Bool,
        minBPM: Double,
        maxBPM: Double,
        controllerIdleTimeout: Double,
        ledOnValue: Int,
        ledOffValue: Int,
        beatSubdivision: BeatSubdivision,
        lastBPM: Double?
    ) {
        self.selectedSourceUniqueID = selectedSourceUniqueID
        self.selectedDestinationUniqueID = selectedDestinationUniqueID
        self.tapInput = tapInput
        self.ledOutputs = ledOutputs
        self.tempoResets = tempoResets
        self.blinkEnabled = blinkEnabled
        self.minBPM = minBPM
        self.maxBPM = maxBPM
        self.controllerIdleTimeout = controllerIdleTimeout
        self.ledOnValue = ledOnValue
        self.ledOffValue = ledOffValue
        self.beatSubdivision = beatSubdivision
        self.lastBPM = lastBPM
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedSourceUniqueID = try container.decodeIfPresent(Int32.self, forKey: .selectedSourceUniqueID)
        selectedDestinationUniqueID = try container.decodeIfPresent(Int32.self, forKey: .selectedDestinationUniqueID)
        tapInput = try container.decode(MIDIMapping.self, forKey: .tapInput)
        ledOutputs = try container.decode([MIDIMapping].self, forKey: .ledOutputs)
        tempoResets = try container.decodeIfPresent([MIDIMapping].self, forKey: .tempoResets) ?? []
        blinkEnabled = try container.decode(Bool.self, forKey: .blinkEnabled)
        minBPM = try container.decode(Double.self, forKey: .minBPM)
        maxBPM = try container.decode(Double.self, forKey: .maxBPM)
        controllerIdleTimeout = try container.decode(Double.self, forKey: .controllerIdleTimeout)
        ledOnValue = try container.decode(Int.self, forKey: .ledOnValue)
        ledOffValue = try container.decode(Int.self, forKey: .ledOffValue)
        beatSubdivision = try container.decode(BeatSubdivision.self, forKey: .beatSubdivision)
        lastBPM = try container.decodeIfPresent(Double.self, forKey: .lastBPM)
    }
}

final class SettingsStore: ObservableObject {
    static let bpmRange = 40.0...240.0
    /// Controller idle timeout in minutes.
    static let controllerIdleTimeoutRange = 1.0...60.0
    static let midiValueRange = 0...127
    static let ledOutputLimit = 8
    static let tempoResetLimit = 8
    static let defaultControllerIdleTimeout = 5.0
    static let defaultMinBPM = 40.0
    static let defaultMaxBPM = 240.0
    static let defaultLEDOnValue: UInt8 = 127
    static let defaultLEDOffValue: UInt8 = 0

    private enum Keys {
        static let selectedSourceUniqueID = "selectedSourceUniqueID"
        static let selectedDestinationUniqueID = "selectedDestinationUniqueID"
        static let tapMapping = "tapMapping"
        static let tapInput = "tapInput"
        static let ledOutputs = "ledOutputs"
        static let tempoResets = "tempoResets"
        static let blinkEnabled = "blinkEnabled"
        static let minBPM = "minBPM"
        static let maxBPM = "maxBPM"
        static let controllerIdleTimeout = "controllerIdleTimeout"
        static let ledOnValue = "ledOnValue"
        static let ledOffValue = "ledOffValue"
        static let midiChannel = "midiChannel"
        static let beatSubdivision = "beatSubdivision"
        static let lastBPM = "lastBPM"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    @Published var selectedSourceUniqueID: Int32? {
        didSet { save() }
    }

    @Published var selectedDestinationUniqueID: Int32? {
        didSet { save() }
    }

    @Published var tapInput: MIDIMapping {
        didSet { save() }
    }

    @Published var ledOutputs: [MIDIMapping] {
        didSet {
            if ledOutputs.isEmpty {
                ledOutputs = [tapInput]
                return
            }
            if ledOutputs.count > Self.ledOutputLimit {
                ledOutputs = Array(ledOutputs.prefix(Self.ledOutputLimit))
                return
            }
            save()
        }
    }

    /// Controls that clear known tempo (e.g. preset prev/next) so LEDs don't blink a stale BPM.
    @Published var tempoResets: [MIDIMapping] {
        didSet {
            if tempoResets.count > Self.tempoResetLimit {
                tempoResets = Array(tempoResets.prefix(Self.tempoResetLimit))
                return
            }
            save()
        }
    }

    @Published var blinkEnabled: Bool {
        didSet { save() }
    }

    @Published var minBPM: Double {
        didSet {
            let clamped = Self.clampBPM(minBPM)
            if clamped != minBPM {
                minBPM = clamped
                return
            }
            if minBPM > maxBPM {
                maxBPM = minBPM
            }
            save()
        }
    }

    @Published var maxBPM: Double {
        didSet {
            let clamped = Self.clampBPM(maxBPM)
            if clamped != maxBPM {
                maxBPM = clamped
                return
            }
            if maxBPM < minBPM {
                minBPM = maxBPM
            }
            save()
        }
    }

    /// Minutes of controller inactivity before LED blink stops.
    @Published var controllerIdleTimeout: Double {
        didSet {
            let clamped = min(
                Self.controllerIdleTimeoutRange.upperBound,
                max(Self.controllerIdleTimeoutRange.lowerBound, controllerIdleTimeout)
            )
            if clamped != controllerIdleTimeout {
                controllerIdleTimeout = clamped
                return
            }
            save()
        }
    }

    var controllerIdleTimeoutSeconds: TimeInterval {
        controllerIdleTimeout * 60.0
    }

    @Published var ledOnValue: Int {
        didSet {
            let clamped = min(Self.midiValueRange.upperBound, max(Self.midiValueRange.lowerBound, ledOnValue))
            if clamped != ledOnValue {
                ledOnValue = clamped
                return
            }
            save()
        }
    }

    @Published var ledOffValue: Int {
        didSet {
            let clamped = min(Self.midiValueRange.upperBound, max(Self.midiValueRange.lowerBound, ledOffValue))
            if clamped != ledOffValue {
                ledOffValue = clamped
                return
            }
            save()
        }
    }

    @Published var beatSubdivision: BeatSubdivision {
        didSet { save() }
    }

    @Published var lastBPM: Double? {
        didSet {
            if let lastBPM {
                let clamped = Self.clampBPM(lastBPM)
                if clamped != lastBPM {
                    self.lastBPM = clamped
                    return
                }
            }
            save()
        }
    }

    @Published var hasCompletedOnboarding: Bool {
        didSet { save() }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard !isSyncingLaunchAtLogin else { return }
            updateLaunchAtLogin(enabled: launchAtLogin)
        }
    }

    @Published private(set) var launchAtLoginError: String?

    private let defaults: UserDefaults
    private var isSyncingLaunchAtLogin = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if defaults.object(forKey: Keys.selectedSourceUniqueID) != nil {
            selectedSourceUniqueID = Int32(defaults.integer(forKey: Keys.selectedSourceUniqueID))
        } else {
            selectedSourceUniqueID = nil
        }

        if defaults.object(forKey: Keys.selectedDestinationUniqueID) != nil {
            selectedDestinationUniqueID = Int32(defaults.integer(forKey: Keys.selectedDestinationUniqueID))
        } else {
            selectedDestinationUniqueID = nil
        }

        let migrated = Self.loadMappings(from: defaults)
        tapInput = migrated.tapInput
        ledOutputs = migrated.ledOutputs

        if let resetData = defaults.data(forKey: Keys.tempoResets),
           let decoded = try? JSONDecoder().decode([MIDIMapping].self, from: resetData) {
            tempoResets = Array(decoded.prefix(Self.tempoResetLimit))
        } else {
            tempoResets = []
        }

        if defaults.object(forKey: Keys.blinkEnabled) != nil {
            blinkEnabled = defaults.bool(forKey: Keys.blinkEnabled)
        } else {
            blinkEnabled = true
        }

        let storedMin = defaults.object(forKey: Keys.minBPM) as? Double ?? Self.defaultMinBPM
        let storedMax = defaults.object(forKey: Keys.maxBPM) as? Double ?? Self.defaultMaxBPM
        let clampedMin = Self.clampBPM(storedMin)
        let clampedMax = max(Self.clampBPM(storedMax), clampedMin)
        minBPM = clampedMin
        maxBPM = clampedMax

        let storedIdle = defaults.object(forKey: Keys.controllerIdleTimeout) as? Double
            ?? Self.defaultControllerIdleTimeout
        controllerIdleTimeout = min(
            Self.controllerIdleTimeoutRange.upperBound,
            max(Self.controllerIdleTimeoutRange.lowerBound, storedIdle)
        )

        if defaults.object(forKey: Keys.ledOnValue) != nil {
            ledOnValue = min(127, max(0, defaults.integer(forKey: Keys.ledOnValue)))
        } else {
            ledOnValue = Int(Self.defaultLEDOnValue)
        }

        if defaults.object(forKey: Keys.ledOffValue) != nil {
            ledOffValue = min(127, max(0, defaults.integer(forKey: Keys.ledOffValue)))
        } else {
            ledOffValue = Int(Self.defaultLEDOffValue)
        }

        if let raw = defaults.string(forKey: Keys.beatSubdivision),
           let subdivision = BeatSubdivision(rawValue: raw) {
            beatSubdivision = subdivision
        } else {
            beatSubdivision = .quarter
        }

        if defaults.object(forKey: Keys.lastBPM) != nil {
            lastBPM = Self.clampBPM(defaults.double(forKey: Keys.lastBPM))
        } else {
            lastBPM = nil
        }

        hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)

        launchAtLogin = LaunchAtLogin.isEnabled
        launchAtLoginError = nil
    }

    func refreshLaunchAtLogin() {
        isSyncingLaunchAtLogin = true
        launchAtLogin = LaunchAtLogin.isEnabled
        launchAtLoginError = LaunchAtLogin.statusMessage
        isSyncingLaunchAtLogin = false
    }

    func resetTapInputToDefault() {
        tapInput = .default
    }

    func addLEDOutput() {
        guard ledOutputs.count < Self.ledOutputLimit else { return }
        var copy = tapInput
        copy.id = UUID()
        ledOutputs.append(copy)
    }

    func removeLEDOutput(id: UUID) {
        guard ledOutputs.count > 1 else { return }
        ledOutputs.removeAll { $0.id == id }
    }

    func updateLEDOutput(_ mapping: MIDIMapping) {
        guard let index = ledOutputs.firstIndex(where: { $0.id == mapping.id }) else { return }
        ledOutputs[index] = mapping
    }

    func addTempoReset() {
        guard tempoResets.count < Self.tempoResetLimit else { return }
        tempoResets.append(MIDIMapping(kind: .controlChange, note: 0, velocity: 127, channel: 0))
    }

    func removeTempoReset(id: UUID) {
        tempoResets.removeAll { $0.id == id }
    }

    func updateTempoReset(_ mapping: MIDIMapping) {
        guard let index = tempoResets.firstIndex(where: { $0.id == mapping.id }) else { return }
        tempoResets[index] = mapping
    }

    func useSameDeviceForInputAndOutput(sources: [MIDIEndpointInfo], destinations: [MIDIEndpointInfo]) {
        guard let sourceID = selectedSourceUniqueID,
              let source = sources.first(where: { $0.uniqueID == sourceID }) else { return }

        if destinations.contains(where: { $0.uniqueID == sourceID }) {
            selectedDestinationUniqueID = sourceID
            return
        }

        if let match = destinations.first(where: { $0.name == source.name }) {
            selectedDestinationUniqueID = match.uniqueID
        }
    }

    func exportSettingsData() throws -> Data {
        let snapshot = SettingsSnapshot(
            selectedSourceUniqueID: selectedSourceUniqueID,
            selectedDestinationUniqueID: selectedDestinationUniqueID,
            tapInput: tapInput,
            ledOutputs: ledOutputs,
            tempoResets: tempoResets,
            blinkEnabled: blinkEnabled,
            minBPM: minBPM,
            maxBPM: maxBPM,
            controllerIdleTimeout: controllerIdleTimeout,
            ledOnValue: ledOnValue,
            ledOffValue: ledOffValue,
            beatSubdivision: beatSubdivision,
            lastBPM: lastBPM
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(snapshot)
    }

    func importSettingsData(_ data: Data) throws {
        guard let snapshot = try? JSONDecoder().decode(SettingsSnapshot.self, from: data) else {
            throw SettingsTransferError.invalidFile
        }
        apply(snapshot: snapshot)
    }

    private func apply(snapshot: SettingsSnapshot) {
        selectedSourceUniqueID = snapshot.selectedSourceUniqueID
        selectedDestinationUniqueID = snapshot.selectedDestinationUniqueID
        tapInput = snapshot.tapInput
        ledOutputs = snapshot.ledOutputs.isEmpty ? [snapshot.tapInput] : Array(snapshot.ledOutputs.prefix(Self.ledOutputLimit))
        tempoResets = Array(snapshot.tempoResets.prefix(Self.tempoResetLimit))
        blinkEnabled = snapshot.blinkEnabled
        minBPM = Self.clampBPM(snapshot.minBPM)
        maxBPM = max(Self.clampBPM(snapshot.maxBPM), minBPM)
        controllerIdleTimeout = min(
            Self.controllerIdleTimeoutRange.upperBound,
            max(Self.controllerIdleTimeoutRange.lowerBound, snapshot.controllerIdleTimeout)
        )
        ledOnValue = min(127, max(0, snapshot.ledOnValue))
        ledOffValue = min(127, max(0, snapshot.ledOffValue))
        beatSubdivision = snapshot.beatSubdivision
        lastBPM = snapshot.lastBPM.map(Self.clampBPM)
    }

    private static func loadMappings(from defaults: UserDefaults) -> (tapInput: MIDIMapping, ledOutputs: [MIDIMapping]) {
        if let data = defaults.data(forKey: Keys.tapInput),
           let tap = try? JSONDecoder().decode(MIDIMapping.self, from: data) {
            let outputs: [MIDIMapping]
            if let outData = defaults.data(forKey: Keys.ledOutputs),
               let decoded = try? JSONDecoder().decode([MIDIMapping].self, from: outData),
               !decoded.isEmpty {
                outputs = Array(decoded.prefix(ledOutputLimit))
            } else {
                outputs = [tap]
            }
            return (tap, outputs)
        }

        // Legacy single tapMapping → tap input + one LED out.
        if let data = defaults.data(forKey: Keys.tapMapping),
           let legacy = try? JSONDecoder().decode(MIDIMapping.self, from: data) {
            var migrated = legacy
            if defaults.object(forKey: Keys.midiChannel) != nil {
                migrated.channel = UInt8(clamping: min(15, max(0, defaults.integer(forKey: Keys.midiChannel))))
            }
            return (migrated, [migrated])
        }

        return (.default, [.default])
    }

    private func updateLaunchAtLogin(enabled: Bool) {
        guard LaunchAtLogin.isSupported else {
            launchAtLoginError = "Launch at login requires installing the app as a macOS application."
            isSyncingLaunchAtLogin = true
            launchAtLogin = false
            isSyncingLaunchAtLogin = false
            return
        }

        do {
            try LaunchAtLogin.setEnabled(enabled)
            launchAtLoginError = LaunchAtLogin.statusMessage
        } catch {
            launchAtLoginError = error.localizedDescription
            isSyncingLaunchAtLogin = true
            launchAtLogin = LaunchAtLogin.isEnabled
            isSyncingLaunchAtLogin = false
        }
    }

    static func clampBPM(_ value: Double) -> Double {
        min(bpmRange.upperBound, max(bpmRange.lowerBound, value))
    }

    private func save() {
        if let selectedSourceUniqueID {
            defaults.set(Int(selectedSourceUniqueID), forKey: Keys.selectedSourceUniqueID)
        } else {
            defaults.removeObject(forKey: Keys.selectedSourceUniqueID)
        }

        if let selectedDestinationUniqueID {
            defaults.set(Int(selectedDestinationUniqueID), forKey: Keys.selectedDestinationUniqueID)
        } else {
            defaults.removeObject(forKey: Keys.selectedDestinationUniqueID)
        }

        if let data = try? JSONEncoder().encode(tapInput) {
            defaults.set(data, forKey: Keys.tapInput)
        }
        if let data = try? JSONEncoder().encode(ledOutputs) {
            defaults.set(data, forKey: Keys.ledOutputs)
        }
        if let data = try? JSONEncoder().encode(tempoResets) {
            defaults.set(data, forKey: Keys.tempoResets)
        }

        defaults.set(blinkEnabled, forKey: Keys.blinkEnabled)
        defaults.set(minBPM, forKey: Keys.minBPM)
        defaults.set(maxBPM, forKey: Keys.maxBPM)
        defaults.set(controllerIdleTimeout, forKey: Keys.controllerIdleTimeout)
        defaults.set(ledOnValue, forKey: Keys.ledOnValue)
        defaults.set(ledOffValue, forKey: Keys.ledOffValue)
        defaults.set(beatSubdivision.rawValue, forKey: Keys.beatSubdivision)
        defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding)

        if let lastBPM {
            defaults.set(lastBPM, forKey: Keys.lastBPM)
        } else {
            defaults.removeObject(forKey: Keys.lastBPM)
        }
    }
}
