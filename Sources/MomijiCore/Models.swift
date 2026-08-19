import Foundation

public enum CursorRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case arrow
    case iBeam
    case pointingHand
    case wait
    case progress
    case crosshair
    case operationNotAllowed
    case resizeNorthSouth
    case resizeEastWest
    case resizeNorthwestSoutheast
    case resizeNortheastSouthwest
    case move
    case help
    case openHand
    case closedHand

    public var id: String { rawValue }

    public var localizationKey: String { "cursor.role.\(rawValue)" }
}

public struct CursorPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct CursorSize: Codable, Equatable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct CursorFrame: Codable, Equatable, Sendable {
    public var pngData: Data

    public init(pngData: Data) {
        self.pngData = pngData
    }
}

public struct CursorRepresentation: Codable, Equatable, Sendable {
    public var scale: Int
    public var frames: [CursorFrame]

    public init(scale: Int, frames: [CursorFrame]) {
        self.scale = scale
        self.frames = frames
    }
}

public struct AnimationStep: Codable, Equatable, Sendable {
    public var frameIndex: Int
    public var durationTicks: Int

    public init(frameIndex: Int, durationTicks: Int) {
        self.frameIndex = frameIndex
        self.durationTicks = durationTicks
    }
}

public struct AnimationTimeline: Codable, Equatable, Sendable {
    public var ticksPerSecond: Int
    public var steps: [AnimationStep]

    public init(ticksPerSecond: Int = 60, steps: [AnimationStep]) {
        self.ticksPerSecond = ticksPerSecond
        self.steps = steps
    }

    public static let still = AnimationTimeline(steps: [.init(frameIndex: 0, durationTicks: 6)])

    public var totalDuration: TimeInterval {
        guard ticksPerSecond > 0 else { return 0 }
        return Double(steps.reduce(0) { $0 + max(1, $1.durationTicks) }) / Double(ticksPerSecond)
    }

    public func uniformlyExpanded(maxFrames: Int) -> UniformAnimation {
        guard !steps.isEmpty else {
            return UniformAnimation(frameIndices: [0], frameDuration: 0.1, wasQuantized: false)
        }

        let durations = steps.map { max(1, $0.durationTicks) }
        let exactQuantum = durations.dropFirst().reduce(durations[0], greatestCommonDivisor)
        let exactCount = expandedCount(durations, quantum: exactQuantum)
        let safeLimit = max(1, maxFrames)
        var quantum = exactQuantum
        var quantized = false

        if exactCount > safeLimit {
            quantized = true
            var lower = exactQuantum
            var upper = durations.max() ?? exactQuantum
            while lower < upper {
                let candidate = lower + (upper - lower) / 2
                if expandedCount(durations, quantum: candidate) > safeLimit {
                    lower = candidate + 1
                } else {
                    upper = candidate
                }
            }
            quantum = lower
        }

        var indices: [Int] = []
        for (step, duration) in zip(steps, durations) {
            let repeats = roundedQuotient(duration, quantum)
            indices.append(contentsOf: repeatElement(step.frameIndex, count: repeats))
        }

        if indices.count > safeLimit {
            indices = (0..<safeLimit).map { index in
                let source = min(indices.count - 1, index * indices.count / safeLimit)
                return indices[source]
            }
            quantized = true
        }

        let duration = Double(quantum) / Double(max(1, ticksPerSecond))
        return UniformAnimation(frameIndices: indices, frameDuration: duration, wasQuantized: quantized)
    }
}

public struct UniformAnimation: Equatable, Sendable {
    public var frameIndices: [Int]
    public var frameDuration: TimeInterval
    public var wasQuantized: Bool
}

