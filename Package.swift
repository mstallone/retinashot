// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RetinaShot",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "RetinaShot",
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
