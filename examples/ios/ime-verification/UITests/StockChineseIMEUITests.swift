import XCTest

@MainActor
final class StockChineseIMEUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testConfigureStockSimplifiedChinesePinyin() throws {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        if settings.buttons["KEYBOARDS"].exists {
            tap(settings.buttons["KEYBOARDS"], in: settings)
        } else if settings.buttons["com.apple.settings.general.keyboard"].exists {
            tap(settings.buttons["com.apple.settings.general.keyboard"], in: settings)
        } else {
            tap(label(in: settings, ["General", "通用"]), in: settings)
            tap(settings.buttons["com.apple.settings.general.keyboard"], in: settings)
        }
        capture(settings, named: "keyboard-settings")
        tap(settings.cells["KEYBOARDS"], in: settings)
        capture(settings, named: "keyboards-before")
        let pinyin = settings.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS %@", "Pinyin", "拼音")
        ).firstMatch
        if !pinyin.exists {
            tap(label(in: settings, ["Add New Keyboard...", "添加新键盘…", "添加新键盘..."]), in: settings)
            capture(settings, named: "add-keyboard")
            let chinese = label(in: settings, ["Chinese, Simplified", "中文（简体）", "简体中文"])
            XCTAssertTrue(chinese.waitForExistence(timeout: 10), settings.debugDescription)
            chinese.tap()
            capture(settings, named: "chinese-layouts")
            tap(label(in: settings, ["Pinyin", "拼音"]), in: settings)
            capture(settings, named: "pinyin-added")
        }
        XCTAssertTrue(pinyin.waitForExistence(timeout: 5), settings.debugDescription)
        capture(settings, named: "pinyin-configured")
    }

    func testStockPinyinEditingFocusDoneAndDraft() throws {
        let app = XCUIApplication()
        app.launch()
        let field = app.textFields["composer"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), app.debugDescription)
        field.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 10), "Real software keyboard required:\n\(app.debugDescription)")
        Thread.sleep(forTimeInterval: 1)
        selectPinyin(app)
        tapKey("n", in: app)
        tapKey("i", in: app)
        let candidate = app.cells["你"]
        XCTAssertTrue(candidate.waitForExistence(timeout: 5), "No native Chinese candidate:\n\(app.debugDescription)")
        capture(app, named: "pinyin-marked")
        print("REFRACT_PINYIN_UI \(app.debugDescription)")

        candidate.tap()
        XCTAssertTrue(waitForValue(of: field, equals: "你"), "Candidate was not committed:\n\(app.debugDescription)")
        XCTAssertEqual(app.staticTexts["draft"].label, "Draft: 你")
        XCTAssertFalse(app.cells["你"].exists)
        capture(app, named: "candidate-committed")

        // Moving native focus away and requesting it through the original host
        // must preserve the committed draft and restore the real keyboard.
        app.textFields["alternate-focus"].tap()
        XCTAssertTrue(waitForFocus(of: app.textFields["alternate-focus"]), app.debugDescription)
        XCTAssertTrue(waitForFocusLoss(of: field), app.debugDescription)
        XCTAssertEqual(app.staticTexts["draft"].label, "Draft: 你")
        app.buttons["restore-focus"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(waitForFocus(of: field), "Focus was not restored:\n\(app.debugDescription)")
        XCTAssertEqual(field.value as? String, "你")
        capture(app, named: "focus-restored")

        // The onscreen return key, not injected text or a synthetic callback,
        // must publish the committed value before the app's commit action.
        app.buttons["Done"].tap()
        XCTAssertTrue(waitForLabel(of: app.staticTexts["committed-drafts"], equals: "Committed drafts: 1"), app.debugDescription)
        XCTAssertEqual(app.staticTexts["commit-actions"].label, "Commit actions: 1")
        XCTAssertEqual(app.staticTexts["last-committed-draft"].label, "Last committed draft: 你")
        XCTAssertEqual(app.staticTexts["commit-order"].label, "Draft committed before action: true")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "Done did not dismiss the keyboard:\n\(app.debugDescription)")
        capture(app, named: "done-committed")

        app.buttons["toggle-host"].tap()
        XCTAssertFalse(field.exists)
        XCTAssertEqual(app.staticTexts["draft"].label, "Draft: 你")
        app.buttons["toggle-host"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "你")
        XCTAssertEqual(app.staticTexts["draft"].label, "Draft: 你")
        capture(app, named: "draft-preserved")
    }

    private func selectPinyin(_ app: XCUIApplication) {
        let nextKeyboard = app.buttons["Next keyboard"]
        XCTAssertTrue(nextKeyboard.waitForExistence(timeout: 5), app.debugDescription)
        nextKeyboard.press(forDuration: 1.2)
        let pinyin = app.cells.matching(
            NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS %@", "Pinyin", "拼音")
        ).firstMatch
        XCTAssertTrue(pinyin.waitForExistence(timeout: 5), app.debugDescription)
        pinyin.tap()
        Thread.sleep(forTimeInterval: 0.5)
        capture(app, named: "pinyin-mode-selected")
    }

    private func tapKey(_ key: String, in app: XCUIApplication) {
        let element = app.keys[key].exists ? app.keys[key] : app.keys[key.uppercased()]
        XCTAssertTrue(element.waitForExistence(timeout: 3), "Missing actual key \(key):\n\(app.debugDescription)")
        element.tap()
        Thread.sleep(forTimeInterval: 0.3)
    }

    private func waitForValue(of element: XCUIElement, equals value: String) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        return XCTNSPredicateExpectation(predicate: predicate, object: element).waitForResult(timeout: 5)
    }

    private func waitForFocus(of element: XCUIElement) -> Bool {
        let predicate = NSPredicate(format: "hasKeyboardFocus == true")
        return XCTNSPredicateExpectation(predicate: predicate, object: element).waitForResult(timeout: 5)
    }

    private func waitForFocusLoss(of element: XCUIElement) -> Bool {
        let predicate = NSPredicate(format: "hasKeyboardFocus == false")
        return XCTNSPredicateExpectation(predicate: predicate, object: element).waitForResult(timeout: 5)
    }

    private func waitForLabel(of element: XCUIElement, equals value: String) -> Bool {
        let predicate = NSPredicate(format: "label == %@", value)
        return XCTNSPredicateExpectation(predicate: predicate, object: element).waitForResult(timeout: 5)
    }

    private func label(in app: XCUIApplication, _ labels: [String]) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "label IN %@", labels)
        ).firstMatch
    }

    private func tap(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), app.debugDescription)
        element.tap()
    }

    private func capture(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private extension XCTNSPredicateExpectation {
    func waitForResult(timeout: TimeInterval) -> Bool {
        XCTWaiter.wait(for: [self], timeout: timeout) == .completed
    }
}