public struct CursorAsset: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var role: CursorRole
    public var logicalSize: CursorSize
    public var hotspot: CursorPoint
    public var representations: [CursorRepresentation]
    public var timeline: AnimationTimeline
    public var playbackRate: Double

    public init(
        id: UUID = UUID(),
        role: CursorRole,
        logicalSize: CursorSize,
        hotspot: CursorPoint,
        representations: [CursorRepresentation],
        timeline: AnimationTimeline,
        playbackRate: Double = 1
    ) {
        self.id = id
        self.role = role
        self.logicalSize = logicalSize
        self.hotspot = hotspot
        self.representations = representations
        self.timeline = timeline
        self.playbackRate = playbackRate
    }

    public var frameCount: Int {
        representations.map(\.frames.count).max() ?? 0
    }
}

public struct CursorTheme: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var author: String?
    public var createdAt: Date
    public var cursors: [CursorAsset]

    public init(
        id: UUID = UUID(),
        name: String,
        author: String? = nil,
        createdAt: Date = Date(),
        cursors: [CursorAsset]
    ) {
        self.id = id
        self.name = name
        self.author = author
        self.createdAt = createdAt
        self.cursors = cursors
    }
}

public enum CursorScale {
    public static let minimum = 0.5
    public static let maximum = 2.0
    public static let `default` = 1.0

    public static func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return `default` }
        return min(maximum, max(minimum, value))
    }
}

public extension CursorTheme {
    func scaled(by value: Double) -> CursorTheme {
        let factor = CursorScale.clamped(value)
        guard factor != 1 else { return self }
        var result = self
        result.cursors = cursors.map { cursor in
            var scaled = cursor
            scaled.logicalSize = CursorSize(
                width: cursor.logicalSize.width * factor,
                height: cursor.logicalSize.height * factor
            )
            scaled.hotspot = CursorPoint(
                x: cursor.hotspot.x * factor,
                y: cursor.hotspot.y * factor
            )
            return scaled
        }
        return result
    }
}

public enum ImportWarning: Equatable, Sendable {
    case message(String)
    case timingQuantized(file: String)
    case hotspotNormalized(file: String)
    case unmapped(file: String)
    case conflict(role: CursorRole, files: [String])

    public var description: String {
        switch self {
        case .message(let value): value
        case .timingQuantized(let file): "Animation timing was approximated for \(file)."
        case .hotspotNormalized(let file): "Frame hotspots were normalized for \(file)."
        case .unmapped(let file): "No cursor role could be inferred for \(file)."
        case .conflict(let role, let files): "Multiple files map to \(role.rawValue): \(files.joined(separator: ", "))."
        }
    }
}

public struct ThemeImportItem: Identifiable, Sendable {
    public let id: UUID
    public let sourceURL: URL
    public var role: CursorRole?
    public var asset: CursorAsset?
    public var warnings: [ImportWarning]
    public var errorDescription: String?

    public init(
        id: UUID = UUID(),
        sourceURL: URL,
        role: CursorRole?,
        asset: CursorAsset?,
        warnings: [ImportWarning] = [],
        errorDescription: String? = nil
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.role = role
        self.asset = asset
        self.warnings = warnings
        self.errorDescription = errorDescription
    }
}

public struct ThemeImportResult: Sendable {
    public var suggestedName: String
    public var author: String?
    public var items: [ThemeImportItem]
    public var warnings: [ImportWarning]

    public init(suggestedName: String, author: String?, items: [ThemeImportItem], warnings: [ImportWarning]) {
        self.suggestedName = suggestedName
        self.author = author
        self.items = items
        self.warnings = warnings
    }

    public var selectedRoles: [CursorRole] {
        items.compactMap { item in
            guard item.errorDescription == nil, item.asset != nil else { return nil }
            return item.role
        }
    }

    public var conflictingRoles: Set<CursorRole> {
        let counts = selectedRoles.reduce(into: [CursorRole: Int]()) { counts, role in
            counts[role, default: 0] += 1
        }
        return Set(counts.compactMap { role, count in count > 1 ? role : nil })
    }

    public var canMakeTheme: Bool {
        !selectedRoles.isEmpty && conflictingRoles.isEmpty
    }

