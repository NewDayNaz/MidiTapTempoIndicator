import Combine
import Foundation

final class SettingsStore: ObservableObject {
    static let bpmRange = 40.0...240.0
    /// Controller idle timeout in minutes.
    static let controllerIdleTimeoutRange = 1.0...60.0
    static let midiValueRange = 0...127
    static let defaultControllerIdleTimeout = 5.0
    static let defaultMinBPM = 40.0
    static let defaultMaxBPM = 240.0
    static let defaultLEDOnValue: UInt8 = 127
    static let defaultLEDOffValue: UInt8 = 0
    static let defaultMIDIChannel: UInt8 = 0

    private enum Keys {
        static let selectedSourceUniqueID = "selectedSourceUniqueID"
        static let selectedDestinationUniqueID = "selectedDestinationUniqueID"
        static let tapMapping = "tapMapping"
        static let blinkEnabled = "blinkEnabled"
        static let minBPM = "minBPM"
        static let maxBPM = "maxBPM"
        static let controllerIdleTimeout = "controllerIdleTimeout"
        static let ledOnValue = "ledOnValue"
        static let ledOffValue = "ledOffValue"
        static let midiChannel = "midiChannel"
    }

    @Published var selectedSourceUniqueID: Int32? {
        didSet { save() }
    }

    @Published var selectedDestinationUniqueID: Int32? {
        didSet { save() }
    }

    @Published var tapMapping: MIDIMapping {
        didSet { save() }
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

    /// Idle timeout as a `TimeInterval` in seconds for runtime use.
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

    @Published var midiChannel: Int {
        didSet {
            let clamped = min(15, max(0, midiChannel))
            if clamped != midiChannel {
                midiChannel = clamped
                return
            }
            save()
        }
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

        if let data = defaults.data(forKey: Keys.tapMapping),
           let decoded = try? JSONDecoder().decode(MIDIMapping.self, from: data) {
            tapMapping = decoded
        } else {
            tapMapping = .default
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

        if defaults.object(forKey: Keys.midiChannel) != nil {
            midiChannel = min(15, max(0, defaults.integer(forKey: Keys.midiChannel)))
        } else {
            midiChannel = Int(Self.defaultMIDIChannel)
        }

        launchAtLogin = LaunchAtLogin.isEnabled
        launchAtLoginError = nil
    }

    func refreshLaunchAtLogin() {
        isSyncingLaunchAtLogin = true
        launchAtLogin = LaunchAtLogin.isEnabled
        launchAtLoginError = LaunchAtLogin.statusMessage
        isSyncingLaunchAtLogin = false
    }

    func resetTapMappingToDefault() {
        tapMapping = .default
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

    private static func clampBPM(_ value: Double) -> Double {
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

        if let data = try? JSONEncoder().encode(tapMapping) {
            defaults.set(data, forKey: Keys.tapMapping)
        }

        defaults.set(blinkEnabled, forKey: Keys.blinkEnabled)
        defaults.set(minBPM, forKey: Keys.minBPM)
        defaults.set(maxBPM, forKey: Keys.maxBPM)
        defaults.set(controllerIdleTimeout, forKey: Keys.controllerIdleTimeout)
        defaults.set(ledOnValue, forKey: Keys.ledOnValue)
        defaults.set(ledOffValue, forKey: Keys.ledOffValue)
        defaults.set(midiChannel, forKey: Keys.midiChannel)
    }
}
