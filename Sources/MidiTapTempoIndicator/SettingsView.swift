import AppKit
import SwiftUI

struct SettingsView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case general = "General"
        case mapping = "Mapping"

        var id: String { rawValue }
    }

    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var midiManager: MIDIManager
    @ObservedObject var activityMonitor: ControllerActivityMonitor
    @ObservedObject var tempoState: TempoState

    @State private var selectedTab: Tab = .general

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if midiManager.isLearning {
                learnBanner
            }

            Picker("Section", selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            Group {
                switch selectedTab {
                case .general:
                    generalTab
                case .mapping:
                    mappingTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(20)
        .frame(minWidth: 700, minHeight: 600)
        .onAppear {
            settingsStore.refreshLaunchAtLogin()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("MIDI Tap Tempo Indicator")
                    .font(.system(size: 24, weight: .semibold))
                Text("Track tap tempo from your controller and blink its LED at the BPM you tap.")
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                StatusCard(
                    title: "BPM",
                    value: bpmDisplay,
                    detail: activityMonitor.isActive ? "Controller active — LED blink armed." : "Controller idle — LED blink stopped.",
                    tone: tempoState.currentBPM == nil ? .neutral : .accent
                )
                StatusCard(
                    title: "MIDI Input",
                    value: selectedSourceName,
                    detail: midiManager.inputConnectionStatus ?? "Choose an input to start listening.",
                    tone: inputTone
                )
                StatusCard(
                    title: "MIDI Output",
                    value: selectedDestinationName,
                    detail: midiManager.outputConnectionStatus ?? "Choose an output for LED control.",
                    tone: outputTone
                )
                StatusCard(
                    title: "Input Activity",
                    value: midiManager.lastReceivedMessage ?? "Waiting",
                    detail: "Last MIDI message from the selected input.",
                    tone: midiManager.lastReceivedMessage == nil ? .neutral : .accent
                )
            }
        }
    }

    private var learnBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.title3)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Listening for Tap Tempo")
                    .font(.headline)
                Text(midiManager.lastLearnedMessage ?? "Press the tap tempo button on your controller.")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Cancel") {
                midiManager.cancelLearning()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
        }
    }

    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                settingsCard(title: "Startup") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Open at login", isOn: $settingsStore.launchAtLogin)
                            .disabled(!LaunchAtLogin.isSupported)

                        if !LaunchAtLogin.isSupported {
                            supportingText("Available when the app is packaged as a macOS application (.app).")
                        } else if let message = settingsStore.launchAtLoginError {
                            supportingText(message)
                        }
                    }
                }

                settingsCard(title: "MIDI Devices") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .center, spacing: 12) {
                            Picker("Input", selection: selectedSourceBinding) {
                                if midiManager.sources.isEmpty {
                                    Text("No devices found").tag(Optional<Int32>.none)
                                }
                                ForEach(midiManager.sources) { source in
                                    Text(source.name).tag(Optional(source.uniqueID))
                                }
                            }
                            .pickerStyle(.menu)

                            Picker("Output", selection: selectedDestinationBinding) {
                                if midiManager.destinations.isEmpty {
                                    Text("No devices found").tag(Optional<Int32>.none)
                                }
                                ForEach(midiManager.destinations) { destination in
                                    Text(destination.name).tag(Optional(destination.uniqueID))
                                }
                            }
                            .pickerStyle(.menu)

                            Button("Refresh") {
                                midiManager.refreshEndpoints()
                            }
                        }

                        if let setupError = midiManager.setupError {
                            InlineMessageCard(
                                title: "MIDI setup issue",
                                message: setupError,
                                tone: .warning
                            )
                        } else {
                            if let inputStatus = midiManager.inputConnectionStatus {
                                supportingText(inputStatus)
                            }
                            if let outputStatus = midiManager.outputConnectionStatus {
                                supportingText(outputStatus)
                            }
                        }

                        supportingText("Other apps can keep using the same controller at the same time. Select it here for input (taps) and output (LED blink).")
                    }
                }

                settingsCard(title: "Tempo & Blink") {
                    VStack(alignment: .leading, spacing: 16) {
                        Toggle("Blink tap button LED", isOn: $settingsStore.blinkEnabled)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Controller idle timeout")
                                Spacer()
                                valuePill(String(format: "%.0f min", settingsStore.controllerIdleTimeout))
                            }
                            Slider(
                                value: $settingsStore.controllerIdleTimeout,
                                in: SettingsStore.controllerIdleTimeoutRange,
                                step: 1
                            )
                            supportingText("Any use of the controller (knobs, faders, buttons) keeps the LED blinking. After this many minutes with no MIDI, the LED turns off.")
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Minimum BPM")
                                Spacer()
                                valuePill(String(format: "%.0f", settingsStore.minBPM))
                            }
                            Slider(value: $settingsStore.minBPM, in: SettingsStore.bpmRange, step: 1)

                            HStack {
                                Text("Maximum BPM")
                                Spacer()
                                valuePill(String(format: "%.0f", settingsStore.maxBPM))
                            }
                            Slider(value: $settingsStore.maxBPM, in: SettingsStore.bpmRange, step: 1)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("LED on value")
                                Spacer()
                                MIDIValueStepper(value: $settingsStore.ledOnValue, range: 0...127)
                            }
                            HStack {
                                Text("LED off value")
                                Spacer()
                                MIDIValueStepper(value: $settingsStore.ledOffValue, range: 0...127)
                            }
                            HStack {
                                Text("MIDI channel")
                                Spacer()
                                MIDIValueStepper(value: $settingsStore.midiChannel, range: 0...15)
                            }
                            supportingText("Channel is zero-based (0 = MIDI channel 1). Many controllers drive button LEDs with the same CC number as the button, using 127 on and 0 off.")
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var mappingTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                settingsCard(title: "Mapping Guide") {
                    VStack(alignment: .leading, spacing: 8) {
                        supportingText("Learn the button used for tap tempo. Presses (value > 0) update BPM; releases are ignored. Other apps still receive the hardware message directly.")
                        if let message = midiManager.lastLearnedMessage {
                            supportingText(message)
                        }
                    }
                }

                settingsCard(title: "Tap Tempo") {
                    VStack(alignment: .leading, spacing: 14) {
                        MappingHeaderRow()
                        MappingEditorRow(
                            mapping: $settingsStore.tapMapping,
                            defaultMapping: .default,
                            isLearning: midiManager.isLearning,
                            onLearn: { midiManager.beginLearning() },
                            onCancelLearn: { midiManager.cancelLearning() }
                        )
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func settingsCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func valuePill(_ value: String) -> some View {
        Text(value)
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.12), in: Capsule())
    }

    private func supportingText(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var bpmDisplay: String {
        if let bpm = tempoState.currentBPM {
            return String(format: "%.1f", bpm)
        }
        return "—"
    }

    private var selectedSourceName: String {
        if let selectedID = settingsStore.selectedSourceUniqueID,
           let source = midiManager.sources.first(where: { $0.uniqueID == selectedID }) {
            return source.name
        }
        return midiManager.sources.isEmpty ? "No Device" : "Not Selected"
    }

    private var selectedDestinationName: String {
        if let selectedID = settingsStore.selectedDestinationUniqueID,
           let destination = midiManager.destinations.first(where: { $0.uniqueID == selectedID }) {
            return destination.name
        }
        return midiManager.destinations.isEmpty ? "No Device" : "Not Selected"
    }

    private var inputTone: MessageTone {
        if midiManager.setupError != nil { return .warning }
        if let selectedID = settingsStore.selectedSourceUniqueID,
           midiManager.sources.contains(where: { $0.uniqueID == selectedID }) {
            return .success
        }
        return .neutral
    }

    private var outputTone: MessageTone {
        if midiManager.setupError != nil { return .warning }
        if let selectedID = settingsStore.selectedDestinationUniqueID,
           midiManager.destinations.contains(where: { $0.uniqueID == selectedID }) {
            return .success
        }
        return .neutral
    }

    private var selectedSourceBinding: Binding<Int32?> {
        Binding(
            get: { settingsStore.selectedSourceUniqueID },
            set: { settingsStore.selectedSourceUniqueID = $0 }
        )
    }

    private var selectedDestinationBinding: Binding<Int32?> {
        Binding(
            get: { settingsStore.selectedDestinationUniqueID },
            set: { settingsStore.selectedDestinationUniqueID = $0 }
        )
    }
}

