import AppKit
import MomijiCore
import SwiftUI

struct ThemeDetailView: View {
    @Binding var theme: CursorTheme
    var saveAction: () -> Void
    @State private var selectedCursorID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    TextField("theme.name", text: $theme.name)
                        .font(.title.bold())
                        .textFieldStyle(.plain)
                        .accessibilityIdentifier("theme-name-field")
                    TextField("theme.author", text: Binding(
                        get: { theme.author ?? "" },
                        set: { theme.author = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button("action.save", action: saveAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding()
            Divider()

            HStack(spacing: 0) {
                List(selection: $selectedCursorID) {
                    ForEach(theme.cursors) { cursor in
                        HStack {
                            CursorThumbnail(asset: cursor)
                                .frame(width: 34, height: 34)
                            VStack(alignment: .leading) {
                                Text(LocalizedStringKey(cursor.role.localizationKey))
                                Text("\(cursor.frameCount) " + String(localized: "theme.frames"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .tag(cursor.id)
                    }
                }
                .accessibilityIdentifier("cursor-list")
                .frame(width: 270)
                .frame(maxHeight: .infinity)

                Divider()

                if let index = selectedIndex {
                    CursorEditorView(asset: $theme.cursors[index])
                        .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView("theme.selectCursor", systemImage: "cursorarrow")
                        .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { selectedCursorID = selectedCursorID ?? theme.cursors.first?.id }
    }

    private var selectedIndex: Int? {
        theme.cursors.firstIndex { $0.id == selectedCursorID }
    }
}

struct CursorEditorView: View {
    @Binding var asset: CursorAsset

    var body: some View {
        Form {
            CursorPreview(asset: $asset)
                .frame(height: 160)

            if asset.timeline.uniformlyExpanded(maxFrames: 240).wasQuantized {
                Label("cursorEditor.timingApproximation", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            Picker("cursorEditor.role", selection: $asset.role) {
                ForEach(CursorRole.allCases) { role in
                    Text(LocalizedStringKey(role.localizationKey)).tag(role)
                }
            }

            LabeledContent("cursorEditor.size") {
                HStack {
                    TextField("W", value: $asset.logicalSize.width, format: .number.precision(.fractionLength(0...1)))
                        .frame(width: 70)
                        .accessibilityIdentifier("cursor-width-field")
                    Text("×")
                    TextField("H", value: $asset.logicalSize.height, format: .number.precision(.fractionLength(0...1)))
                        .frame(width: 70)
                        .accessibilityIdentifier("cursor-height-field")
                }
            }

            LabeledContent("cursorEditor.hotspot") {
                HStack {
                    TextField("X", value: $asset.hotspot.x, format: .number.precision(.fractionLength(0...1)))
                        .frame(width: 70)
                        .accessibilityIdentifier("hotspot-x-field")
                    TextField("Y", value: $asset.hotspot.y, format: .number.precision(.fractionLength(0...1)))
                        .frame(width: 70)
                        .accessibilityIdentifier("hotspot-y-field")
                }
            }

            LabeledContent("cursorEditor.speed") {
                HStack {
                    Slider(value: $asset.playbackRate, in: 0.25...4, step: 0.25)
                        .accessibilityIdentifier("playback-rate-slider")
                    Text("\(asset.playbackRate, specifier: "%.2g")×")
                        .monospacedDigit().frame(width: 48, alignment: .trailing)
                }
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("cursor-editor")
    }
}

private struct CursorPreview: View {
    @Binding var asset: CursorAsset

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Checkerboard()
                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
                    if let image = currentImage(at: context.date) {
                        Image(nsImage: image)
                            .interpolation(.high)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(
                                width: min(proxy.size.width * 0.6, max(32, asset.logicalSize.width * 4)),
                                height: min(proxy.size.height * 0.8, max(32, asset.logicalSize.height * 4))
                            )
                    }
                }
                hotspotMarker(in: proxy.size)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let imageRect = previewRect(in: proxy.size)
                guard imageRect.contains(value.location) else { return }
                asset.hotspot.x = min(asset.logicalSize.width - 0.01, max(0,
                    (value.location.x - imageRect.minX) / imageRect.width * asset.logicalSize.width
                ))
                asset.hotspot.y = min(asset.logicalSize.height - 0.01, max(0,
                    (value.location.y - imageRect.minY) / imageRect.height * asset.logicalSize.height
                ))
            })
        }
    }

    private func currentImage(at date: Date) -> NSImage? {
        guard let representation = asset.representations.max(by: { $0.scale < $1.scale }),
              !representation.frames.isEmpty else { return nil }
        let timeline = asset.timeline
        let totalTicks = timeline.steps.reduce(0) { $0 + max(1, $1.durationTicks) }
        guard totalTicks > 0 else { return NSImage(data: representation.frames[0].pngData) }
        let elapsed = date.timeIntervalSinceReferenceDate * Double(max(1, timeline.ticksPerSecond)) * asset.playbackRate
        var position = Int(elapsed.rounded(.down)) % totalTicks
        var frameIndex = 0
        for step in timeline.steps {
            if position < step.durationTicks {
                frameIndex = step.frameIndex
                break
            }
            position -= max(1, step.durationTicks)
        }
        guard representation.frames.indices.contains(frameIndex) else { return nil }
        return NSImage(data: representation.frames[frameIndex].pngData)
    }

    private func previewRect(in size: CGSize) -> CGRect {
        let width = min(size.width * 0.6, max(32, asset.logicalSize.width * 4))
        let height = min(size.height * 0.8, max(32, asset.logicalSize.height * 4))
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    @ViewBuilder
    private func hotspotMarker(in size: CGSize) -> some View {
        let rect = previewRect(in: size)
        let x = rect.minX + rect.width * asset.hotspot.x / max(1, asset.logicalSize.width)
        let y = rect.minY + rect.height * asset.hotspot.y / max(1, asset.logicalSize.height)
        ZStack {
            Circle().fill(.red).frame(width: 10, height: 10)
            Circle().stroke(.white, lineWidth: 2).frame(width: 10, height: 10)
        }
        .position(x: x, y: y)
    }
}

private struct CursorThumbnail: View {
    var asset: CursorAsset
    var body: some View {
        Group {
            if let data = asset.representations.first?.frames.first?.pngData,
               let image = NSImage(data: data) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "questionmark")
            }
        }
    }
}

private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 12
            for row in 0...Int(size.height / cell) {
                for column in 0...Int(size.width / cell) where (row + column).isMultiple(of: 2) {
                    context.fill(
                        Path(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)),
                        with: .color(.gray.opacity(0.16))
                    )
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
