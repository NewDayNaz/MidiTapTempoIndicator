import Foundation

final class LEDBlinker {
    var onSendLED: ((UInt8) -> Void)?
    /// Called on the main queue whenever the blink phase changes (`true` = LED on / beat).
    var onPhaseChange: ((Bool) -> Void)?
    var isControllerActive: (() -> Bool)?

    private var bpm: Double?
    private var enabled = true
    private var subdivision: BeatSubdivision = .quarter
    private var ledOnValue: UInt8 = SettingsStore.defaultLEDOnValue
    private var ledOffValue: UInt8 = SettingsStore.defaultLEDOffValue
    private var isLit = false
    private var beatCounter = 0
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.newdaynaz.miditaptempoindicator.led", qos: .userInteractive)

    func configure(
        enabled: Bool,
        ledOnValue: UInt8,
        ledOffValue: UInt8,
        subdivision: BeatSubdivision
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            self.enabled = enabled
            self.ledOnValue = ledOnValue
            self.ledOffValue = ledOffValue
            self.subdivision = subdivision
            if !enabled {
                self.stopLocked(turnOff: true)
            } else {
                self.restartTimerLocked()
            }
        }
    }

    func setBPM(_ bpm: Double?) {
        queue.async { [weak self] in
            guard let self else { return }
            self.bpm = bpm
            self.restartTimerLocked()
        }
    }

    func stop(turnOff: Bool = true) {
        queue.async { [weak self] in
            self?.stopLocked(turnOff: turnOff)
        }
    }

    func evaluateActivity() {
        queue.async { [weak self] in
            guard let self else { return }
            let active = self.isControllerActive?() ?? false
            if !active {
                self.stopLocked(turnOff: true)
            } else if self.timer == nil, self.enabled, self.bpm != nil {
                self.restartTimerLocked()
            }
        }
    }

    /// Pulse all LEDs a few times for hardware verification.
    func runTestBlink(cycles: Int = 3, halfPeriod: TimeInterval = 0.12) {
        queue.async { [weak self] in
            guard let self else { return }
            self.stopLocked(turnOff: false)
            for cycle in 0..<(cycles * 2) {
                let value = cycle % 2 == 0 ? self.ledOnValue : self.ledOffValue
                let delay = halfPeriod * Double(cycle)
                self.queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.sendLocked(value)
                }
            }
            let finishDelay = halfPeriod * Double(cycles * 2)
            self.queue.asyncAfter(deadline: .now() + finishDelay) { [weak self] in
                guard let self else { return }
                self.sendLocked(self.ledOffValue)
                self.restartTimerLocked()
            }
        }
    }

    private func restartTimerLocked() {
        stopLocked(turnOff: false)
        beatCounter = 0

        guard enabled,
              let bpm,
              bpm > 0,
              isControllerActive?() ?? false else {
            if enabled == false || bpm == nil {
                sendLocked(ledOffValue)
            }
            return
        }

        let interval = subdivision.timerInterval(bpm: bpm)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.tickLocked()
        }
        timer.resume()
        self.timer = timer
    }

    private func tickLocked() {
        guard enabled, let bpm, bpm > 0 else {
            stopLocked(turnOff: true)
            return
        }

        if !(isControllerActive?() ?? false) {
            stopLocked(turnOff: true)
            return
        }

        switch subdivision {
        case .quarter, .eighth:
            let nextLit = !isLit
            sendLocked(nextLit ? ledOnValue : ledOffValue)
        case .downbeat:
            // One short on-pulse at the start of each 4-beat bar; off for the other beats.
            if beatCounter % 4 == 0 {
                sendLocked(ledOnValue)
                let offDelay = min(0.08, subdivision.timerInterval(bpm: bpm) * 0.35)
                queue.asyncAfter(deadline: .now() + offDelay) { [weak self] in
                    self?.sendLocked(self?.ledOffValue ?? 0)
                }
            } else {
                sendLocked(ledOffValue)
            }
            beatCounter += 1
        }
    }

    private func stopLocked(turnOff: Bool) {
        timer?.cancel()
        timer = nil
        if turnOff {
            sendLocked(ledOffValue)
            beatCounter = 0
        }
    }

    private func sendLocked(_ value: UInt8) {
        let lit: Bool
        if ledOnValue == ledOffValue {
            lit = value > 0
        } else {
            lit = value == ledOnValue
        }
        isLit = lit

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onSendLED?(value)
            self.onPhaseChange?(lit)
        }
    }
}
