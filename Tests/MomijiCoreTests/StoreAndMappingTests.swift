import Foundation
import Testing
@testable import MomijiCore

@Suite("Theme mapping and storage")
struct StoreAndMappingTests {
    @Test("Common Windows cursor names map deterministically", arguments: [
        ("aero_arrow", CursorRole.arrow),
        ("aero_text", CursorRole.iBeam),
        ("aero_link", CursorRole.pointingHand),
        ("aero_working", CursorRole.progress),
        ("aero_busy", CursorRole.wait),
        ("aero_nwse", CursorRole.resizeNorthwestSoutheast),
        ("aero_nesw", CursorRole.resizeNortheastSouthwest),
        ("aero_move", CursorRole.move),
    ])
    func mapsNames(_ value: (String, CursorRole)) {
        #expect(WindowsThemeImporter.inferRole(from: value.0) == value.1)
    }

    @Test("Handwriting cursor is not mistaken for a pointing hand")
    func leavesUnsupportedHandwritingUnmapped() {
        #expect(WindowsThemeImporter.inferRole(from: "Handwriting") == nil)
        #expect(WindowsThemeImporter.inferRole(from: "aero_handwriting") == nil)
        #expect(WindowsThemeImporter.inferRole(from: "aero_hand") == .pointingHand)
    }

    @Test("Momiji package round-trips without image or timing loss")
    func packageRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MomijiTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MomijiThemeStore(rootURL: root)
        let parsed = try ANIParser().parseCUR(data: makeCUR(red: 20, green: 40, blue: 60))
        let theme = CursorTheme(name: "Fixture", author: "Momiji Tests", cursors: [parsed.asset(role: .arrow)])

        _ = try store.save(theme)
        let loaded = try store.loadTheme(id: theme.id)
        #expect(loaded.id == theme.id)
        #expect(loaded.name == theme.name)
        #expect(loaded.author == theme.author)
        #expect(abs(loaded.createdAt.timeIntervalSince(theme.createdAt)) < 0.001)
        #expect(loaded.cursors == theme.cursors)
        let listed = try store.listThemes()
        #expect(listed.count == 1)
        #expect(listed.first?.id == theme.id)
        #expect(listed.first?.cursors == theme.cursors)
        try store.setActiveThemeID(theme.id)
        #expect(try store.activeThemeID() == theme.id)
        #expect(try store.activeCursorScale() == CursorScale.default)

