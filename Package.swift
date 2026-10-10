// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Ferry",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sunwrobert/swiftcur", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "Ferry",
            dependencies: [.product(name: "Swiftcur", package: "swiftcur")],
            path: "Sources/Ferry",
            swiftSettings: [.unsafeFlags(["-Osize"])]
        )
    ]
)
