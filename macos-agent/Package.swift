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
            linkerSettings: [
                .linkedFramework("EventKit")
            ]
        ),
        .executableTarget(
            name: "BusyLight",
            dependencies: ["BusyLightCore"],
            path: "Sources/BusyLight",
            exclude: ["Resources"]   // Info.plist is for the Xcode .app bundle; SPM forbids it as a resource
        )
        // Note: Tests are in Tests/BusyLightTests/ and require a full Xcode
        // installation to build (Swift Testing's cross-import overlay for
        // Foundation is not available in Command Line Tools).
        // Run them with: xcodebuild test -scheme BusyLight
    ]
)

