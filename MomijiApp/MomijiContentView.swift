import MomijiCore
import SwiftUI

struct MomijiContentView: View {
    @Bindable var model: MomijiAppModel

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                VStack(spacing: 0) {
                    List(selection: $model.selectedThemeID) {
                        Section("library.themes") {
                            ForEach(model.themes) { theme in
                                Label(theme.name, systemImage: "cursorarrow.motionlines")
                                    .tag(theme.id)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Divider()

                    HStack {
                        Button { model.chooseThemeFolder() } label: {
                            Label("action.import", systemImage: "plus")
                        }
                        Spacer()
                        Button(role: .destructive) { model.deleteSelectedTheme() } label: {
                            Image(systemName: "trash")
                        }
                        .disabled(model.selectedThemeID == nil)
                    }
                    .padding(10)
                    .background(.bar)
                }
                .navigationTitle("app.name")
            } detail: {
                if let index = model.themes.firstIndex(where: { $0.id == model.selectedThemeID }) {
                    ThemeDetailView(theme: $model.themes[index]) {
                        model.saveEditedTheme(model.themes[index])
                    }
                } else {
                    EmptyLibraryView { model.chooseThemeFolder() }
                }
            }

            if let status = model.statusMessage {
                Divider()
                StatusBar(message: status) { model.statusMessage = nil }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.statusMessage)
        .toolbar {
            ToolbarItemGroup {
                Button { model.chooseThemeFolder() } label: {
                    Label("action.importFolder", systemImage: "folder.badge.plus")
                }
                .accessibilityIdentifier("import-folder-button")
                Button { model.exportSelectedTheme() } label: {
                    Label("action.export", systemImage: "square.and.arrow.up")
                }
                .disabled(model.selectedThemeID == nil)
                Divider()
                Button { model.restoreDefaults() } label: {
                    Label("action.restore", systemImage: "arrow.counterclockwise")
                }
                .accessibilityIdentifier("restore-defaults-button")
                Button { model.applySelectedTheme() } label: {
                    Label("action.apply", systemImage: "cursorarrow.click.2")
                }
                .accessibilityIdentifier("apply-theme-button")
                .buttonStyle(.borderedProminent)
                .disabled(model.selectedThemeID == nil || !isSystemAvailable)
                Button { model.isShowingSettings = true } label: {
                    Label("action.settings", systemImage: "gearshape")
                }
                .accessibilityIdentifier("settings-button")
            }
        }
        .dropDestination(for: URL.self) { urls, _ in model.handleDroppedURLs(urls) }
        .onOpenURL { url in
            if url.pathExtension.lowercased() == MomijiThemeStore.packageExtension {
                model.importPackage(url)
            } else {
                model.importThemeFolder(url)
            }
        }
        .sheet(isPresented: $model.isShowingImportReview) {
            if model.importResult != nil {
                ImportReviewView(model: model)
                    .frame(minWidth: 780, minHeight: 700)
            }
        }
        .sheet(isPresented: $model.isShowingSettings) {
            MomijiSettingsView(model: model)
                .frame(width: 540, height: 500)
        }
        .alert("error.title", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("action.ok") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var isSystemAvailable: Bool {
        if case .available = model.systemAvailability { return true }
        return false
    }
}

private struct StatusBar: View {
    var message: String
    var dismissAction: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(message)
            Spacer()
            Button(action: dismissAction) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(.bar)
    }
}

private struct EmptyLibraryView: View {
    var importAction: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("empty.title", systemImage: "cursorarrow.rays")
        } description: {
            Text("empty.description")
        } actions: {
            Button("action.importFolder", action: importAction)
                .buttonStyle(.borderedProminent)
        }
    }
}
