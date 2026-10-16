import ServiceManagement
import SwiftUI

/// The login item can also be switched off in System Settings, so the status is read again whenever Settings shows it.
@MainActor final class LoginItem: ObservableObject {
    @Published private(set) var status = SMAppService.mainApp.status
    @Published private(set) var failure: String?
    /// The demo never registers the copy it runs from.
    private let active: Bool

    init(active: Bool) { self.active = active }

    var enabled: Bool { status == .enabled || status == .requiresApproval }
    var detail: String {
        if let failure { return failure }
        if status == .requiresApproval { return String(localized: "Allow Stowia in System Settings › General › Login Items.") }
        return String(localized: "Starts Stowia in the menu bar when you log in.")
    }

    func refresh() { status = SMAppService.mainApp.status }

    func set(_ enabled: Bool) {
        guard active else { return }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            failure = nil
        } catch {
            failure = String(localized: "macOS did not change the login item: \(error.localizedDescription)")
        }
        refresh()
    }
}
