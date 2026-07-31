import Cocoa
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    let settingsStore = SettingsStore()
    let activityMonitor = ControllerActivityMonitor()
    let tempoState = TempoState()
    private(set) lazy var midiManager = MIDIManager(settingsStore: settingsStore)
    private let ledBlinker = LEDBlinker()
    private var tapEngine = TapTempoEngine()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        configureEngines()
        wireMIDI()
        midiManager.start()
        observeSettings()
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
        } else {
            statusItem?.button?.image = NSImage(
                systemSymbolName: "metronome",
                accessibilityDescription: "MIDI Tap Tempo Indicator"
            )
        }
        statusItem?.menu = buildMenu()
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
            guard let self else { return }
            let mapping = self.settingsStore.tapMapping
            guard mapping.kind == .controlChange || mapping.kind == .noteOn else { return }
            // Many controllers drive button LEDs with the same CC number as the button.
            let controller = mapping.note
            self.midiManager.sendControlChange(
                controller: controller,
                value: value,
                channel: UInt8(clamping: self.settingsStore.midiChannel)
            )
        }
        ledBlinker.configure(
            enabled: settingsStore.blinkEnabled,
            ledOnValue: UInt8(clamping: settingsStore.ledOnValue),
            ledOffValue: UInt8(clamping: settingsStore.ledOffValue)
        )
    }

    private func wireMIDI() {
        midiManager.onControllerActivity = { [weak self] in
            guard let self else { return }
            self.activityMonitor.noteActivity()
            self.ledBlinker.evaluateActivity()
            if let bpm = self.tempoState.currentBPM ?? self.tapEngine.currentBPM {
                self.ledBlinker.setBPM(bpm)
            }
        }

        midiManager.onTapPress = { [weak self] in
            guard let self else { return }
            self.activityMonitor.noteActivity()
            let bpm = self.tapEngine.registerTap()
            self.tempoState.currentBPM = bpm
            self.updateMenuBPM()
            if let bpm {
                self.ledBlinker.setBPM(bpm)
            }
            self.ledBlinker.evaluateActivity()
        }
    }

    private func observeSettings() {
        settingsStore.$minBPM
            .combineLatest(settingsStore.$maxBPM)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] minBPM, maxBPM in
                self?.tapEngine.updateLimits(minBPM: minBPM, maxBPM: maxBPM)
            }
            .store(in: &cancellables)

        settingsStore.$controllerIdleTimeout
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.activityMonitor.updateTimeout(self.settingsStore.controllerIdleTimeoutSeconds)
                self.ledBlinker.evaluateActivity()
            }
            .store(in: &cancellables)

        settingsStore.$blinkEnabled
            .combineLatest(settingsStore.$ledOnValue, settingsStore.$ledOffValue)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled, onValue, offValue in
                self?.ledBlinker.configure(
                    enabled: enabled,
                    ledOnValue: UInt8(clamping: onValue),
                    ledOffValue: UInt8(clamping: offValue)
                )
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
            }
            .store(in: &cancellables)
    }

    private func updateMenuBPM() {
        guard let bpmItem = statusItem?.menu?.item(withTag: 100) else { return }
        if let bpm = tempoState.currentBPM {
            bpmItem.title = String(format: "BPM: %.1f", bpm)
        } else {
            bpmItem.title = "BPM: —"
        }
    }

    @objc private func openSettings() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView(
            settingsStore: settingsStore,
            midiManager: midiManager,
            activityMonitor: activityMonitor,
            tempoState: tempoState
        )
        let hostingController = NSHostingController(rootView: view)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MIDI Tap Tempo Indicator"
        window.contentViewController = hostingController
        window.toolbarStyle = .unifiedCompact
        window.titlebarAppearsTransparent = true
        window.setContentSize(NSSize(width: 760, height: 680))
        window.minSize = NSSize(width: 700, height: 600)
        window.setFrameAutosaveName("MidiTapTempoIndicatorSettings")
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        settingsWindow = window
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
