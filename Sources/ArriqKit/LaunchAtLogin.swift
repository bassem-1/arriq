import Foundation
import ServiceManagement

/// login item through SMAppService.mainApp
public enum LaunchAtLogin {
    public static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// nil on success, else a lower-case reason
    public static func set(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return error.localizedDescription.lowercased()
        }
    }
}
