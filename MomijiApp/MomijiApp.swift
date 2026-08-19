import AppKit
import SwiftUI

@main
struct MomijiApp: App {
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