        try store.setPreferredCursorScale(1.35)
        #expect(try store.preferredCursorScale() == 1.35)
        try store.setActiveTheme(id: theme.id, cursorScale: 1.5)
        #expect(try store.activeCursorScale() == 1.5)
    }

    @Test("Global cursor scale preserves source data and scales geometry")
    func scalesThemeGeometry() throws {
        let parsed = try ANIParser().parseCUR(data: makeCUR(red: 3, green: 6, blue: 9))
        var asset = parsed.asset(role: .arrow)
        asset.logicalSize = CursorSize(width: 32, height: 24)
        asset.hotspot = CursorPoint(x: 4, y: 6)
        let theme = CursorTheme(name: "Scale", cursors: [asset])

        let scaled = theme.scaled(by: 1.5)
        #expect(theme.cursors[0].logicalSize == CursorSize(width: 32, height: 24))
        #expect(theme.cursors[0].hotspot == CursorPoint(x: 4, y: 6))
        #expect(scaled.cursors[0].logicalSize == CursorSize(width: 48, height: 36))
        #expect(scaled.cursors[0].hotspot == CursorPoint(x: 6, y: 9))
        #expect(scaled.cursors[0].representations == theme.cursors[0].representations)
    }

    @Test("Duplicate role selections are rejected")
    func rejectsRoleConflict() throws {
        let parsed = try ANIParser().parseCUR(data: makeCUR(red: 1, green: 2, blue: 3))
        let result = ThemeImportResult(
            suggestedName: "Conflict",
            author: nil,
            items: [
                ThemeImportItem(sourceURL: URL(fileURLWithPath: "/a.cur"), role: .arrow, asset: parsed.asset(role: .arrow)),
                ThemeImportItem(sourceURL: URL(fileURLWithPath: "/b.cur"), role: .arrow, asset: parsed.asset(role: .arrow)),
            ],
            warnings: []
        )
        #expect(throws: MomijiError.conflictingRole(.arrow)) {
            try result.makeTheme()
        }
    }

    @Test("Disabling one duplicate role makes an import savable")
    func disablingConflictMakesTheme() throws {
        let parsed = try ANIParser().parseCUR(data: makeCUR(red: 1, green: 2, blue: 3))
        var result = ThemeImportResult(
            suggestedName: "Resolved Conflict",
            author: nil,
            items: [
                ThemeImportItem(sourceURL: URL(fileURLWithPath: "/Link.cur"), role: .pointingHand, asset: parsed.asset(role: .pointingHand)),
                ThemeImportItem(sourceURL: URL(fileURLWithPath: "/Handwriting.cur"), role: .pointingHand, asset: parsed.asset(role: .pointingHand)),
            ],
            warnings: []
        )

        #expect(result.conflictingRoles == [.pointingHand])
        #expect(!result.canMakeTheme)
        result.items[1].role = nil
        #expect(result.conflictingRoles.isEmpty)
        #expect(result.canMakeTheme)

        let theme = try result.makeTheme()
        #expect(theme.cursors.count == 1)
        #expect(theme.cursors[0].role == .pointingHand)
    }

    @Test("INF role assignments take priority over filename heuristics")
    func prefersINFMapping() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MomijiINFTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try makeCUR(red: 4, green: 5, blue: 6).write(to: root.appendingPathComponent("aero_busy.cur"))
        let inf = #"HKCU,"Control Panel\\Cursors","Arrow",0,"%10%\\aero_busy.cur""#
        try Data(inf.utf8).write(to: root.appendingPathComponent("theme.inf"))

        let result = try WindowsThemeImporter().importTheme(at: root)
        #expect(result.items.count == 1)
        #expect(result.items[0].role == .arrow)
    }

    @Test("INF filenames do not masquerade as registry roles")
    func ignoresRoleWordsInsideINFFilenames() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MomijiINFRoleTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try makeCUR(red: 4, green: 5, blue: 6).write(to: root.appendingPathComponent("Handwriting.cur"))
        try makeCUR(red: 7, green: 8, blue: 9).write(to: root.appendingPathComponent("Link.cur"))
        let inf = """
        HKCU,"Control Panel\\Cursors","NWPen",0,"%10%\\Handwriting.cur"
        HKCU,"Control Panel\\Cursors","Hand",0,"%10%\\Link.cur"
        """
        try Data(inf.utf8).write(to: root.appendingPathComponent("theme.inf"))

        let result = try WindowsThemeImporter().importTheme(at: root)
        let handwriting = try #require(result.items.first { $0.sourceURL.lastPathComponent == "Handwriting.cur" })
        let link = try #require(result.items.first { $0.sourceURL.lastPathComponent == "Link.cur" })
        #expect(handwriting.role == nil)
        #expect(link.role == .pointingHand)
    }

    @Test("Theme source symbolic links are rejected")
    func rejectsThemeSymlinks() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MomijiSymlinkTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let real = root.appendingPathComponent("real.cur")
        try makeCUR(red: 1, green: 2, blue: 3).write(to: real)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("linked.cur"),
            withDestinationURL: real
        )
        #expect(throws: MomijiError.unsafeInput("theme source contains a symbolic link")) {
            try WindowsThemeImporter().importTheme(at: root)
        }
    }

    @Test("Unsupported and invalid package manifests are rejected")
    func rejectsCorruptManifest() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MomijiManifestTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MomijiThemeStore(rootURL: root)
        let parsed = try ANIParser().parseCUR(data: makeCUR(red: 8, green: 9, blue: 10))
        let theme = CursorTheme(name: "Manifest", cursors: [parsed.asset(role: .arrow)])
        let package = try store.save(theme)
        let manifestURL = package.appendingPathComponent("manifest.json")
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        object["schemaVersion"] = 99
        try JSONSerialization.data(withJSONObject: object).write(to: manifestURL, options: .atomic)
        #expect(throws: MomijiError.packageVersion(99)) {
            try store.loadTheme(id: theme.id)
        }
    }

    @Test("A failed system apply restores the previous active theme")
    func rollsBackFailedApply() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MomijiRollbackTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MomijiThemeStore(rootURL: root)
        let parsed = try ANIParser().parseCUR(data: makeCUR(red: 12, green: 34, blue: 56))
        let previous = CursorTheme(name: "Previous", cursors: [parsed.asset(role: .arrow)])
        let replacement = CursorTheme(name: "Replacement", cursors: [parsed.asset(role: .arrow)])
        _ = try store.save(previous)
        _ = try store.save(replacement)
        try store.setActiveTheme(id: previous.id, cursorScale: 1.25)

        let engine = RecordingCursorEngine(failingThemeID: replacement.id)
        let coordinator = CursorApplicationCoordinator(store: store, engine: engine)
        #expect(throws: RecordingCursorEngine.Failure.self) {
            try coordinator.apply(replacement, cursorScale: 1.5)
        }
        #expect(try store.activeThemeID() == previous.id)
        #expect(try store.activeCursorScale() == 1.25)
        #expect(engine.appliedThemeIDs == [replacement.id, previous.id])
        #expect(engine.appliedWidths == [1.5, 1.25])
    }

    @Test("Restoring defaults clears the active theme")
    func restoresDefaultsTransactionally() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MomijiRestoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MomijiThemeStore(rootURL: root)
        let parsed = try ANIParser().parseCUR(data: makeCUR(red: 10, green: 20, blue: 30))
        let theme = CursorTheme(name: "Active", cursors: [parsed.asset(role: .arrow)])
        _ = try store.save(theme)
        try store.setActiveThemeID(theme.id)

        let engine = RecordingCursorEngine()
        try CursorApplicationCoordinator(store: store, engine: engine).restoreDefaults()
        #expect(try store.activeThemeID() == nil)
        #expect(engine.restoreCount == 1)
    }
}

private final class RecordingCursorEngine: SystemCursorApplying, @unchecked Sendable {
    enum Failure: Error { case requested }

    let failingThemeID: UUID?
    private(set) var appliedThemeIDs: [UUID] = []
    private(set) var appliedWidths: [Double] = []
    private(set) var restoreCount = 0

    init(failingThemeID: UUID? = nil) {
        self.failingThemeID = failingThemeID
    }

    var availability: SystemCursorAvailability { .available }

    func apply(_ theme: CursorTheme) throws {
        appliedThemeIDs.append(theme.id)
        appliedWidths.append(theme.cursors.first?.logicalSize.width ?? 0)
        if theme.id == failingThemeID { throw Failure.requested }
    }

    func restoreDefaults() throws {
        restoreCount += 1
    }
}
