import PackageDescription

let package = Package(
    name: "Sukusho",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Sukusho", targets: ["Sukusho"]),
        .library(name: "SukushoCore", targets: ["SukushoCore"])
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
            dependencies: ["SukushoCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Carbon")
            ]
        )
    ]
)
