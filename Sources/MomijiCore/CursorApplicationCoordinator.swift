import Foundation

/// Keeps the system cursor and Momiji's persisted active-theme state in sync.
/// If either half of an apply operation fails, the previously active theme is restored.
public final class CursorApplicationCoordinator: @unchecked Sendable {
    private let store: any ThemeStoring
    private let engine: any SystemCursorApplying
    private let lock = NSRecursiveLock()

    public init(store: any ThemeStoring, engine: any SystemCursorApplying) {
        self.store = store
        self.engine = engine
    }

    public func apply(_ theme: CursorTheme, cursorScale: Double = CursorScale.default) throws {
        try lock.withLock {
            let previous = try previousTheme()
            let previousScale = try store.activeCursorScale()
            let scale = CursorScale.clamped(cursorScale)
            do {
                try engine.apply(theme.scaled(by: scale))
                try store.setActiveTheme(id: theme.id, cursorScale: scale)
            } catch {
                rollback(to: previous, cursorScale: previousScale)
                throw error
            }
        }
    }

    public func restoreDefaults() throws {
        try lock.withLock {
            let previous = try previousTheme()
            let previousScale = try store.activeCursorScale()
            do {
                try engine.restoreDefaults()
                try store.setActiveThemeID(nil)
            } catch {
                rollback(to: previous, cursorScale: previousScale)
                throw error
            }
        }
    }

    private func previousTheme() throws -> CursorTheme? {
        guard let id = try store.activeThemeID() else { return nil }
        return try store.loadTheme(id: id)
    }

    private func rollback(to theme: CursorTheme?, cursorScale: Double) {
        if let theme {
            try? engine.apply(theme.scaled(by: cursorScale))
            try? store.setActiveTheme(id: theme.id, cursorScale: cursorScale)
        } else {
            try? engine.restoreDefaults()
            try? store.setActiveTheme(id: nil, cursorScale: cursorScale)
        }
    }
}
