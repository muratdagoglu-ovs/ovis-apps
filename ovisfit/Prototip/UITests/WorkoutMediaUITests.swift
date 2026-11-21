import XCTest

/// Antrenman: eğitmen (kadın/erkek) kapakları, yerel MP4 oynatma/duraklatma, hareket değişince doğru klip,
/// profil değişince açık ekranların güncellenmesi ve cinsiyeti belirtilmemiş profilde eğitmen seçiminin kalıcılığı.
/// Videolar uygulama paketindeki WorkoutMedia klasöründen okunur; oynat/duraklat düğmesi yalnızca
/// paket içinde ilgili .mp4 bulunduğunda görünür (ağ bağlantısı kullanılmaz).
final class WorkoutMediaUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private let gym = ["Barbell squat", "Lat pulldown", "Dambıl bench press"]
    private let home = ["Şınav", "Kalça köprüsü"]

    private func launch(sex: String, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-OvisScreenshotData", "-OvisSex", sex] + extra
        app.launch()
        app.tabBars.buttons["Antrenman"].tap()
        return app
    }

    func testFemaleTrainerFiveExercises() { checkFiveExercises(sex: "female", trainer: "Kadın eğitmen") }
    func testMaleTrainerFiveExercises() { checkFiveExercises(sex: "male", trainer: "Erkek eğitmen") }

    private func checkFiveExercises(sex: String, trainer: String) {
        let app = launch(sex: sex)
        XCTAssertFalse(app.segmentedControls.buttons[trainer].exists, "Cinsiyeti belli profilde eğitmen seçici görünmemeli")
        for (place, names) in [("Salon", gym), ("Ev", home)] {
            tap(app, place)
            XCTAssertTrue(button(app, names[0]).waitForExistence(timeout: 5), "\(place) programı açılmadı")
            for name in names {
                tap(app, name)                                          // satır → detay
                XCTAssertTrue(element(app, "\(name), \(trainer)").waitForExistence(timeout: 8), "\(name): \(trainer) gösterimi yok")
                let pause = app.buttons["Gösterimi duraklat"]
                XCTAssertTrue(pause.waitForExistence(timeout: 5), "\(name): yerel video oynamıyor (paket içinde .mp4 yok mu?)")
                pause.tap()
                XCTAssertTrue(app.buttons["Egzersiz gösterimini oynat"].waitForExistence(timeout: 3), "\(name): duraklatılamadı")
                app.buttons["Egzersiz gösterimini oynat"].tap()
                XCTAssertTrue(app.buttons["Gösterimi duraklat"].waitForExistence(timeout: 3), "\(name): yeniden oynatılamadı")
                app.navigationBars.buttons.element(boundBy: 0).tap()   // geri
            }
        }
    }

    func testPlayerSwitchesClipWithExercise() {
        let app = launch(sex: "female")
        tap(app, "Salon")
        tap(app, "Antrenmanı başlat")

        XCTAssertTrue(element(app, "Barbell squat, Kadın eğitmen").waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Gösterimi duraklat"].waitForExistence(timeout: 5), "Set ekranında video oynamıyor")

        tap(app, "Bu hareketi atla")
        XCTAssertTrue(element(app, "Lat pulldown, Kadın eğitmen").waitForExistence(timeout: 5), "Hareket değişince klip değişmedi")
        XCTAssertFalse(element(app, "Barbell squat, Kadın eğitmen").exists, "Önceki klip ekranda kaldı")

        tap(app, "Seti bitirdim")                                      // dinlenme: video durur, kapak kalır
        XCTAssertTrue(app.buttons["Dinlenmeyi atla"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Gösterimi duraklat"].exists, "Dinlenmede video oynamamalı")
        tap(app, "Dinlenmeyi atla")
        XCTAssertTrue(app.buttons["Gösterimi duraklat"].waitForExistence(timeout: 5), "2. sette video yeniden başlamadı")

        tap(app, "Bu hareketi atla")
        XCTAssertTrue(element(app, "Dambıl bench press, Kadın eğitmen").waitForExistence(timeout: 5))
        app.buttons["Kapat"].tap()
        tap(app, "Kaydetmeden çık")
    }

    /// Profilde cinsiyet değişince Antrenman sekmesine dönüldüğünde eğitmen güncellenir.
    func testProfileChangeUpdatesTrainer() {
        let app = launch(sex: "female")
        tap(app, "Salon")
        tap(app, "Barbell squat")
        XCTAssertTrue(element(app, "Barbell squat, Kadın eğitmen").waitForExistence(timeout: 8))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        tap(app, "Profilim")
        let sexPicker = app.buttons["Cinsiyet"]
        XCTAssertTrue(sexPicker.waitForExistence(timeout: 5), "Cinsiyet seçicisi yok")
        sexPicker.tap()
        let male = app.buttons.matching(NSPredicate(format: "label == %@", "Erkek")).firstMatch
        XCTAssertTrue(male.waitForExistence(timeout: 3))
        male.tap()
        tap(app, "Devam et")
        tap(app, "Değişiklikleri kaydet")

        tap(app, "Barbell squat")
        XCTAssertTrue(element(app, "Barbell squat, Erkek eğitmen").waitForExistence(timeout: 8), "Profil değişince eğitmen güncellenmedi")
    }

    /// Cinsiyeti belirtilmemiş profil: eğitmen seçici görünür, seçim yeniden açılışta korunur.
    func testUnspecifiedProfileTrainerChoicePersists() {
        var app = launch(sex: "unspecified")
        let maleSeg = app.segmentedControls.buttons["Erkek eğitmen"]
        XCTAssertTrue(maleSeg.waitForExistence(timeout: 5), "Eğitmen seçici görünmüyor")
        maleSeg.tap()
        tap(app, "Barbell squat")
        XCTAssertTrue(element(app, "Barbell squat, Erkek eğitmen").waitForExistence(timeout: 8))

        app.terminate()
        app = launch(sex: "unspecified")
        XCTAssertTrue(app.segmentedControls.buttons["Erkek eğitmen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls.buttons["Erkek eğitmen"].isSelected, "Eğitmen seçimi yeniden açılışta korunmadı")
        tap(app, "Barbell squat")
        XCTAssertTrue(element(app, "Barbell squat, Erkek eğitmen").waitForExistence(timeout: 8))

        // Sonraki testler için varsayılana dön
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.segmentedControls.buttons["Kadın eğitmen"].tap()
    }

    private func element(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func button(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func tap(_ app: XCUIApplication, _ text: String) {
        let b = button(app, text)
        XCTAssertTrue(b.waitForExistence(timeout: 8), "'\(text)' yok")
        // Ekran dışındaysa önce yukarı, sonra aşağı kaydırarak görünür yap.
        var tries = 0
        while !b.isHittable && tries < 3 { app.swipeDown(); tries += 1 }
        tries = 0
        while !b.isHittable && tries < 4 { app.swipeUp(); tries += 1 }
        b.tap()
    }
}
