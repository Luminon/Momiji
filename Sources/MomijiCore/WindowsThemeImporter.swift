import Foundation

public struct WindowsThemeImporter: WindowsThemeImporting {
    public static let maximumFiles = 512
    public static let maximumTotalBytes = 256 * 1_024 * 1_024

    private let parser = ANIParser()

    public init() {}

    public func importTheme(at folderURL: URL) throws -> ThemeImportResult {
        let values = try folderURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw MomijiError.unsafeInput("theme source must be a real directory")
        }

        let files = try cursorFiles(in: folderURL)
        let infFiles = files.filter { $0.pathExtension.lowercased() == "inf" }
        var infMapping: [String: CursorRole] = [:]
        var author: String?
        var importWarnings: [ImportWarning] = []
        for infURL in infFiles {
            do {
                let parsed = try parseINF(at: infURL)
                infMapping.merge(parsed.mapping) { current, _ in current }
                author = author ?? parsed.author
            } catch {
                importWarnings.append(.message("Could not read \(infURL.lastPathComponent): \(error.localizedDescription)"))
            }
        }

        var items: [ThemeImportItem] = []
        for file in files where ["ani", "cur"].contains(file.pathExtension.lowercased()) {
            let fileName = file.lastPathComponent.lowercased()
            let role = infMapping[fileName] ?? Self.inferRole(from: file.deletingPathExtension().lastPathComponent)
            do {
                let data = try Data(contentsOf: file, options: [.mappedIfSafe])
                let parsed: ParsedWindowsCursor
                switch file.pathExtension.lowercased() {
                case "ani":
                    parsed = try parser.parse(data: data, sourceName: file.lastPathComponent)
                default:
                    parsed = try parser.parseCUR(data: data, sourceName: file.lastPathComponent)
                }
                let warnings = parsed.warnings + (role == nil ? [.unmapped(file: file.lastPathComponent)] : [])
                items.append(ThemeImportItem(
                    sourceURL: file,
                    role: role,
                    asset: parsed.asset(role: role ?? .arrow),
                    warnings: warnings
                ))
            } catch {
                items.append(ThemeImportItem(
                    sourceURL: file,
                    role: role,
                    asset: nil,
                    errorDescription: error.localizedDescription
                ))
            }
        }

        guard !items.isEmpty else { throw MomijiError.noUsableCursors }
        var warnings = importWarnings + items.flatMap(\.warnings)
        let grouped = Dictionary(grouping: items.compactMap { item -> (CursorRole, String)? in
            guard item.asset != nil, let role = item.role else { return nil }
            return (role, item.sourceURL.lastPathComponent)
        }, by: \.0)
        for (role, entries) in grouped where entries.count > 1 {
            warnings.append(.conflict(role: role, files: entries.map(\.1)))
        }

