// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RetinaShot",
    platforms: [.macOS(.v26)],
    dependencies: [.package(path: "/Users/stallone/Developer/menuhub")],
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
