import SwiftUI

struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case devices
        case learn
        case test
    }

    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var midiManager: MIDIManager
    var onTestBlink: () -> Void
    var onFinished: () -> Void

    @State private var step: Step = .devices

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("MIDI Tap Tempo Indicator")
                .font(.title2.weight(.semibold))
            Text(stepSubtitle)
                .foregroundStyle(.secondary)

            Group {
                switch step {
                case .devices:
                    devicesStep
                case .learn:
                    learnStep
                case .test:
                    testStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack {
                Button("Skip") {
                    onFinished()
                }
                Spacer()
                if step != .devices {
                    Button("Back") {
                        if let previous = Step(rawValue: step.rawValue - 1) {
                            step = previous
                        }
                    }
                }
                Button(primaryButtonTitle) {
                    advance()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560, height: 420)
    }

    private var stepSubtitle: String {
        switch step {
        case .devices: return "Step 1 of 3 — Choose your MIDI input and output."
        case .learn: return "Step 2 of 3 — Learn the tap tempo button."
        case .test: return "Step 3 of 3 — Verify LED control with a test blink."
        }
    }

    private var primaryButtonTitle: String {
        step == .test ? "Done" : "Continue"
    }

    private var devicesStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Input", selection: selectedSourceBinding) {
                if midiManager.sources.isEmpty {
                    Text("No devices found").tag(Optional<Int32>.none)
                }
                ForEach(midiManager.sources) { source in
                    Text(source.name).tag(Optional(source.uniqueID))
                }
            }
            Picker("Output", selection: selectedDestinationBinding) {
                if midiManager.destinations.isEmpty {
                    Text("No devices found").tag(Optional<Int32>.none)
                }
                ForEach(midiManager.destinations) { destination in
                    Text(destination.name).tag(Optional(destination.uniqueID))
                }
            }
            HStack {
                Button("Use same device for input & output") {
                    settingsStore.useSameDeviceForInputAndOutput(
                        sources: midiManager.sources,
                        destinations: midiManager.destinations
                    )
                }
                Button("Refresh") {
                    midiManager.refreshEndpoints()
                }
            }
        }
    }

    private var learnStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current tap mapping: \(settingsStore.tapInput.summaryLabel)")
            if midiManager.learningTarget == .tapInput {
                Text(midiManager.lastLearnedMessage ?? "Listening…")
                    .foregroundStyle(.secondary)
                Button("Cancel Learn") {
                    midiManager.cancelLearning()
                }
            } else {
                Button("Learn Tap Button") {
                    midiManager.beginLearning(.tapInput)
                }
            }
        }
    }

    private var testStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Send a short blink pattern to the mapped LED output(s). Your controller must allow external LED control.")
                .foregroundStyle(.secondary)
            Button("Test Blink") {
                onTestBlink()
            }
        }
    }

    private func advance() {
        if step == .test {
            onFinished()
            return
        }
        if let next = Step(rawValue: step.rawValue + 1) {
            step = next
        }
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
