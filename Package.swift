// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RetinaShot",
    platforms: [.macOS(.v14)],
    dependencies: [.package(url: "https://github.com/mstallone/menuhub", exact: "0.1.0")],
    targets: [
        .executableTarget(
            name: "RetinaShot",
            dependencies: [.product(name: "MenuHub", package: "menuhub")],
            path: "Sources/RetinaShot",
            swiftSettings: [.swiftLanguageMode(.v6)],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
    ]
)