private enum MessageTone {
    case neutral
    case success
    case warning
    case accent

    var color: Color {
        switch self {
        case .neutral: return .secondary
        case .success: return .green
        case .warning: return .orange
        case .accent: return .accentColor
        }
    }

    var iconName: String {
        switch self {
        case .neutral: return "circle"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .accent: return "metronome"
        }
    }
}

private struct StatusCard: View {
    let title: String
    let value: String
    let detail: String
    let tone: MessageTone

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Image(systemName: tone.iconName)
                    .foregroundStyle(tone.color)
            }

            Text(value)
                .font(.title3.weight(.semibold))
                .lineLimit(2)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct InlineMessageCard: View {
    let title: String
    let message: String
    let tone: MessageTone

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: tone.iconName)
                .foregroundStyle(tone.color)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(tone.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private enum MappingRowLayout {
    static let typeColumnWidth: CGFloat = 120
    static let noteColumnWidth: CGFloat = 170
    static let valueColumnWidth: CGFloat = 84
    static let columnSpacing: CGFloat = 12
}

private struct MappingHeaderRow: View {
    var body: some View {
        HStack(spacing: MappingRowLayout.columnSpacing) {
            Text("Type")
                .mappingColumnLabel()
                .frame(width: MappingRowLayout.typeColumnWidth, alignment: .leading)
            Text("Note / CC")
                .mappingColumnLabel()
                .frame(width: MappingRowLayout.noteColumnWidth, alignment: .leading)
            Text("Value")
                .mappingColumnLabel()
                .frame(width: MappingRowLayout.valueColumnWidth, alignment: .leading)
            Text("Actions")
                .mappingColumnLabel()
            Spacer(minLength: 0)
        }
    }
}

private struct MappingEditorRow: View {
    @Binding var mapping: MIDIMapping
    let defaultMapping: MIDIMapping
    let isLearning: Bool
    let onLearn: () -> Void
    let onCancelLearn: () -> Void

    var body: some View {
        HStack(spacing: MappingRowLayout.columnSpacing) {
            Picker("", selection: $mapping.kind) {
                Text("Note").tag(MIDIMessageKind.noteOn)
                Text("CC").tag(MIDIMessageKind.controlChange)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: MappingRowLayout.typeColumnWidth, alignment: .leading)

            HStack(spacing: 8) {
                MIDIValueStepper(value: noteBinding, range: 0...127)
                Text(mapping.noteLabel)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: MappingRowLayout.noteColumnWidth, alignment: .leading)

            MIDIValueStepper(value: velocityBinding, range: 0...127)
                .frame(width: MappingRowLayout.valueColumnWidth, alignment: .leading)

            HStack(spacing: 8) {
                if isLearning {
                    Button("Cancel", action: onCancelLearn)
                        .keyboardShortcut(.cancelAction)
                } else {
                    Button("Learn", action: onLearn)
                }

                Button("Reset") {
                    mapping = defaultMapping
                }
                .disabled(mapping == defaultMapping)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isLearning ? Color.accentColor : Color.clear, lineWidth: 2)
        }
    }

    private var rowBackground: Color {
        isLearning ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.03)
    }

    private var noteBinding: Binding<Int> {
        Binding(
            get: { Int(mapping.note) },
            set: { mapping.note = UInt8(clamping: $0) }
        )
    }

    private var velocityBinding: Binding<Int> {
        Binding(
            get: { Int(mapping.velocity) },
            set: { mapping.velocity = UInt8(clamping: $0) }
        )
    }
}

