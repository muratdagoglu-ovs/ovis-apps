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

        // 1 · Adım adım açılış: isim klavyeyle, yaş/boy/kilo çarkla, diğerleri kartlarla
        tapButton(app, containing: "Başlayalım")
        let name = app.textFields["onb.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 8), "İsim kutusu yok")
        name.tap()
        name.typeText("Murat")
        XCTAssertEqual(name.value as? String, "Murat", "İsim kutusuna yazılamadı")
        tapButton(app, containing: "Devam")                      // → cinsiyet
        tapButton(app, containing: "Erkek")
        tapButton(app, containing: "Devam")                      // → yaş
        app.pickerWheels.element(boundBy: 0).adjust(toPickerWheelValue: "35")
        tapButton(app, containing: "Devam")                      // → boy
        app.pickerWheels.element(boundBy: 0).adjust(toPickerWheelValue: "175")
        tapButton(app, containing: "Devam")                      // → kilo
        app.pickerWheels.element(boundBy: 0).adjust(toPickerWheelValue: "72")
        app.pickerWheels.element(boundBy: 1).adjust(toPickerWheelValue: ",5")
        tapButton(app, containing: "Devam")                      // → hareket
        tapButton(app, containing: "Devam")                      // → hedef
        tapButton(app, containing: "Kilo vermek")
        tapButton(app, containing: "Devam")                      // → beslenme
        tapButton(app, containing: "Süt ve süt ürünleri")
        tapButton(app, containing: "Devam")                      // → özet
        XCTAssertTrue(element(app, "Günlük enerji hedefin").waitForExistence(timeout: 5), "Özet ekranı yok")
        tapButton(app, containing: "Planımı oluştur")

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
