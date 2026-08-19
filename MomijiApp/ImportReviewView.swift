import MomijiCore
import SwiftUI

struct ImportReviewView: View {
    @Bindable var model: MomijiAppModel
    @State private var selectedItemID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("importReview.title").font(.title2.bold())
                    Text("importReview.description").foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()

            Divider()
            VSplitView {
                Table(items, selection: $selectedItemID) {
                    TableColumn("importReview.status") { item in
                        Image(systemName: statusSymbol(item))
                            .foregroundStyle(statusColor(item))
                    }
                    .width(38)
                    TableColumn("importReview.file") { item in
                        VStack(alignment: .leading) {
                            Text(item.sourceURL.lastPathComponent)
                            if let error = item.errorDescription {
                                Text(error).font(.caption).foregroundStyle(.red).lineLimit(2)
                            } else if isConflicting(item) {
                                Text("importReview.rowConflict")
                                    .font(.caption).foregroundStyle(.orange).lineLimit(2)
                            } else if let warning = item.warnings.first {
                                Text(warning.description).font(.caption).foregroundStyle(.orange).lineLimit(2)
                            }
                        }
                    }
                    TableColumn("importReview.role") { item in
                        Picker("", selection: roleBinding(for: item)) {
                            Text("importReview.unmapped").tag(CursorRole?.none)
                            ForEach(CursorRole.allCases) { role in
                                Text(LocalizedStringKey(role.localizationKey)).tag(CursorRole?.some(role))
                            }
                        }
                        .labelsHidden()
                        .disabled(item.asset == nil)
                        .accessibilityIdentifier("import-role-picker-\(item.sourceURL.lastPathComponent)")
                    }
                    .width(min: 180, ideal: 220)
                    TableColumn("importReview.frames") { item in
                        Text(item.asset.map { String($0.frameCount) } ?? "—")
                    }
                    .width(60)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
                .accessibilityIdentifier("import-review-table")

                if let asset = selectedAssetBinding {
                    CursorEditorView(asset: asset)
                        .frame(maxWidth: .infinity, minHeight: 280)
                } else {
                    ContentUnavailableView("importReview.selectCursor", systemImage: "cursorarrow")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .frame(minHeight: 160)
                        .accessibilityIdentifier("import-review-placeholder")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            HStack {
                if hasConflict {
                    Label("importReview.conflict", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button("action.cancel") {
                    model.isShowingImportReview = false
                    model.importResult = nil
                }
                Button("action.save") { model.saveImport(apply: false) }
                    .accessibilityIdentifier("save-import-button")
                    .disabled(!canSave)
                Button("action.saveApply") { model.saveImport(apply: true) }
                    .accessibilityIdentifier("save-apply-import-button")
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave || !systemAvailable)
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            selectedItemID = selectedItemID ?? items.first(where: isUsable)?.id
        }
    }

    private var items: [ThemeImportItem] { model.importResult?.items ?? [] }
    private var conflictingRoles: Set<CursorRole> { model.importResult?.conflictingRoles ?? [] }
    private var hasConflict: Bool { !conflictingRoles.isEmpty }
    private var canSave: Bool { model.importResult?.canMakeTheme == true }
    private var systemAvailable: Bool {
        if case .available = model.systemAvailability { return true }
        return false
    }

    private var selectedAssetBinding: Binding<CursorAsset>? {
        guard let selectedItemID,
              let item = model.importResult?.items.first(where: { $0.id == selectedItemID }),
              item.errorDescription == nil,
              item.role != nil,
              let fallback = item.asset else {
            return nil
        }
        return Binding(
            get: {
                model.importResult?.items.first(where: { $0.id == selectedItemID })?.asset ?? fallback
            },
            set: { model.updateImportAsset(itemID: selectedItemID, asset: $0) }
        )
    }

    private func roleBinding(for item: ThemeImportItem) -> Binding<CursorRole?> {
        Binding(
            get: { model.importResult?.items.first(where: { $0.id == item.id })?.role },
            set: { role in
                model.updateImportRole(itemID: item.id, role: role)
                if role == nil, selectedItemID == item.id {
                    selectedItemID = items.first(where: { $0.id != item.id && isUsable($0) })?.id
                }
            }
        )
    }

    private func statusSymbol(_ item: ThemeImportItem) -> String {
        if item.errorDescription != nil { return "xmark.circle.fill" }
        if item.role == nil || isConflicting(item) || !item.warnings.isEmpty {
            return "exclamationmark.triangle.fill"
        }
        return "checkmark.circle.fill"
    }

    private func statusColor(_ item: ThemeImportItem) -> Color {
        if item.errorDescription != nil { return .red }
        if item.role == nil || isConflicting(item) || !item.warnings.isEmpty { return .orange }
        return .green
    }

    private func isConflicting(_ item: ThemeImportItem) -> Bool {
        item.role.map(conflictingRoles.contains) == true
    }

    private func isUsable(_ item: ThemeImportItem) -> Bool {
        item.errorDescription == nil && item.asset != nil && item.role != nil
    }
}
