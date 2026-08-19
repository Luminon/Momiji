import Foundation
import MomijiCore
import MomijiSystem
import Testing

@Suite("Opt-in system cursor integration")
struct SystemCursorIntegrationTests {
    @Test(
        "A real cursor can be applied and always restored",
        .enabled(if: ProcessInfo.processInfo.environment["MOMIJI_RUN_SYSTEM_INTEGRATION_TESTS"] == "1")
    )
    func appliesAndRestoresRealCursor() throws {
        let engine = PrivateSystemCursorEngine()
        guard case .available = engine.availability else {
            throw MomijiError.systemCursorUnavailable("private runtime symbols are unavailable")
        }
        guard let png = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Zl8sAAAAASUVORK5CYII="
        ) else {
            throw MomijiError.invalidFormat("integration PNG fixture is invalid")
        }
        let cursor = CursorAsset(
            role: .arrow,
            logicalSize: CursorSize(width: 1, height: 1),
            hotspot: CursorPoint(x: 0, y: 0),
            representations: [
                CursorRepresentation(scale: 1, frames: [CursorFrame(pngData: png)]),
                CursorRepresentation(scale: 2, frames: [CursorFrame(pngData: png)]),
            ],
            timeline: .still
        )

        defer { try? engine.restoreDefaults() }
        try engine.apply(CursorTheme(name: "Momiji Integration Fixture", cursors: [cursor]))
    }
}
