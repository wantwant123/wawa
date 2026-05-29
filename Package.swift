// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "FileFrogNative",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "FileFrogNative", targets: ["FileFrogNative"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "FileFrogNative",
            path: "Sources/FileFrogNative"
        )
    ],
    swiftLanguageVersions: [.v5]
)
