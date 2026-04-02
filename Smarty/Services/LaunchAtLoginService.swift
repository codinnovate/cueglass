import Foundation
import ServiceManagement

protocol LaunchAtLoginServing: Sendable {
    func setEnabled(_ enabled: Bool) throws
    func isEnabled() -> Bool
}

struct LaunchAtLoginService: LaunchAtLoginServing {
    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    func isEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }
}