        return ThemeImportResult(
            suggestedName: folderURL.lastPathComponent,
            author: author,
            items: items,
            warnings: warnings
        )
    }

    public static func inferRole(from rawName: String) -> CursorRole? {
        let name = rawName
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        // Windows' Handwriting/NWPen cursor has no direct macOS role. In
        // particular, it must not match the generic "hand" link heuristic.
        if name.contains("handwriting") || name.contains("nwpen") { return nil }

        let ordered: [(CursorRole, [String])] = [
            (.resizeNorthwestSoutheast, ["nwse", "diagonal1", "diag1", "northwest_southeast"]),
            (.resizeNortheastSouthwest, ["nesw", "diagonal2", "diag2", "northeast_southwest"]),
            (.resizeNorthSouth, ["sizens", "size_ns", "vertical", "resize_ns", "northsouth"]),
            (.resizeEastWest, ["sizewe", "size_we", "horizontal", "resize_ew", "eastwest"]),
            (.operationNotAllowed, ["unavailable", "unavail", "notallowed", "forbidden", "no_"]),
            (.openHand, ["openhand", "open_hand", "grab"]),
            (.closedHand, ["closedhand", "closed_hand", "grabbing"]),
            (.pointingHand, ["pointinghand", "pointing", "link", "hand", "hand2", "hyperlink"]),
            (.progress, ["appstarting", "working", "work", "background"]),
            (.wait, ["busy", "wait", "loading"]),
            (.iBeam, ["ibeam", "text", "beam"]),
            (.crosshair, ["crosshair", "precision", "cross"]),
            (.move, ["sizeall", "size_all", "move", "allscroll"]),
            (.help, ["help", "question"]),
            (.arrow, ["normal", "arrow", "default", "pointer"]),
        ]
        return ordered.first { _, tokens in tokens.contains { name.contains($0) } }?.0
    }

    private func cursorFiles(in folder: URL) throws -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw MomijiError.invalidFormat("could not enumerate theme folder")
        }
        var output: [URL] = []
        var totalBytes = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                throw MomijiError.unsafeInput("theme source contains a symbolic link")
            }
            guard values.isRegularFile == true else { continue }
            let ext = url.pathExtension.lowercased()
            guard ["ani", "cur", "inf"].contains(ext) else { continue }
            output.append(url)
            let addition = totalBytes.addingReportingOverflow(values.fileSize ?? 0)
            guard !addition.overflow else { throw MomijiError.resourceLimit("theme source size overflow") }
            totalBytes = addition.partialValue
            guard output.count <= Self.maximumFiles else {
                throw MomijiError.resourceLimit("theme contains more than \(Self.maximumFiles) files")
            }
            guard totalBytes <= Self.maximumTotalBytes else {
                throw MomijiError.resourceLimit("theme source exceeds 256 MiB")
            }
        }
        return output.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private func parseINF(at url: URL) throws -> INFResult {
        let data = try Data(contentsOf: url)
        guard data.count <= 4 * 1_024 * 1_024 else {
            throw MomijiError.resourceLimit("INF file exceeds 4 MiB")
        }
        let text = decodeWindowsText(data)
        var mapping: [String: CursorRole] = [:]
        var author: String?

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix(";") else { continue }
            if author == nil, line.lowercased().hasPrefix("author") {
                author = line.split(separator: "=", maxSplits: 1).dropFirst().first.map {
                    cleanINFToken(String($0))
                }
            }
            let tokens = line
                .split(whereSeparator: { $0 == "," || $0 == "=" })
                .map { cleanINFToken(String($0)) }
            guard let pathIndex = tokens.lastIndex(where: {
                let lower = $0.lowercased()
                return lower.contains(".cur") || lower.contains(".ani")
            }) else { continue }
            let roleFields = tokens[..<pathIndex].joined(separator: ",")
            guard let role = roleMentioned(in: roleFields) else { continue }
            let path = tokens[pathIndex]
            let expanded = path.replacingOccurrences(
                of: #"%[^%]+%[\\/]*"#,
                with: "",
                options: .regularExpression
            )
            let filename = expanded.replacingOccurrences(of: "\\", with: "/")
                .split(separator: "/").last.map(String.init)?.lowercased() ?? expanded.lowercased()
            mapping[filename] = role
        }
        return INFResult(mapping: mapping, author: author)
    }
}

private struct INFResult {
    var mapping: [String: CursorRole]
    var author: String?
}

private func decodeWindowsText(_ data: Data) -> String {
    if data.starts(with: [0xFF, 0xFE]), let value = String(data: data.dropFirst(2), encoding: .utf16LittleEndian) {
        return value
    }
    if let value = String(data: data, encoding: .utf8) { return value }
    if let value = String(data: data, encoding: .windowsCP1252) { return value }
    return String(decoding: data, as: UTF8.self)
}

private func cleanINFToken(_ value: String) -> String {
    value.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'"))
}

private func roleMentioned(in line: String) -> CursorRole? {
    let lower = line.lowercased()
    let keys: [(String, CursorRole)] = [
        ("appstarting", .progress),
        ("sizenwse", .resizeNorthwestSoutheast),
        ("sizenesw", .resizeNortheastSouthwest),
        ("sizens", .resizeNorthSouth),
        ("sizewe", .resizeEastWest),
        ("sizeall", .move),
        ("crosshair", .crosshair),
        ("ibeam", .iBeam),
        ("arrow", .arrow),
        ("hand", .pointingHand),
        ("wait", .wait),
        ("help", .help),
        ("\"no\"", .operationNotAllowed),
    ]
    return keys.first { lower.contains($0.0) }?.1
}
