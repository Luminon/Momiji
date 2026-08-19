import SwiftUI

@main
struct MomijiApp: App {
    @State private var model = MomijiAppModel()

    var body: some Scene {
        WindowGroup {
            MomijiContentView(model: model)
                .frame(minWidth: 900, minHeight: 620)
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
    }
}
