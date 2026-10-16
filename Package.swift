// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Stowia",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Stowia", targets: ["Stowia"])],
    targets: [
        .target(name: "StowiaCore"),
        .executableTarget(name: "Stowia", dependencies: ["StowiaCore"]),
        .testTarget(name: "StowiaCoreTests", dependencies: ["StowiaCore"])
    ]
)
