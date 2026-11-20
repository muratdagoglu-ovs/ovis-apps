// swift-tools-version:5.9
// Uygulamanın platformdan bağımsız mantığı (iOS/Core) için test paketi.
// Xcode projesi aynı dosyaları doğrudan OvisFit hedefinde derler.
import PackageDescription

let package = Package(
    name: "OvisFitCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "OvisFitCore", targets: ["OvisFitCore"])],
    targets: [
        .target(name: "OvisFitCore", path: "iOS/Core"),
        .testTarget(name: "OvisFitCoreTests", dependencies: ["OvisFitCore"], path: "Tests/OvisFitCoreTests")
    ]
)
