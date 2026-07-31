import Foundation
import ServiceManagement

enum LaunchAtLogin {
    static var isSupported: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var statusMessage: String? {
        switch SMAppService.mainApp.status {
        case .requiresApproval:
            return "Approve MIDI Tap Tempo Indicator in System Settings → General → Login Items."
        case .notFound:
            return "Launch at login requires installing the app as a macOS application."
        case .enabled, .notRegistered:
            return nil
        @unknown default:
            return nil
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
