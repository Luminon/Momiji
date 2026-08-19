import AppKit
import MomijiCore
import MomijiSystem
import SwiftUI

@main
struct MomijiHelperApp: App {
    @NSApplicationDelegateAdaptor(HelperDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class HelperDelegate: NSObject, NSApplicationDelegate {
    private let engine = PrivateSystemCursorEngine()
    private var store: MomijiThemeStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.prohibited)
        store = try? MomijiThemeStore.makeDefault()
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(activeThemeChanged(_:)),
            name: MomijiNotifications.activeThemeChanged,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceBecameActive(_:)),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceBecameActive(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        applyActiveTheme()
    }

    func applicationWillTerminate(_ notification: Notification) {
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func activeThemeChanged(_ notification: Notification) {
        applyActiveTheme()
    }

    @objc private func workspaceBecameActive(_ notification: Notification) {
        applyActiveTheme()
    }

    private func applyActiveTheme() {
        guard let store,
              let id = try? store.activeThemeID(),
              let theme = try? store.loadTheme(id: id),
              let cursorScale = try? store.activeCursorScale() else { return }
        do {
            try engine.apply(theme.scaled(by: cursorScale))
        } catch {
            NSLog("MomijiHelper could not apply active theme: %@", error.localizedDescription)
        }
    }
}
