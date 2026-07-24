// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacGestureLock",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "mac-gesture-lock", targets: ["MacGestureLock"])
    ],
    targets: [
        .executableTarget(name: "MacGestureLock")
    ]
)
