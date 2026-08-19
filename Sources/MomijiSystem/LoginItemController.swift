import Foundation
import ServiceManagement

public enum MomijiLoginItemStatus: Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

@MainActor
public final class MomijiLoginItemController {
    public static let helperIdentifier = "app.momiji.Momiji.Helper"

    private var service: SMAppService { .loginItem(identifier: Self.helperIdentifier) }

    public init() {}

    public var status: MomijiLoginItemStatus {
        switch service.status {
        case .notRegistered: .notRegistered
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        @unknown default: .notFound
        }
    }

    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try service.register()
        } else {
            try service.unregister()
        }
    }

    public func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

public enum MomijiNotifications {
    public static let activeThemeChanged = Notification.Name("app.momiji.active-theme-changed")

    public static func postActiveThemeChanged() {
        DistributedNotificationCenter.default().postNotificationName(
            activeThemeChanged,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }
}