    public func makeTheme() throws -> CursorTheme {
        var used = Set<CursorRole>()
        var assets: [CursorAsset] = []
        for item in items {
            guard item.errorDescription == nil, let role = item.role, var asset = item.asset else { continue }
            guard used.insert(role).inserted else {
                throw MomijiError.conflictingRole(role)
            }
            asset.role = role
            assets.append(asset)
        }
        guard !assets.isEmpty else { throw MomijiError.noUsableCursors }
        return CursorTheme(name: suggestedName, author: author, cursors: assets)
    }
}

public protocol WindowsThemeImporting: Sendable {
    func importTheme(at folderURL: URL) throws -> ThemeImportResult
}

public protocol ThemeStoring: Sendable {
    func listThemes() throws -> [CursorTheme]
    @discardableResult func save(_ theme: CursorTheme) throws -> URL
    func loadTheme(id: UUID) throws -> CursorTheme
    func deleteTheme(id: UUID) throws
    func importPackage(at url: URL) throws -> CursorTheme
    func exportTheme(id: UUID, to url: URL) throws
    func activeThemeID() throws -> UUID?
    func activeCursorScale() throws -> Double
    func setActiveTheme(id: UUID?, cursorScale: Double) throws
    func setActiveThemeID(_ id: UUID?) throws
}

public enum SystemCursorAvailability: Equatable, Sendable {
    case available
    case unavailable(reason: String)
}

public protocol SystemCursorApplying: Sendable {
    var availability: SystemCursorAvailability { get }
    func apply(_ theme: CursorTheme) throws
    func restoreDefaults() throws
}

public enum MomijiError: Error, LocalizedError, Equatable {
    case invalidFormat(String)
    case truncatedData
    case unsupportedBitmap(String)
    case unsafeInput(String)
    case resourceLimit(String)
    case noUsableCursors
    case conflictingRole(CursorRole)
    case packageVersion(Int)
    case missingTheme(UUID)
    case systemCursorUnavailable(String)
    case systemCursorFailure(String)

    public var errorDescription: String? {
        switch self {
        case .invalidFormat(let detail): "Invalid cursor format: \(detail)"
        case .truncatedData: "The cursor file is truncated."
        case .unsupportedBitmap(let detail): "Unsupported cursor bitmap: \(detail)"
        case .unsafeInput(let detail): "Unsafe input rejected: \(detail)"
        case .resourceLimit(let detail): "Cursor resource limit exceeded: \(detail)"
        case .noUsableCursors: "No usable cursors were found."
        case .conflictingRole(let role): "More than one cursor is assigned to \(role.rawValue)."
        case .packageVersion(let version): "Unsupported Momiji package version \(version)."
        case .missingTheme(let id): "Theme \(id.uuidString) was not found."
        case .systemCursorUnavailable(let reason): "System cursor replacement is unavailable: \(reason)"
        case .systemCursorFailure(let detail): "Could not apply the cursor theme: \(detail)"
        }
    }
}

private func greatestCommonDivisor(_ lhs: Int, _ rhs: Int) -> Int {
    var a = abs(lhs)
    var b = abs(rhs)
    while b != 0 {
        (a, b) = (b, a % b)
    }
    return max(1, a)
}

private func expandedCount(_ durations: [Int], quantum: Int) -> Int {
    var total = 0
    for duration in durations {
        let addition = total.addingReportingOverflow(roundedQuotient(duration, quantum))
        if addition.overflow { return Int.max }
        total = addition.partialValue
    }
    return total
}

private func roundedQuotient(_ duration: Int, _ quantum: Int) -> Int {
    let safeDuration = max(1, duration)
    let safeQuantum = max(1, quantum)
    let quotient = safeDuration / safeQuantum
    let remainder = safeDuration % safeQuantum
    let roundsUp = remainder >= safeQuantum / 2 + safeQuantum % 2
    return max(1, quotient + (roundsUp ? 1 : 0))
}
