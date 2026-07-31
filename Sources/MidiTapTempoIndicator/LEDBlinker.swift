import Foundation

final class LEDBlinker {
    var onSendLED: ((UInt8) -> Void)?
    var isControllerActive: (() -> Bool)?

    private var bpm: Double?
    private var enabled = true
    private var ledOnValue: UInt8 = SettingsStore.defaultLEDOnValue
    private var ledOffValue: UInt8 = SettingsStore.defaultLEDOffValue
    private var isLit = false
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.newdaynaz.miditaptempoindicator.led", qos: .userInteractive)

    func configure(enabled: Bool, ledOnValue: UInt8, ledOffValue: UInt8) {
        queue.async { [weak self] in
            guard let self else { return }
            self.enabled = enabled
            self.ledOnValue = ledOnValue
            self.ledOffValue = ledOffValue
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

    /// Called periodically or on activity changes to stop blink when controller is idle.
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

    private func restartTimerLocked() {
        stopLocked(turnOff: false)

        guard enabled,
              let bpm,
              bpm > 0,
              isControllerActive?() ?? false else {
            if enabled == false || bpm == nil {
                sendLocked(ledOffValue)
                isLit = false
            }
            return
        }

        let interval = 60.0 / bpm / 2.0
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.tickLocked()
        }
        timer.resume()
        self.timer = timer
    }

    private func tickLocked() {
        guard enabled, bpm != nil else {
            stopLocked(turnOff: true)
            return
        }

        if !(isControllerActive?() ?? false) {
            stopLocked(turnOff: true)
            return
        }

        isLit.toggle()
        sendLocked(isLit ? ledOnValue : ledOffValue)
    }

    private func stopLocked(turnOff: Bool) {
        timer?.cancel()
        timer = nil
        if turnOff {
            sendLocked(ledOffValue)
            isLit = false
        }
    }

    private func sendLocked(_ value: UInt8) {
        DispatchQueue.main.async { [weak self] in
            self?.onSendLED?(value)
        }
    }
}
