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
    private var service: SMAppService { .mainApp }

    private var legacyHelperService: SMAppService? {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return nil }
        return .loginItem(identifier: bundleIdentifier + ".Helper")
    }

    public init() {}

    /// Login items need a stable app location. A build launched from Xcode or a
    /// mounted disk image must not become the persisted login target.
    public var isInstalledInApplications: Bool {
        let path = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        return path.hasPrefix("/Applications/") || path.hasPrefix("/System/Applications/")
    }

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
            if service.status == .notRegistered || service.status == .notFound {
                try service.register()
            }
            try unregisterLegacyHelperIfNeeded()
        } else {
            if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            }
            try unregisterLegacyHelperIfNeeded()
        }
    }

    /// v1.0.1 registered an embedded helper. Preserve that opt-in while moving
    /// it to the main app so Momiji appears in System Settings > Login Items and
    /// can reapply the cursor theme itself after login.
    @discardableResult
    public func migrateLegacyHelperRegistrationIfNeeded() throws -> Bool {
        guard isInstalledInApplications,
              let legacyHelperService,
              legacyHelperService.status == .enabled || legacyHelperService.status == .requiresApproval else {
            return false
        }

        if service.status == .notRegistered || service.status == .notFound {
            try service.register()
        }
        guard service.status == .enabled || service.status == .requiresApproval else { return false }
        try unregisterLegacyHelperIfNeeded()
        return true
    }

    public func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func unregisterLegacyHelperIfNeeded() throws {
        guard let legacyHelperService,
              legacyHelperService.status == .enabled || legacyHelperService.status == .requiresApproval else {
            return
        }
        try legacyHelperService.unregister()
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