private extension Text {
    func mappingColumnLabel() -> some View {
        font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

private struct MIDIValueStepper: NSViewRepresentable {
    @Binding var value: Int
    let range: ClosedRange<Int>

    func makeNSView(context: Context) -> NSStackView {
        let field = makeField(coordinator: context.coordinator)
        let stepper = makeStepper(coordinator: context.coordinator)

        let stack = NSStackView(views: [field, stepper])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        stack.setHuggingPriority(.required, for: .vertical)
        stack.setContentHuggingPriority(.required, for: .vertical)

        context.coordinator.field = field
        context.coordinator.stepper = stepper

        sync(value: value, field: field, stepper: stepper)
        return stack
    }

    func updateNSView(_ stack: NSStackView, context: Context) {
        guard let field = context.coordinator.field,
              let stepper = context.coordinator.stepper else { return }
        sync(value: value, field: field, stepper: stepper)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private func makeField(coordinator: Coordinator) -> NSTextField {
        let field = NSTextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.isBordered = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.controlSize = .small
        field.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        field.alignment = .right
        field.delegate = coordinator
        field.widthAnchor.constraint(equalToConstant: 48).isActive = true
        return field
    }

    private func makeStepper(coordinator: Coordinator) -> NSStepper {
        let stepper = NSStepper()
        stepper.translatesAutoresizingMaskIntoConstraints = false
        stepper.controlSize = .small
        stepper.minValue = Double(range.lowerBound)
        stepper.maxValue = Double(range.upperBound)
        stepper.target = coordinator
        stepper.action = #selector(Coordinator.stepperChanged(_:))
        return stepper
    }

    private func sync(value: Int, field: NSTextField, stepper: NSStepper) {
        let clamped = min(range.upperBound, max(range.lowerBound, value))
        if field.integerValue != clamped {
            field.integerValue = clamped
        }
        if stepper.integerValue != clamped {
            stepper.integerValue = clamped
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: MIDIValueStepper
        weak var field: NSTextField?
        weak var stepper: NSStepper?

        init(parent: MIDIValueStepper) {
            self.parent = parent
        }

        @objc func stepperChanged(_ sender: NSStepper) {
            let clamped = min(parent.range.upperBound, max(parent.range.lowerBound, sender.integerValue))
            parent.value = clamped
            field?.integerValue = clamped
            sender.integerValue = clamped
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            commit(from: obj.object as? NSTextField)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                commit(from: control as? NSTextField)
                control.window?.makeFirstResponder(nil)
                return true
            }
            return false
        }

        private func commit(from field: NSTextField?) {
            guard let field else { return }
            let clamped = min(parent.range.upperBound, max(parent.range.lowerBound, field.integerValue))
            parent.value = clamped
            field.integerValue = clamped
            stepper?.integerValue = clamped
        }
    }
}
