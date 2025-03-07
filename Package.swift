// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "ClipboardManager",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        .executable(name: "ClipboardManager", targets: ["ClipboardManager"])
    ],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey", from: "0.1.3")
    ],
    targets: [
        .executableTarget(
            name: "ClipboardManager",
            dependencies: ["HotKey"],
            path: "Clipboard Manager",
            exclude: ["Info.plist"],
            resources: [
                .process("Assets.xcassets"),
                .process("ClipboardManagerSwift.entitlements")
            ]
        )
    ]
) 