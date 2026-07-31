import Combine
import Foundation

final class ControllerActivityMonitor: ObservableObject {
    @Published private(set) var lastActivityDate: Date?
    @Published private(set) var isActive = false

    private var timeout: TimeInterval
    private var timer: Timer?

    init(timeout: TimeInterval = SettingsStore.defaultControllerIdleTimeout * 60.0) {
        self.timeout = timeout
    }

    func updateTimeout(_ timeout: TimeInterval) {
        self.timeout = timeout
        refreshActiveState()
    }

    func noteActivity(at date: Date = Date()) {
        lastActivityDate = date
        refreshActiveState()
        restartTimer()
    }

    func isActive(at date: Date = Date()) -> Bool {
        guard let lastActivityDate else { return false }
        return date.timeIntervalSince(lastActivityDate) <= timeout
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func restartTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.refreshActiveState()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func refreshActiveState() {
        let active = isActive()
        if active != isActive {
            isActive = active
        }
        if !active {
            timer?.invalidate()
            timer = nil
        }
    }
}
