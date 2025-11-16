// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ZeroCtrl",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.2.0")
    ],
    targets: [
        .executableTarget(
            name: "ZeroCtrl",
            dependencies: [
                .product(name: "Atomics", package: "swift-atomics")
            ],
            path: "Sources/ZeroCtrl"
        )
    ]
)
