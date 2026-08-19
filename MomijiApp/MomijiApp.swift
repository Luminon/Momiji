import AppKit
import CoreServices
import MomijiCore
import MomijiSystem
import SwiftUI

@main
struct MomijiApp: App {
    @NSApplicationDelegateAdaptor(MomijiApplicationDelegate.self) private var applicationDelegate
    @State private var model = MomijiAppModel()

    var body: some Scene {
        Window("app.name", id: "main") {
            MomijiContentView(model: model)
                .frame(minWidth: 900, minHeight: 620)
                .task { model.applyDockIconPreference() }
        }
        .defaultSize(width: 1_100, height: 720)
        .defaultPosition(.center)
        .commands {
            CommandGroup(after: .newItem) {
                Button("command.importFolder") { model.chooseThemeFolder() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Button("command.importPackage") { model.choosePackage() }
                    .keyboardShortcut("o", modifiers: .command)
                Divider()
                Button("command.export") { model.exportSelectedTheme() }
                    .disabled(model.selectedThemeID == nil)
            }
        }

        MenuBarExtra(
            isInserted: Binding(
                get: { model.isDockIconHidden },
                set: { if !$0 { model.setDockIconHidden(false) } }
            )
        ) {
            MomijiMenuBarMenu(model: model)
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .accessibilityLabel(Text("app.name"))
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
private final class MomijiApplicationDelegate: NSObject, NSApplicationDelegate {
    private let engine = PrivateSystemCursorEngine()
    private var applicationCoordinator: CursorApplicationCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["MOMIJI_UI_TEST_MOCK_SYSTEM"] != "1" else { return }

        let hideDockIcon = UserDefaults.standard.bool(forKey: MomijiPreferenceKey.hideDockIcon)
        NSApp.setActivationPolicy(hideDockIcon ? .accessory : .regular)

        do {
            let store = try MomijiThemeStore.makeDefault()
            applicationCoordinator = CursorApplicationCoordinator(store: store, engine: engine)
            _ = try MomijiLoginItemController().migrateLegacyHelperRegistrationIfNeeded()
        } catch {
            NSLog("Momiji could not initialize login persistence: %@", error.localizedDescription)
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceStateChanged(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceStateChanged(_:)),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
        reapplyActiveTheme()
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return true }
        return event.paramDescriptor(forKeyword: AEKeyword(keyAELaunchedAsLogInItem)) == nil
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func workspaceStateChanged(_ notification: Notification) {
        reapplyActiveTheme()
    }

    private func reapplyActiveTheme() {
        do {
            _ = try applicationCoordinator?.reapplyActiveTheme()
        } catch {
            NSLog("Momiji could not reapply the active theme: %@", error.localizedDescription)
        }
    }
}

private struct MomijiMenuBarMenu: View {
    @Bindable var model: MomijiAppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("menu.openMomiji") {
            showMainWindow()
        }

        Button("action.settings") {
            showMainWindow()
            model.isShowingSettings = true
        }

        Divider()

        Button("menu.quitMomiji") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func showMainWindow() {
        openWindow(id: "main")
        NSApplication.shared.activate()
    }
}
