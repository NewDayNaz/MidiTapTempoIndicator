import Cocoa
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    let settingsStore = SettingsStore()
    let activityMonitor = ControllerActivityMonitor()
    let tempoState = TempoState()
    private(set) lazy var midiManager = MIDIManager(settingsStore: settingsStore)
    private let ledBlinker = LEDBlinker()
    private var tapEngine = TapTempoEngine()
    /// Mirrors LED blink phase for menu-bar BPM coloring.
    private var blinkPhaseLit = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        tempoState.currentBPM = settingsStore.lastBPM
        setupStatusItem()
        configureEngines()
        wireMIDI()
        midiManager.start()
        observeSettings()
        updateMenuBarStatus()
        if !settingsStore.hasCompletedOnboarding {
            DispatchQueue.main.async { [weak self] in
                self?.openOnboarding()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ledBlinker.stop(turnOff: true)
        activityMonitor.stop()
        midiManager.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let image = Self.loadMenuBarIcon() {
            statusItem?.button?.image = image
            statusItem?.button?.imagePosition = .imageLeading
        } else {
            statusItem?.button?.image = NSImage(
                systemSymbolName: "metronome",
                accessibilityDescription: "MIDI Tap Tempo Indicator"
            )
            statusItem?.button?.imagePosition = .imageLeading
        }
        statusItem?.menu = buildMenu()
        updateMenuBarStatus()
    }

    private static func loadMenuBarIcon() -> NSImage? {
        for name in ["MenuBarIcon@2x", "MenuBarIcon"] {
            for url in menuBarIconCandidateURLs(named: name) {
                guard let data = try? Data(contentsOf: url),
                      let rep = NSBitmapImageRep(data: data) else { continue }

                let image = NSImage(size: NSSize(width: 18, height: 18))
                rep.size = NSSize(width: 18, height: 18)
                image.addRepresentation(rep)
                image.isTemplate = true
                return image
            }
        }
        return nil
    }

    private static func menuBarIconCandidateURLs(named name: String) -> [URL] {
        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let executableDirectory = executableURL.deletingLastPathComponent()

        return [
            Bundle.main.resourceURL?.appendingPathComponent(name).appendingPathExtension("png"),
            executableDirectory.appendingPathComponent("Resources").appendingPathComponent(name).appendingPathExtension("png"),
            executableDirectory
                .appendingPathComponent("MidiTapTempoIndicator_MidiTapTempoIndicator.bundle")
                .appendingPathComponent(name)
                .appendingPathExtension("png"),
        ].compactMap { $0 }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let bpmItem = NSMenuItem(title: "BPM: —", action: nil, keyEquivalent: "")
        bpmItem.tag = 100
        menu.addItem(bpmItem)

        let plusItem = NSMenuItem(title: "BPM +1", action: #selector(nudgeBPMUp), keyEquivalent: "")
        plusItem.target = self
        menu.addItem(plusItem)

        let minusItem = NSMenuItem(title: "BPM −1", action: #selector(nudgeBPMDown), keyEquivalent: "")
        minusItem.target = self
        menu.addItem(minusItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func configureEngines() {
        tapEngine = TapTempoEngine(minBPM: settingsStore.minBPM, maxBPM: settingsStore.maxBPM)
        activityMonitor.updateTimeout(settingsStore.controllerIdleTimeoutSeconds)

        ledBlinker.isControllerActive = { [weak self] in
            self?.activityMonitor.isActive() ?? false
        }
        ledBlinker.onSendLED = { [weak self] value in
            self?.midiManager.sendLEDValue(value)
        }
        ledBlinker.onPhaseChange = { [weak self] lit in
            guard let self else { return }
            self.blinkPhaseLit = lit
            self.updateMenuBarStatus()
        }
        applyBlinkerConfiguration()
    }

    private func applyBlinkerConfiguration() {
        ledBlinker.configure(
            enabled: settingsStore.blinkEnabled,
            ledOnValue: UInt8(clamping: settingsStore.ledOnValue),
            ledOffValue: UInt8(clamping: settingsStore.ledOffValue),
            subdivision: settingsStore.beatSubdivision
        )
    }

    private func wireMIDI() {
        midiManager.onControllerActivity = { [weak self] in
            guard let self else { return }
            self.activityMonitor.noteActivity()
            self.ledBlinker.evaluateActivity()
            if let bpm = self.tempoState.currentBPM ?? self.tapEngine.currentBPM ?? self.settingsStore.lastBPM {
                self.ledBlinker.setBPM(bpm)
            }
            self.updateMenuBarStatus()
        }

        midiManager.onTapPress = { [weak self] in
            guard let self else { return }
            self.activityMonitor.noteActivity()
            if let bpm = self.tapEngine.registerTap() {
                self.applyBPM(bpm)
            }
            self.ledBlinker.evaluateActivity()
            self.updateMenuBarStatus()
        }

        midiManager.onTempoReset = { [weak self] in
            self?.clearKnownTempo()
        }
    }

    private func observeSettings() {
        settingsStore.$minBPM
            .combineLatest(settingsStore.$maxBPM)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] minBPM, maxBPM in
                guard let self else { return }
                self.tapEngine.updateLimits(minBPM: minBPM, maxBPM: maxBPM)
                if let bpm = self.tempoState.currentBPM {
                    self.applyBPM(bpm)
                }
            }
            .store(in: &cancellables)

        settingsStore.$controllerIdleTimeout
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.activityMonitor.updateTimeout(self.settingsStore.controllerIdleTimeoutSeconds)
                self.ledBlinker.evaluateActivity()
                self.updateMenuBarStatus()
            }
            .store(in: &cancellables)

        settingsStore.$blinkEnabled
            .combineLatest(settingsStore.$ledOnValue, settingsStore.$ledOffValue, settingsStore.$beatSubdivision)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _, _ in
                self?.applyBlinkerConfiguration()
            }
            .store(in: &cancellables)

        activityMonitor.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] active in
                guard let self else { return }
                if active {
                    self.ledBlinker.evaluateActivity()
                } else {
                    self.ledBlinker.stop(turnOff: true)
                }
                self.updateMenuBarStatus()
            }
            .store(in: &cancellables)

        midiManager.$inputConnected
            .combineLatest(midiManager.$outputConnected, midiManager.$deviceWarningMessage)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _ in
                self?.updateMenuBarStatus()
            }
            .store(in: &cancellables)

        tempoState.$currentBPM
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateMenuBarStatus()
            }
            .store(in: &cancellables)
    }

    private func applyBPM(_ bpm: Double) {
        let clamped = SettingsStore.clampBPM(bpm)
        tempoState.currentBPM = clamped
        settingsStore.lastBPM = clamped
        ledBlinker.setBPM(clamped)
        updateMenuBarStatus()
    }

    /// Temp becomes unknown (e.g. host preset change). Stop blinking until the user taps again.
    private func clearKnownTempo() {
        activityMonitor.noteActivity()
        tapEngine.reset()
        tempoState.currentBPM = nil
        settingsStore.lastBPM = nil
        blinkPhaseLit = false
        ledBlinker.setBPM(nil)
        ledBlinker.stop(turnOff: true)
        updateMenuBarStatus()
    }

    func nudgeBPM(by delta: Double) {
        tempoState.adjustBPM(by: delta, minBPM: settingsStore.minBPM, maxBPM: settingsStore.maxBPM)
        if let bpm = tempoState.currentBPM {
            settingsStore.lastBPM = bpm
            ledBlinker.setBPM(bpm)
            if activityMonitor.isActive() {
                ledBlinker.evaluateActivity()
            }
        }
        updateMenuBarStatus()
    }

    func runTestBlink() {
        ledBlinker.runTestBlink()
    }

    private func updateMenuBarStatus() {
        guard let button = statusItem?.button else { return }

        let warning = midiManager.deviceWarningMessage != nil
        let active = activityMonitor.isActive
        let bpm = tempoState.currentBPM
        let pulsing = active && !warning && bpm != nil && settingsStore.blinkEnabled

        let text: String
        if let bpm {
            let prefix = warning ? "⚠ " : ""
            text = String(format: "%@%.1f", prefix, bpm)
        } else {
            text = warning ? "⚠ —" : "—"
        }

        let color: NSColor
        if warning {
            color = .systemOrange
        } else if pulsing, blinkPhaseLit {
            color = .controlAccentColor
        } else if active, bpm != nil {
            color = .labelColor
        } else {
            color = .secondaryLabelColor
        }

        let font = NSFont.menuBarFont(ofSize: 0)
        button.attributedTitle = NSAttributedString(
            string: text,
            attributes: [
                .foregroundColor: color,
                .font: font,
            ]
        )

        // Mild dim when idle; on the beat, fully opaque for a clear pulse.
        button.appearsDisabled = false
        if !active || warning {
            button.alphaValue = 0.78
        } else if pulsing {
            button.alphaValue = blinkPhaseLit ? 1.0 : 0.88
        } else {
            button.alphaValue = 1.0
        }

        if let bpmItem = statusItem?.menu?.item(withTag: 100) {
            if let bpm {
                bpmItem.title = String(format: "BPM: %.1f", bpm)
            } else {
                bpmItem.title = "BPM: —"
            }
        }
    }

    @objc private func nudgeBPMUp() {
        nudgeBPM(by: 1)
    }

    @objc private func nudgeBPMDown() {
        nudgeBPM(by: -1)
    }

    @objc func openSettings() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView(
            settingsStore: settingsStore,
            midiManager: midiManager,
            activityMonitor: activityMonitor,
            tempoState: tempoState,
            onNudgeBPM: { [weak self] delta in self?.nudgeBPM(by: delta) },
            onSetBPM: { [weak self] bpm in self?.applyBPM(bpm) },
            onTestBlink: { [weak self] in self?.runTestBlink() }
        )
        let hostingController = NSHostingController(rootView: view)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 740),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MIDI Tap Tempo Indicator"
        window.contentViewController = hostingController
        window.toolbarStyle = .unifiedCompact
        window.titlebarAppearsTransparent = true
        window.setContentSize(NSSize(width: 820, height: 740))
        window.minSize = NSSize(width: 760, height: 640)
        window.setFrameAutosaveName("MidiTapTempoIndicatorSettings")
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        settingsWindow = window
    }

    private func openOnboarding() {
        if onboardingWindow != nil { return }

        let view = OnboardingView(
            settingsStore: settingsStore,
            midiManager: midiManager,
            onTestBlink: { [weak self] in self?.runTestBlink() },
            onFinished: { [weak self] in
                self?.settingsStore.hasCompletedOnboarding = true
                self?.onboardingWindow?.close()
                self?.onboardingWindow = nil
            }
        )
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome"
        window.contentViewController = hostingController
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
