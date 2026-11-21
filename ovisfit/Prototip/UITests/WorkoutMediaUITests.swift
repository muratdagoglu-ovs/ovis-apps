import XCTest

/// Antrenman: beş hareketin Ovi kapakları, yerel MP4 oynatma/duraklatma ve hareket değişince doğru klip.
/// Videolar uygulama paketindeki WorkoutMedia klasöründen okunur; oynat/duraklat düğmesi yalnızca
/// paket içinde ilgili .mp4 bulunduğunda görünür (ağ bağlantısı kullanılmaz).
final class WorkoutMediaUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private let gym = ["Barbell squat", "Lat pulldown", "Dambıl bench press"]
    private let home = ["Şınav", "Kalça köprüsü"]

    func testFiveExercisesPosterAndLocalVideo() {
        let app = XCUIApplication()
        app.launchArguments = ["-OvisScreenshotData"]
        app.launch()
        app.tabBars.buttons["Antrenman"].tap()

        for (place, names) in [("Salon", gym), ("Ev", home)] {
            tap(app, place)
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", names[0])).firstMatch
                .waitForExistence(timeout: 5), "\(place) programı açılmadı")
            for name in names {
                tap(app, name)                                          // satır → detay
                XCTAssertTrue(element(app, "Ovi ile \(name)").waitForExistence(timeout: 8), "\(name): kapak/demo yok")
                let pause = app.buttons["Gösterimi duraklat"]
                XCTAssertTrue(pause.waitForExistence(timeout: 5), "\(name): yerel video oynamıyor (paket içinde .mp4 yok mu?)")
                pause.tap()
                XCTAssertTrue(app.buttons["Ovi ile hareketi izle"].waitForExistence(timeout: 3), "\(name): duraklatılamadı")
                app.buttons["Ovi ile hareketi izle"].tap()
                XCTAssertTrue(app.buttons["Gösterimi duraklat"].waitForExistence(timeout: 3), "\(name): yeniden oynatılamadı")
                app.navigationBars.buttons.element(boundBy: 0).tap()   // geri
            }
        }
    }

    func testPlayerSwitchesClipWithExercise() {
        let app = XCUIApplication()
        app.launchArguments = ["-OvisScreenshotData"]
        app.launch()
        app.tabBars.buttons["Antrenman"].tap()
        tap(app, "Salon")
        tap(app, "Antrenmanı başlat")

        XCTAssertTrue(element(app, "Ovi ile Barbell squat").waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Gösterimi duraklat"].waitForExistence(timeout: 5), "Set ekranında video oynamıyor")

        tap(app, "Bu hareketi atla")
        XCTAssertTrue(element(app, "Ovi ile Lat pulldown").waitForExistence(timeout: 5), "Hareket değişince klip değişmedi")
        XCTAssertFalse(element(app, "Ovi ile Barbell squat").exists, "Önceki klip ekranda kaldı")

        tap(app, "Seti bitirdim")                                      // dinlenme: video durur, kapak kalır
        XCTAssertTrue(app.buttons["Dinlenmeyi atla"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Gösterimi duraklat"].exists, "Dinlenmede video oynamamalı")
        tap(app, "Dinlenmeyi atla")
        XCTAssertTrue(app.buttons["Gösterimi duraklat"].waitForExistence(timeout: 5), "2. sette video yeniden başlamadı")

        tap(app, "Bu hareketi atla")
        XCTAssertTrue(element(app, "Ovi ile Dambıl bench press").waitForExistence(timeout: 5))
        app.buttons["Kapat"].tap()
        tap(app, "Kaydetmeden çık")
    }

    private func element(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func tap(_ app: XCUIApplication, _ text: String) {
        let b = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        XCTAssertTrue(b.waitForExistence(timeout: 8), "'\(text)' yok")
        // Ekran dışındaysa önce yukarı, sonra aşağı kaydırarak görünür yap.
        var tries = 0
        while !b.isHittable && tries < 3 { app.swipeDown(); tries += 1 }
        tries = 0
        while !b.isHittable && tries < 4 { app.swipeUp(); tries += 1 }
        b.tap()
    }
}
