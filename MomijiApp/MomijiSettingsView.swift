import MomijiCore
import MomijiSystem
import SwiftUI

struct MomijiSettingsView: View {
    @Bindable var model: MomijiAppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("settings.application") {
                    Toggle("settings.hideDockIcon", isOn: Binding(
                        get: { model.isDockIconHidden },
                        set: { model.setDockIconHidden($0) }
                    ))
                    .accessibilityIdentifier("hide-dock-icon-toggle")
                    Text("settings.hideDockIcon.help")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("settings.cursorAppearance") {
                    LabeledContent("settings.cursorScale") {
                        HStack(spacing: 12) {
                            Slider(
                                value: Binding(
                                    get: { model.cursorScale },
                                    set: { model.setCursorScale($0) }
                                ),
                                in: CursorScale.minimum...CursorScale.maximum,
                                step: 0.05
                            )
                            .frame(minWidth: 190)
                            .accessibilityIdentifier("cursor-scale-slider")

                            Text(model.cursorScale, format: .percent.precision(.fractionLength(0)))
                                .monospacedDigit()
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                    HStack {
                        Button("settings.resetCursorScale") {
                            model.setCursorScale(CursorScale.default)
                        }
                        .disabled(model.cursorScale == CursorScale.default)
                        Spacer()
                    }
                    Text("settings.cursorScale.help")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("settings.persistence") {
                    Toggle("settings.loginItem", isOn: Binding(
                        get: { model.loginItemStatus == .enabled || model.loginItemStatus == .requiresApproval },
                        set: { model.setLoginItemEnabled($0) }
                    ))
                    Text("settings.loginItem.help")
                        .font(.caption).foregroundStyle(.secondary)
                    if model.loginItemStatus == .requiresApproval {
                        Button("settings.openLoginItems") { model.openLoginItemSettings() }
                    }
                }

                Section("settings.compatibility") {
                    Text("settings.privateAPIWarning")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    switch model.systemAvailability {
                    case .available:
                        Label("settings.systemAvailable", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    case .unavailable(let reason):
                        Label("settings.systemUnavailable", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(reason).font(.caption).textSelection(.enabled)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("action.close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("settings-close-button")
            }
            .padding()
            .background(.bar)
        }
        .onAppear { model.refreshLoginItemStatus() }
    }
}
