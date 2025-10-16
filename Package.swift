// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Sukusho",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Sukusho", targets: ["Sukusho"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SukushoCore",
            dependencies: [],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Carbon")
            ]
        ),
        .executableTarget(
            name: "Sukusho",
            path: "Sources/Sukusho",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Carbon")
            ]
        )
    ]
)
