// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "LingoCore",
    platforms: [.macOS(.v12), .iOS(.v16)],
    products: [.library(name: "LingoCore", targets: ["LingoCore"])],
    targets: [
        .target(name: "LingoCore", path: "GameLingo/Core", resources: [.process("Resources")]),
        .testTarget(name: "LingoCoreTests", dependencies: ["LingoCore"], path: "CoreTests")
    ]
)
