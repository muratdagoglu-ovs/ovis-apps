import XCTest

/// Gerçek kullanıcı akışı: boş uygulamada profil oluşturma, su ekleme/geri alma ve yeniden açılışta kalıcılık.
final class OnboardingUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testProfileWaterAndPersistence() {
        let app = XCUIApplication()
        app.launchArguments = ["-OvisResetData"]
        app.launch()

        // 1 · Profil: kutulara gerçekten yazılabiliyor mu? İlk kutuya dokunulur,
        // sonrakilere klavyenin üstündeki "Sonraki" ile geçilir (kullanıcının yaptığı gibi).
        let name = app.textFields["field.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 8), "İsim kutusu yok")
        name.tap()
        name.typeText("Murat")
        XCTAssertEqual(name.value as? String, "Murat", "İsim kutusuna yazılamadı")
        for (id, text) in [("field.age", "35"), ("field.height", "175"), ("field.weight", "72.5")] {
            app.buttons["Sonraki"].tap()
            let field = app.textFields[id]
            field.typeText(text)
            XCTAssertEqual(field.value as? String, text, "\(id) kutusuna yazılamadı")
        }
        app.buttons["Bitti"].tap()

        // Kilo kutusuna klavye kapalıyken doğrudan dokunup düzeltme de çalışmalı
        let weight = app.textFields["field.weight"]
        weight.tap()
        weight.typeText("0")   // 72.50
        XCTAssertEqual(weight.value as? String, "72.50")
        app.buttons["Bitti"].tap()
        tapButton(app, containing: "Devam et")

        // 2 · Hedef
        XCTAssertTrue(app.staticTexts["Kilomu korumak"].waitForExistence(timeout: 5), "Hedef ekranı açılmadı")
        tapButton(app, containing: "Kilo vermek")
        tapButton(app, containing: "Onayla ve planımı gör")

        // 3 · Bugün ekranı ve isim
        XCTAssertTrue(app.tabBars.buttons["Bugün"].waitForExistence(timeout: 8), "Ana sekmelere geçilmedi")
        XCTAssertTrue(element(app, "Murat").waitForExistence(timeout: 5), "İsim ana ekranda yok")

        // 4 · Su ekle ve geri al
        app.tabBars.buttons["Su"].tap()
        tapButton(app, containing: "250 mililitre su ekle")
        XCTAssertTrue(element(app, "tüm içecekler 250 mililitre").waitForExistence(timeout: 5), "Su eklenmedi")
        tapButton(app, containing: "Son eklemeyi geri al")
        XCTAssertTrue(element(app, "tüm içecekler 0 mililitre").waitForExistence(timeout: 5), "Geri alma çalışmadı")
        tapButton(app, containing: "500 mililitre su ekle")
        XCTAssertTrue(element(app, "tüm içecekler 500 mililitre").waitForExistence(timeout: 5))

        // 5 · Yeniden açılış: profil ve su kaydı kalıcı mı?
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Bugün"].waitForExistence(timeout: 8), "Profil kalıcı değil")
        app.tabBars.buttons["Su"].tap()
        XCTAssertTrue(element(app, "tüm içecekler 500 mililitre").waitForExistence(timeout: 5), "Su kaydı kalıcı değil")
    }

    private func type(_ app: XCUIApplication, _ id: String, _ text: String) {
        let field = app.textFields[id]
        XCTAssertTrue(field.waitForExistence(timeout: 8), "\(id) bulunamadı")
        field.tap()
        field.typeText(text)
        XCTAssertEqual(field.value as? String, text, "\(id) kutusuna yazılamadı")
    }

    private func element(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func tapButton(_ app: XCUIApplication, containing text: String) {
        let button = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 8), "'\(text)' düğmesi yok")
        if !button.isHittable { app.swipeUp() }
        button.tap()
    }
}
