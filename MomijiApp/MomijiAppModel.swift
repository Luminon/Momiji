import AppKit
import Foundation
import MomijiCore
import MomijiSystem
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class MomijiAppModel {
    var themes: [CursorTheme] = []
    var selectedThemeID: UUID?
    var importResult: ThemeImportResult?
    var isShowingImportReview = false
    var isShowingSettings = false
    var errorMessage: String?
    var statusMessage: String?
    var loginItemStatus: MomijiLoginItemStatus = .notRegistered
    var cursorScale: Double = CursorScale.default
    var isDockIconHidden: Bool = false

    @ObservationIgnored private let importer = WindowsThemeImporter()
    @ObservationIgnored private let engine: any SystemCursorApplying
    @ObservationIgnored private let loginItem = MomijiLoginItemController()
    @ObservationIgnored private var store: MomijiThemeStore?
    @ObservationIgnored private var applicationCoordinator: CursorApplicationCoordinator?

    init() {
        isDockIconHidden = UserDefaults.standard.bool(forKey: MomijiPreferenceKey.hideDockIcon)
        if ProcessInfo.processInfo.environment["MOMIJI_UI_TEST_MOCK_SYSTEM"] == "1" {
            engine = UITestSystemCursorEngine()
        } else {
            engine = PrivateSystemCursorEngine()
        }
        do {
            let themeStore: MomijiThemeStore
            if let testRoot = ProcessInfo.processInfo.environment["MOMIJI_LIBRARY_ROOT"] {
                themeStore = MomijiThemeStore(rootURL: URL(fileURLWithPath: testRoot, isDirectory: true))
            } else {
                themeStore = try MomijiThemeStore.makeDefault()
            }
            store = themeStore
            cursorScale = (try? themeStore.preferredCursorScale()) ?? CursorScale.default
            applicationCoordinator = CursorApplicationCoordinator(store: themeStore, engine: engine)
            refreshLibrary()
        } catch {
            errorMessage = error.localizedDescription
        }
        loginItemStatus = loginItem.status
        if let fixture = ProcessInfo.processInfo.environment["MOMIJI_UI_TEST_FIXTURE"] {
            importThemeFolder(URL(fileURLWithPath: fixture, isDirectory: true))
        }
    }

    var systemAvailability: SystemCursorAvailability { engine.availability }
    var canConfigureLoginItem: Bool { loginItem.isInstalledInApplications }

    var selectedTheme: CursorTheme? {
        guard let selectedThemeID else { return nil }
        return themes.first { $0.id == selectedThemeID }
    }

    func refreshLibrary(select id: UUID? = nil) {
        guard let store else { return }
        do {
            themes = try store.listThemes()
            selectedThemeID = id ?? selectedThemeID ?? themes.first?.id
            if selectedThemeID.flatMap({ selected in themes.contains { $0.id == selected } }) != true {
                selectedThemeID = themes.first?.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func chooseThemeFolder() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "panel.importFolder.title")
        panel.prompt = String(localized: "panel.import")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importThemeFolder(url)
    }

    func choosePackage() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "panel.importPackage.title")
        panel.prompt = String(localized: "panel.import")
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if let type = UTType(filenameExtension: MomijiThemeStore.packageExtension) {
            panel.allowedContentTypes = [type]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importPackage(url)
    }

    func handleDroppedURLs(_ urls: [URL]) -> Bool {
        guard let url = urls.first else { return false }
        if url.pathExtension.lowercased() == MomijiThemeStore.packageExtension {
            importPackage(url)
        } else {
            importThemeFolder(url)
        }
        return true
    }

    func importThemeFolder(_ url: URL) {
        do {
            importResult = try importer.importTheme(at: url)
            isShowingImportReview = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importPackage(_ url: URL) {
        guard let store else { return }
        do {
            let theme = try store.importPackage(at: url)
            refreshLibrary(select: theme.id)
            statusMessage = String(localized: "status.packageImported")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateImportRole(itemID: UUID, role: CursorRole?) {
        guard var result = importResult,
              let index = result.items.firstIndex(where: { $0.id == itemID }) else { return }
        result.items[index].role = role
        if let role { result.items[index].asset?.role = role }
        importResult = result
    }

    func updateImportAsset(itemID: UUID, asset: CursorAsset) {
        guard var result = importResult,
              let index = result.items.firstIndex(where: { $0.id == itemID }) else { return }
        let isEnabled = result.items[index].role != nil
        result.items[index].asset = asset
        if isEnabled { result.items[index].role = asset.role }
        importResult = result
    }

    func saveImport(apply: Bool) {
        guard let store, let result = importResult else { return }
        do {
            let theme = try result.makeTheme()
            _ = try store.save(theme)
            if apply { try applyTheme(theme) }
            isShowingImportReview = false
            importResult = nil
            refreshLibrary(select: theme.id)
            statusMessage = String(localized: apply ? "status.savedAndApplied" : "status.saved")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveEditedTheme(_ theme: CursorTheme) {
        guard let store else { return }
        do {
            _ = try store.save(theme)
            refreshLibrary(select: theme.id)
            statusMessage = String(localized: "status.saved")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applySelectedTheme() {
        guard let theme = selectedTheme else { return }
        do {
            try applyTheme(theme)
            statusMessage = String(localized: "status.applied")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restoreDefaults() {
        guard let applicationCoordinator else { return }
        do {
            try applicationCoordinator.restoreDefaults()
            MomijiNotifications.postActiveThemeChanged()
            statusMessage = String(localized: "status.restored")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteSelectedTheme() {
        guard let store, let id = selectedThemeID else { return }
        do {
            if try store.activeThemeID() == id {
                try applicationCoordinator?.restoreDefaults()
                MomijiNotifications.postActiveThemeChanged()
            }
            try store.deleteTheme(id: id)
            refreshLibrary()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportSelectedTheme() {
        guard let store, let theme = selectedTheme else { return }
        let panel = NSSavePanel()
        panel.title = String(localized: "panel.export.title")
        panel.prompt = String(localized: "panel.export")
        panel.nameFieldStringValue = safeFileName(theme.name) + ".momiji"
        if let type = UTType(filenameExtension: MomijiThemeStore.packageExtension) {
            panel.allowedContentTypes = [type]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try store.exportTheme(id: theme.id, to: url)
            statusMessage = String(localized: "status.exported")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setLoginItemEnabled(_ enabled: Bool) {
        guard !enabled || loginItem.isInstalledInApplications else {
            errorMessage = String(localized: "error.loginItemRequiresApplicationsFolder")
            return
        }
        do {
            try loginItem.setEnabled(enabled)
            loginItemStatus = loginItem.status
            if enabled, loginItemStatus == .requiresApproval {
                loginItem.openSystemSettings()
            }
            statusMessage = String(localized: enabled ? "status.loginItemEnabled" : "status.loginItemDisabled")
        } catch {
            errorMessage = error.localizedDescription
            loginItemStatus = loginItem.status
        }
    }

    func refreshLoginItemStatus() {
        loginItemStatus = loginItem.status
    }

    func setCursorScale(_ value: Double) {
        let scale = CursorScale.clamped(value)
        cursorScale = scale
        do {
            try store?.setPreferredCursorScale(scale)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openLoginItemSettings() {
        loginItem.openSystemSettings()
    }

    func setDockIconHidden(_ hidden: Bool) {
        isDockIconHidden = hidden
        UserDefaults.standard.set(hidden, forKey: MomijiPreferenceKey.hideDockIcon)

        // Let SwiftUI insert the menu bar item before the Dock icon disappears,
        // so there is always a visible path back to the app window.
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.applyDockIconPreference()
        }
    }

    func applyDockIconPreference() {
        let policy: NSApplication.ActivationPolicy = isDockIconHidden ? .accessory : .regular
        guard NSApplication.shared.activationPolicy() != policy else { return }
        NSApplication.shared.setActivationPolicy(policy)
        if policy == .regular {
            NSApplication.shared.activate()
        }
    }

    private func applyTheme(_ theme: CursorTheme) throws {
        guard let applicationCoordinator else { return }
        try applicationCoordinator.apply(theme, cursorScale: cursorScale)
        MomijiNotifications.postActiveThemeChanged()
    }
}

enum MomijiPreferenceKey {
    static let hideDockIcon = "MomijiHideDockIcon"
}

private final class UITestSystemCursorEngine: SystemCursorApplying, @unchecked Sendable {
    var availability: SystemCursorAvailability { .available }
    func apply(_ theme: CursorTheme) throws {}
    func restoreDefaults() throws {}
}

private func safeFileName(_ value: String) -> String {
    let forbidden = CharacterSet(charactersIn: "/:\\")
    return value.components(separatedBy: forbidden).joined(separator: "-")
}
