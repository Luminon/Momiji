import Foundation

public struct ThemeManifestV1: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var id: UUID
    public var name: String
    public var author: String?
    public var createdAt: Date
    public var cursors: [ManifestCursor]

    public init(theme: CursorTheme, cursors: [ManifestCursor]) {
        self.schemaVersion = 1
        self.id = theme.id
        self.name = theme.name
        self.author = theme.author
        self.createdAt = theme.createdAt
        self.cursors = cursors
    }
}

public struct ManifestCursor: Codable, Equatable, Sendable {
    public var id: UUID
    public var role: CursorRole
    public var logicalSize: CursorSize
    public var hotspot: CursorPoint
    public var representations: [ManifestRepresentation]
    public var timeline: AnimationTimeline
    public var playbackRate: Double
}

public struct ManifestRepresentation: Codable, Equatable, Sendable {
    public var scale: Int
    public var framePaths: [String]
}

public final class MomijiThemeStore: ThemeStoring, @unchecked Sendable {
    public static let packageExtension = "momiji"
    public static let maximumPackageBytes = 256 * 1_024 * 1_024
    public static let maximumPackageFiles = 2_048

    public let rootURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let lock = NSRecursiveLock()

    public init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        self.encoder.dateEncodingStrategy = .secondsSince1970
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .secondsSince1970
    }

    public static func makeDefault(fileManager: FileManager = .default) throws -> MomijiThemeStore {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return MomijiThemeStore(rootURL: applicationSupport.appendingPathComponent("Momiji", isDirectory: true))
    }

    public func listThemes() throws -> [CursorTheme] {
        try lock.withLock {
            try ensureRoot()
            let urls = try fileManager.contentsOfDirectory(
                at: themesURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )
            return try urls
                .filter { $0.pathExtension.lowercased() == Self.packageExtension }
                .map(loadPackage)
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    @discardableResult
    public func save(_ theme: CursorTheme) throws -> URL {
        try lock.withLock {
            try ensureRoot()
            let staging = rootURL.appendingPathComponent(".staging-\(UUID().uuidString).momiji", isDirectory: true)
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
            do {
                let manifest = try write(theme, into: staging)
                let manifestData = try encoder.encode(manifest)
                try manifestData.write(to: staging.appendingPathComponent("manifest.json"), options: .atomic)
                let destination = packageURL(id: theme.id)
                if fileManager.fileExists(atPath: destination.path) {
                    _ = try fileManager.replaceItemAt(destination, withItemAt: staging)
                } else {
                    try fileManager.moveItem(at: staging, to: destination)
                }
                return destination
            } catch {
                try? fileManager.removeItem(at: staging)
                throw error
            }
        }
    }

    public func loadTheme(id: UUID) throws -> CursorTheme {
        try lock.withLock {
            let url = packageURL(id: id)
            guard fileManager.fileExists(atPath: url.path) else { throw MomijiError.missingTheme(id) }
            return try loadPackage(url)
        }
    }

    public func deleteTheme(id: UUID) throws {
        try lock.withLock {
            if try activeThemeID() == id { try setActiveThemeID(nil) }
            let url = packageURL(id: id)
            guard fileManager.fileExists(atPath: url.path) else { throw MomijiError.missingTheme(id) }
            try fileManager.removeItem(at: url)
        }
    }

    public func importPackage(at url: URL) throws -> CursorTheme {
        try lock.withLock {
            let theme = try loadPackage(url)
            _ = try save(theme)
            return theme
        }
    }

    public func exportTheme(id: UUID, to url: URL) throws {
        try lock.withLock {
            let source = packageURL(id: id)
            guard fileManager.fileExists(atPath: source.path) else { throw MomijiError.missingTheme(id) }
            guard !fileManager.fileExists(atPath: url.path) else {
                throw CocoaError(.fileWriteFileExists)
            }
            try fileManager.copyItem(at: source, to: url)
        }
    }

    public func activeThemeID() throws -> UUID? {
        try lock.withLock {
            try readActiveState().themeID
        }
    }

    public func activeCursorScale() throws -> Double {
        try lock.withLock {
            try readActiveState().cursorScale
        }
    }

    public func setActiveTheme(id: UUID?, cursorScale: Double) throws {
        try lock.withLock {
            let scale = CursorScale.clamped(cursorScale)
            try ensureRoot()
            try encoder.encode(ActiveThemeState(themeID: id, cursorScale: scale))
                .write(to: activeStateURL, options: .atomic)
        }
    }

    public func setActiveThemeID(_ id: UUID?) throws {
        try lock.withLock {
            try setActiveTheme(id: id, cursorScale: activeCursorScale())
        }
    }

    public func preferredCursorScale() throws -> Double {
        try lock.withLock {
            guard fileManager.fileExists(atPath: preferencesURL.path) else { return CursorScale.default }
            let preferences = try decoder.decode(ThemePreferences.self, from: Data(contentsOf: preferencesURL))
            return CursorScale.clamped(preferences.cursorScale)
        }
    }

    public func setPreferredCursorScale(_ value: Double) throws {
        try lock.withLock {
            try ensureRoot()
            try encoder.encode(ThemePreferences(cursorScale: CursorScale.clamped(value)))
                .write(to: preferencesURL, options: .atomic)
        }
    }

    private var themesURL: URL { rootURL.appendingPathComponent("Themes", isDirectory: true) }
    private var activeStateURL: URL { rootURL.appendingPathComponent("active-theme.json") }
    private var preferencesURL: URL { rootURL.appendingPathComponent("preferences.json") }

    private func packageURL(id: UUID) -> URL {
        themesURL.appendingPathComponent(id.uuidString).appendingPathExtension(Self.packageExtension)
    }

    private func ensureRoot() throws {
        try fileManager.createDirectory(at: themesURL, withIntermediateDirectories: true)
    }

    private func readActiveState() throws -> ActiveThemeState {
        guard fileManager.fileExists(atPath: activeStateURL.path) else { return ActiveThemeState() }
        return try decoder.decode(ActiveThemeState.self, from: Data(contentsOf: activeStateURL))
    }

    private func write(_ theme: CursorTheme, into packageURL: URL) throws -> ThemeManifestV1 {
        guard !theme.cursors.isEmpty else { throw MomijiError.noUsableCursors }
        var manifestCursors: [ManifestCursor] = []
        var roles = Set<CursorRole>()
        for cursor in theme.cursors {
            guard roles.insert(cursor.role).inserted else { throw MomijiError.conflictingRole(cursor.role) }
            try validate(cursor)
            let cursorRoot = packageURL
                .appendingPathComponent("Cursors", isDirectory: true)
                .appendingPathComponent(cursor.role.rawValue, isDirectory: true)
            var manifestRepresentations: [ManifestRepresentation] = []
            for representation in cursor.representations.sorted(by: { $0.scale < $1.scale }) {
                let repRoot = cursorRoot.appendingPathComponent("\(representation.scale)x", isDirectory: true)
                try fileManager.createDirectory(at: repRoot, withIntermediateDirectories: true)
                var paths: [String] = []
                for (index, frame) in representation.frames.enumerated() {
                    _ = try PNGCodec.decode(frame.pngData)
                    let fileName = String(format: "frame-%03d.png", index)
                    try frame.pngData.write(to: repRoot.appendingPathComponent(fileName), options: .atomic)
                    paths.append("Cursors/\(cursor.role.rawValue)/\(representation.scale)x/\(fileName)")
                }
                manifestRepresentations.append(.init(scale: representation.scale, framePaths: paths))
            }
            manifestCursors.append(.init(
                id: cursor.id,
                role: cursor.role,
                logicalSize: cursor.logicalSize,
                hotspot: cursor.hotspot,
                representations: manifestRepresentations,
                timeline: cursor.timeline,
                playbackRate: cursor.playbackRate
            ))
        }
        return ThemeManifestV1(theme: theme, cursors: manifestCursors)
    }

    private func loadPackage(_ url: URL) throws -> CursorTheme {
        try validatePackageTree(url)
        let manifestURL = url.appendingPathComponent("manifest.json")
        let manifest = try decoder.decode(ThemeManifestV1.self, from: Data(contentsOf: manifestURL))
        guard manifest.schemaVersion == 1 else { throw MomijiError.packageVersion(manifest.schemaVersion) }
        var assets: [CursorAsset] = []
        var roles = Set<CursorRole>()
        for cursor in manifest.cursors {
            guard roles.insert(cursor.role).inserted else { throw MomijiError.conflictingRole(cursor.role) }
            var representations: [CursorRepresentation] = []
            for representation in cursor.representations {
                var frames: [CursorFrame] = []
                for relativePath in representation.framePaths {
                    guard isSafeRelativePath(relativePath) else {
                        throw MomijiError.unsafeInput("invalid package path \(relativePath)")
                    }
                    let frameURL = url.appendingPathComponent(relativePath)
                    let data = try Data(contentsOf: frameURL, options: [.mappedIfSafe])
                    _ = try PNGCodec.decode(data)
                    frames.append(CursorFrame(pngData: data))
                }
                representations.append(.init(scale: representation.scale, frames: frames))
            }
            guard !representations.isEmpty else {
                throw MomijiError.invalidFormat("package cursor \(cursor.role.rawValue) has no images")
            }
            let asset = CursorAsset(
                id: cursor.id,
                role: cursor.role,
                logicalSize: cursor.logicalSize,
                hotspot: cursor.hotspot,
                representations: representations,
                timeline: cursor.timeline,
                playbackRate: cursor.playbackRate
            )
            try validate(asset)
            assets.append(asset)
        }
        guard !assets.isEmpty else { throw MomijiError.noUsableCursors }
        return CursorTheme(
            id: manifest.id,
            name: manifest.name,
            author: manifest.author,
            createdAt: manifest.createdAt,
            cursors: assets
        )
    }

    private func validate(_ cursor: CursorAsset) throws {
        guard cursor.logicalSize.width.isFinite, cursor.logicalSize.height.isFinite,
              cursor.hotspot.x.isFinite, cursor.hotspot.y.isFinite,
              cursor.playbackRate.isFinite,
              cursor.logicalSize.width > 0, cursor.logicalSize.height > 0,
              cursor.logicalSize.width <= 1024, cursor.logicalSize.height <= 1024,
              cursor.hotspot.x >= 0, cursor.hotspot.y >= 0,
              cursor.hotspot.x < cursor.logicalSize.width,
              cursor.hotspot.y < cursor.logicalSize.height,
              cursor.playbackRate >= 0.25, cursor.playbackRate <= 4 else {
            throw MomijiError.invalidFormat("cursor \(cursor.role.rawValue) has invalid geometry")
        }
        guard !cursor.representations.isEmpty else {
            throw MomijiError.invalidFormat("cursor \(cursor.role.rawValue) has no representations")
        }
        var scales = Set<Int>()
        for representation in cursor.representations {
            guard scales.insert(representation.scale).inserted,
                  representation.scale > 0, representation.scale <= 4,
                  !representation.frames.isEmpty,
                  representation.frames.count <= 256 else {
                throw MomijiError.resourceLimit("invalid representation for \(cursor.role.rawValue)")
            }
        }
        guard cursor.timeline.ticksPerSecond > 0, cursor.timeline.ticksPerSecond <= 10_000,
              !cursor.timeline.steps.isEmpty, cursor.timeline.steps.count <= 256,
              cursor.timeline.steps.allSatisfy({ step in
                  step.durationTicks > 0 && step.durationTicks <= 36_000_000
                      && cursor.representations.allSatisfy { $0.frames.indices.contains(step.frameIndex) }
              }) else {
            throw MomijiError.invalidFormat("cursor \(cursor.role.rawValue) has an invalid animation timeline")
        }
    }

    private func validatePackageTree(_ url: URL) throws {
        let rootValues = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else {
            throw MomijiError.unsafeInput("Momiji package must be a real directory")
        }
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { throw MomijiError.invalidFormat("could not inspect package") }
        var count = 0
        var bytes = 0
        for case let child as URL in enumerator {
            let values = try child.resourceValues(forKeys: Set(keys))
            guard values.isSymbolicLink != true else { throw MomijiError.unsafeInput("package contains a symbolic link") }
            if values.isRegularFile == true {
                count += 1
                let addition = bytes.addingReportingOverflow(values.fileSize ?? 0)
                guard !addition.overflow else { throw MomijiError.resourceLimit("package size overflow") }
                bytes = addition.partialValue
            }
            guard count <= Self.maximumPackageFiles, bytes <= Self.maximumPackageBytes else {
                throw MomijiError.resourceLimit("Momiji package is too large")
            }
        }
    }
}

private struct ActiveThemeState: Codable {
    var themeID: UUID?
    var cursorScale: Double

    init(themeID: UUID? = nil, cursorScale: Double = CursorScale.default) {
        self.themeID = themeID
        self.cursorScale = CursorScale.clamped(cursorScale)
    }

    private enum CodingKeys: String, CodingKey {
        case themeID
        case cursorScale
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        themeID = try container.decodeIfPresent(UUID.self, forKey: .themeID)
        cursorScale = CursorScale.clamped(
            try container.decodeIfPresent(Double.self, forKey: .cursorScale) ?? CursorScale.default
        )
    }
}

private struct ThemePreferences: Codable {
    var cursorScale: Double
}

private func isSafeRelativePath(_ path: String) -> Bool {
    guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("~") else { return false }
    let components = NSString(string: path).pathComponents
    return !components.contains("..") && !components.contains(".")
}
