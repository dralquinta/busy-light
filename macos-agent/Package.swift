// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "BusyLight",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "BusyLightCore",
            dependencies: [],
            path: "Sources/BusyLightCore",
            exclude: ["State/README.md"],
            linkerSettings: [
                .linkedFramework("EventKit")
            ]
        ),
        .executableTarget(
            name: "BusyLight",
            dependencies: ["BusyLightCore"],
            path: "Sources/BusyLight",
            exclude: ["Resources"]   // Info.plist is for the Xcode .app bundle; SPM forbids it as a resource
        ),
        .testTarget(
            name: "BusyLightCoreTests",
            dependencies: ["BusyLightCore"],
            path: "Tests/BusyLightCoreTests"
        )
    ]
)

