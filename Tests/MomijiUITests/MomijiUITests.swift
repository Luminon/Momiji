import XCTest

final class MomijiUITests: XCTestCase {
    private var temporaryRoot: URL!
    private var fixtureFolder: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MomijiUITests-\(UUID().uuidString)", isDirectory: true)
        fixtureFolder = temporaryRoot.appendingPathComponent("Fixture", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureFolder, withIntermediateDirectories: true)
        try makeCUR().write(to: fixtureFolder.appendingPathComponent("aero_arrow.cur"))
    }

    override func tearDownWithError() throws {
        if let temporaryRoot { try? FileManager.default.removeItem(at: temporaryRoot) }
    }

    @MainActor
    func testEnglishImportEditApplyAndRestoreFlow() throws {
        try runWorkflow(language: "en", locale: "en_US", restoredText: "System cursors restored.")
    }

    @MainActor
    func testKoreanImportEditApplyAndRestoreFlow() throws {
        try runWorkflow(language: "ko", locale: "ko_KR", restoredText: "시스템 커서를 복원했습니다.")
    }

    @MainActor
    func testDisablingDuplicateRoleEnablesSaveAndApply() throws {
        try makeCUR().write(to: fixtureFolder.appendingPathComponent("normal.cur"))

        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(ko)",
            "-AppleLocale", "ko_KR",
            "-ApplePersistenceIgnoreState", "YES",
            "-MomijiHideDockIcon", "NO",
        ]
        app.launchEnvironment["MOMIJI_LIBRARY_ROOT"] = temporaryRoot.appendingPathComponent("Library").path
        app.launchEnvironment["MOMIJI_UI_TEST_FIXTURE"] = fixtureFolder.path
        app.launchEnvironment["MOMIJI_UI_TEST_MOCK_SYSTEM"] = "1"
        app.launch()
        defer { app.terminate() }

        let saveAndApply = app.buttons["save-apply-import-button"]
        XCTAssertTrue(saveAndApply.waitForExistence(timeout: 5))
        XCTAssertFalse(saveAndApply.isEnabled)

        let duplicateRole = app.popUpButtons["import-role-picker-normal.cur"]
        XCTAssertTrue(duplicateRole.waitForExistence(timeout: 5))
        duplicateRole.click()
        let unused = app.menuItems["사용 안 함"]
        XCTAssertTrue(unused.waitForExistence(timeout: 5))
        unused.click()

        XCTAssertTrue(saveAndApply.isEnabled)
        saveAndApply.click()
        XCTAssertTrue(app.staticTexts["Fixture"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testMissingPreviewKeepsImportTableWidth() throws {
        try makeCUR().write(to: fixtureFolder.appendingPathComponent("Alternate.cur"))

        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(ko)",
            "-AppleLocale", "ko_KR",
            "-ApplePersistenceIgnoreState", "YES",
            "-MomijiHideDockIcon", "NO",
        ]
        app.launchEnvironment["MOMIJI_LIBRARY_ROOT"] = temporaryRoot.appendingPathComponent("Library").path
        app.launchEnvironment["MOMIJI_UI_TEST_FIXTURE"] = fixtureFolder.path
        app.launchEnvironment["MOMIJI_UI_TEST_MOCK_SYSTEM"] = "1"
        app.launch()
        defer { app.terminate() }

        let table = app.descendants(matching: .any)["import-review-table"].firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: 5))
        let widthWithPreview = table.frame.width
        XCTAssertGreaterThan(widthWithPreview, 700)

        let alternate = app.staticTexts["Alternate.cur"]
        XCTAssertTrue(alternate.waitForExistence(timeout: 5))
        alternate.click()

        let placeholder = app.descendants(matching: .any)["import-review-placeholder"].firstMatch
        XCTAssertTrue(placeholder.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(table.frame.width, widthWithPreview * 0.95)
    }

    @MainActor
    func testDockIconVisibilityCanBeChangedFromSettings() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(ko)",
            "-AppleLocale", "ko_KR",
            "-ApplePersistenceIgnoreState", "YES",
            "-MomijiHideDockIcon", "NO",
        ]
        app.launchEnvironment["MOMIJI_LIBRARY_ROOT"] = temporaryRoot.appendingPathComponent("Library").path
        app.launchEnvironment["MOMIJI_UI_TEST_MOCK_SYSTEM"] = "1"
        app.launch()
        defer { app.terminate() }

        let settings = app.buttons["settings-button"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.click()

        let toggle = app.switches["hide-dock-icon-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForToggle(toggle, value: false))

        toggle.click()
        XCTAssertTrue(waitForToggle(toggle, value: true))

        // Switching to accessory mode can hand focus to another application.
        // Bring Momiji back to the front before testing the restore path.
        app.activate()
        toggle.click()
        XCTAssertTrue(waitForToggle(toggle, value: false))
    }

    @MainActor
    private func runWorkflow(language: String, locale: String, restoredText: String) throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale,
            "-ApplePersistenceIgnoreState", "YES",
            "-MomijiHideDockIcon", "NO",
        ]
        app.launchEnvironment["MOMIJI_LIBRARY_ROOT"] = temporaryRoot.appendingPathComponent("Library").path
        app.launchEnvironment["MOMIJI_UI_TEST_FIXTURE"] = fixtureFolder.path
        app.launchEnvironment["MOMIJI_UI_TEST_MOCK_SYSTEM"] = "1"
        app.launch()
        defer { app.terminate() }
        app.activate()

        let save = app.buttons["save-import-button"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        let saveEnabled = save.isEnabled
        XCTAssertTrue(saveEnabled)
        app.activate()
        save.click()

        XCTAssertTrue(app.staticTexts["Fixture"].waitForExistence(timeout: 5))
        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists)
        assertDetailLayout(in: window, app: app)
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02))
            .press(
                forDuration: 0.1,
                thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: -0.2))
            )

        let hotspot = app.textFields["hotspot-x-field"]
        XCTAssertTrue(hotspot.waitForExistence(timeout: 5))
        XCTAssertTrue(hotspot.isEnabled)
        hotspot.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        app.typeKey("a", modifierFlags: .command)
        app.typeText("0")

        app.typeKey(.tab, modifierFlags: [])
        app.typeKey(.tab, modifierFlags: [])
        app.typeKey(.rightArrow, modifierFlags: [])

        let apply = app.buttons["apply-theme-button"]
        XCTAssertTrue(apply.isEnabled)
        app.activate()
        apply.click()
        let restore = app.buttons["restore-defaults-button"]
        XCTAssertTrue(restore.exists)
        app.activate()
        restore.click()
        XCTAssertTrue(app.staticTexts[restoredText].waitForExistence(timeout: 5))

        let settings = app.buttons["settings-button"]
        XCTAssertTrue(settings.exists)
        app.activate()
        settings.click()

        let cursorScale = app.sliders["cursor-scale-slider"]
        XCTAssertTrue(cursorScale.waitForExistence(timeout: 5))
        cursorScale.adjust(toNormalizedSliderPosition: 0.5)

        let closeSettings = app.buttons["settings-close-button"]
        XCTAssertTrue(closeSettings.exists)
        closeSettings.click()
        XCTAssertFalse(closeSettings.exists)
    }

    @MainActor
    private func assertDetailLayout(in window: XCUIElement, app: XCUIApplication) {
        let themeName = app.textFields["theme-name-field"]
        let cursorList = app.descendants(matching: .any)["cursor-list"].firstMatch
        let editor = app.descendants(matching: .any)["cursor-editor"].firstMatch

        XCTAssertTrue(themeName.waitForExistence(timeout: 5))
        XCTAssertTrue(cursorList.waitForExistence(timeout: 5))
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertLessThan(themeName.frame.minY, window.frame.minY + 220)
        XCTAssertGreaterThan(cursorList.frame.width, 220)
        XCTAssertLessThan(cursorList.frame.width, 320)
        XCTAssertGreaterThan(editor.frame.width, 360)
    }

    private func waitForToggle(_ toggle: XCUIElement, value: Bool) -> Bool {
        let predicate = NSPredicate(format: "value == %d", value ? 1 : 0)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: toggle)
        return XCTWaiter.wait(for: [expectation], timeout: 3) == .completed
    }
}

private func makeCUR() -> Data {
    var dib = Data()
    dib.appendLE(UInt32(40))
    dib.appendLE(Int32(1))
    dib.appendLE(Int32(2))
    dib.appendLE(UInt16(1))
    dib.appendLE(UInt16(32))
    dib.appendLE(UInt32(0))
    dib.appendLE(UInt32(4))
    dib.appendLE(Int32(0))
    dib.appendLE(Int32(0))
    dib.appendLE(UInt32(0))
    dib.appendLE(UInt32(0))
    dib.append(contentsOf: [0, 0, 255, 255, 0, 0, 0, 0])

    var cur = Data()
    cur.appendLE(UInt16(0))
    cur.appendLE(UInt16(2))
    cur.appendLE(UInt16(1))
    cur.append(contentsOf: [1, 1, 0, 0])
    cur.appendLE(UInt16(0))
    cur.appendLE(UInt16(0))
    cur.appendLE(UInt32(dib.count))
    cur.appendLE(UInt32(22))
    cur.append(dib)
    return cur
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
